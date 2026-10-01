import SwiftUI

struct VerticalLiquidSlider: View {
    @Binding var value: Float
    let range: ClosedRange<Float> = -12...12
    let step: Float = 2
    var enabled: Bool = true
    @Environment(\.colorScheme) var colorScheme

    @State private var isDragging = false

    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let w = geo.size.width

            let fraction = CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound))
            let fillH = h * fraction

            ZStack(alignment: .bottom) {
                ZStack(alignment: .center) {
                    Capsule()
                        .fill(isDark ? .white.opacity(0.08) : .black.opacity(0.06))

                    VStack {
                        Text("+12")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.secondary.opacity(0.5))
                            .padding(.top, 14)
                        Spacer()
                        Text("-12")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.secondary.opacity(0.5))
                            .padding(.bottom, 14)
                    }

                    VStack(spacing: 0) {
                        ForEach(0...12, id: \.self) { i in
                            let val = 12 - (i * 2)
                            let isZero = val == 0

                            Rectangle()
                                .fill(isZero ? (isDark ? .white.opacity(0.8) : .black.opacity(0.3)) : (isDark ? .white.opacity(0.12) : .black.opacity(0.08)))
                                .frame(width: isZero ? w * 0.8 : w * 0.4, height: isZero ? 1.5 : 0.8)

                            if i < 12 { Spacer() }
                        }
                    }
                    .padding(.vertical, 30)
                }
                .frame(width: w)

                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                enabled ? .blue : .gray.opacity(0.5),
                                enabled ? .blue.opacity(0.6) : .gray.opacity(0.3)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: w, height: max(w, fillH))
                    .clipShape(RoundedRectangle(cornerRadius: value == 0 ? 4 : w / 2, style: .continuous))
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: value == 0)

                if isDragging {
                    Text("\(Int(value))")
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(.blue, in: Circle())
                        .offset(x: w + 20, y: -(fillH))
                        .shadow(radius: 4)
                }
            }
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(isDark ? .white.opacity(0.12) : .black.opacity(0.08), lineWidth: 0.5)
            )
            .overlay(alignment: .bottom) {
                let ballSize = w * 0.9
                let ballR = ballSize / 2
                let thumbCenter = min(max(fillH, ballR), h - ballR)
                GlassBall(size: ballSize, pressed: isDragging)
                    .offset(y: -(thumbCenter - ballR))
                    .allowsHitTesting(false)
                    .animation(.interactiveSpring(response: 0.35, dampingFraction: 0.75), value: value)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        guard enabled else { return }
                        if !isDragging {
                            isDragging = true
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }

                        let touchY = gesture.location.y
                        let rawFrac = 1.0 - (touchY / h)
                        let clampedFrac = min(max(rawFrac, 0), 1)
                        let rawValue = range.lowerBound + Float(clampedFrac) * (range.upperBound - range.lowerBound)

                        var steppedValue = round(rawValue / step) * step
                        if abs(rawValue) < 0.8 { steppedValue = 0 }

                        let finalValue = min(max(steppedValue, range.lowerBound), range.upperBound)

                        if finalValue != value {
                            value = finalValue
                            if finalValue == 0 {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            } else {
                                UISelectionFeedbackGenerator().selectionChanged()
                            }
                        }
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
            .animation(.interactiveSpring(response: 0.35, dampingFraction: 0.75), value: value)
            .animation(.easeOut(duration: 0.15), value: isDragging)
        }
    }
}

private struct GlassBall: View {
    let size: CGFloat
    let pressed: Bool

    var body: some View {
        ball
            .frame(width: size, height: size)
            .scaleEffect(pressed ? 1.1 : 1.0)
            .shadow(color: .black.opacity(0.16), radius: pressed ? 6 : 3, y: pressed ? 3 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.65), value: pressed)
    }

    @ViewBuilder private var ball: some View {
        if #available(iOS 26.0, *) {
            Circle()
                .fill(.clear)
                .glassEffect(.clear.interactive(), in: Circle())
        } else {
            Circle().fill(.ultraThinMaterial)
        }
    }
}

struct EqualizerSheet: View {
    var body: some View {
        NavigationStack { EqualizerView(isSheet: true) }
            .presentationSizing(.form)
    }
}

struct EqualizerView: View {
    var isSheet = false
    @ObservedObject var eq = Equalizer.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Equalizer", isOn: $eq.enabled.animation(.smooth))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .glassEffect(.regular, in: .rect(cornerRadius: 26))
                Text("Adjusts the sound for all songs.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)

                VStack(spacing: 18) {
                    HStack {
                        Text(eq.selectedPreset?.name ?? (eq.bands.allSatisfy { $0 == 0 } ? "Flat" : "Custom"))
                            .font(.headline)
                        Spacer()
                    }
                    EqualizerGraph(bands: $eq.bands, labels: eq.bandLabels, enabled: eq.enabled) {
                        eq.selectedPreset = nil
                    }
                    .frame(height: 250)
                    presetChips
                }
                .padding(16)
                .glassEffect(.regular, in: .rect(cornerRadius: 26))
                .padding(.top, 20)
                .disabled(!eq.enabled)
                .opacity(eq.enabled ? 1 : 0.4)
            }
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Equalizer")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Reset") {
                    withAnimation(.smooth(duration: 0.35)) {
                        if let flat = Equalizer.presets.first(where: { $0.id == "flat" }) { eq.applyPreset(flat) }
                    }
                }
                .disabled(!eq.enabled || eq.bands.allSatisfy { $0 == 0 })
            }
            if isSheet {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", role: .confirm) { dismiss() }
                }
            }
        }
    }

    private var presetChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(Equalizer.presets) { preset in
                    let selected = eq.selectedPreset == preset
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        withAnimation(.smooth(duration: 0.4)) { eq.applyPreset(preset) }
                    } label: {
                        Text(preset.name)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .foregroundStyle(selected ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(selected ? .regular.tint(.accentColor).interactive() : .regular.interactive(), in: .capsule)
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            }
        }
        .padding(.horizontal, -16)
        .contentMargins(.horizontal, 16, for: .scrollContent)
    }
}

