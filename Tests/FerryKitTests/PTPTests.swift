@testable import FerryKit
import XCTest

final class PTPTests: XCTestCase {
    func testCommandContainerEncoding() {
        let c = Container.command(0x1002, transaction: 1, params: [1])
        XCTAssertEqual([UInt8](c.encoded()), [16, 0, 0, 0, 1, 0, 0x02, 0x10, 1, 0, 0, 0, 1, 0, 0, 0])
    }

    func testObjectInfoParse() throws {
        var w = DataWriter()
        w.u32(0x10000001); w.u16(0x3801); w.u16(0); w.u32(123456)
        w.u16(0x3808); w.u32(9000); w.u32(160); w.u32(120)
        w.u32(6000); w.u32(4000); w.u32(24); w.u32(0); w.u16(0); w.u32(0); w.u32(0)
        for s in ["DSCF0001.JPG", "20261030T101500"] {
            w.u8(UInt8(s.utf16.count + 1))
            s.utf16.forEach { w.u16($0) }
            w.u16(0)
        }
        let info = try ObjectInfo.parse(handle: 7, payload: w.data)
        XCTAssertEqual(info.filename, "DSCF0001.JPG")
        XCTAssertEqual(info.compressedSize, 123456)
        XCTAssertEqual(info.imageWidth, 6000)
        XCTAssertNotNil(info.date)
        XCTAssertFalse(info.isVideo)
    }

    func testProtectionAndKind() throws {
        var w = DataWriter()
        w.u32(0x10000001); w.u16(0x3801); w.u16(1); w.u32(10)
        w.u16(0); w.u32(0); w.u32(0); w.u32(0); w.u32(0); w.u32(0); w.u32(0); w.u32(0); w.u16(0); w.u32(0); w.u32(0)
        for s in ["DSCF0001.RAF", ""] {
            w.u8(UInt8(s.utf16.count + 1))
            s.utf16.forEach { w.u16($0) }
            w.u16(0)
        }
        let info = try ObjectInfo.parse(handle: 1, payload: w.data)
        XCTAssertTrue(info.isProtected)
        XCTAssertEqual(info.kind, .raw)
        XCTAssertEqual(ObjectInfo(handle: 1, format: 0, compressedSize: 0, imageWidth: 0, imageHeight: 0,
                                  filename: "a.HIF", captureDate: "").kind, .heif)
    }
}
