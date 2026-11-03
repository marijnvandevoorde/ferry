import Foundation

/// The Bluetooth hand-off of newer Fujifilm cameras (X-T30, X-T4 and later): the computer pairs over Bluetooth
/// Low Energy, reads the camera's Wi-Fi network name and password, joins that network, and then talks to the
/// camera over Wi-Fi as usual (with `afterBluetoothHandoff`, which selects the XApp gallery on newer models).
///
/// Follows libfuji's `lib/bluetooth.c` (MIT, github.com/petabyt/libfuji), itself derived from furble (MIT,
/// github.com/gkoh/furble). Not yet tested on a real camera; see docs/bluetooth.md.
///
/// This file holds what doesn't depend on a Bluetooth stack; `FujiBluetoothCentral` drives CoreBluetooth on macOS.
public enum FujiBluetooth {
    /// Fujifilm's Bluetooth company identifier, the first two bytes (little-endian) of its manufacturer data.
    public static let companyID: UInt16 = 0x04D8
    static let tokenType: UInt8 = 0x02

    /// GATT services and characteristics, by libfuji's names where it has them.
    public enum UUIDs {
        /// Cameras from about 2019 on. Reading its status characteristic triggers the system's pairing prompt.
        public static let securePairService = "123D8F06-62A1-4935-9322-833C531EE225"
        public static let secureStatus = "F557D96B-8284-4667-8793-B971C1DECA2A"
        /// Older Bluetooth cameras: the advertised token is written here instead.
        public static let pairService = "91F1DE68-DFF6-466E-8B65-FF13B0F16FB8"
        public static let pairToken = "ABA356EB-9633-4E60-B73F-F52516DBD671"
        /// The client's name, shown on the camera. In whichever pairing service the camera has.
        public static let clientName = "85B9163E-62D1-49FF-A6F5-054B4630D4A1"

        public static let configService = "4C0020FE-F3B6-40DE-ACC9-77D129067B14"
        /// Indicates 1 once the camera's Wi-Fi is up, 0 when the camera is busy.
        public static let wifiStatus = "A68E3F66-0FCC-4395-8D4C-AA980B5877FA"
        static let indication2 = "BD17BA04-B76B-4892-A545-B73BA1F74DAE"
        /// Notifies when the camera wants the time; answered on `time`.
        public static let timeRequest = "F9150137-5D40-4801-A8DC-F7FC5B01DA50"
        static let indication3 = "049EC406-EF75-4205-A390-08FE209C51F0"
        static let geotagUpdate = "AD06C7B7-F41A-46F4-A29A-712055319122"
        static let notification6 = "E6692C5C-B7CD-44F4-95FC-EDA07CE32560"

        public static let wifiService = "4E941240-D01D-46B9-A5EA-67636806830B"
        public static let wifiSSID = "BF6DC9CF-3606-4EC9-A4C8-D77576E93EA4"
        public static let wifiPassword = "E809256A-915C-4967-92E8-53B7D4CAD213"
        static let notification5 = "75823784-FBB7-4B71-ABAE-CD9A34072E3C"
        static let notification7 = "AAB609C4-94DD-4D89-BC60-665D5090B828"
        static let notification8 = "2A125640-706D-4DD1-B420-C0F4AB93C361"
        static let notification9 = "82A9F452-C5CE-4EF5-8203-3FC9A47F8171"
        static let notification10 = "DEEF7187-3F43-4364-9E22-11A8C8A15951"
        static let geotagSyncInterval = "C95D91AE-B247-4D6D-8661-7DD5D6A0F85B"

        static let notification3Service = "804DAA8E-FFEB-4AB3-8E75-6EDD7303208D"
        static let notification3 = "7170FD5A-56D9-4C19-B043-7A7047D8E1A0"

        public static let timeService = "E872B11F-D526-4AE1-9BB4-89A99D48FA59"
        public static let time = "B9BFD37F-CCAD-4D36-A1EE-018E792B3EDF"

        /// Writing `startWiFi` to `wifiStart` makes the camera start its network.
        public static let shutterService = "6514EB81-4E8F-458D-AA2A-E691336CDFAC"
        public static let wifiStart = "600655E6-3637-42F1-8FB2-44EFC5C63B13"
    }

