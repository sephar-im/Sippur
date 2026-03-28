import Foundation

protocol NoteExporting {
    func saveNote(transcription: String, using settings: ExportSettings, date: Date) throws -> URL
}

struct NoteExporter: NoteExporting {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func saveNote(transcription: String, using settings: ExportSettings, date: Date = .now) throws -> URL {
        let draft = buildNoteDraft(transcription: transcription, using: settings, date: date)

        try fileManager.createDirectory(
            at: settings.folderURL,
            withIntermediateDirectories: true
        )

        let fileURL = settings.folderURL.appending(component: draft.fileName, directoryHint: .notDirectory)
        try draft.contents.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    func buildNoteDraft(
        transcription: String,
        using settings: ExportSettings,
        date: Date,
        timeZone: TimeZone = .autoupdatingCurrent,
        locale: Locale = Locale(identifier: "en_US_POSIX")
    ) -> NoteDraft {
        let fileTimestamp = formatted(date: date, pattern: "yyyy-MM-dd HH-mm-ss", timeZone: timeZone, locale: locale)
        let displayTimestamp = formatted(date: date, pattern: "yyyy-MM-dd HH:mm:ss", timeZone: timeZone, locale: locale)
        let cleanTranscription = transcription.trimmingCharacters(in: .whitespacesAndNewlines)

        switch settings.format {
        case .txt:
            return NoteDraft(
                fileName: "\(fileTimestamp).txt",
                contents: cleanTranscription + "\n"
            )
        case .md:
            let markdownBody: String

            switch settings.mode {
            case .normal:
                markdownBody = """
                # Voice Note

                Date: \(displayTimestamp)

                \(cleanTranscription)
                """
            case .obsidian:
                markdownBody = """
                # \(displayTimestamp)

                Created: \(displayTimestamp)

                \(cleanTranscription)
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
