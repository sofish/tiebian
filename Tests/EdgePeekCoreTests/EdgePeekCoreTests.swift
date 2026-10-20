import XCTest
@testable import EdgePeekCore

final class EdgeGeometryTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let size = CGSize(width: 22, height: 88)

    func testFramesSitInsideEachEdge() {
        let left = EdgeGeometry.frame(for: EdgeAnchor(edge: .left, fraction: 0.5),
                                      size: size, in: screen)
        XCTAssertEqual(left.minX, screen.minX + 4)
        XCTAssertEqual(left.midY, screen.midY, accuracy: 1)

        let right = EdgeGeometry.frame(for: EdgeAnchor(edge: .right, fraction: 0.5),
                                       size: size, in: screen)
        XCTAssertEqual(right.maxX, screen.maxX - 4)

        let top = EdgeGeometry.frame(for: EdgeAnchor(edge: .top, fraction: 0.5),
                                     size: CGSize(width: 88, height: 22), in: screen)
        XCTAssertEqual(top.maxY, screen.maxY - 4)

        let bottom = EdgeGeometry.frame(for: EdgeAnchor(edge: .bottom, fraction: 0.5),
                                        size: CGSize(width: 88, height: 22), in: screen)
        XCTAssertEqual(bottom.minY, screen.minY + 4)
    }

    func testFractionIsClampedOnScreen() {
        let frame = EdgeGeometry.frame(for: EdgeAnchor(edge: .left, fraction: 0),
                                       size: size, in: screen)
        XCTAssertGreaterThanOrEqual(frame.minY, screen.minY)
        XCTAssertLessThanOrEqual(frame.maxY, screen.maxY)

        let bottom = EdgeGeometry.frame(for: EdgeAnchor(edge: .bottom, fraction: 1),
                                        size: CGSize(width: 88, height: 22), in: screen)
        XCTAssertLessThanOrEqual(bottom.maxX, screen.maxX)
    }

    func testNearestEdge() {
        XCTAssertEqual(EdgeGeometry.nearestEdge(to: CGPoint(x: 20, y: 450), in: screen), .left)
        XCTAssertEqual(EdgeGeometry.nearestEdge(to: CGPoint(x: 1420, y: 450), in: screen), .right)
        XCTAssertEqual(EdgeGeometry.nearestEdge(to: CGPoint(x: 700, y: 880), in: screen), .top)
        XCTAssertEqual(EdgeGeometry.nearestEdge(to: CGPoint(x: 700, y: 20), in: screen), .bottom)
    }

    func testAnchorRoundTrip() {
        let anchor = EdgeAnchor(edge: .right, fraction: 0.25, displayID: 3)
        let frame = EdgeGeometry.frame(for: anchor, size: size, in: screen)
        let result = EdgeGeometry.anchor(for: frame, in: screen)
        XCTAssertEqual(result.edge, .right)
        XCTAssertEqual(result.fraction, 0.25, accuracy: 0.001)
    }

    func testScreenSelection() {
        let second = CGRect(x: 1440, y: 0, width: 1280, height: 800)
        let index = EdgeGeometry.screenIndex(for: CGPoint(x: 1600, y: 400),
                                             among: [screen, second])
        XCTAssertEqual(index, 1)
    }
}

final class NoteTextTests: XCTestCase {
    func testTitleAndExcerpt() {
        let content = "# 颜色备忘\n\n刚才那个橙是 `#C96F45`。\n- 下次别再翻三分钟"
        XCTAssertEqual(NoteText.title(from: content), "颜色备忘")
        XCTAssertEqual(NoteText.excerpt(from: content), "刚才那个橙是 #C96F45。")
    }

    func testMarkdownKinds() {
        let content = """
        # 标题
        - [ ] 没做
        - [x] 做了
        - 普通条目
        > 引用
        ```
        let x = 1
        ```
        ---
        最后一行
        """
        let lines = NoteText.lines(from: content)
        XCTAssertEqual(lines.map(\.kind), [
            .heading(1), .checkbox(false), .checkbox(true), .bullet,
            .quote, .code, .divider, .text
        ])
    }

    func testTitleFromFirstMeaningfulLine() {
        let content = "\n\n  \n- 第一件事\n第二行"
        XCTAssertEqual(NoteText.title(from: content), "第一件事")
        XCTAssertEqual(NoteText.excerpt(from: content), "第二行")
    }

    func testHashtagAtStartIsTagNotHeading() {
        let content = "#旅行\n窗外的稻田一层一层退后。"
        XCTAssertEqual(NoteText.plainText(from: content), content)
        XCTAssertEqual(NoteText.title(from: content), "#旅行")
        XCTAssertEqual(NoteText.primaryTag(in: content), "#旅行")
    }

    func testPlainTextRemovesMarkdownWithoutLosingTags() {
        let content = """
        # 一个标题
        - [ ] 没做
        - [x] 做了
        **重点**和 [链接](https://example.com)
        用 #用法 归类
        """
        let plain = NoteText.plainText(from: content)
        XCTAssertEqual(
            plain,
            "一个标题\n☐ 没做\n☑ 做了\n重点和 链接\n用 #用法 归类"
        )
        XCTAssertEqual(NoteText.tags(in: plain), ["#用法"])
    }

    func testEmptyNote() {
        XCTAssertEqual(NoteText.title(from: "   \n\n"), "")
        XCTAssertTrue(NoteStore.welcomeNotes().count >= 3)
    }
}

@MainActor
final class NoteStoreTests: XCTestCase {
    func testAddUpdatePinAndDelete() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("EdgePeekTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("notes.json")
        let store = NoteStore(fileURL: url, seedIfMissing: false)
        let note = store.addNote(content: "第一行\n第二行", color: .rose)
        XCTAssertEqual(store.notes.count, 1)
        XCTAssertEqual(store.note(with: note.id)?.title, "第一行")

        store.updateContent(id: note.id, content: "改过了\n新的第二行")
        store.togglePin(id: note.id)
        XCTAssertTrue(store.note(with: note.id)?.isPinned == true)
        store.saveNow()

        let reloaded = NoteStore(fileURL: url, seedIfMissing: false)
        XCTAssertEqual(reloaded.notes.count, 1)
        XCTAssertEqual(reloaded.notes.first?.content, "改过了\n新的第二行")

        reloaded.delete(id: note.id)
        XCTAssertTrue(reloaded.notes.isEmpty)
    }
}