struct EqualizerGraph: View {
    @Binding var bands: [Float]
    let labels: [String]
    let enabled: Bool
    var onEdit: () -> Void = {}

    private let range: ClosedRange<Float> = -12...12
    @State private var dragging: Int?

    var body: some View {
        GeometryReader { geo in
            let labelH: CGFloat = 22
            let w = geo.size.width
            let h = geo.size.height - labelH
            let knob: CGFloat = 26
            let insetY = knob / 2 + 4
            let plotH = h - insetY * 2
            let xs = (0..<bands.count).map { w * (CGFloat($0) + 0.5) / CGFloat(bands.count) }
            let y: (Float) -> CGFloat = { v in
                insetY + plotH * (1 - CGFloat((v - range.lowerBound) / (range.upperBound - range.lowerBound)))
            }
            let points = zip(xs, bands).map { CGPoint(x: $0, y: y($1)) }
            let curve = Self.curvePath(points, width: w)

            ZStack(alignment: .topLeading) {
                ForEach([12, 6, 0, -6, -12], id: \.self) { db in
                    let yy = y(Float(db))
                    Path { p in p.move(to: CGPoint(x: 0, y: yy)); p.addLine(to: CGPoint(x: w, y: yy)) }
                        .stroke(.secondary.opacity(db == 0 ? 0.45 : 0.15),
                                style: StrokeStyle(lineWidth: db == 0 ? 1 : 0.5, dash: db == 0 ? [] : [2, 4]))
                    Text(db > 0 ? "+\(db)" : "\(db)")
                        .font(.system(size: 9, weight: .medium).monospacedDigit())
                        .foregroundStyle(.tertiary)
                        .position(x: 12, y: yy - 7)
                }
                ForEach(xs.indices, id: \.self) { i in
                    Path { p in p.move(to: CGPoint(x: xs[i], y: insetY)); p.addLine(to: CGPoint(x: xs[i], y: insetY + plotH)) }
                        .stroke(.secondary.opacity(dragging == i ? 0.4 : 0.1), lineWidth: 1)
                }

                var fill = curve
                let _ = fill.addLine(to: CGPoint(x: w, y: insetY + plotH))
                let _ = fill.addLine(to: CGPoint(x: 0, y: insetY + plotH))
                let _ = fill.closeSubpath()
                fill.fill(LinearGradient(colors: [Color.accentColor.opacity(0.35), Color.accentColor.opacity(0.02)],
                                         startPoint: .top, endPoint: .bottom))
                curve.stroke(Color.accentColor.opacity(0.35), lineWidth: 10).blur(radius: 8)
                curve.stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

                ForEach(points.indices, id: \.self) { i in
                    let active = dragging == i
                    Capsule()
                        .fill(active ? Color.clear : Color.white)
                        .glassEffect(active ? .clear.interactive() : .regular.interactive(), in: .capsule)
                        .frame(width: active ? knob * 1.9 : knob * 1.45, height: active ? knob * 1.3 : knob)
                        .shadow(color: .black.opacity(active ? 0.12 : 0.25), radius: active ? 8 : 3, y: active ? 4 : 1)
                        .animation(.spring(response: 0.3, dampingFraction: 0.65), value: active)
                        .position(points[i])
                    .overlay(alignment: .topLeading) {
                        if dragging == i {
                            Text(EqualizerView.gainText(bands[i]))
                                .font(.caption.weight(.bold).monospacedDigit())
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .glassEffect(.regular, in: .capsule)
                                .position(x: points[i].x, y: max(12, points[i].y - 30))
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                }

                ForEach(xs.indices, id: \.self) { i in
                    Text(labels[i] + " Hz")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(dragging == i ? Color.accentColor : .secondary)
                        .position(x: xs[i], y: h + labelH / 2)
                }
            }
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        guard enabled else { return }
                        let i = dragging ?? min(bands.count - 1, max(0, Int(g.startLocation.x / (w / CGFloat(bands.count)))))
                        if dragging == nil {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { dragging = i }
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                        let frac = 1 - (g.location.y - insetY) / plotH
                        let raw = range.lowerBound + Float(min(max(frac, 0), 1)) * (range.upperBound - range.lowerBound)
                        let v = raw.rounded()
                        if v != bands[i] {
                            bands[i] = v
                            onEdit()
                            v == 0 ? UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                   : UISelectionFeedbackGenerator().selectionChanged()
                        }
                    }
                    .onEnded { _ in
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { dragging = nil }
                    }
            )
            .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.8), value: bands)
        }
    }

    static func curvePath(_ pts: [CGPoint], width: CGFloat) -> Path {
        Path { p in
            guard let first = pts.first, let last = pts.last else { return }
            p.move(to: CGPoint(x: 0, y: first.y))
            p.addLine(to: first)
            for k in 1..<pts.count {
                let a = pts[k - 1], b = pts[k]
                let mid = (a.x + b.x) / 2
                p.addCurve(to: b, control1: CGPoint(x: mid, y: a.y), control2: CGPoint(x: mid, y: b.y))
            }
            p.addLine(to: CGPoint(x: width, y: last.y))
        }
    }
}

extension EqualizerView {
    static func gainText(_ v: Float) -> String {
        v == 0 ? "0 dB" : String(format: "%+.0f dB", v)
    }
}
