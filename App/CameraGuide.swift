import FujiKit
import SwiftUI

/// How to put a camera into the right Wi-Fi mode. Menu names differ between camera generations, so once a
/// camera has connected we remember its generation and show the matching steps next time.
struct CameraGuide {
    var cameraName: String?
    var generation: CameraProfile.Generation?

    static var lastConnected: CameraGuide {
        let defaults = UserDefaults.standard
        return CameraGuide(cameraName: defaults.string(forKey: Prefs.lastCameraName),
                           generation: defaults.string(forKey: Prefs.lastCameraGeneration).flatMap(CameraProfile.Generation.init))
    }

    static func remember(_ profile: CameraProfile) {
        UserDefaults.standard.set(profile.model, forKey: Prefs.lastCameraName)
        UserDefaults.standard.set(profile.generation.rawValue, forKey: Prefs.lastCameraGeneration)
    }

    /// The step that starts Wi-Fi on the camera.
    var cameraStep: LocalizedStringKey {
        switch generation {
        case .imageViewOnly:
            "On the \(name), press **Playback**, then the **Wi-Fi** button (on some models: Menu → **Wireless Communication**)."
        case .remote:
            "On the \(name), press **Playback**, then choose **Wireless Communication** (Wi-Fi button, or Menu → Connection Setting)."
        case .remoteNew:
            "On the \(name), open the **Playback** menu and choose **Wireless Communication**. If it offers Bluetooth pairing, skip it."
        case nil:
            "On the camera, press **Playback**, then choose **Wireless Communication** (Wi-Fi button, or Menu → Connection Setting)."
        }
    }

    private var name: String { cameraName.flatMap { $0.isEmpty ? nil : $0 } ?? "camera" }
}
