import EdgePeekCore
import Foundation

private let server = MCPServer(service: NoteService())
server.run()

final class MCPServer {
    private let service: NoteService
    private let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
    private let fractionalDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    init(service: NoteService) {
        self.service = service
    }

    func run() {
        while let line = readLine(strippingNewline: true) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            handle(line: trimmed)
        }
    }

    // MARK: - JSON-RPC

    private func handle(line: String) {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let request = object as? [String: Any] else {
            sendError(id: NSNull(), code: -32700, message: "Parse error")
            return
        }

        let id = request["id"]
        let isNotification = id == nil
        guard let method = request["method"] as? String else {
            if !isNotification {
                sendError(id: id, code: -32600, message: "Invalid Request")
            }
            return
        }

        switch method {
        case "initialize":
            let params = request["params"] as? [String: Any] ?? [:]
            let requested = params["protocolVersion"] as? String ?? "2025-06-18"
            respond(
                id: id,
                result: [
                    "protocolVersion": requested,
                    "capabilities": [
                        "tools": [:]
                    ],
                    "serverInfo": [
                        "name": "edgepeek-notes",
                        "version": "1.0.0"
                    ],
                    "instructions": "Read and edit the local EdgePeek sticky-note list. Hashtags in note content are tags; the first hashtag is the group."
                ]
            )

        case "notifications/initialized", "notifications/cancelled":
            return

        case "ping":
            if !isNotification {
                respond(id: id, result: [:])
            }

        case "tools/list":
            respond(id: id, result: ["tools": toolDefinitions])

        case "tools/call":
            guard let params = request["params"] as? [String: Any],
                  let name = params["name"] as? String else {
                sendError(id: id, code: -32602, message: "tools/call requires a tool name")
                return
            }
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            do {
                let content = try callTool(name: name, arguments: arguments)
                respond(id: id, result: content)
            } catch {
                respond(
                    id: id,
                    result: [
                        "content": [
                            [
                                "type": "text",
                                "text": "Error: \(error.localizedDescription)"
                            ]
                        ],
                        "isError": true
                    ]
                )
            }

        default:
            if !isNotification {
                sendError(id: id, code: -32601, message: "Method not found: \(method)")
            }
        }
    }

    private func respond(id: Any?, result: Any) {
        guard let id else { return }
        send([
            "jsonrpc": "2.0",
            "id": id,
            "result": result
        ])
    }

    private func sendError(id: Any?, code: Int, message: String) {
        send([
            "jsonrpc": "2.0",
            "id": id ?? NSNull(),
            "error": [
                "code": code,
                "message": message
            ]
        ])
    }

    private func send(_ object: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(
                withJSONObject: object,
                options: [.withoutEscapingSlashes]
              ) else {
            return
        }
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([0x0A]))
    }

    // MARK: - Tools

    private var toolDefinitions: [[String: Any]] {
        [
            [
                "name": "list_notes",
                "description": "List every EdgePeek note with content, title, hashtags, colour, pin state, timestamps and due date.",
                "inputSchema": objectSchema(properties: [:], required: [])
            ],
            [
                "name": "list_groups",
                "description": "List the note groups. Notes are grouped by their first hashtag; an untagged note is its own group.",
                "inputSchema": objectSchema(properties: [:], required: [])
            ],
            [
                "name": "get_note",
                "description": "Read one note by its UUID.",
                "inputSchema": objectSchema(
                    properties: [
                        "id": stringProperty("UUID of the note.")
                    ],
                    required: ["id"]
                )
            ],
            [
                "name": "create_note",
                "description": "Create a note. A hashtag in the content becomes its tag/group; the first hashtag wins. Paper colour is chosen automatically.",
                "inputSchema": objectSchema(
                    properties: [
                        "content": stringProperty("Note text, including any #hashtags."),
                        "dueAt": dueProperty(),
                        "pinned": boolProperty("Pin the note.")
                    ],
                    required: ["content"]
                )
            ],
            [
                "name": "update_note",
                "description": "Modify a note. Omit a field to leave it unchanged. Set dueAt to null to clear the reminder.",
                "inputSchema": objectSchema(
                    properties: [
                        "id": stringProperty("UUID of the note."),
                        "content": stringProperty("New note text, including any #hashtags."),
                        "dueAt": dueProperty(),
                        "pinned": boolProperty("Pin or unpin the note.")
                    ],
                    required: ["id"]
                )
            ],
            [
                "name": "delete_note",
                "description": "Delete a note by UUID.",
                "inputSchema": objectSchema(
                    properties: [
                        "id": stringProperty("UUID of the note.")
                    ],
                    required: ["id"]
                )
            ],
            [
                "name": "search_notes",
                "description": "Search note content, titles and hashtags.",
                "inputSchema": objectSchema(
                    properties: [
                        "query": stringProperty("Text to search for.")
                    ],
                    required: ["query"]
                )
            ]
        ]
    }

    private func callTool(name: String, arguments: [String: Any]) throws -> [String: Any] {
        switch name {
        case "list_notes":
            let notes = try service.allNotes()
            return textResult([
                "count": notes.count,
                "notes": notes.map(noteDictionary)
            ])

        case "list_groups":
            let groups = try service.groups()
            return textResult([
                "count": groups.count,
                "groups": groups.map(groupDictionary)
            ])

        case "get_note":
            let id = try noteID(arguments)
            guard let note = try service.note(id: id) else {
                throw ServiceError.invalidArguments("No note with id \(id.uuidString).")
            }
            return textResult(noteDictionary(note))

        case "create_note":
            guard let content = arguments["content"] as? String else {
                throw ServiceError.invalidArguments("`content` is required.")
            }
            let due = try parseDue(arguments["dueAt"], present: arguments.keys.contains("dueAt"))
            let pinned = arguments["pinned"] as? Bool ?? false
            let note = try service.create(content: content, dueAt: due, pinned: pinned)
            return textResult(noteDictionary(note))

        case "update_note":
            let id = try noteID(arguments)
            let content = arguments["content"] as? String
            let pinned = arguments["pinned"] as? Bool
            let due = try parseDue(arguments["dueAt"], present: arguments.keys.contains("dueAt"))
            let updated = try service.update(
                id: id,
                content: content,
                pinned: pinned,
                due: DueUpdate(
                    isSet: arguments.keys.contains("dueAt"),
                    value: due
                )
            )
            return textResult(noteDictionary(updated))

        case "delete_note":
            let id = try noteID(arguments)
            let deleted = try service.delete(id: id)
            let remaining = try service.allNotes().count
            return textResult([
                "deleted": noteDictionary(deleted),
                "remaining": remaining
            ])

        case "search_notes":
            guard let query = arguments["query"] as? String else {
                throw ServiceError.invalidArguments("`query` is required.")
            }
            let notes = try service.search(query)
            return textResult([
                "count": notes.count,
                "notes": notes.map(noteDictionary)
            ])

        default:
            throw ServiceError.invalidArguments("Unknown tool: \(name)")
        }
    }

    // MARK: - Shapes

    private func noteDictionary(_ note: StickyNote) -> [String: Any] {
        [
            "id": note.id.uuidString,
            "content": note.content,
            "plainText": note.plainText,
            "title": note.displayTitle,
            "excerpt": note.excerpt,
            "tags": NoteText.tags(in: note.content),
            "primaryTag": NoteText.primaryTag(in: note.content) ?? NSNull(),
            "color": note.color.rawValue,
            "colorName": note.color.displayName,
            "isPinned": note.isPinned,
            "isOverdue": note.isOverdue,
            "createdAt": dateString(note.createdAt),
            "updatedAt": dateString(note.updatedAt),
            "dueAt": note.dueAt.map(dateString) ?? NSNull()
        ]
    }

    private func groupDictionary(_ group: NoteGroup) -> [String: Any] {
        [
            "key": group.key,
            "tag": group.tag ?? NSNull(),
            "count": group.notes.count,
            "noteIDs": group.notes.map { $0.id.uuidString },
            "color": group.notes.first?.color.rawValue ?? NoteColor.cream.rawValue
        ]
    }

    private func textResult(_ object: Any) -> [String: Any] {
        let text: String
        if let data = try? JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        ), let string = String(data: data, encoding: .utf8) {
            text = string
        } else {
            text = "{}"
        }
        return [
            "content": [
                [
                    "type": "text",
                    "text": text
                ]
            ],
            "isError": false
        ]
    }

    private func noteID(_ arguments: [String: Any]) throws -> UUID {
        guard let raw = arguments["id"] as? String,
              let id = UUID(uuidString: raw) else {
            throw ServiceError.invalidArguments("`id` must be a UUID string.")
        }
        return id
    }

    private func parseDue(_ value: Any?, present: Bool) throws -> Date? {
        guard present else { return nil }
        guard let value, !(value is NSNull) else { return nil }
        guard let string = value as? String else {
            throw ServiceError.invalidArguments(
                "`dueAt` must be an ISO-8601 string or null."
            )
        }
        if let date = fractionalDateFormatter.date(from: string) {
            return date
        }
        if let date = dateFormatter.date(from: string) {
            return date
        }
        throw ServiceError.invalidArguments(
            "`dueAt` is not a valid ISO-8601 date: \(string)"
        )
    }

    private func dateString(_ date: Date) -> String {
        dateFormatter.string(from: date)
    }

    private func objectSchema(
        properties: [String: Any],
        required: [String]
    ) -> [String: Any] {
        [
            "type": "object",
            "properties": properties,
            "required": required,
            "additionalProperties": false
        ]
    }

    private func stringProperty(_ description: String) -> [String: Any] {
        [
            "type": "string",
            "description": description
        ]
    }

    private func boolProperty(_ description: String) -> [String: Any] {
        [
            "type": "boolean",
            "description": description
        ]
    }

    private func dueProperty() -> [String: Any] {
        [
            "type": ["string", "null"],
            "description": "ISO-8601 date/time. Use null to clear a reminder."
        ]
    }
}
