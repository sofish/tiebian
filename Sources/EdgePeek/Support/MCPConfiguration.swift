import Foundation

struct MCPConfiguration {
    let appURL: URL

    var helperURL: URL {
        appURL.appendingPathComponent("Contents/MacOS/edgepeek-mcp")
    }

    static var bundled: MCPConfiguration {
        MCPConfiguration(appURL: Bundle.main.bundleURL)
    }

    var isAvailable: Bool {
        FileManager.default.isExecutableFile(atPath: helperURL.path)
    }

    func installationPrompt() throws -> String {
        let data = try JSONSerialization.data(withJSONObject: [
            "mcpServers": ["edgepeek": ["command": helperURL.path, "args": [String]()]]
        ], options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        let configuration = String(decoding: data, as: UTF8.self)
        return """
        Connect the locally installed EdgePeek (贴边) app to the MCP client I am currently using.

        Configure a stdio MCP server named "edgepeek" using this exact executable path. This is a reference definition; inspect this client's supported configuration format and adapt it without guessing:

        \(configuration)

        Merge it into the current user's MCP configuration while preserving all other servers and settings. Do not download or install another MCP package, change note data, start a background daemon, or expose a network port. The executable is already bundled inside the app and the client should launch it on demand.

        Verify that the helper exists and is executable. If this client requires shell syntax, safely quote the complete path as one argument; do not paste a raw path into a shell command. If the app is running from a disk image or an AppTranslocation location, ask me to move it to a permanent local folder, reopen it, and copy a fresh Prompt first.

        Reload the MCP connection if supported, otherwise tell me the exact reload/restart step. Validate with initialize and tools/list only, then report whether all seven tools are available: list_notes, list_groups, get_note, create_note, update_note, delete_note, search_notes. Never create, edit, or delete a note to test the connection.

        This path reflects the app's current location. If I move or rename the app later, I must copy a fresh Prompt from its menu bar and update this server's path. Keep all data local.
        """
    }
}