    /// (service, characteristic) pairs to subscribe to; the camera seems to expect them before starting its Wi-Fi.
    public static let secureSubscriptions: [(service: String, characteristic: String)] = [
        (UUIDs.configService, UUIDs.wifiStatus), (UUIDs.configService, UUIDs.indication2),
        (UUIDs.configService, UUIDs.timeRequest), (UUIDs.configService, UUIDs.geotagUpdate),
        (UUIDs.notification3Service, UUIDs.notification3), (UUIDs.wifiService, UUIDs.wifiSSID),
        (UUIDs.wifiService, UUIDs.notification5), (UUIDs.configService, UUIDs.notification6),
        (UUIDs.wifiService, UUIDs.notification7), (UUIDs.wifiService, UUIDs.notification8),
        (UUIDs.wifiService, UUIDs.notification9), (UUIDs.wifiService, UUIDs.notification10),
        (UUIDs.wifiService, UUIDs.geotagSyncInterval),
    ]

    public static let legacySubscriptions: [(service: String, characteristic: String)] = [
        (UUIDs.wifiService, UUIDs.wifiSSID), (UUIDs.configService, UUIDs.wifiStatus),
        (UUIDs.configService, UUIDs.indication2), (UUIDs.configService, UUIDs.timeRequest),
        (UUIDs.configService, UUIDs.geotagUpdate), (UUIDs.configService, UUIDs.indication3),
    ]

    public static let startWiFi = Data([0x04, 0x00])

    /// A camera this computer paired with. `identifier` is the Bluetooth stack's id for the device.
    public struct Pairing: Codable, Sendable, Equatable, Identifiable {
        public var identifier: String
        public var name: String
        public var token: Data
        public var id: String { identifier }

        public init(identifier: String, name: String, token: Data) {
            self.identifier = identifier
            self.name = name
            self.token = token
        }
    }

    public struct WiFiCredentials: Sendable, Equatable {
        public var ssid: String
        public var password: String

        public init(ssid: String, password: String) {
            self.ssid = ssid
            self.password = password
        }
    }

    public enum HandoffError: Error, LocalizedError, Equatable {
        case bluetoothUnavailable
        case notInPairingMode
        case notAFujifilmCamera
        case rejected
        case cameraBusy
        case timeout
        case failed(String)

        public var errorDescription: String? {
            switch self {
            case .bluetoothUnavailable: localized("Bluetooth is off or not allowed for this app.")
            case .notInPairingMode: localized("The camera isn't in pairing mode. On the camera, choose Bluetooth Settings, then Pairing Registration.")
            case .notAFujifilmCamera: localized("This device doesn't look like a Fujifilm camera.")
            case .rejected: localized("The camera rejected this computer. Remove the pairing on the camera and pair again.")
            case .cameraBusy: localized("The camera is busy. Switch it to shooting mode and try again.")
            case .timeout: localized("The camera stopped answering over Bluetooth.")
            case .failed(let reason): reason
            }
        }
    }

    /// The pairing token from manufacturer data as CoreBluetooth reports it (company id first), or nil when the
    /// camera isn't in pairing mode or this isn't a Fujifilm device.
    public static func pairingToken(manufacturerData data: Data) -> Data? {
        let bytes = [UInt8](data)
        guard bytes.count >= 7, UInt16(bytes[0]) | UInt16(bytes[1]) << 8 == companyID, bytes[2] == tokenType else {
            return nil
        }
        return Data(bytes[3..<7])
    }

    /// True for manufacturer data from a Fujifilm device, in pairing mode or not.
    public static func isFujifilm(manufacturerData data: Data) -> Bool {
        data.count >= 2 && UInt16(data[data.startIndex]) | UInt16(data[data.startIndex + 1]) << 8 == companyID
    }

    /// The secure pairing acknowledgement: the camera's 4-byte status with its last byte set to 0x20.
    public static func acknowledgement(status: Data) -> Data? {
        guard status.count == 4 else { return nil }
        var ack = [UInt8](status)
        ack[3] = 0x20
        return Data(ack)
    }

    /// The time packet the camera asks for: year (little-endian), month, day, hour, minute, second.
    public static func timePacket(_ date: Date, calendar: Calendar = .current) -> Data {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let year = UInt16(c.year ?? 2000)
        return Data([UInt8(year & 0xFF), UInt8(year >> 8), UInt8(c.month ?? 1), UInt8(c.day ?? 1),
                     UInt8(c.hour ?? 0), UInt8(c.minute ?? 0), UInt8(c.second ?? 0)])
    }

    /// Characteristic values are UTF-8 and may be zero-padded.
    public static func string(_ data: Data) -> String {
        String(decoding: data.prefix { $0 != 0 }, as: UTF8.self)
    }
}
