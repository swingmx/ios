import SwiftUI
import AVKit

struct SheetBlurBackground: View {
    var image: UIImage?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black
                if let img = image {
                    Image(uiImage: img)
                        .resizable().scaledToFill()
                        .frame(width: geo.size.width + 120, height: geo.size.height + 240)
                        .clipped()
                        .blur(radius: 60, opaque: true)
                        .opacity(0.6)
                }
                Color.black.opacity(0.4)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
        .ignoresSafeArea()
    }
}

struct AirPlayButton: UIViewRepresentable {
    var hidden = false
    /// Bumping this opens the route picker.
    var trigger = 0
    var onRouteChange: (() -> Void)?

    /// Picking any output in the app while another device plays moves playback to this phone.
    @MainActor
    final class Coordinator: NSObject, @preconcurrency AVRoutePickerViewDelegate {
        var trigger = 0
        var onRouteChange: (() -> Void)?
        private var route: [String] = []
        private var deadline = Date.distantPast

        private static var outputs: [String] { AVAudioSession.sharedInstance().currentRoute.outputs.map(\.uid) }

        override init() {
            super.init()
            NotificationCenter.default.addObserver(
                self, selector: #selector(routeChanged),
                name: AVAudioSession.routeChangeNotification, object: nil
            )
        }

        func routePickerViewWillBeginPresentingRoutes(_ v: AVRoutePickerView) {
            route = Self.outputs
            deadline = .distantFuture
        }

        func routePickerViewDidEndPresentingRoutes(_ v: AVRoutePickerView) {
            // AirPlay can take a few seconds to connect after the picker closes
            deadline = Date() + 10
            apply()
        }

        @objc nonisolated private func routeChanged() {
            Task { @MainActor in self.apply() }
        }

        private func apply() {
            guard Date() < deadline, Self.outputs != route else { return }
            deadline = .distantPast
            let remote = RemoteControl.shared
            guard remote.playingElsewhere != nil else { return }
            onRouteChange?()
            remote.transfer(to: remote.deviceID)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView()
        v.tintColor = hidden ? .clear : .label
        v.activeTintColor = hidden ? .clear : .systemBlue
        v.prioritizesVideoDevices = false
        v.delegate = context.coordinator
        return v
    }

    func updateUIView(_ v: AVRoutePickerView, context: Context) {
        context.coordinator.onRouteChange = onRouteChange
        guard trigger != context.coordinator.trigger else { return }
        context.coordinator.trigger = trigger
        (v.subviews.first { $0 is UIButton } as? UIButton)?.sendActions(for: .touchUpInside)
    }
}
