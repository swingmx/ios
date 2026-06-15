import SwiftUI

struct LyricsView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ZStack {
            if state.loadingLyrics {
                VStack(spacing: 14) {
                    ProgressView().tint(.white)
                    Text("Loading lyrics...").font(.system(size: 14)).foregroundStyle(.white.opacity(0.3))
                }
            } else if let lyrics = state.lyrics, !lyrics.lines.isEmpty {
                if lyrics.synced {
                    SyncedLyricsView(lyrics: lyrics, index: state.lyricIdx) { state.player.seek($0) }
                } else {
                    StaticLyricsView(lyrics: lyrics)
                }
            } else if state.player.current != nil {
                VStack(spacing: 20) {
                    VStack(spacing: 12) {
                        Image(systemName: "music.note")
                            .font(.system(size: 32)).foregroundStyle(.white.opacity(0.1))
                        Text("No lyrics available")
                            .font(.system(size: 15, weight: .medium)).foregroundStyle(.white.opacity(0.2))
                    }

                    Button {
                        Task { await state.forceSearchLyrics() }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                            Text("Search on Server")
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.vertical, 10)
                        .padding(.horizontal, 20)
                        .background(.white.opacity(0.08))
                        .clipShape(Capsule())
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SyncedLyricsView: View {
    let lyrics: ParsedLyrics
    let index: Int
    @EnvironmentObject var state: AppState
    @ObservedObject var player = AudioPlayer.shared
    var onSeek: (Double) -> Void
    @State private var userScrolledAway = false
    @State private var autoScrollEnabled = true

    var body: some View {
        GeometryReader { geo in
            ScrollViewReader { proxy in
                ZStack(alignment: .bottom) {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 0) {
                            Spacer().frame(height: 60)

                            ForEach(Array(lyrics.lines.enumerated()), id: \.element.id) { i, line in
                                let isActive = i == index
                                let isPast = i < index

                                let isBg = line.text.hasPrefix("(")
                                ZStack(alignment: isBg ? .trailing : .leading) {
                                    composedText(for: line, isActive: isActive, isPast: isPast, isBg: isBg)
                                        .font(.system(size: isBg ? 26 : 34, weight: .bold, design: .default))
                                }

                                .compositingGroup()
                                .scaleEffect(isActive ? 1.0 : 0.92, anchor: isBg ? .trailing : .leading)
                                .blur(radius: isActive ? 0 : (abs(i - index) > 2 ? 2.5 : 1.5))
                                .opacity(isActive ? 1.0 : (abs(i - index) > 2 ? 0.3 : 0.5))

                                .geometryGroup()
                                .frame(width: geo.size.width - 48, alignment: isBg ? .trailing : .leading)
                                .padding(.vertical, isBg ? 6 : 10)
                                .padding(.horizontal, 24)
                                .id(i)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    onSeek(line.time)
                                    autoScrollEnabled = true
                                    userScrolledAway = false
                                }

                                .animation(
                                    .spring(response: 0.6, dampingFraction: 1.0)
                                        .delay(Double(min(abs(i - index), 4)) * 0.03),
                                    value: index
                                )
                            }

                            if let cr = lyrics.copyright, !cr.isEmpty {
                                Text(cr)
                                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.12))
                                    .multilineTextAlignment(.center)
                                    .padding(.top, 32).padding(.horizontal, 24)
                            }

                            Spacer().frame(height: geo.size.height / 2)
                        }
                        .frame(width: geo.size.width)
                    }
                    .clipped()
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 10)
                            .onChanged { _ in
                                autoScrollEnabled = false
                                userScrolledAway = true
                            }
                    )
                    .onChange(of: index) { _, idx in
                        guard autoScrollEnabled else { return }

                        withAnimation(.spring(response: 0.6, dampingFraction: 1.0)) {
                            proxy.scrollTo(idx, anchor: UnitPoint(x: 0.5, y: 0.35))
                        }
                    }

