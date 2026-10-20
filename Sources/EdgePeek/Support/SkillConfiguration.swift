import Foundation

struct SkillConfiguration {
    let appURL: URL

    var helperURL: URL { appURL.appendingPathComponent("Contents/MacOS/edgepeek-cli") }
    var skillURL: URL { appURL.appendingPathComponent("Contents/Resources/Skills/edgepeek/SKILL.md") }
    static var bundled: SkillConfiguration { SkillConfiguration(appURL: Bundle.main.bundleURL) }
    var isAvailable: Bool {
        FileManager.default.isExecutableFile(atPath: helperURL.path)
            && FileManager.default.isReadableFile(atPath: skillURL.path)
    }

    func installationPrompt() throws -> String {
        let data = try JSONSerialization.data(withJSONObject: [
            "executable": helperURL.path, "skill": skillURL.path
        ], options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return """
        Install the local EdgePeek (贴边) skill for the agent client I am currently using.

        These are the exact paths in my currently installed app:

        \(String(decoding: data, as: UTF8.self))

        Inspect this client's supported local skill directory rather than guessing. Read the bundled SKILL.md. Run the executable with `install-skill` and the full destination skill folder (named edgepeek). This copies the skill and creates a launcher pointing to this exact app; inspect or back up an existing edgepeek skill before replacing its files. Preserve all unrelated skills and settings. Safely quote complete paths as individual shell arguments, including spaces, apostrophes, and shell metacharacters.

        If this client has an old edgepeek MCP entry, remove only that entry while preserving all other servers and settings. Do not configure any new MCP server, download packages, start daemons, or expose network ports. If this client cannot execute local shell commands or load local skills, explain that requirement rather than claiming success.

        Verify that the executable and bundled skill exist. If the app is in a disk image or AppTranslocation location, ask me to move it to a permanent local folder, reopen it, and copy a fresh Prompt first. Validate the installed launcher with --help only; never read, create, edit, or delete a note for installation testing. Reload skills if supported, otherwise tell me the required reload/restart step.

        Keep all note data local. If I move or rename the app, I must copy a fresh Prompt and reinstall the skill to update its launcher path.
        """
    }
}
