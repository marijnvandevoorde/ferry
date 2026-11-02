import SwiftUI

struct ContentView: View {
    @Environment(CameraModel.self) private var model

    var body: some View {
        Group {
            switch model.phase {
            case .connected:
                GalleryView()
            case .searching, .connecting, .waitingForApproval:
                ConnectView()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: model.phase)
    }
}
