@testable import FerryKit
import XCTest

final class TraceTests: XCTestCase {
    private func json(_ trace: Trace) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: trace.export()) as? [String: Any])
    }

    private func sessions(_ trace: Trace) throws -> [[String: Any]] {
        try XCTUnwrap(json(trace)["sessions"] as? [[String: Any]])
    }

    func testAttemptsWhereNothingAnsweredAreReplaced() throws {
        let trace = Trace()
        for _ in 0..<3 {
            trace.begin(host: "192.168.0.1")
            XCTAssertThrowsError(try trace.connecting("fuji", host: "192.168.0.1", port: 55740) {
                throw FujiError.connectionFailed("refused")
            })
        }
        let all = try sessions(trace)
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual((all[0]["attempts"] as? [[String: Any]])?.first?["result"] as? String, "not found")
        XCTAssertTrue(trace.summary().contains("no camera answered"))
    }

    func testAFailureIsExplainedAndKeptWhenRetrying() throws {
        let trace = Trace()
        trace.begin(host: "192.168.0.1")
        XCTAssertThrowsError(try trace.connecting("ptpip", host: "192.168.0.1", port: 15740) {
            trace.stage(.reached)
            trace.identified(camera: "Canon EOS R", protocolName: "ptpip")
            trace.ptp("ptpip", op: PTP.Op.openSession, params: [1], code: 0x2019, dataIn: Data(), ms: 3)
            throw FujiError.response(op: PTP.Op.openSession, code: 0x2019)
        })
        // A retry where nothing answers doesn't push it out.
        trace.begin(host: "192.168.0.1")
        XCTAssertThrowsError(try trace.connecting("ptpip", host: "192.168.0.1", port: 15740) {
            throw FujiError.connectionFailed("refused")
        })

        let summary = trace.summary()
        XCTAssertTrue(summary.contains("Camera: Canon EOS R"), summary)
        XCTAssertTrue(summary.contains("[x] Something answered on a camera port"), summary)
        XCTAssertTrue(summary.contains("[ ] Opened a session"), summary)
        XCTAssertTrue(summary.contains("OpenSession with DeviceBusy"), summary)
        XCTAssertTrue(summary.contains("the camera is busy"), summary)
        XCTAssertEqual(try json(trace)["mainSession"] as? Int, 0)
    }

    func testPhotoDataIsNeverKept() throws {
        let trace = Trace()
        trace.begin(host: "127.0.0.1")
        trace.ptp("fuji", op: PTP.Op.getPartialObject, params: [1, 0, 1000], code: PTP.Response.ok,
                  dataIn: Data(repeating: 0xAB, count: 1000), ms: 1)
        trace.http(method: "GET", url: URL(string: "http://10.5.5.9:8080/videos/DCIM/100GOPRO/GOPR0001.JPG")!,
                   requestBody: nil, status: 200, contentType: "image/jpeg", body: Data([0xFF, 0xD8, 0xAB, 0xAB]), ms: 1)
        let text = String(decoding: trace.export(), as: UTF8.self)
        XCTAssertFalse(text.contains("abab"))
        XCTAssertFalse(text.contains("q6s")) // base64 of 0xABAB
        let events = try XCTUnwrap(sessions(trace).first?["events"] as? [[String: Any]])
        XCTAssertEqual(events.first { $0["kind"] as? String == "ptp" }?["inSize"] as? Int, 1000)
        XCTAssertEqual(events.first { $0["kind"] as? String == "http" }?["bodySize"] as? Int, 4)
    }

    func testComputerNameAndHomeFolderAreReplaced() {
        let trace = Trace()
        trace.redact("Marijn's MacBook")
        trace.note("Registered as Marijn's MacBook")
        trace.note("Could not write \(NSHomeDirectory())/Pictures/x.jpg")
        trace.redact(#"C:\Users\Marijn"#)
        trace.note(#"Could not write C:\Users\Marijn\Pictures"#)
        let text = String(decoding: trace.export(), as: UTF8.self)
        XCTAssertFalse(text.contains("Marijn's MacBook"))
        XCTAssertTrue(text.contains("Registered as <computer>"))
        XCTAssertFalse(text.contains(NSHomeDirectory()))
        XCTAssertTrue(text.contains("~/Pictures/x.jpg"))
        XCTAssertFalse(text.contains("Marijn\\\\Pictures"), text)
    }

    func testDeviceInfoIsParsedAndTheSerialNumberBlanked() throws {
        var w = DataWriter()
        func string(_ s: String) {
            w.u8(UInt8(s.utf16.count + 1))
            s.utf16.forEach { w.u16($0) }
            w.u16(0)
        }
        w.u16(100); w.u32(11); w.u16(100); string("canon.com: 1.0"); w.u16(0)
        for codes: [UInt16] in [[0x1001, 0x1002], [0x4002], [0x5001], [], [0x3801]] {
            w.u32(UInt32(codes.count))
            codes.forEach { w.u16($0) }
        }
        string("Canon Inc."); string("Canon EOS R"); string("3-1.6.0"); string("SN12345")

        let info = try DeviceInfo.parse(w.data)
        XCTAssertEqual(info.model, "Canon EOS R")
        XCTAssertEqual(info.version, "3-1.6.0")
        XCTAssertEqual(info.operations, [0x1001, 0x1002])

        let trace = Trace()
        trace.begin(host: "127.0.0.1")
        trace.ptp("ptpip", op: PTP.Op.getDeviceInfo, params: [], code: PTP.Response.ok, dataIn: w.data, ms: 1)
        let event = try XCTUnwrap((sessions(trace).first?["events"] as? [[String: Any]])?.first { $0["kind"] as? String == "ptp" })
        let recorded = try XCTUnwrap(Data(hexString: event["in"] as? String ?? ""))
        var r = DataReader(recorded, offset: info.serialRange!.lowerBound - 1)
        XCTAssertEqual(try r.ptpString(), "0000000")
        XCTAssertTrue(trace.summary().contains("Model Canon EOS R, firmware 3-1.6.0"))
    }
}

private extension Data {
    init?(hexString: String) {
        var bytes: [UInt8] = []
        var index = hexString.startIndex
        while index < hexString.endIndex {
            let next = hexString.index(index, offsetBy: 2)
            guard let byte = UInt8(hexString[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self.init(bytes)
    }
}
