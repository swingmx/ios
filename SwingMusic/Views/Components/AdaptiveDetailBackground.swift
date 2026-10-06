import SwiftUI

struct AdaptiveDetailBackground: View {
    let image: UIImage?
    var blendHeight: CGFloat = 0.45
    // How far the screen has scrolled down; the image moves up by this much so it stays with the header.
    var scrollOffset: CGFloat = 0
    @Environment(\.colorScheme) var colorScheme

    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                (isDark ? Color.black : Color(.systemBackground))

                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: isDark ? 440 : 620)
                        .clipped()
                        .blur(radius: isDark ? 70 : 110, opaque: true)
                        .saturation(isDark ? 1.35 : 1.45)
                        .opacity(isDark ? 0.75 : 0.8)
                        .mask(
                            LinearGradient(
                                stops: isDark
                                    ? [.init(color: .black, location: 0),
                                       .init(color: .black, location: 0.45),
                                       .init(color: .clear, location: 1)]
                                    : [.init(color: .black, location: 0),
                                       .init(color: .black, location: 0.08),
                                       .init(color: .clear, location: 0.95)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .offset(y: -scrollOffset)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .ignoresSafeArea()

                    if isDark {
                        LinearGradient(
                            colors: [.black.opacity(0.18), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: geo.size.height * 0.25)
                        .frame(maxHeight: .infinity, alignment: .top)
                    }
                }
            }
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.8), value: image != nil)
    }
}

// The colors a detail screen takes from its artwork, like Apple Music's album pages: a deep version of
// the cover's main color for the whole page and a pale one for the Play button.
struct ArtworkPalette: Equatable {
    let background: Color
    let accent: Color

    private static var cache: [String: ArtworkPalette] = [:]

    // The server's color (as the web client uses it) when it has some color in it, otherwise the
    // most prominent hue of the cover.
    @MainActor
    static func make(image: UIImage?, serverColor: String?) -> ArtworkPalette? {
        let key = "\(serverColor ?? "")|\(image.map { "\(ObjectIdentifier($0).hashValue)" } ?? "")"
        if let hit = cache[key] { return hit }
        var hsb: (h: CGFloat, s: CGFloat, b: CGFloat)?
        if let server = serverColor.flatMap(parse), server.s >= 0.18, server.b >= 0.15 {
            hsb = server
        } else if let image {
            hsb = dominantHue(of: image)
        }
        guard let hsb else { return nil }
        let palette = from(hsb)
        cache[key] = palette
        return palette
    }

    private static func from(_ c: (h: CGFloat, s: CGFloat, b: CGFloat)) -> ArtworkPalette {
        let colorful = c.s >= 0.12
        // Keep the color's own character: vivid covers stay vivid, darker ones stay darker.
        let sat = colorful ? 0.38 + min(c.s, 1) * 0.42 : c.s * 0.5
        // Yellows and oranges turn muddy when dark, so they get more light.
        let warmth = colorful && c.h > 0.07 && c.h < 0.2 ? 0.1 : 0
        let bright = 0.22 + min(max(c.b, 0), 1) * 0.22 + warmth
        return ArtworkPalette(
            background: Color(hue: c.h, saturation: sat, brightness: bright),
            accent: Color(hue: c.h, saturation: colorful ? min(0.28 + c.s * 0.2, 0.45) : 0.04, brightness: 0.95)
        )
    }

    // "rgb(65, 171, 66)" or "#41ab42".
    private static func parse(_ string: String) -> (h: CGFloat, s: CGFloat, b: CGFloat)? {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        let nums = string.split(whereSeparator: { !"0123456789.".contains($0) }).compactMap { Double($0) }
        if string.lowercased().hasPrefix("rgb"), nums.count >= 3 {
            r = nums[0] / 255; g = nums[1] / 255; b = nums[2] / 255
        } else {
            let hex = string.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
            guard hex.count == 6, let v = UInt32(hex, radix: 16) else { return nil }
            r = CGFloat((v >> 16) & 0xFF) / 255; g = CGFloat((v >> 8) & 0xFF) / 255; b = CGFloat(v & 0xFF) / 255
        }
        return hsb(r, g, b)
    }

    private static func hsb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> (h: CGFloat, s: CGFloat, b: CGFloat) {
        var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0, a: CGFloat = 0
        UIColor(red: r, green: g, blue: b, alpha: 1).getHue(&h, saturation: &s, brightness: &v, alpha: &a)
        return (h, s, v)
    }

