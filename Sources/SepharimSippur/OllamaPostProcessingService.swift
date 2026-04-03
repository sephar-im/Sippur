import AppKit
import Foundation

@MainActor
protocol LLMPostProcessingServicing {
    func isOllamaInstalled() async -> Bool

    func prepare(
        progress: @escaping @MainActor (String, String?) -> Void
    ) async throws -> LocalLLMModel

    func removeModel(
        progress: @escaping @MainActor (String, String?) -> Void
    ) async throws -> LocalLLMModel

    func postProcess(
        transcription: String,
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
        struct GenerateOptions: Encodable {
            let temperature: Double
            let top_p: Double
            let repeat_penalty: Double

            static let cleanupDefault = GenerateOptions(
                temperature: 0.15,
                top_p: 0.9,
                repeat_penalty: 1.08
            )
        }

        let model: String
        let prompt: String
        let system: String
        let format: String
        let stream: Bool
        let keep_alive: String
        let options: GenerateOptions
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
        progress: @escaping @MainActor (String, String?) -> Void
    ) async throws -> NoteContent {
        let model = try await prepare(progress: progress)
        progress(L10n.tr("llm.progress.cleaning_transcription"), nil)

        var request = GenerateRequest(
            model: model.rawValue,
            prompt: prompt(transcription: transcription),
            system: systemPrompt(),
            format: "json",
            stream: false,
            keep_alive: "5m",
            options: .cleanupDefault
        )

        var llmResponse = try await generateNoteResponse(for: request)
        var cleanedBody = llmResponse.body.trimmingCharacters(in: .whitespacesAndNewlines)

        if shouldRetryForMoreCleanup(original: transcription, cleaned: cleanedBody) {
            request = GenerateRequest(
                model: model.rawValue,
                prompt: strongerRetryPrompt(
                    transcription: transcription,
                    previousResult: cleanedBody
                ),
                system: strongerRetrySystemPrompt(),
                format: "json",
                stream: false,
                keep_alive: "5m",
                options: .cleanupDefault
            )
            llmResponse = try await generateNoteResponse(for: request)
            cleanedBody = llmResponse.body.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard !cleanedBody.isEmpty else {
            throw OllamaPostProcessingError.invalidResponse
        }

        return NoteContent.whisperOnly(body: cleanedBody)
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
    ) -> String {
        return """
        You clean short voice note transcriptions into final saved plain-text notes.
        Preserve the original language of the transcription. Never translate it into English or any other language.
        If the transcription mixes languages, keep that mix only where it already exists.
        Correct only obvious transcription mistakes that are strongly supported by nearby context.
        Improve punctuation, sentence boundaries, capitalization, and paragraph breaks.
        Split the note into short natural paragraphs whenever the idea or topic shifts.
        Remove filler words, repeated starts, and speech disfluencies only when the intended meaning stays the same.
        When the speaker clearly corrects themselves, keep the final corrected information and remove the superseded draft wording.
        When a word is misspelled by transcription but the nearby context makes the intended spelling clear, fix it.
        Keep the writing clean and readable, but do not make it sound more formal than necessary.
        If a term is uncertain, keep the original wording instead of guessing.
        Do not summarize, invent facts, extract tasks, add bullets, add headings, or add assistant commentary.
        Do not simply echo the raw transcription when it is clearly messy. Normalize it into readable prose.
        Return valid JSON with keys "title" and "body".
        Set "title" to null.
        The "body" value must contain only the cleaned plain-text note body.
        """
    }

    private func prompt(
        transcription: String
    ) -> String {
        return """
        Output target: plain text export
        Generate title: no
        Add Obsidian wikilinks: no
        Keep the same language as the raw transcription: yes
        Prefer final self-corrections over earlier mistaken wording: yes
        Clean up punctuation and paragraphing: yes
        If the transcription is messy, do not keep it almost unchanged.

        Example 1
        Raw: mañana tengo que ir a las cinco al dentista ah no era a las ocho
        Body: Mañana tengo que ir al dentista a las ocho.

        Example 2
        Raw: vale vamos a ver si está funcionando parece que sí el costo de envío sería unos 200 yen perdón no esto es 2500 yen no 2800 vale gracias
        Body: Vale, vamos a ver si está funcionando. Parece que sí.

        El costo de envío sería de 2.800 yen. Gracias.

        Raw transcription:
        \(transcription)
        """
    }

    private func strongerRetrySystemPrompt() -> String {
        """
        You are doing a second cleanup pass because the first result stayed too close to the raw transcript.
        Be more decisive about punctuation, capitalization, paragraphing, filler removal, and obvious speech repairs.
        Preserve the original language and meaning.
        Keep explicit self-corrections and final numbers, times, and dates.
        Do not translate, summarize, invent facts, add bullets, or add headings.
        Return valid JSON with keys "title" and "body".
        Set "title" to null.
        The "body" value must contain only the cleaned plain-text note body.
        """
    }

    private func strongerRetryPrompt(transcription: String, previousResult: String) -> String {
        """
        The previous cleanup stayed too close to the raw transcript.
        Clean the text more actively while preserving meaning.
        Add punctuation and capitalization.
        Break into short paragraphs when the idea changes.
        Remove filler words and false starts when safe.
        Keep the final corrected wording when the speaker revises themselves.
        If a number or term is explicitly corrected later, use the final corrected version.

        Raw transcription:
        \(transcription)

        Previous cleanup result:
        \(previousResult)
        """
    }

    private func generateNoteResponse(for request: GenerateRequest) async throws -> LLMNoteResponse {
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

        return try JSONDecoder().decode(LLMNoteResponse.self, from: responseData)
    }

    private func shouldRetryForMoreCleanup(original: String, cleaned: String) -> Bool {
        let normalizedOriginal = normalizedForComparison(original)
        let normalizedCleaned = normalizedForComparison(cleaned)

        guard normalizedOriginal == normalizedCleaned else {
            return false
        }

        let lowercased = normalizedOriginal.lowercased()
        let wordCount = normalizedOriginal.split(whereSeparator: \.isWhitespace).count
        let punctuationCharacters = CharacterSet(charactersIn: ".?!;:\n")
        let punctuationCount = normalizedOriginal.unicodeScalars.filter { punctuationCharacters.contains($0) }.count

        let repairMarkers = [
            "ah no",
            "perdón",
            "no no",
            "o sea",
            "vale",
            "eh",
            "umm",
            "uh",
            "sorry",
            "actually",
            "i mean",
        ]

        let hasRepairMarker = repairMarkers.contains { lowercased.contains($0) }
        let looksUnderPunctuated = wordCount >= 12 && punctuationCount <= 1

        return hasRepairMarker || looksUnderPunctuated
    }

    private func normalizedForComparison(_ text: String) -> String {
        text
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
