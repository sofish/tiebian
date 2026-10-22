import XCTest
@testable import EdgePeek

final class CardDropHintTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let hint = CGSize(width: 128, height: 34)
    private let card = CGSize(width: 248, height: 92)

    func testHintNamesTheOutcome() {
        XCTAssertEqual(CardDropTarget.none.title, "")
        XCTAssertEqual(CardDropTarget.delete.title, "松手删除")
        XCTAssertEqual(CardDropTarget.group("#工作").title, "松手并入 #工作")
        XCTAssertEqual(CardDropTarget.group(nil).title, "松手并入 散页")

        XCTAssertEqual(CardDropTarget.delete.systemImage, "trash")
        XCTAssertEqual(CardDropTarget.group("#工作").systemImage, "number")
        XCTAssertEqual(CardDropTarget.group(nil).systemImage, "doc")
    }

    func testHintSitsUnderTheCardByDefault() {
        let cardFrame = CGRect(x: 600, y: 400, width: card.width, height: card.height)
        let frame = CardDropHintLayout.placement(
            cardFrame: cardFrame,
            hintSize: hint,
            screenFrame: screen
        )
        XCTAssertEqual(frame.maxY, cardFrame.minY - CardDropHintLayout.gap)
        XCTAssertEqual(frame.midX, cardFrame.midX, accuracy: 1)
    }

    func testHintFlipsAboveWhenTheCardRestsNearTheBottom() {
        let cardFrame = CGRect(x: 600, y: 4, width: card.width, height: card.height)
        let frame = CardDropHintLayout.placement(
            cardFrame: cardFrame,
            hintSize: hint,
            screenFrame: screen
        )
        XCTAssertEqual(frame.minY, cardFrame.maxY + CardDropHintLayout.gap)
    }

    func testHintStaysInsideTheScreenAtTheTrailingEdge() {
        let cardFrame = CGRect(
            x: screen.maxX - card.width + 80,
            y: 400,
            width: card.width,
            height: card.height
        )
        let frame = CardDropHintLayout.placement(
            cardFrame: cardFrame,
            hintSize: hint,
            screenFrame: screen
        )
        XCTAssertEqual(frame.minX, screen.maxX - hint.width - CardDropHintLayout.screenMargin)
        XCTAssertLessThanOrEqual(frame.maxY, screen.maxY)
        XCTAssertGreaterThanOrEqual(frame.minY, screen.minY)
    }

    func testHintIsClampedIntoAScreenTooShortForEitherSide() {
        let shortScreen = CGRect(x: 0, y: 0, width: 500, height: 60)
        let cardFrame = CGRect(x: 20, y: 0, width: card.width, height: card.height)
        let frame = CardDropHintLayout.placement(
            cardFrame: cardFrame,
            hintSize: hint,
            screenFrame: shortScreen
        )
        // Neither below nor above clears the margin, so the top clamp wins.
        XCTAssertEqual(
            frame.minY,
            shortScreen.maxY - hint.height - CardDropHintLayout.screenMargin
        )
        XCTAssertLessThanOrEqual(frame.maxX, shortScreen.maxX)
        XCTAssertGreaterThanOrEqual(frame.minX, shortScreen.minX)
    }
}
