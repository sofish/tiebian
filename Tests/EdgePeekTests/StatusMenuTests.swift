import AppKit
import ServiceManagement
import XCTest
@testable import EdgePeek

@MainActor
final class StatusMenuTests: XCTestCase {
    func testSettingsAndStartupAreAvailableFromDropdown() throws {
        _ = NSApplication.shared
        let delegate = AppDelegate()
        let menu = delegate.buildStatusMenu()
        XCTAssertEqual(menu.items.filter { !$0.isSeparatorItem }.prefix(5).map(\.title),
                       ["新建便签", "配置", "光条大小", "本地 MCP…", "便签存放位置"])
        let size = try XCTUnwrap(menu.item(withTitle: "光条大小")?.submenu)
        XCTAssertTrue(size.items.first?.view is SeamSizeMenuView)
        XCTAssertNotNil(size.item(withTitle: "恢复默认尺寸（2 倍）")?.action)
        let mcp = try XCTUnwrap(menu.item(withTitle: "本地 MCP…"))
        XCTAssertNil(mcp.submenu)
        XCTAssertNotNil(mcp.action)
        XCTAssertTrue(mcp.target === delegate)
        XCTAssertNotNil(menu.item(withTitle: "管理系统登录项…")?.action)
        let login = try XCTUnwrap(menu.item(withTitle: "登录时启动贴边")
            ?? menu.item(withTitle: "登录时启动贴边（待系统批准）"))
        for (status, state) in [(SMAppService.Status.enabled, NSControl.StateValue.on),
                                (.requiresApproval, .mixed), (.notRegistered, .off)] {
            delegate.updateStartupMenu(status: status)
            XCTAssertEqual(login.state, state)
            XCTAssertEqual(login.title.contains("待系统批准"), status == .requiresApproval)
        }
    }

    func testSeamSliderClampsAndDeliversContinuousChanges() throws {
        _ = NSApplication.shared
        let view = SeamSizeMenuView()
        view.update(value: 900, range: 220...720)
        let slider = try XCTUnwrap(view.subviews.compactMap { $0 as? NSSlider }.first)
        XCTAssertEqual(slider.doubleValue, 720)
        XCTAssertTrue(slider.isContinuous)
        var requested: Double?
        view.onChange = { requested = $0 }
        slider.doubleValue = 440
        XCTAssertTrue(slider.sendAction(slider.action, to: slider.target))
        XCTAssertEqual(requested, 440)
        XCTAssertEqual(slider.accessibilityLabel(), "光条长度")
    }

    func testMCPDialogOnlyOffersCopyPromptAndCloseWithCurrentLocation() {
        _ = NSApplication.shared
        let configuration = MCPConfiguration(appURL: URL(fileURLWithPath: "/Users/alice/Apps/Renamed.app"))
        let alert = AppDelegate().makeMCPAlert(configuration: configuration)
        XCTAssertEqual(alert.buttons.map(\.title), ["复制 Prompt", "关闭"])
        XCTAssertFalse(alert.buttons[0].isEnabled)
        XCTAssertTrue(alert.buttons[1].isEnabled)
        XCTAssertTrue(alert.informativeText.contains(configuration.appURL.path))
        XCTAssertFalse(alert.informativeText.contains("/Users/sofish"))
    }

    func testCompleteAppEnablesCopyPrompt() throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("EdgePeekPromptTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let configuration = MCPConfiguration(appURL: directory.appendingPathComponent("重命名 App.app"))
        try FileManager.default.createDirectory(at: configuration.helperURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"),
                                         to: configuration.helperURL)
        let alert = AppDelegate().makeMCPAlert(configuration: configuration)
        XCTAssertEqual(alert.buttons.map(\.title), ["复制 Prompt", "关闭"])
        XCTAssertTrue(alert.buttons[0].isEnabled)
        XCTAssertTrue(try configuration.installationPrompt().contains(configuration.helperURL.path))
    }
}

final class MCPConfigurationTests: XCTestCase {
    func testPromptTracksInstallLocationRenameAndSpecialCharacters() throws {
        for path in ["/Applications/贴边.app", "/Users/alice/Apps/My Notes.app",
                     "/tmp/it's \"贴边\" $(echo untouched).app"] {
            let configuration = MCPConfiguration(appURL: URL(fileURLWithPath: path))
            let prompt = try configuration.installationPrompt()
            let json = try XCTUnwrap(prompt.range(of: "{\n"))
            let end = try XCTUnwrap(prompt.range(of: "\n\nMerge it"))
            let definition = try XCTUnwrap(JSONSerialization.jsonObject(
                with: Data(prompt[json.lowerBound..<end.lowerBound].utf8)) as? [String: Any])
            let servers = try XCTUnwrap(definition["mcpServers"] as? [String: Any])
            let server = try XCTUnwrap(servers["edgepeek"] as? [String: Any])
            XCTAssertEqual(server["command"] as? String, path + "/Contents/MacOS/edgepeek-mcp")
            XCTAssertEqual(server["args"] as? [String], [])
            XCTAssertFalse(prompt.contains("/Users/sofish"))
            XCTAssertTrue(prompt.contains("preserving all other servers"))
            XCTAssertTrue(prompt.contains("AppTranslocation"))
            XCTAssertTrue(prompt.contains("initialize and tools/list only"))
        }
    }
}
