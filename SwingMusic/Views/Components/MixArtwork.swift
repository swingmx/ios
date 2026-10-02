import SwiftUI

// A mix's cover, matching the web client's MixImage. Artist mixes have one image of their own; track
// mixes are composed from up to three images (the source album, then artists) tinted with the first
// image's color and labelled with the mix type and title.
struct MixArtwork: View {
    let mix: Mix
    var cornerRadius: CGFloat = 12

    var body: some View {
        Group {
            if mix.hasOwnImage {
                Img(urls: mix.coverURLs, radius: 0, placeholderColor: mix.extra.image?.color)
            } else {
                composite
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var composite: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let side = h * 0.5
            let refs = Array((mix.extra.images ?? []).prefix(3))
            let tint = MixArtworkColors.parse(refs.first?.color)

            ZStack(alignment: .topLeading) {
                Color(.secondarySystemBackground)

                // Later images overlap earlier ones, each a quarter of the width further right.
                ForEach(Array(refs.enumerated()), id: \.offset) { i, ref in
                    Img(urls: Mix.imageURLs(for: ref), radius: 0, placeholderColor: ref.color)
                        .frame(width: side, height: side)
                        .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                        .offset(x: w * 0.25 * CGFloat(i), y: (h - side) / 2)
                }

                if let tint {
                    let color = tint.color
                    // CSS: linear-gradient(-17deg, c 10%, transparent 30%) under linear-gradient(27deg, c 21%, c/0.15).
                    gradient(cssDegrees: -17, stops: [.init(color: color, location: 0.10), .init(color: color.opacity(0), location: 0.30)])
                    gradient(cssDegrees: 27, stops: [.init(color: color, location: 0.21), .init(color: color.opacity(0.15), location: 1)])
                }

                // Too small to read on list rows, so the label only shows on cards and headers.
                if w >= 80 {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(mix.typeLabel)
                            .font(.system(size: w * 0.075, weight: .bold))
                            .foregroundStyle(tint.map { MixArtworkColors.typeColor(for: $0).color } ?? .secondary)
                        Text(mix.coverTitle)
                            .font(.system(size: w * 0.095, weight: .bold))
                            .foregroundStyle(tint.map { MixArtworkColors.textColor(for: $0).color } ?? .primary)
                            .lineLimit(1)
                    }
                    .padding(w * 0.05)
                    .frame(width: w, height: h, alignment: .bottomLeading)
                }
            }
        }
    }

    private func gradient(cssDegrees: Double, stops: [Gradient.Stop]) -> some View {
        let (start, end) = MixArtworkColors.gradientPoints(cssDegrees: cssDegrees)
        return LinearGradient(stops: stops, startPoint: start, endPoint: end)
    }
}

extension Mix {
    // Artist mixes carry their own image; track mixes only have the images used to compose one.
    var hasOwnImage: Bool { !(extra.image?.image ?? "").isEmpty }

    var coverURLs: [URL] {
        guard let file = extra.image?.image, !file.isEmpty else { return [] }
        return [API.shared.mixImg(file, size: "medium"), API.shared.img(file, size: "medium")].compactMap { $0 }
    }

    // Grid images use the large size (512px covers, 500px artists), which downloads keep offline.
    static func imageURL(for ref: MixImageRef) -> URL? {
        guard let file = ref.image, !file.isEmpty else { return nil }
        return ref.type == "artist" ? API.shared.artistImg(file, size: "") : API.shared.img(file, size: "")
    }

    // The large size first, then medium, which mixes downloaded before the large size was kept still have.
    static func imageURLs(for ref: MixImageRef) -> [URL] {
        guard let file = ref.image, !file.isEmpty else { return [] }
        let medium = ref.type == "artist" ? API.shared.artistImg(file, size: "medium") : API.shared.img(file, size: "medium")
        return [imageURL(for: ref), medium].compactMap { $0 }
    }

    // The image the mix page uses for its blurred background.
    var backgroundURLs: [URL] {
        hasOwnImage ? coverURLs : (extra.images ?? []).compactMap(Self.imageURL(for:)).prefix(1).map { $0 }
    }

    // Every image the mix's artwork shows, cached for offline use when the mix is downloaded.
    var offlineImageURLs: [URL] {
        var seen = Set<URL>()
        return (coverURLs + (extra.images ?? []).prefix(3).compactMap(Self.imageURL(for:)))
            .filter { seen.insert($0).inserted }
    }

    var typeLabel: String { "\((extra.type ?? "track").capitalized) Mix" }

    var coverTitle: String {
        title.replacingOccurrences(of: "Radio", with: "").trimmingCharacters(in: .whitespaces)
    }
}

// The web client's color rules (utils/colortools), so both clients tint mixes the same way.
enum MixArtworkColors {
    struct RGB: Equatable {
        var r: Double, g: Double, b: Double
        var color: Color { Color(red: r / 255, green: g / 255, blue: b / 255) }
    }

    // Accepts "rgb(r, g, b)" as the server sends it, and "#rrggbb".
    static func parse(_ string: String?) -> RGB? {
        guard let string else { return nil }
        let s = string.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#"), s.count == 7, let v = Int(s.dropFirst(), radix: 16) {
            return RGB(r: Double((v >> 16) & 0xFF), g: Double((v >> 8) & 0xFF), b: Double(v & 0xFF))
        }
        let parts = s.components(separatedBy: CharacterSet(charactersIn: "0123456789.").inverted)
            .compactMap(Double.init)
        guard s.lowercased().hasPrefix("rgb"), parts.count >= 3 else { return nil }
        return RGB(r: parts[0], g: parts[1], b: parts[2])
    }

    // Perceived brightness as a percentage (Rec. 709 luminance), as @nextcss/color-tools computes it.
    static func brightness(_ c: RGB) -> Int {
        Int(((0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b) / 255 * 100).rounded())
    }

    static func isLight(_ c: RGB) -> Bool { brightness(c) > 50 }

    // Positive amounts darken by that percentage, negative ones lighten toward white.
    static func shift(_ c: RGB, by amount: Double) -> RGB {
        let o = amount / 100
        func channel(_ v: Double) -> Double {
            let shifted = o < 0 ? v + (255 - v) * abs(o) : v - v * o
            return min(max(shifted.rounded(), 0), 255)
        }
        return RGB(r: channel(c.r), g: channel(c.g), b: channel(c.b))
    }

    static func textColor(for c: RGB) -> RGB { shift(c, by: isLight(c) ? 80 : -80) }

    static func typeColor(for c: RGB) -> RGB {
        isLight(c) ? RGB(r: 109, g: 69, b: 16) : RGB(r: 0xAC, g: 0x8E, b: 0x68)
    }

    // Start and end points for a CSS gradient angle (0° points up, clockwise) across a square.
    static func gradientPoints(cssDegrees: Double) -> (UnitPoint, UnitPoint) {
        let r = cssDegrees * .pi / 180
        let length = abs(sin(r)) + abs(cos(r))
        let dx = sin(r) * length / 2, dy = -cos(r) * length / 2
        return (UnitPoint(x: 0.5 - dx, y: 0.5 - dy), UnitPoint(x: 0.5 + dx, y: 0.5 + dy))
    }
}
