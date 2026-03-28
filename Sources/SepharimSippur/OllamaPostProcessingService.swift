import AppKit
import Foundation
import Darwin.Mach

struct OllamaModelSelector {
    static let lowMemoryThresholdBytes: UInt64 = 6 * 1024 * 1024 * 1024

    static func recommendedModel(availableMemoryBytes: UInt64) -> LocalLLMModel {
        if availableMemoryBytes < lowMemoryThresholdBytes {
            return .qwen25_05b
        }

        return .qwen25_15b
    }
}

struct SystemMemorySnapshot {
    let physicalMemoryBytes: UInt64
    let availableMemoryBytes: UInt64

    static func current() -> SystemMemorySnapshot {
        let physicalMemoryBytes = ProcessInfo.processInfo.physicalMemory
        let availableMemoryBytes = availableMemoryEstimate() ?? physicalMemoryBytes
        return SystemMemorySnapshot(
            physicalMemoryBytes: physicalMemoryBytes,
            availableMemoryBytes: availableMemoryBytes
        )
    }

    private static func availableMemoryEstimate() -> UInt64? {
        var statistics = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout.size(ofValue: statistics) / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &statistics) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, reboundPointer, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return nil
        }

        var pageSize: vm_size_t = 0
        guard host_page_size(mach_host_self(), &pageSize) == KERN_SUCCESS else {
            return nil
        }

        let availablePages = UInt64(statistics.free_count + statistics.inactive_count + statistics.speculative_count)
        return availablePages * UInt64(pageSize)
    }
}

@MainActor
protocol LLMPostProcessingServicing {
    func prepare(
        settings: LLMPostProcessingSettings,
        progress: @escaping @MainActor (String, String?) -> Void
    ) async throws -> LocalLLMModel

    func postProcess(
        transcription: String,
        exportSettings: ExportSettings,
        llmSettings: LLMPostProcessingSettings,
        progress: @escaping @MainActor (String, String?) -> Void
    ) async throws -> NoteContent
}

@MainActor
final class OllamaPostProcessingService: LLMPostProcessingServicing {
    enum OllamaPostProcessingError: LocalizedError {
        case ollamaNotInstalled
        case ollamaUnavailable
        case invalidResponse
        case generationFailed(String)

        var errorDescription: String? {
            switch self {
            case .ollamaNotInstalled:
                return "Ollama is not installed. Install Ollama to enable local LLM cleanup."
            case .ollamaUnavailable:
                return "Ollama is installed but unavailable. Open Ollama and try again."
            case .invalidResponse:
                return "The local LLM returned an unreadable response."
            case .generationFailed(let message):
                return message
            }
        }
    }

    private struct OllamaInstallation {
        let executableURL: URL
        let appURL: URL?
    }

    private struct ModelTagsResponse: Decodable {
        struct ModelEntry: Decodable {
            let name: String
            let model: String
        }

        let models: [ModelEntry]
    }

    private struct PullRequest: Encodable {
        let model: String
    }

    private struct PullProgressChunk: Decodable {
        let status: String?
        let total: Int64?
        let completed: Int64?
        let error: String?
    }

    private struct GenerateRequest: Encodable {
        let model: String
        let prompt: String
        let system: String
        let format: String
        let stream: Bool
        let keep_alive: String
    }

    private struct GenerateResponse: Decodable {
        let response: String
        let error: String?
    }

    private struct LLMNoteResponse: Decodable {
        let title: String?
        let body: String
    }

    private let fileManager: FileManager
    private let urlSession: URLSession
    private let apiBaseURL: URL
    private var preparedModel: LocalLLMModel?

    init(
        fileManager: FileManager = .default,
        urlSession: URLSession = .shared,
        apiBaseURL: URL = URL(string: "http://127.0.0.1:11434")!
    ) {
        self.fileManager = fileManager
        self.urlSession = urlSession
        self.apiBaseURL = apiBaseURL
    }

    func prepare(
        settings: LLMPostProcessingSettings,
        progress: @escaping @MainActor (String, String?) -> Void
    ) async throws -> LocalLLMModel {
        let selectedModel = OllamaModelSelector.recommendedModel(
            availableMemoryBytes: SystemMemorySnapshot.current().availableMemoryBytes
        )

        if preparedModel == selectedModel, (try? await fetchVersion()) != nil {
            progress("LLM ready.", nil)
            return selectedModel
        }

        progress("Checking Ollama.", nil)
        let installation = try locateInstallation()
        try await ensureOllamaIsReachable(using: installation, progress: progress)

        progress("Checking local model.", nil)
        if try await !isModelAvailable(selectedModel) {
            progress("Downloading local model.", "This can take a while the first time.")
            try await pullModel(selectedModel, progress: progress)
        }

        preparedModel = selectedModel
        progress("LLM ready.", nil)
        return selectedModel
    }

