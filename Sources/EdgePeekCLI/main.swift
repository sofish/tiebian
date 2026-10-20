import CoreFoundation
import EdgePeekCore
import Foundation

enum Command: String, CaseIterable {
    case listNotes = "list_notes", listGroups = "list_groups", getNote = "get_note"
    case createNote = "create_note", updateNote = "update_note", deleteNote = "delete_note"
    case searchNotes = "search_notes"

    var fields: Set<String> {
        switch self {
        case .listNotes, .listGroups: return []
        case .getNote, .deleteNote: return ["id"]
        case .searchNotes: return ["query"]
        case .createNote: return ["content", "pinned", "dueAt"]
        case .updateNote: return ["id", "content", "pinned", "dueAt"]
        }
    }
}

struct NotesCLI {
    let service = NoteService()
    private let outputDateFormatter = ISO8601DateFormatter()

    func run(_ command: Command, input: [String: Any]) throws -> Any {
        let unknown = Set(input.keys).subtracting(command.fields)
        guard unknown.isEmpty else {
            throw ServiceError.invalidArguments("Unknown fields: \(unknown.sorted().joined(separator: ", "))")
        }
        switch command {
        case .listNotes: return try notesResult(service.allNotes())
        case .listGroups:
            let groups = try service.groups().map { group -> [String: Any] in
                ["key": group.key, "tag": group.tag ?? NSNull(), "count": group.notes.count,
                 "noteIDs": group.notes.map { $0.id.uuidString },
                 "color": group.notes.first?.color.rawValue ?? NoteColor.cream.rawValue]
            }
            return ["count": groups.count, "groups": groups]
        case .getNote:
            guard let note = try service.note(id: noteID(input)) else { throw ServiceError.noteNotFound }
            return noteDictionary(note)
        case .searchNotes:
            return try notesResult(service.search(requiredString("query", input)))
        case .createNote:
            let note = try service.create(content: requiredString("content", input),
                                          dueAt: dueDate(input), pinned: boolean("pinned", input) ?? false)
            return noteDictionary(note)
        case .updateNote:
            let note = try service.update(id: noteID(input), content: optionalString("content", input),
                                         pinned: boolean("pinned", input),
                                         due: DueUpdate(isSet: input.keys.contains("dueAt"),
                                                        value: dueDate(input)))
            return noteDictionary(note)
        case .deleteNote:
            let note = try service.delete(id: noteID(input))
            return ["deleted": noteDictionary(note)]
        }
    }

    private func requiredString(_ key: String, _ input: [String: Any]) throws -> String {
        guard let value = try optionalString(key, input) else {
            throw ServiceError.invalidArguments("`\(key)` is required.")
        }
        return value
    }

    private func optionalString(_ key: String, _ input: [String: Any]) throws -> String? {
        guard let value = input[key] else { return nil }
        guard let string = value as? String else {
            throw ServiceError.invalidArguments("`\(key)` must be a string.")
        }
        return string
    }

    private func boolean(_ key: String, _ input: [String: Any]) throws -> Bool? {
        guard let value = input[key] else { return nil }
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else {
            throw ServiceError.invalidArguments("`\(key)` must be a boolean.")
        }
        return number.boolValue
    }

    private func noteID(_ input: [String: Any]) throws -> UUID {
        guard let id = try UUID(uuidString: requiredString("id", input)) else {
            throw ServiceError.invalidArguments("`id` must be a UUID.")
        }
        return id
    }

    private func dueDate(_ input: [String: Any]) throws -> Date? {
        guard let value = input["dueAt"], !(value is NSNull) else { return nil }
        guard let string = value as? String else {
            throw ServiceError.invalidArguments("`dueAt` must be an ISO-8601 date or null.")
        }
        let formatter = ISO8601DateFormatter()
        for options: ISO8601DateFormatter.Options in [
            [.withInternetDateTime, .withFractionalSeconds], [.withInternetDateTime]
        ] {
            formatter.formatOptions = options
            if let date = formatter.date(from: string) { return date }
        }
        throw ServiceError.invalidArguments("`dueAt` must be an ISO-8601 date with a timezone.")
    }

    private func notesResult(_ notes: [StickyNote]) -> [String: Any] {
        ["count": notes.count, "notes": notes.map(noteDictionary)]
    }

    private func noteDictionary(_ note: StickyNote) -> [String: Any] {
        return [
            "id": note.id.uuidString, "content": note.content, "title": note.displayTitle,
            "tags": NoteText.tags(in: note.content), "primaryTag": NoteText.primaryTag(in: note.content) ?? NSNull(),
            "color": note.color.rawValue, "isPinned": note.isPinned, "isOverdue": note.isOverdue,
            "createdAt": outputDateFormatter.string(from: note.createdAt),
            "updatedAt": outputDateFormatter.string(from: note.updatedAt),
            "dueAt": note.dueAt.map { outputDateFormatter.string(from: $0) } ?? NSNull()
        ]
    }
}

func installSkill(at directory: URL) throws -> [String: String] {
    let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.resolvingSymlinksInPath()
    let source = executable.deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Resources/Skills/edgepeek/SKILL.md")
    let skill = try Data(contentsOf: source)
    let script = directory.appendingPathComponent("scripts/edgepeek")
    try FileManager.default.createDirectory(at: script.deletingLastPathComponent(), withIntermediateDirectories: true)
    let quotedPath = "'" + executable.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    try Data("#!/bin/sh\nexec \(quotedPath) \"$@\"\n".utf8).write(to: script, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
    try skill.write(to: directory.appendingPathComponent("SKILL.md"), options: .atomic)
    return ["skill": directory.path, "executable": executable.path]
}

func emit(_ object: Any, to output: FileHandle = .standardOutput) throws {
    let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
    output.write(data + Data("\n".utf8))
}

do {
    let arguments = Array(CommandLine.arguments.dropFirst())
    if arguments == ["--help"] || arguments == ["help"] {
        print("""
        EdgePeek local notes CLI
        Usage: edgepeek-cli COMMAND < input.json
        Commands: \(Command.allCases.map(\.rawValue).joined(separator: ", "))
        list_notes and list_groups require no input; other commands accept one JSON object on stdin.
        Install the bundled skill: edgepeek-cli install-skill /path/to/skills/edgepeek
        EDGEPEEK_DATA_FILE overrides the shared note file for isolated tests.
        """)
    } else if arguments.count == 2, arguments[0] == "install-skill" {
        try emit(installSkill(at: URL(fileURLWithPath: arguments[1])))
    } else {
        guard arguments.count == 1, let command = Command(rawValue: arguments[0]) else {
            throw ServiceError.invalidArguments("Unknown command. Run edgepeek-cli --help.")
        }
        var input: [String: Any] = [:]
        if command != .listNotes && command != .listGroups {
            let object = try JSONSerialization.jsonObject(with: FileHandle.standardInput.readDataToEndOfFile())
            guard let dictionary = object as? [String: Any] else {
                throw ServiceError.invalidArguments("Input must be one JSON object.")
            }
            input = dictionary
        }
        try emit(NotesCLI().run(command, input: input))
    }
} catch {
    try? emit(["error": error.localizedDescription], to: .standardError)
    exit(EXIT_FAILURE)
}