                    if userScrolledAway {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            autoScrollEnabled = true
                            userScrolledAway = false
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                proxy.scrollTo(index, anchor: UnitPoint(x: 0.5, y: 0.35))
                            }
                        } label: {
                            HStack(spacing: 7) {
                                Image(systemName: "arrow.down.circle.fill")
                                Text("Back to Now")
                            }
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.vertical, 14)
                            .padding(.horizontal, 22)
                            .modifier(AccentLiquidGlassBackground())
                        }

                        .buttonStyle(.plain)
                        .shadow(color: .black.opacity(0.35), radius: 16, y: 6)
                        .padding(.bottom, 40)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: userScrolledAway)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func composedText(for line: LyricLine, isActive: Bool, isPast: Bool, isBg: Bool) -> some View {

        let words = line.words ?? []

        if !words.isEmpty {
            WordLayout {
                ForEach(Array(words.enumerated()), id: \.element.id) { i, word in
                    let isLast = i == words.count - 1
                    let duration = isLast ? max(0.4, (line.time + 3.0) - word.time) : (words[i+1].time - word.time)

                    KaraokeWord(
                        text: word.text,
                        startTime: word.time,
                        duration: duration,
                        hasSpace: word.hasSpace,
                        isBg: isBg,
                        isActive: isActive,
                        isPast: isPast
                    )
                }
            }
            .lineLimit(nil)
            .multilineTextAlignment(isBg ? .trailing : .leading)
            .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(line.text)
                .foregroundStyle(isActive ? .white : .white.opacity(isPast ? 0.35 : 0.3))
                .blur(radius: isActive ? 0 : (isPast ? 0 : 1.2))
                .lineLimit(nil)
                .multilineTextAlignment(isBg ? .trailing : .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct KaraokeWord: View {
    let text: String
    let startTime: Double
    let duration: Double
    let hasSpace: Bool
    let isBg: Bool
    var isActive: Bool = true
    var isPast: Bool = false

    @ObservedObject private var player = AudioPlayer.shared

    private var fontSize: Double { isBg ? 26 : 34 }
    private var emphasized: Bool { duration >= 1.0 && !text.isEmpty }

    var body: some View {
        Group {
            if isActive {
                TimelineView(.animation) { context in
                    let now = player.smoothTime(at: context.date)
                    let fill = min(max((now - startTime) / max(duration, 0.1), 0), 1)

                    Group {
                        if emphasized {
                            emphasizedWord(now: now, fill: fill)
                        } else {
                            plainWord(fill: fill)
                        }
                    }
                }
            } else {

                Text(text)
                    .foregroundStyle(Color.white.opacity(isPast ? 0.35 : 0.3))
            }
        }
        .padding(.trailing, hasSpace ? (isBg ? 6 : 8) : 0)
    }

    private func plainWord(fill: Double) -> some View {
        Text(text)
            .foregroundStyle(Color.white.opacity(0.28))
            .overlay {
                Text(text)
                    .foregroundStyle(Color.white)
                    .mask { fillGradient(fill) }
            }
    }

    private func emphasizedWord(now: Double, fill: Double) -> some View {
        Text(text)
            .opacity(0)
            .overlay(alignment: .leading) {
                ZStack(alignment: .leading) {
                    charRow(now: now, bright: false)
                    charRow(now: now, bright: true)
                        .mask { fillGradient(fill) }
                }
                .fixedSize(horizontal: true, vertical: false)
            }
    }

    private func charRow(now: Double, bright: Bool) -> some View {
        let chars = Array(text)
        let n = max(chars.count, 1)
        let amount = min(1.2, 0.55 * duration)
        let pB = (now - startTime) / max(duration, 0.1)

        return HStack(spacing: 0) {
            ForEach(0..<chars.count, id: \.self) { i in
                let center = (Double(i) + 0.5) / Double(n)
                let x = (pB - center) / 0.4
                let b = max(0, 1 - x * x)
                let s = b * amount
                Text(String(chars[i]))
                    .foregroundStyle(bright ? Color.white : Color.white.opacity(0.28))
                    .shadow(color: bright ? Color.white.opacity(0.5 * s) : .clear,
                            radius: bright ? 6 * s : 0)
                    .scaleEffect(1 + 0.1 * s, anchor: .bottom)
                    .offset(y: -0.07 * fontSize * s)
            }
        }
    }

    private func fillGradient(_ fill: Double) -> LinearGradient {

        let edge = fill * 1.12
        return LinearGradient(
            stops: [
                .init(color: .black, location: 0),
                .init(color: .black, location: min(1, max(0, edge - 0.12))),
                .init(color: .clear, location: min(1, edge)),
                .init(color: .clear, location: 1)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

struct WordLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        var w: CGFloat = 0, h: CGFloat = 0, rowH: CGFloat = 0, rowW: CGFloat = 0
        for sz in sizes {
            if rowW + sz.width > (proposal.width ?? .infinity) {
                w = max(w, rowW)
                h += rowH + 10
                rowW = 0
                rowH = 0
            }
            if sz.width > 0 {
                rowW += sz.width
            }
            rowH = max(rowH, sz.height)
        }
        w = max(w, rowW)
        h += rowH
        return CGSize(width: w, height: h)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        for (i, v) in subviews.enumerated() {
            let sz = sizes[i]
            if x + sz.width > bounds.maxX {
                x = bounds.minX
                y += rowH + 10
                rowH = 0
            }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
            if sz.width > 0 {
                x += sz.width
            }
            rowH = max(rowH, sz.height)
        }
    }
}

struct GlassButton: UIViewRepresentable {
    func makeUIView(context: Context) -> UIVisualEffectView {
        let blur = UIBlurEffect(style: .systemUltraThinMaterialDark)
        let v = UIVisualEffectView(effect: blur)
        v.layer.cornerCurve = .continuous

        let highlight = CAGradientLayer()
        highlight.colors = [
            UIColor.white.withAlphaComponent(0.25).cgColor,
            UIColor.white.withAlphaComponent(0.05).cgColor,
            UIColor.clear.cgColor
        ]
        highlight.locations = [0, 0.3, 1]
        highlight.startPoint = CGPoint(x: 0.5, y: 0)
        highlight.endPoint = CGPoint(x: 0.5, y: 1)
        highlight.cornerRadius = v.layer.cornerRadius
        v.layer.addSublayer(highlight)

        let border = CAShapeLayer()
        border.strokeColor = UIColor.white.withAlphaComponent(0.18).cgColor
        border.fillColor = nil
        border.lineWidth = 0.5
        v.layer.addSublayer(border)

        v.tag = 100
        return v
    }

    func updateUIView(_ v: UIVisualEffectView, context: Context) {
        DispatchQueue.main.async {
            let bounds = v.bounds
            guard bounds.size != .zero else { return }
            v.layer.cornerRadius = bounds.height / 2

            if let highlight = v.layer.sublayers?.first(where: { $0 is CAGradientLayer }) as? CAGradientLayer {
                highlight.frame = bounds
                highlight.cornerRadius = bounds.height / 2
            }
            if let border = v.layer.sublayers?.first(where: { $0 is CAShapeLayer }) as? CAShapeLayer {
                border.path = UIBezierPath(roundedRect: bounds.insetBy(dx: 0.25, dy: 0.25), cornerRadius: bounds.height / 2).cgPath
                border.frame = bounds
            }
        }
    }
}

struct StaticLyricsView: View {
    let lyrics: ParsedLyrics

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 6) {
                Spacer(minLength: 40)
                ForEach(lyrics.lines) { line in
                    if line.text.isEmpty {
                        Spacer(minLength: 16)
                    } else {
                        Text(line.text)
                            .font(.system(size: 19, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))
                            .lineSpacing(8)
                    }
                }
                if let cr = lyrics.copyright, !cr.isEmpty {
                    Text(cr).font(.system(size: 11)).foregroundStyle(.white.opacity(0.12))
                        .padding(.top, 24)
                }
                Spacer(minLength: 40)
            }
            .padding(.horizontal, 24)
        }
    }
}

private struct AccentLiquidGlassBackground: ViewModifier {
    private let accent = Color(red: 1.0, green: 0.216, blue: 0.373)

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.tint(accent).interactive(), in: Capsule(style: .continuous))
        } else {
            content
                .background(accent, in: Capsule(style: .continuous))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(.white.opacity(0.22), lineWidth: 0.6)
                )
        }
    }
}
