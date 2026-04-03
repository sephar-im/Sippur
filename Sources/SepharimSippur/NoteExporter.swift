import Foundation

protocol NoteExporting {
    func saveNote(content: NoteContent, using settings: ExportSettings, date: Date) throws -> URL
    func saveFixedNote(content: NoteContent, basedOn originalNoteURL: URL) throws -> URL
}

struct NoteExporter: NoteExporting {
    enum NoteExportError: LocalizedError {
        case outputFolderIsFile(URL)
        case couldNotAllocateUniqueFileName(URL)

        var errorDescription: String? {
            switch self {
            case .outputFolderIsFile(let folderURL):
                return L10n.format("note_export.error.path_not_folder", folderURL.path)
            case .couldNotAllocateUniqueFileName(let fileURL):
                return L10n.format("note_export.error.unique_filename", fileURL.deletingLastPathComponent().path)
            }
        }
    }

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func saveNote(content: NoteContent, using settings: ExportSettings, date: Date = .now) throws -> URL {
        let draft = buildNoteDraft(content: content, using: settings, date: date)
        let outputFolderURL = try prepareOutputFolder(at: settings.folderURL)
        let fileURL = try resolvedOutputURL(for: draft, in: outputFolderURL)
        try draft.contents.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    func saveFixedNote(content: NoteContent, basedOn originalNoteURL: URL) throws -> URL {
        let outputFolderURL = try prepareOutputFolder(at: originalNoteURL.deletingLastPathComponent())
        let draft = buildFixedNoteDraft(content: content, basedOn: originalNoteURL)
        let fileURL = try resolvedOutputURL(for: draft, in: outputFolderURL)
        try draft.contents.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    func buildNoteDraft(
        content: NoteContent,
        using settings: ExportSettings,
        date: Date,
        timeZone: TimeZone = .autoupdatingCurrent,
        locale: Locale = Locale(identifier: "en_US_POSIX")
    ) -> NoteDraft {
        let fileTimestamp = formatted(date: date, pattern: "yyyy-MM-dd HH-mm-ss", timeZone: timeZone, locale: locale)
        let cleanBody = content.body.trimmingCharacters(in: .whitespacesAndNewlines)

        return NoteDraft(
            fileName: "\(fileTimestamp).txt",
            contents: cleanBody + "\n"
        )
    }

    func buildFixedNoteDraft(content: NoteContent, basedOn originalNoteURL: URL) -> NoteDraft {
        let cleanBody = content.body.trimmingCharacters(in: .whitespacesAndNewlines)
        let originalBaseName = originalNoteURL.deletingPathExtension().lastPathComponent
        let normalizedBaseName = normalizedFixedBaseName(from: originalBaseName)

        return NoteDraft(
            fileName: "\(normalizedBaseName) fixed.txt",
            contents: cleanBody + "\n"
        )
    }

    private func prepareOutputFolder(at folderURL: URL) throws -> URL {
        var isDirectory: ObjCBool = false
        let fileExists = fileManager.fileExists(atPath: folderURL.path, isDirectory: &isDirectory)

        if fileExists {
            guard isDirectory.boolValue else {
                throw NoteExportError.outputFolderIsFile(folderURL)
            }
        } else {
            try fileManager.createDirectory(
                at: folderURL,
                withIntermediateDirectories: true
            )
        }

        return folderURL
    }

    private func resolvedOutputURL(for draft: NoteDraft, in folderURL: URL) throws -> URL {
        let baseURL = folderURL.appending(component: draft.fileName, directoryHint: .notDirectory)
        guard fileManager.fileExists(atPath: baseURL.path) else {
            return baseURL
        }

        let fileExtension = baseURL.pathExtension
        let baseName = baseURL.deletingPathExtension().lastPathComponent

        for suffix in 1...999 {
            let candidateName = "\(baseName) \(String(format: "%02d", suffix)).\(fileExtension)"
            let candidateURL = folderURL.appending(component: candidateName, directoryHint: .notDirectory)

            if !fileManager.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
        }

        throw NoteExportError.couldNotAllocateUniqueFileName(baseURL)
    }

    private func normalizedFixedBaseName(from baseName: String) -> String {
        baseName.replacingOccurrences(
            of: #" fixed(?: \d{2})?$"#,
            with: "",
            options: .regularExpression
        )
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
