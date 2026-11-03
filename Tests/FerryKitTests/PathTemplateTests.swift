import FerryKit
import XCTest

final class PathTemplateTests: XCTestCase {
    let utc = TimeZone(identifier: "UTC")!
    let date = ISO8601DateFormatter().date(from: "2026-03-07T09:05:02Z")!

    func testDateFolders() {
        XCTAssertEqual(PathTemplate.defaultFolder.render(date: date, camera: "X-T20", original: "DSCF0001", timeZone: utc),
                       "2026/2026-03-07")
    }

    func testFilenameTokens() {
        let t = PathTemplate("{yyyy}{MM}{dd}_{HH}{mm}{ss}_{camera}_{original}")
        XCTAssertEqual(t.render(date: date, camera: "X-T20", original: "DSCF0001", timeZone: utc),
                       "20260307_090502_X-T20_DSCF0001")
    }

    func testValuesCannotAddFolders() {
        XCTAssertEqual(PathTemplate("{camera}").render(date: date, camera: "a/b", original: ""), "a-b")
        XCTAssertEqual(PathTemplate("{yyyy}/../{camera}").folderComponents(date: date, camera: "X", original: ""), ["2026", "X"])
    }

    func testUnknownTokensAreKept() {
        XCTAssertEqual(PathTemplate("{nope}-{dd").render(date: date, camera: "", original: "", timeZone: utc), "{nope}-{dd")
    }

    func testUniqueName() {
        let taken: Set = ["A.JPG", "A-2.JPG"]
        XCTAssertEqual(PathTemplate.uniqueName("A.JPG") { taken.contains($0) }, "A-3.JPG")
        XCTAssertEqual(PathTemplate.uniqueName("B.JPG") { taken.contains($0) }, "B.JPG")
    }
}
