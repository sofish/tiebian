import XCTest
@testable import EdgePeekCore

final class SeamSizingTests: XCTestCase {
    func testMinimumDefaultAndMaximumOnAllEdges() {
        let size = CGSize(width: 1440, height: 900)
        for edge in EdgeSide.allCases {
            XCTAssertEqual(SeamSizing.length(0, edge: edge, availableSize: size), 220)
            XCTAssertEqual(SeamSizing.length(440, edge: edge, availableSize: size), 440)
            let maximum = edge.isVertical ? 720.0 : 1152.0
            XCTAssertEqual(SeamSizing.length(5000, edge: edge, availableSize: size), maximum)
            XCTAssertEqual(SeamSizing.range(edge: edge, availableSize: size), 220...maximum)
        }
    }

    func testSmallScreensAndInvalidValuesRemainVisible() {
        XCTAssertEqual(SeamSizing.length(440, edge: .left,
                                         availableSize: CGSize(width: 500, height: 400)), 320)
        XCTAssertEqual(SeamSizing.length(440, edge: .left,
                                         availableSize: CGSize(width: 100, height: 100)), 80)
        let size = CGSize(width: 1440, height: 900)
        for invalid in [Double.nan, .infinity, -.infinity] {
            XCTAssertEqual(SeamSizing.length(invalid, edge: .right, availableSize: size), 440)
        }
    }

    func testPreferenceDefaultsToDoubleTheOldSizeAndPersistsChanges() throws {
        let name = "EdgePeekSeamTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let preference = SeamSizePreference(defaults: defaults)
        XCTAssertEqual(preference.length, 440)
        preference.length = 560
        XCTAssertEqual(SeamSizePreference(defaults: defaults).length, 560)
        preference.length = 10
        XCTAssertEqual(preference.length, 220)
        preference.length = .nan
        XCTAssertEqual(preference.length, 220)
        // A smaller screen clamps the displayed size without losing the saved preference.
        preference.length = 720
        XCTAssertEqual(SeamSizing.length(preference.length, edge: .top,
                                         availableSize: CGSize(width: 600, height: 400)), 480)
        XCTAssertEqual(preference.length, 720)
    }
}
