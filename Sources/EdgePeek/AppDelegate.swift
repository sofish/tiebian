import AppKit
import EdgePeekCore
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var store: NoteStore!
    private var controller: EdgeController!
    private var statusItem: NSStatusItem!
    private var hotKey: GlobalHotKey?
    private var launchAtLoginItem: NSMenuItem?
    private var seamSizeView: SeamSizeMenuView?

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

        statusItem.menu = buildStatusMenu()
    }

    func buildStatusMenu() -> NSMenu {
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

        menu.addItem(.sectionHeader(title: "配置"))

        let sizeItem = NSMenuItem(title: "光条大小", action: nil, keyEquivalent: "")
        let sizeMenu = NSMenu(title: "光条大小")
        sizeMenu.delegate = self
        let sliderItem = NSMenuItem()
        let sizeView = SeamSizeMenuView()
        sizeView.onChange = { [weak self] length in self?.controller?.setSeamLength(length) }
        seamSizeView = sizeView
        sliderItem.view = sizeView
        sizeMenu.addItem(sliderItem)
        let resetSize = NSMenuItem(title: "恢复默认尺寸（2 倍）",
                                  action: #selector(resetSeamSize), keyEquivalent: "")
        resetSize.target = self
        sizeMenu.addItem(resetSize)
        sizeItem.submenu = sizeMenu
        menu.addItem(sizeItem)

        let mcpItem = NSMenuItem(title: "本地 MCP…", action: #selector(showMCPInfo), keyEquivalent: "")
        mcpItem.target = self
        menu.addItem(mcpItem)

        let revealItem = NSMenuItem(
            title: "便签存放位置",
            action: #selector(revealNotes),
            keyEquivalent: ""
        )
        revealItem.target = self
        menu.addItem(revealItem)

        let resetItem = NSMenuItem(
            title: "重置贴边位置",
            action: #selector(resetPosition),
            keyEquivalent: ""
        )
        resetItem.target = self
        menu.addItem(resetItem)

        menu.addItem(.separator())

        menu.addItem(.sectionHeader(title: "启动"))
        let loginItem = NSMenuItem(title: "登录时启动贴边",
                                   action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.target = self
        launchAtLoginItem = loginItem
        menu.addItem(loginItem)
        let loginSettings = NSMenuItem(title: "管理系统登录项…",
                                       action: #selector(openLoginSettings), keyEquivalent: "")
        loginSettings.target = self
        menu.addItem(loginSettings)
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

        menuWillOpen(menu)
        return menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        if let controller {
            seamSizeView?.update(value: controller.seamLength, range: controller.seamLengthRange)
        }
        updateStartupMenu(status: LaunchAtLogin.status)
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

    @objc private func resetSeamSize() {
        controller.setSeamLength(SeamSizing.defaultLength)
    }

    func makeMCPAlert(configuration: MCPConfiguration = .bundled) -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "让 Agent 连接贴边"
        alert.informativeText = """
        复制 Prompt，发给你正在使用的 Agent，它会完成本地 MCP 配置。

        当前安装位置：
        \(configuration.appURL.path)

        移动或重命名 App 后，请重新复制 Prompt。便签只在本机读写。
        \(configuration.isAvailable ? "" : "\n应用内缺少 MCP 服务，请重新安装完整的贴边 App。")
        """
        alert.addButton(withTitle: "复制 Prompt").isEnabled = configuration.isAvailable
        alert.addButton(withTitle: "关闭").keyEquivalent = "\u{1b}"
        return alert
    }

    @objc private func showMCPInfo() {
        NSApp.activate(ignoringOtherApps: true)
        let configuration = MCPConfiguration.bundled
        guard makeMCPAlert(configuration: configuration).runModal() == .alertFirstButtonReturn else { return }
        do {
            copyToPasteboard(try configuration.installationPrompt())
        } catch {
            let alert = NSAlert()
            alert.messageText = "无法复制 Prompt"
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "关闭")
            alert.runModal()
        }
    }

    private func copyToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            try LaunchAtLogin.setEnabled(!LaunchAtLogin.isRegistered)
            if LaunchAtLogin.requiresApproval {
                let alert = NSAlert()
                alert.messageText = "还需要一步确认"
                alert.informativeText = "请到「系统设置 › 通用 › 登录项与扩展」中允许「贴边」在登录时打开。"
                alert.addButton(withTitle: "打开系统设置")
                alert.addButton(withTitle: "稍后")
                NSApp.activate(ignoringOtherApps: true)
                if alert.runModal() == .alertFirstButtonReturn {
                    LaunchAtLogin.openSettings()
                }
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

    func updateStartupMenu(status: SMAppService.Status) {
        switch status {
        case .enabled:
            launchAtLoginItem?.title = "登录时启动贴边"
            launchAtLoginItem?.state = .on
        case .requiresApproval:
            launchAtLoginItem?.title = "登录时启动贴边（待系统批准）"
            launchAtLoginItem?.state = .mixed
        default:
            launchAtLoginItem?.title = "登录时启动贴边"
            launchAtLoginItem?.state = .off
        }
    }

    @objc private func openLoginSettings() {
        LaunchAtLogin.openSettings()
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
            .applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
            .version: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "",
            .credits: credits,
            .applicationIcon: NSImage(named: NSImage.applicationIconName)
                ?? MenuBarIcon.make()
        ])
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
