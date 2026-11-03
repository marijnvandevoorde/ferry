import Foundation
import XCTest
@testable import FerryKit

final class FujiBluetoothTests: XCTestCase {
    func testPairingToken() {
        // Company id 0x04D8 little-endian, type 0x02, token.
        let adv = Data([0xD8, 0x04, 0x02, 0xDE, 0xAD, 0xBE, 0xEF])
        XCTAssertEqual(FujiBluetooth.pairingToken(manufacturerData: adv), Data([0xDE, 0xAD, 0xBE, 0xEF]))
        XCTAssertTrue(FujiBluetooth.isFujifilm(manufacturerData: adv))
    }

    func testNotInPairingMode() {
        XCTAssertNil(FujiBluetooth.pairingToken(manufacturerData: Data([0xD8, 0x04, 0x01, 1, 2, 3, 4])))
        XCTAssertNil(FujiBluetooth.pairingToken(manufacturerData: Data([0xD8, 0x04])))
        XCTAssertTrue(FujiBluetooth.isFujifilm(manufacturerData: Data([0xD8, 0x04])))
    }

    func testOtherCompany() {
        let apple = Data([0x4C, 0x00, 0x02, 1, 2, 3, 4])
        XCTAssertNil(FujiBluetooth.pairingToken(manufacturerData: apple))
        XCTAssertFalse(FujiBluetooth.isFujifilm(manufacturerData: apple))
    }

    func testAcknowledgement() {
        XCTAssertEqual(FujiBluetooth.acknowledgement(status: Data([1, 2, 3, 4])), Data([1, 2, 3, 0x20]))
        XCTAssertNil(FujiBluetooth.acknowledgement(status: Data([1, 2, 3])))
    }

    func testTimePacket() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let date = calendar.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: 14, minute: 5, second: 9))!
        XCTAssertEqual(FujiBluetooth.timePacket(date, calendar: calendar), Data([0xEA, 0x07, 11, 3, 14, 5, 9]))
    }

    func testString() {
        XCTAssertEqual(FujiBluetooth.string(Data("FUJIFILM-X-T5-1234".utf8) + Data([0, 0])), "FUJIFILM-X-T5-1234")
    }
}
