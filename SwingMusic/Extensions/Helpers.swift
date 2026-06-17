import SwiftUI
import UIKit

extension Color {
    init?(hex: String) {
        let h = hex.trimmingCharacters(in: .alphanumerics.inverted)
        var i: UInt64 = 0
        Scanner(string: h).scanHexInt64(&i)
        guard h.count == 6 else { return nil }
        self.init(
            red: Double((i >> 16) & 0xFF) / 255,
            green: Double((i >> 8) & 0xFF) / 255,
            blue: Double(i & 0xFF) / 255
        )
    }

    init?(rgbString: String) {
        let nums = rgbString
            .replacingOccurrences(of: "rgb(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .split(separator: ",")
            .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard nums.count == 3 else { return nil }
        self.init(red: nums[0] / 255, green: nums[1] / 255, blue: nums[2] / 255)
    }

    func adjust(brightness: Double) -> Color {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return Color(UIColor(hue: h, saturation: min(1, s * 1.1), brightness: min(1, b + brightness), alpha: a))
    }
}

struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

extension View {
    func trackScrollOffset(in space: String = "scroll", onChange: @escaping (CGFloat) -> Void) -> some View {
        self.background(
            GeometryReader { geo in
                Color.clear.preference(key: ScrollOffsetKey.self, value: geo.frame(in: .named(space)).minY)
            }
        )
        .onPreferenceChange(ScrollOffsetKey.self, perform: onChange)
    }
}

extension Int {
    var mmss: String {
        let m = self / 60, s = self % 60
        return String(format: "%d:%02d", m, s)
    }
}

extension Double {
    var mmss: String { Int(self).mmss }
}

extension View {
    func glass(_ radius: CGFloat = 16) -> some View {
        self
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
            )
    }

    func liquidGlass(_ radius: CGFloat = 16) -> some View {
        self
            .background {
                GlassBlurView(radius: radius)
                    .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            }
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(.white.opacity(0.22), lineWidth: 0.8)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .inset(by: 1)
                    .stroke(.white.opacity(0.08), lineWidth: 0.6)
            )
    }

    func nativeCard(_ radius: CGFloat = 18) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(.white.opacity(0.05), lineWidth: 0.5)
            )
    }
}

struct GlassBlurView: UIViewRepresentable {
    var radius: CGFloat = 16

    func makeUIView(context: Context) -> UIVisualEffectView {
        let blur = UIBlurEffect(style: .systemUltraThinMaterialDark)
        let v = UIVisualEffectView(effect: blur)
        v.clipsToBounds = true
        v.isUserInteractionEnabled = false
        return v
    }

    func updateUIView(_ v: UIVisualEffectView, context: Context) {}
}

struct Pressed: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension Color {
    static var primaryText: Color { Color(.label) }
    static var secondaryText: Color { Color(.secondaryLabel) }
    static var tertiaryText: Color { Color(.tertiaryLabel) }
    static var adaptiveBackground: Color { Color(.systemBackground) }
    static var secondaryBackground: Color { Color(.secondarySystemBackground) }
}

struct ThinSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    var onEditingChanged: ((Bool) -> Void)? = nil
    var trackHeight: CGFloat = 4
    var activeColor: Color = .white.opacity(0.9)
    var inactiveColor: Color = .white.opacity(0.15)
    var expandOnDrag: Bool = true

    @State private var isDragging = false

    var body: some View {
        GeometryReader { geo in
            let total = geo.size.width
            let fraction = (value - range.lowerBound) / max(range.upperBound - range.lowerBound, 0.001)
            let filled = total * min(max(CGFloat(fraction), 0), 1)
            let height: CGFloat = isDragging && expandOnDrag ? 7 : trackHeight

            ZStack(alignment: .leading) {

                Capsule()
                    .fill(inactiveColor)
                    .frame(height: height)

                Capsule()
                    .fill(activeColor)
                    .frame(width: max(height, filled), height: height)
            }
            .frame(height: 24)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        if !isDragging {
                            isDragging = true
                            onEditingChanged?(true)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                        let frac = Double(drag.location.x / total)
                        let clamped = min(max(frac, 0), 1)
                        value = range.lowerBound + clamped * (range.upperBound - range.lowerBound)
                    }
                    .onEnded { _ in
                        isDragging = false
                        onEditingChanged?(false)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
            )
            .animation(.easeOut(duration: 0.15), value: isDragging)
        }
        .frame(height: 24)
    }
}
