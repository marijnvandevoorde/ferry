import FerryKit
import XCTest

final class ImportHistoryTests: XCTestCase {
    func testMarkAndUnmarkPersist() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        let history = ImportHistory(url: url)
        history.insert(contentsOf: ["a", "b", "c"])
        history.remove(contentsOf: ["b"])

        let reloaded = ImportHistory(url: url)
        XCTAssertTrue(reloaded.contains("a"))
        XCTAssertFalse(reloaded.contains("b"))
        XCTAssertTrue(reloaded.contains("c"))
    }
}
