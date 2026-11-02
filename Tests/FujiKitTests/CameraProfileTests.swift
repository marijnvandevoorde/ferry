@testable import FujiKit
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

final class NetworkInfoTests: XCTestCase {
    func testLinuxRouteTable() {
        let table = """
        Iface\tDestination\tGateway \tFlags\tRefCnt\tUse\tMetric\tMask\t\tMTU\tWindow\tIRTT
        eth0\t00000000\t0101A8C0\t0003\t0\t0\t100\t00000000\t0\t0\t0
        wlan0\t0000A8C0\t00000000\t0001\t0\t0\t600\t00FFFFFF\t0\t0\t0
        wlan0\t00000000\t0100A8C0\t0003\t0\t0\t600\t00000000\t0\t0\t0
        """
        XCTAssertEqual(NetworkInfo.gateway(in: table, interface: "wlan0"), "192.168.0.1")
        XCTAssertNil(NetworkInfo.gateway(in: table, interface: "wlan1"))
    }
}