    // The hue that covers the most of the cover, weighted by how colorful each pixel is, then the
    // average color of just those pixels. Averaging the whole cover instead turns most into brown.
    private static func dominantHue(of image: UIImage) -> (h: CGFloat, s: CGFloat, b: CGFloat)? {
        guard let cg = image.cgImage else { return nil }
        let side = 40
        var px = [UInt8](repeating: 0, count: side * side * 4)
        guard let ctx = CGContext(data: &px, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))

        let buckets = 18
        var score = [Double](repeating: 0, count: buckets)
        var sums = [(r: Double, g: Double, b: Double, w: Double)](repeating: (0, 0, 0, 0), count: buckets)
        var gray = (r: 0.0, g: 0.0, b: 0.0, w: 0.0)
        for i in stride(from: 0, to: px.count, by: 4) {
            let r = CGFloat(px[i]) / 255, g = CGFloat(px[i + 1]) / 255, b = CGFloat(px[i + 2]) / 255
            let c = hsb(r, g, b)
            guard c.b > 0.12 else { continue }
            if c.s < 0.18 {
                gray.r += r; gray.g += g; gray.b += b; gray.w += 1
                continue
            }
            let k = min(Int(c.h * CGFloat(buckets)), buckets - 1)
            let w = Double(c.s * (0.4 + c.b))
            score[k] += w
            sums[k].r += Double(r) * w; sums[k].g += Double(g) * w; sums[k].b += Double(b) * w; sums[k].w += w
        }
        // Neighboring hues belong together (a red can straddle two buckets).
        var best = -1, bestScore = 0.0
        for k in 0..<buckets {
            let total = score[k] + 0.5 * (score[(k + buckets - 1) % buckets] + score[(k + 1) % buckets])
            if total > bestScore { bestScore = total; best = k }
        }
        let pixels = Double(side * side)
        // A hue must cover a fair part of the cover; a bit of skin on a black-and-white photo stays gray.
        if best >= 0, bestScore > pixels * 0.08, sums[best].w > 0 {
            let w = sums[best].w
            return hsb(CGFloat(sums[best].r / w), CGFloat(sums[best].g / w), CGFloat(sums[best].b / w))
        }
        guard gray.w > 0 else { return (0, 0, 0.3) }
        return hsb(CGFloat(gray.r / gray.w), CGFloat(gray.g / gray.w), CGFloat(gray.b / gray.w))
    }
}

private struct DetailTintKey: EnvironmentKey { static let defaultValue: Color? = nil }

extension EnvironmentValues {
    // The pale artwork color for a detail screen's Play button; nil uses the app's accent.
    var detailTint: Color? {
        get { self[DetailTintKey.self] }
        set { self[DetailTintKey.self] = newValue }
    }
}

// The detail screens' background: the whole page in the artwork's color once the cover has loaded,
// with the blurred cover fading out behind the header, as on Apple Music's album pages.
private struct DetailBackground: ViewModifier {
    let image: UIImage?
    var serverColor: String?
    @State private var scrolled: CGFloat = 0
    @State private var palette: ArtworkPalette?

    func body(content: Content) -> some View {
        content
            .environment(\.detailTint, palette?.accent)
            .tint(palette?.accent)
            .environment(\.colorScheme, palette == nil ? colorSchemeFallback : .dark)
            .onScrollGeometryChange(for: CGFloat.self) { geo in
                max(0, geo.contentOffset.y + geo.contentInsets.top)
            } action: { _, value in
                scrolled = value
            }
            .background {
                if let palette {
                    ZStack(alignment: .top) {
                        palette.background
                        LinearGradient(colors: [.white.opacity(0.06), .clear, .black.opacity(0.18)],
                                       startPoint: .top, endPoint: .bottom)
                    }
                    .ignoresSafeArea()
                    .transition(.opacity)
                } else {
                    AdaptiveDetailBackground(image: image, scrollOffset: scrolled)
                }
            }
            .animation(.easeInOut(duration: 0.5), value: palette)
            .task(id: "\(serverColor ?? "")|\(image.map { "\(ObjectIdentifier($0).hashValue)" } ?? "")") {
                palette = ArtworkPalette.make(image: image, serverColor: serverColor)
            }
    }

    @Environment(\.colorScheme) private var colorSchemeFallback
}

extension View {
    func detailBackground(_ image: UIImage?, color: String? = nil) -> some View {
        modifier(DetailBackground(image: image, serverColor: color))
    }
}
