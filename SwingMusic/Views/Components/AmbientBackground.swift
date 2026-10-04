import SwiftUI
import CoreImage

struct AmbientBackground: View {
    @Environment(AppState.self) var state
    @Environment(\.colorScheme) var colorScheme
    @State private var rendered: UIImage?

    private var isDark: Bool { colorScheme == .dark }
    private static let height: CGFloat = 520

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                (isDark ? Color.black : Color(.systemGray5))

                if let rendered {
                    Image(uiImage: rendered)
                        .resizable()
                        .frame(width: geo.size.width, height: Self.height)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .transition(.opacity)

                    LinearGradient(
                        colors: isDark
                            ? [.black.opacity(0.35), .clear]
                            : [Color(.systemGray5).opacity(0.1),
                               Color(.systemGray5).opacity(0.45),
                               Color(.systemGray5).opacity(0.9)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: geo.size.height * (isDark ? 0.3 : 0.55))
                    .frame(maxHeight: .infinity, alignment: .top)
                }
            }
            .animation(.easeInOut(duration: 1.0), value: rendered)
            .task(id: RenderKey(image: state.currentBGImage, dark: isDark, width: Int(geo.size.width))) {
                guard let image = state.currentBGImage, geo.size.width > 0 else { rendered = nil; return }
                let size = CGSize(width: geo.size.width, height: Self.height)
                let dark = isDark
                rendered = await Task.detached(priority: .utility) {
                    AmbientBlur.render(image, size: size, dark: dark)
                }.value
            }
        }
        .ignoresSafeArea()
    }

    private struct RenderKey: Equatable {
        let image: UIImage?
        let dark: Bool
        let width: Int
    }
}

// The ambient background's look, rendered once into a small bitmap. Applying the blur, saturation
// and fade as live filters made Core Animation redo them every frame while lists scrolled over it.
enum AmbientBlur {
    // The result is a heavy blur, so it is rendered at a fraction of screen resolution and scaled up.
    private static let workScale: CGFloat = 0.25
    private static let context = CIContext(options: [.cacheIntermediates: false])

    static func render(_ image: UIImage, size: CGSize, dark: Bool) -> UIImage? {
        guard let input = CIImage(image: image) else { return nil }
        let target = CGSize(width: max(1, size.width * workScale), height: max(1, size.height * workScale))

        // Scale to fill the target, then crop the middle, like scaledToFill + clipped.
        let fill = max(target.width / input.extent.width, target.height / input.extent.height)
        let scaled = input.transformed(by: CGAffineTransform(scaleX: fill, y: fill))
        let crop = CGRect(x: scaled.extent.midX - target.width / 2, y: scaled.extent.midY - target.height / 2,
                          width: target.width, height: target.height)

        let blurred = scaled.clampedToExtent()
            .applyingGaussianBlur(sigma: (dark ? 80 : 120) * workScale)
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: dark ? 1.0 : 1.2])
            .cropped(to: crop)
        guard let cg = context.createCGImage(blurred, from: crop) else { return nil }

        // Bake in the 50% opacity and the fade towards the bottom.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: target, format: format).image { ctx in
            let rect = CGRect(origin: .zero, size: target)
            UIImage(cgImage: cg).draw(in: rect, blendMode: .normal, alpha: 0.5)
            let colors = [UIColor.black.cgColor, UIColor.black.cgColor, UIColor.clear.cgColor] as CFArray
            guard let fade = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.12, 0.92])
            else { return }
            ctx.cgContext.setBlendMode(.destinationIn)
            ctx.cgContext.drawLinearGradient(fade, start: .zero, end: CGPoint(x: 0, y: target.height), options: [])
        }
    }
}
