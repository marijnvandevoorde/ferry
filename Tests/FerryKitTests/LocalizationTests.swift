@testable import FerryKit
import XCTest

final class LocalizationTests: XCTestCase {
    func testEveryLanguageTranslatesEveryError() {
        for (key, values) in translations {
            for lang in ["fr", "es", "it", "de", "nl"] {
                let value = values[lang]
                XCTAssertNotNil(value, "\(lang): \(key)")
                XCTAssertEqual(value?.components(separatedBy: "%@").count, key.components(separatedBy: "%@").count, "\(lang): \(key)")
            }
        }
    }

    func testPicksTheFirstSupportedLanguage() {
        XCTAssertEqual(translation("Cancelled", languages: ["nl-BE", "fr"]), "Geannuleerd")
        XCTAssertEqual(translation("Cancelled", languages: ["ja", "de_DE"]), "Abgebrochen")
        XCTAssertNil(translation("Cancelled", languages: ["en-GB", "nl"]))
        XCTAssertNil(translation("Cancelled", languages: ["ja"]))
        XCTAssertEqual(localized("Could not connect: %@", "x").contains("x"), true)
    }
}
