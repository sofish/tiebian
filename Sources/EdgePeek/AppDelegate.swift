import AppKit
import EdgePeekCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var store: NoteStore!
    private var controller: EdgeController!
    private var statusItem: NSStatusItem!
    private var hotKey: GlobalHotKey?
    private var launchAtLoginItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppFonts.register()
        NSApp.setActivationPolicy(.accessory)
        NSApp.mainMenu = buildMainMenu()

        let environment = ProcessInfo.processInfo.environment
        let noteFile = environment["EDGEPEEK_DATA_FILE"].map {
            URL(fileURLWithPath: $0)
        }
        store = NoteStore(fileURL: noteFile)
        controller = EdgeController(store: store)

        setupStatusItem()

        hotKey = GlobalHotKey { [weak self] in
            self?.controller.createNote()
        }
        if hotKey == nil {
            NSLog("EdgePeek: ⌘⇧Space is already owned by another app.")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.shutdown()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: - Status item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: 25)
        if let button = statusItem.button {
            button.image = MenuBarIcon.make()
            button.imagePosition = .imageOnly
            button.toolTip = "贴边 EdgePeek"
            button.setAccessibilityLabel("贴边")
        }

        let menu = NSMenu()
        menu.delegate = self

        let newItem = NSMenuItem(
            title: "新建便签",
            action: #selector(newNote),
            keyEquivalent: " "
        )
        newItem.keyEquivalentModifierMask = [.command, .shift]
        newItem.target = self
        menu.addItem(newItem)

        menu.addItem(.separator())

        let revealItem = NSMenuItem(
            title: "便签存放位置",
            action: #selector(revealNotes),
            keyEquivalent: ""
        )
        revealItem.target = self
        menu.addItem(revealItem)

        let mcpItem = NSMenuItem(
            title: "Agent / MCP…",
            action: #selector(showMCPInfo),
            keyEquivalent: ""
        )
        mcpItem.target = self
        menu.addItem(mcpItem)

        launchAtLoginItem = NSMenuItem(
            title: "登录时打开",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchAtLoginItem.target = self
        menu.addItem(launchAtLoginItem)

        let resetItem = NSMenuItem(
            title: "重置贴边位置",
            action: #selector(resetPosition),
            keyEquivalent: ""
        )
        resetItem.target = self
        menu.addItem(resetItem)

        menu.addItem(.separator())

        let aboutItem = NSMenuItem(
            title: "关于贴边",
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self
        menu.addItem(aboutItem)

        let quitItem = NSMenuItem(
            title: "退出贴边",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        launchAtLoginItem.state = LaunchAtLogin.isEnabled ? .on : .off
    }

    // MARK: - Main menu

    private func buildMainMenu() -> NSMenu {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: "贴边")
        let aboutItem = NSMenuItem(
            title: "关于贴边",
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self
        appMenu.addItem(aboutItem)
        appMenu.addItem(.separator())

        let newItem = NSMenuItem(
            title: "新建便签",
            action: #selector(newNote),
            keyEquivalent: "n"
        )
        newItem.target = self
        appMenu.addItem(newItem)

        appMenu.addItem(.separator())
        let quitItem = NSMenuItem(
            title: "退出贴边",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        appMenu.addItem(quitItem)
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        return mainMenu
    }

    // MARK: - Actions

    @objc private func newNote() {
        controller.createNote()
    }

    @objc private func revealNotes() {
        controller.revealNotesFile()
    }

    @objc private func resetPosition() {
        controller.resetPosition()
    }

    private var mcpHelperPath: String {
        if let executable = Bundle.main.executableURL {
            let sibling = executable
                .deletingLastPathComponent()
                .appendingPathComponent("edgepeek-mcp")
            if FileManager.default.fileExists(atPath: sibling.path) {
                return sibling.path
            }
            return sibling.path
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("dist/贴边.app/Contents/MacOS/edgepeek-mcp")
            .path
    }

    @objc private func showMCPInfo() {
        NSApp.activate(ignoringOtherApps: true)
        let helper = mcpHelperPath
        let exists = FileManager.default.fileExists(atPath: helper)
        let openCodeConfig = """
        {
          "$schema": "https://opencode.ai/config.json",
          "mcp": {
            "servers": {
              "edgepeek": {
                "type": "local",
                "command": ["\(helper)"]
              }
            }
          }
        }
        """
        let claudeCommand = "claude mcp add edgepeek -- \"\(helper)\""

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "让 Agent 读写贴边便签"
        alert.informativeText = """
        MCP 服务已随贴边一起安装。它直接读写同一份 notes.json，正在运行的贴边会自动刷新。

        \(helper)
        \(exists ? "" : "（未找到这个文件，请先运行 ./scripts/build-app.sh release 构建 App）")

        工具：list_notes / list_groups / get_note / create_note / update_note / delete_note / search_notes

         把 OpenCode 配置粘进 opencode.json 的 mcp.servers 段，重启 OpenCode 即可使用。
        """
        alert.addButton(withTitle: "复制 OpenCode 配置")
        alert.addButton(withTitle: "复制 Claude 命令")
        alert.addButton(withTitle: "好")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            copyToPasteboard(openCodeConfig)
        } else if response == .alertSecondButtonReturn {
            copyToPasteboard(claudeCommand)
        }
    }

    private func copyToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            try LaunchAtLogin.setEnabled(!LaunchAtLogin.isEnabled)
            if LaunchAtLogin.requiresApproval {
                let alert = NSAlert()
                alert.messageText = "还需要一步确认"
                alert.informativeText = "请到「系统设置 › 通用 › 登录项与扩展」中允许「贴边」在登录时打开。"
                alert.addButton(withTitle: "好")
                NSApp.activate(ignoringOtherApps: true)
                alert.runModal()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "无法设置登录时打开"
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "好")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        let credits = NSAttributedString(
            string: "住在屏幕边上的便签。\n随手记下，贴边即现。",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "贴边",
            .applicationVersion: "1.0.0",
            .version: "1",
            .credits: credits,
            .applicationIcon: NSImage(named: NSImage.applicationIconName)
                ?? MenuBarIcon.make()
        ])
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