    func postProcess(
        transcription: String,
        exportSettings: ExportSettings,
        llmSettings: LLMPostProcessingSettings,
        progress: @escaping @MainActor (String, String?) -> Void
    ) async throws -> NoteContent {
        let model = try await prepare(settings: llmSettings, progress: progress)
        progress("Cleaning transcription locally.", nil)

        let request = GenerateRequest(
            model: model.rawValue,
            prompt: prompt(
                transcription: transcription,
                exportSettings: exportSettings,
                llmSettings: llmSettings
            ),
            system: systemPrompt(
                exportSettings: exportSettings,
                llmSettings: llmSettings
            ),
            format: "json",
            stream: false,
            keep_alive: "5m"
        )

        let requestURL = apiBaseURL.appending(path: "/api/generate")
        var urlRequest = URLRequest(url: requestURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(request)

        let (data, response) = try await urlSession.data(for: urlRequest)
        try validateHTTPResponse(response, data: data)

        let generateResponse = try JSONDecoder().decode(GenerateResponse.self, from: data)
        if let error = generateResponse.error {
            throw OllamaPostProcessingError.generationFailed(error)
        }

        guard let responseData = generateResponse.response.data(using: .utf8) else {
            throw OllamaPostProcessingError.invalidResponse
        }

        let llmResponse = try JSONDecoder().decode(LLMNoteResponse.self, from: responseData)
        let cleanedBody = llmResponse.body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedBody.isEmpty else {
            throw OllamaPostProcessingError.invalidResponse
        }

        let cleanedTitle = llmResponse.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        return NoteContent(
            body: cleanedBody,
            title: cleanedTitle.flatMap { $0.isEmpty ? nil : $0 }
        )
    }

    private func locateInstallation() throws -> OllamaInstallation {
        let executableCandidates = executableCandidates()
        for executableURL in executableCandidates {
            if fileManager.isExecutableFile(atPath: executableURL.path) {
                return OllamaInstallation(
                    executableURL: executableURL,
                    appURL: Self.appBundleURL(containing: executableURL.resolvingSymlinksInPath())
                )
            }
        }

        throw OllamaPostProcessingError.ollamaNotInstalled
    }

    private func executableCandidates() -> [URL] {
        let pathURLs = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map { URL(fileURLWithPath: String($0), isDirectory: true) }
            .map { $0.appendingPathComponent("ollama", isDirectory: false) }

        let commonExecutableURLs = [
            "/opt/homebrew/bin/ollama",
            "/usr/local/bin/ollama",
            "/Applications/Ollama.app/Contents/Resources/ollama",
            fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications", isDirectory: true)
                .appendingPathComponent("Ollama.app", isDirectory: true)
                .appendingPathComponent("Contents", isDirectory: true)
                .appendingPathComponent("Resources", isDirectory: true)
                .appendingPathComponent("ollama", isDirectory: false)
                .path,
        ].map(URL.init(fileURLWithPath:))

        return Array(Set(pathURLs + commonExecutableURLs))
    }

    private func ensureOllamaIsReachable(
        using installation: OllamaInstallation,
        progress: @escaping @MainActor (String, String?) -> Void
    ) async throws {
        if (try? await fetchVersion()) != nil {
            return
        }

        if let appURL = installation.appURL {
            progress("Starting Ollama.", nil)
            try await launchOllamaApp(at: appURL)
            if (try? await pollForVersion()) != nil {
                return
            }
        }

        if (try? await fetchVersion()) != nil {
            return
        }

        throw OllamaPostProcessingError.ollamaUnavailable
    }

    private func launchOllamaApp(at appURL: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false

            NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func pollForVersion(timeoutNanoseconds: UInt64 = 15_000_000_000) async throws -> String {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds

        while DispatchTime.now().uptimeNanoseconds < deadline {
            if let version = try? await fetchVersion() {
                return version
            }

            try? await Task.sleep(nanoseconds: 500_000_000)
        }

        throw OllamaPostProcessingError.ollamaUnavailable
    }

    private func fetchVersion() async throws -> String {
        let requestURL = apiBaseURL.appending(path: "/api/version")
        let (data, response) = try await urlSession.data(from: requestURL)
        try validateHTTPResponse(response, data: data)

        struct VersionResponse: Decodable {
            let version: String
        }

        return try JSONDecoder().decode(VersionResponse.self, from: data).version
    }

    private func isModelAvailable(_ model: LocalLLMModel) async throws -> Bool {
        let requestURL = apiBaseURL.appending(path: "/api/tags")
        let (data, response) = try await urlSession.data(from: requestURL)
        try validateHTTPResponse(response, data: data)

        let tagsResponse = try JSONDecoder().decode(ModelTagsResponse.self, from: data)
        return tagsResponse.models.contains { entry in
            entry.name == model.rawValue || entry.model == model.rawValue
        }
    }

    private func pullModel(
        _ model: LocalLLMModel,
        progress: @escaping @MainActor (String, String?) -> Void
    ) async throws {
        let requestURL = apiBaseURL.appending(path: "/api/pull")
        var urlRequest = URLRequest(url: requestURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(PullRequest(model: model.rawValue))

        let (bytes, response) = try await urlSession.bytes(for: urlRequest)
        try validateHTTPResponse(response, data: nil)

        for try await line in bytes.lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedLine.isEmpty else { continue }
            guard let lineData = trimmedLine.data(using: .utf8) else { continue }

            let chunk = try JSONDecoder().decode(PullProgressChunk.self, from: lineData)
            if let error = chunk.error {
                throw OllamaPostProcessingError.generationFailed(error)
            }

            let detail: String?
            if let completed = chunk.completed, let total = chunk.total, total > 0 {
                let percent = Int((Double(completed) / Double(total)) * 100)
                detail = "\(max(0, min(percent, 100)))%"
            } else {
                detail = nil
            }

            progress(chunk.status ?? "Downloading local model.", detail)
        }
    }

    private func validateHTTPResponse(_ response: URLResponse, data: Data?) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OllamaPostProcessingError.ollamaUnavailable
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if let data,
               let errorPayload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let message = errorPayload["error"] as? String {
                throw OllamaPostProcessingError.generationFailed(message)
            }

            throw OllamaPostProcessingError.ollamaUnavailable
        }
    }

