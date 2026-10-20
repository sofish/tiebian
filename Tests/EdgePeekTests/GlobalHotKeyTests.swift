import Carbon
import XCTest
@testable import EdgePeek

@MainActor
final class GlobalHotKeyTests: XCTestCase {
    func testCarbonEventRoutesOnlyMatchingShortcut() throws {
        for (signature, id, expected): (OSType, UInt32, GlobalHotKey.Shortcut?) in [
            (0x4544504B, 1, .newNote), (0x4544504B, 2, .allNotes),
            (0x4544504B, 3, nil), (0x12345678, 1, nil)
        ] {
            var reference: EventRef?
            XCTAssertEqual(CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(kEventHotKeyPressed),
                                       0, EventAttributes(0), &reference), noErr)
            let event = try XCTUnwrap(reference)
            defer { ReleaseEvent(event) }
            var identifier = EventHotKeyID(signature: signature, id: id)
            XCTAssertEqual(SetEventParameter(event, EventParamName(kEventParamDirectObject),
                                            EventParamType(typeEventHotKeyID),
                                            MemoryLayout<EventHotKeyID>.size, &identifier), noErr)
            XCTAssertEqual(GlobalHotKey.shortcut(in: event), expected)
        }
        XCTAssertNotEqual(GlobalHotKey.Shortcut.newNote.modifiers, GlobalHotKey.Shortcut.allNotes.modifiers)
    }
}
