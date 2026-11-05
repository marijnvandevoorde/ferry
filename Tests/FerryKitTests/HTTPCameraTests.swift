@testable import FerryKit
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

    func testGoProMediaList() throws {
        let json = """
        {"id": "1", "media": [{"d": "100GOPRO", "fs": [
          {"n": "GX010001.MP4", "cre": "1696600109", "mod": "1696600109", "s": "2806303", "glrv": "100", "ls": "-1"},
          {"n": "GOPR0002.JPG", "cre": "1696600200", "mod": "1696600200", "s": "4200", "raw": "1"},
          {"n": "G0030004.JPG", "cre": "1696600300", "mod": "1696600300", "g": "3", "b": "4", "l": "7", "s": "4", "m": ["6"], "t": "b"}
        ]}]}
        """
        let files = GoProCamera.parseMediaList(Data(json.utf8))
        XCTAssertEqual(files.map(\.name), ["GX010001.MP4", "GOPR0002.JPG", "GOPR0002.GPR",
                                           "G0030004.JPG", "G0030005.JPG", "G0030007.JPG"])
        XCTAssertEqual(files[0].path, "100GOPRO/GX010001.MP4")
        XCTAssertEqual(files[0].size, 2_806_303)
        XCTAssertEqual(files[2].size, 0)
        XCTAssertEqual(files[3].size, 0)
        // 1696600109 is 2023-10-06 13:48:29 on the camera's clock, whatever this computer's time zone.
        let c = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day, .hour, .minute, .second], from: try XCTUnwrap(files[0].date))
        XCTAssertEqual([c.year, c.month, c.day, c.hour, c.minute, c.second], [2023, 10, 6, 13, 48, 29])
    }
}
