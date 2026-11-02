@testable import FujiKit
import XCTest

final class HTTPCameraTests: XCTestCase {
    func testOlympusListing() {
        let text = "VER_100\r\n/DCIM,100OLYMP,0,16,19520,40000\r\n/DCIM/100OLYMP,P1010001.JPG,3416847,0,19522,40079\r\n"
        let entries = OlympusCamera.parseListing(text)
        XCTAssertEqual(entries.count, 2)
        XCTAssertTrue(entries[0].isDirectory)
        XCTAssertEqual(entries[1].name, "P1010001.JPG")
        XCTAssertEqual(entries[1].size, 3_416_847)
        XCTAssertFalse(entries[1].isDirectory)
        // FAT date 19522 = 2018-02-02, time 40079 = 19:36:30
        let c = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day, .hour, .minute, .second], from: entries[1].date!)
        XCTAssertEqual([c.year, c.month, c.day, c.hour, c.minute, c.second], [2018, 2, 2, 19, 36, 30])
    }

    func testOlympusModelTag() {
        XCTAssertEqual(OlympusCamera.tag("model", in: "<?xml version=\"1.0\"?><caminfo><model>E-M10MarkII</model></caminfo>"), "E-M10MarkII")
        XCTAssertNil(OlympusCamera.tag("model", in: "<html>router</html>"))
    }
}