    private func systemPrompt(
        exportSettings: ExportSettings,
        llmSettings: LLMPostProcessingSettings
    ) -> String {
        let allowTitle = llmSettings.generatesTitle && exportSettings.format == .md
        let allowWikilinks = llmSettings.addsObsidianWikilinks
            && exportSettings.format == .md
            && exportSettings.mode == .obsidian

        return """
        You clean short voice note transcriptions.
        Correct only obvious transcription mistakes supported by nearby context.
        Improve punctuation and paragraphing.
        Do not summarize, invent facts, extract tasks, or add assistant commentary.
        Return valid JSON with keys "title" and "body".
        The "body" value must contain only the cleaned note body.
        \(allowTitle ? "Generate a short plain-text title when it is clearly helpful." : "Set title to null.")
        \(allowWikilinks ? "You may add a small number of Obsidian-style [[wikilinks]] only when they are directly supported by the note." : "Do not use [[wikilinks]].")
        """
    }

    private func prompt(
        transcription: String,
        exportSettings: ExportSettings,
        llmSettings: LLMPostProcessingSettings
    ) -> String {
        let formatDescription: String
        switch exportSettings.format {
        case .txt:
            formatDescription = "plain text export"
        case .md:
            formatDescription = exportSettings.mode == .obsidian ? "Obsidian-friendly markdown export" : "simple markdown export"
        }

        return """
        Output target: \(formatDescription)
        Generate title: \(llmSettings.generatesTitle && exportSettings.format == .md ? "yes" : "no")
        Add Obsidian wikilinks: \(llmSettings.addsObsidianWikilinks && exportSettings.mode == .obsidian && exportSettings.format == .md ? "yes" : "no")

        Raw transcription:
        \(transcription)
        """
    }

    private static func appBundleURL(containing executableURL: URL) -> URL? {
        var currentURL = executableURL

        while currentURL.path != "/" {
            if currentURL.pathExtension == "app" {
                return currentURL
            }

            currentURL.deleteLastPathComponent()
        }

        return nil
    }
}
