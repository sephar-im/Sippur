import AppKit
import Foundation

@MainActor
protocol LLMPostProcessingServicing {
    func isOllamaInstalled() async -> Bool

    func prepare(
        settings: LLMPostProcessingSettings,
        progress: @escaping @MainActor (String, String?) -> Void
    ) async throws -> LocalLLMModel

    func removeModel(
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
                return L10n.tr("llm.error.not_installed")
            case .ollamaUnavailable:
                return L10n.tr("llm.error.unavailable")
            case .invalidResponse:
                return L10n.tr("llm.error.invalid_response")
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
    private let cleanupModel = LocalLLMModel.cleanupModel
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

    func isOllamaInstalled() async -> Bool {
        (try? locateInstallation()) != nil
    }

    func prepare(
        settings _: LLMPostProcessingSettings,
        progress: @escaping @MainActor (String, String?) -> Void
    ) async throws -> LocalLLMModel {
        let selectedModel = cleanupModel

        if preparedModel == selectedModel, (try? await fetchVersion()) != nil {
            progress(L10n.tr("llm.progress.ready"), nil)
            return selectedModel
        }

        progress(L10n.tr("llm.progress.checking_ollama"), nil)
        let installation = try locateInstallation()
        try await ensureOllamaIsReachable(using: installation, progress: progress)

        progress(L10n.tr("llm.progress.checking_local_model"), nil)
        if try await !isModelAvailable(selectedModel) {
            progress(L10n.tr("llm.progress.downloading_local_model"), L10n.tr("llm.progress.downloading_local_model_first_time"))
            try await pullModel(selectedModel, progress: progress)
        }

        preparedModel = selectedModel
        progress(L10n.tr("llm.progress.ready"), nil)
        return selectedModel
    }

    func removeModel(
        settings _: LLMPostProcessingSettings,
        progress: @escaping @MainActor (String, String?) -> Void
    ) async throws -> LocalLLMModel {
        let selectedModel = cleanupModel

        progress(L10n.tr("llm.progress.checking_ollama"), nil)
        let installation = try locateInstallation()
        try await ensureOllamaIsReachable(using: installation, progress: progress)

        guard try await isModelAvailable(selectedModel) else {
            if preparedModel == selectedModel {
                preparedModel = nil
            }
            progress(L10n.tr("llm.progress.no_downloaded_model"), nil)
            return selectedModel
        }

        progress(L10n.tr("llm.progress.removing_model"), selectedModel.rawValue)
        try await runOllamaCommand(
            executableURL: installation.executableURL,
            arguments: ["rm", selectedModel.rawValue]
        )
        if preparedModel == selectedModel {
            preparedModel = nil
        }
        progress(L10n.tr("llm.progress.downloaded_removed"), nil)
        return selectedModel
    }

    func postProcess(
        transcription: String,
        exportSettings: ExportSettings,
        llmSettings: LLMPostProcessingSettings,
        progress: @escaping @MainActor (String, String?) -> Void
    ) async throws -> NoteContent {
        let model = try await prepare(settings: llmSettings, progress: progress)
        progress(L10n.tr("llm.progress.cleaning_transcription"), nil)

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
            progress(L10n.tr("llm.progress.starting_ollama"), nil)
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

            progress(chunk.status ?? L10n.tr("llm.progress.downloading_local_model"), detail)
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
        You clean short voice note transcriptions into final saved note text.
        Preserve the original language of the transcription. Never translate it into English or any other language.
        If the transcription mixes languages, keep that mix only where it already exists.
        Correct only obvious transcription mistakes that are strongly supported by nearby context.
        Improve punctuation and paragraphing.
        Remove filler words, repeated starts, and speech disfluencies only when the intended meaning stays the same.
        When the speaker clearly corrects themselves, keep the final corrected information and remove the superseded draft wording.
        If a term is uncertain, keep the original wording instead of guessing.
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
        Keep the same language as the raw transcription: yes
        Prefer final self-corrections over earlier mistaken wording: yes

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

    private func runOllamaCommand(executableURL: URL, arguments: [String]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            let outputPipe = Pipe()

            process.executableURL = executableURL
            process.arguments = arguments
            process.standardOutput = outputPipe
            process.standardError = outputPipe

            process.terminationHandler = { process in
                let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(decoding: data, as: UTF8.self)

                if process.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(
                        throwing: OllamaPostProcessingError.generationFailed(
                            output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? L10n.tr("llm.error.remove_failed")
                                : output.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                    )
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
