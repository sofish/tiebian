import XCTest
@testable import EdgePeekCore

final class NoteFontSizingTests: XCTestCase {
    func testReadingSizesAreOrderedAndPreviewStaysLarger() {
        XCTAssertEqual(NoteFontSize.allCases, [.compact, .standard, .large])
        let cardSizes = NoteFontSize.allCases.map(\.cardPointSize)
        XCTAssertEqual(cardSizes, cardSizes.sorted())
        XCTAssertEqual(Set(cardSizes).count, cardSizes.count, "each preset needs its own size")
        for size in NoteFontSize.allCases {
            XCTAssertGreaterThan(size.previewPointSize, size.cardPointSize)
        }
    }

    func testPreferenceDefaultsToStandardAndPersistsEachSize() throws {
        let name = "EdgePeekFontTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }

        let preference = NoteFontPreferences(defaults: defaults)
        XCTAssertEqual(preference.size, .standard)
        preference.size = .large
        XCTAssertEqual(NoteFontPreferences(defaults: defaults).size, .large)
        preference.size = .compact
        XCTAssertEqual(NoteFontPreferences(defaults: defaults).size, .compact)

        defaults.set("unknown-future-size", forKey: NoteFontPreferences.defaultsKey)
        XCTAssertEqual(preference.size, .standard)
    }
}
