import FujiKit
import XCTest

final class CameraProfileTests: XCTestCase {
    func testXT20() {
        let p = CameraProfile(model: "X-T20", getObjectVersion: 4, remoteImageViewVersion: 2, imageGetVersion: 3, remoteVersion: 0x20004)
        XCTAssertEqual(p.generation, .remote)
        XCTAssertTrue(p.hasRemoteMode)
        XCTAssertFalse(p.listsOldestFirst)
        XCTAssertFalse(p.thumbnailNeedsObjectInfo)
    }

    func testXA2HasNoRemoteMode() {
        let p = CameraProfile(model: "X-A2", getObjectVersion: 3, remoteVersion: 0)
        XCTAssertEqual(p.generation, .imageViewOnly)
        XCTAssertFalse(p.hasRemoteMode)
        XCTAssertNil(p.remoteVersion)
    }

    func testNewerCamera() {
        let p = CameraProfile(model: "X-S10", remoteImageViewVersion: 5, remoteVersion: 0x2000A)
        XCTAssertEqual(p.generation, .remoteNew)
        XCTAssertTrue(p.listsOldestFirst)
        XCTAssertTrue(p.thumbnailNeedsObjectInfo)
    }
}
