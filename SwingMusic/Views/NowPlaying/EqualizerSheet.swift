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
                    .blur(radius: isDragging ? 1.5 : 0)
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

struct EqualizerSheet: View {
    @ObservedObject var eq = Equalizer.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) var colorScheme

    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle(isOn: $eq.enabled) {
                        HStack {
                            Image(systemName: "slider.vertical.3")
                                .foregroundStyle(.blue)
                            Text("Equalizer")
                        }
                    }
                    .tint(.blue)
                }

                Section {
                    VStack(spacing: 20) {
                        HStack {
                            Text("Bass")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("Treble")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.secondary)
                        }

                        HStack(alignment: .bottom, spacing: 18) {
                            ForEach(0..<5, id: \.self) { i in
                                VStack(spacing: 14) {
                                    Text("\(Int(eq.bands[i]))")
                                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                                        .foregroundStyle(.primary.opacity(eq.enabled ? (eq.bands[i] == 0 ? 0.4 : 1.0) : 0.15))
                                        .frame(height: 20)

                                    VerticalLiquidSlider(value: Binding(
                                        get: { eq.bands[i] },
                                        set: { eq.bands[i] = $0; eq.selectedPreset = nil }
                                    ), enabled: eq.enabled)
                                    .frame(width: 48, height: 280)

                                    Text(eq.bandLabels[i])
                                        .font(.system(size: 11, weight: .black))
                                        .foregroundStyle(.primary.opacity(eq.enabled ? 0.8 : 0.15))
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                    }
                    .padding(.vertical, 16)
                    .opacity(eq.enabled ? 1 : 0.4)
                }

                Section(header: Text("Presets")) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(Equalizer.presets) { preset in
                                Button {
                                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                    eq.applyPreset(preset)
                                } label: {
                                    Text(preset.name)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(eq.selectedPreset == preset ? .white : .primary)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(
                                            eq.selectedPreset == preset ? Color.blue : Color(.systemFill),
                                            in: Capsule()
                                        )
                                }
                                .buttonStyle(.plain)
                                .disabled(!eq.enabled)
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 4, bottom: 8, trailing: 4))
                    .opacity(eq.enabled ? 1 : 0.3)
                }
            }
            .scrollContentBackground(.hidden)

            .contentMargins(.bottom, 40, for: .scrollContent)
            .navigationTitle("Equalizer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
