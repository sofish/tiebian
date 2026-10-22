import XCTest
@testable import EdgePeekCore

final class SeamSizingTests: XCTestCase {
    func testVisibleWidthDefaultsToDoubleAndClampsIndependentlyOfLength() throws {
        let name = "EdgePeekWidthTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let preference = SeamPreferences(defaults: defaults)
        XCTAssertEqual(preference.width, 5.4)
        XCTAssertEqual(preference.animation, .flow)
        preference.animation = .ripple
        XCTAssertEqual(SeamPreferences(defaults: defaults).animation, .ripple)
        defaults.set("unknown-future-mode", forKey: "EdgePeek.seamAnimation.v1")
        XCTAssertEqual(preference.animation, .flow)
        preference.width = 10
        XCTAssertEqual(SeamPreferences(defaults: defaults).width, 10)
        XCTAssertEqual(preference.length, 440)
        preference.width = 0
        XCTAssertEqual(preference.width, 2.7)
        preference.width = .infinity
        XCTAssertEqual(preference.width, 2.7)
        preference.width = 100
        XCTAssertEqual(preference.width, SeamSizing.widthRange.upperBound)
        XCTAssertEqual(SeamSizing.width(.nan), 5.4)
    }

    func testCountSizeDefaultsAndClampsIndependently() throws {
        let name = "EdgePeekCountTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }

        let preference = SeamPreferences(defaults: defaults)
        XCTAssertEqual(preference.countSize, 8.4)
        preference.countSize = 12
        XCTAssertEqual(SeamPreferences(defaults: defaults).countSize, 12)
        preference.countSize = 1
        XCTAssertEqual(preference.countSize, SeamSizing.countSizeRange.lowerBound)
        preference.countSize = 99
        XCTAssertEqual(preference.countSize, SeamSizing.countSizeRange.upperBound)
        preference.countSize = .nan
        XCTAssertEqual(preference.countSize, SeamSizing.countSizeRange.upperBound)
        XCTAssertEqual(SeamSizing.countSize(.nan), 8.4)
    }

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
        let preference = SeamPreferences(defaults: defaults)
        XCTAssertEqual(preference.length, 440)
        preference.length = 560
        XCTAssertEqual(SeamPreferences(defaults: defaults).length, 560)
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
