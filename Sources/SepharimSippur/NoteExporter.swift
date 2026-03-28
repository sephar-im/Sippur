import Foundation

protocol NoteExporting {
    func savePlaceholderNote(from recordingURL: URL, using settings: ExportSettings, date: Date) throws -> URL
}

struct NoteExporter: NoteExporting {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func savePlaceholderNote(from recordingURL: URL, using settings: ExportSettings, date: Date = .now) throws -> URL {
        let draft = buildPlaceholderDraft(from: recordingURL, using: settings, date: date)

        try fileManager.createDirectory(
            at: settings.folderURL,
            withIntermediateDirectories: true
        )

        let fileURL = settings.folderURL.appending(component: draft.fileName, directoryHint: .notDirectory)
        try draft.contents.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    func buildPlaceholderDraft(
        from recordingURL: URL,
        using settings: ExportSettings,
        date: Date,
        timeZone: TimeZone = .autoupdatingCurrent,
        locale: Locale = Locale(identifier: "en_US_POSIX")
    ) -> NoteDraft {
        let fileTimestamp = formatted(date: date, pattern: "yyyy-MM-dd HH-mm-ss", timeZone: timeZone, locale: locale)
        let displayTimestamp = formatted(date: date, pattern: "yyyy-MM-dd HH:mm:ss", timeZone: timeZone, locale: locale)
        let placeholderBody = """
        Transcription placeholder.

        Audio captured locally.
        Source audio: \(recordingURL.lastPathComponent)
        """

        switch settings.format {
        case .txt:
            return NoteDraft(
                fileName: "\(fileTimestamp).txt",
                contents: placeholderBody + "\n"
            )
        case .md:
            let markdownBody: String

            switch settings.mode {
            case .normal:
                markdownBody = """
                # Voice Note

                Date: \(displayTimestamp)

                \(placeholderBody)
                """
            case .obsidian:
                markdownBody = """
                # \(displayTimestamp)

                Created: \(displayTimestamp)

                \(placeholderBody)
                """
            }

            return NoteDraft(
                fileName: "\(fileTimestamp).md",
                contents: markdownBody + "\n"
            )
        }
    }

    private func formatted(
        date: Date,
        pattern: String,
        timeZone: TimeZone,
        locale: Locale
    ) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = pattern
        formatter.timeZone = timeZone
        formatter.locale = locale
        return formatter.string(from: date)
    }
}
