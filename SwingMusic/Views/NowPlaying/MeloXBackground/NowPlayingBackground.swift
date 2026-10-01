import SwiftUI

struct NowPlayingBackground: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    let artworkURL: URL?
    var beatTimeline: PlaybackBeatTimeline? = nil
    var isMotionPaused: Bool = false

    @State private var artwork: UIImage?

    private let motionIntensity: Double = 1.0
    private let saturation: Double = 0.82
    private let blurRadius: Double = 90

    @State private var flowingLightPalette: ArtworkFlowingLightPalette = .fallback

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black

                backgroundContent(in: proxy.size)
                    .transition(.opacity)

                Color.black.opacity(backgroundVeilOpacity)

                LinearGradient(
                    colors: legibilityGradientColors,
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .frame(
                width: proxy.size.width,
                height: proxy.size.height
            )
            .clipped()
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .task(id: artworkURL) {
            await loadArtwork()
            await loadFlowingLightPalette()
        }
    }

    @ViewBuilder
    private func backgroundContent(in size: CGSize) -> some View {
        NowPlayingFlowingLightBackground(
            palette: flowingLightPalette,
            motionIntensity: motionIntensity,
            saturation: saturation,
            beatEffectsEnabled: false,
            isMotionPaused: isMotionPaused
        )
        .frame(width: size.width, height: size.height)
    }

    private var backgroundVeilOpacity: Double { 0.02 }

    private var legibilityGradientColors: [Color] {
        [
            .black.opacity(0.015),
            .black.opacity(0.05),
            .black.opacity(0.36),
        ]
    }

    private func loadArtwork() async {
        guard let artworkURL else { artwork = nil; return }
        var req = URLRequest(url: artworkURL)
        if let tk = API.shared.token { req.setValue("Bearer \(tk)", forHTTPHeaderField: "Authorization") }
        guard let (data, _) = try? await Net.session.data(for: req),
              let img = UIImage(data: data) else { return }
        artwork = img
    }

    private func loadFlowingLightPalette() async {
        guard let artwork else { return }
        let palette = await Task.detached(priority: .userInitiated) {
            FlowingLightPaletteBuilder.palette(from: artwork)
        }.value

        guard !Task.isCancelled, palette != flowingLightPalette else { return }
        withAnimation(accessibilityReduceMotion ? nil : .easeInOut(duration: 0.8)) {
            flowingLightPalette = palette
        }
    }
}
