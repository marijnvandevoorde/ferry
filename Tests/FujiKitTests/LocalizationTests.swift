@testable import FujiKit
import XCTest

final class LocalizationTests: XCTestCase {
    func testEveryLanguageTranslatesEveryError() throws {
        let english = try XCTUnwrap(Bundle.module.path(forResource: "en", ofType: "lproj").flatMap(Bundle.init(path:)))
        let keys = try XCTUnwrap(NSDictionary(contentsOfFile: english.path(forResource: "Localizable", ofType: "strings")!) as? [String: String]).keys
        for lang in ["fr", "es", "it", "de", "nl"] {
            let bundle = try XCTUnwrap(Bundle.module.path(forResource: lang, ofType: "lproj").flatMap(Bundle.init(path:)), lang)
            for key in keys {
                let value = bundle.localizedString(forKey: key, value: "MISSING", table: nil)
                XCTAssertNotEqual(value, "MISSING", "\(lang): \(key)")
                XCTAssertEqual(value.components(separatedBy: "%@").count, key.components(separatedBy: "%@").count, "\(lang): \(key)")
            }
        }
        XCTAssertEqual(localized("Could not connect: %@", "x"), "Could not connect: x")
    }
}
