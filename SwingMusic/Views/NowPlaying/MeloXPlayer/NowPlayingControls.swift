import MediaPlayer
import SwiftUI

struct NowPlayingProgressControl: View {
    @Environment(PlayerStore.self) private var player

    let song: Song

    @State private var scrubValue: Double = 0
    @State private var isScrubbing = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !player.isPlaying || isScrubbing)) { context in
            content(at: context.date)
        }
    }

    private func content(at date: Date) -> some View {
        let live = min(player.estimatedProgress(at: date), progressMaximum)
        let shown = isScrubbing ? scrubValue : live
        return VStack(spacing: 2) {
            ElasticSlider(
                value: Binding(get: { shown }, set: { scrubValue = $0 }),
                in: 0...progressMaximum,
                onEditingChanged: { editing in
                    if editing {
                        scrubValue = live
                        isScrubbing = true
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    } else {
                        player.seek(to: scrubValue)
                        isScrubbing = false
                    }
                },
                leadingLabel: { EmptyView() },
                trailingLabel: { EmptyView() }
            )
            .sliderStyle(.playerProgress)
            .frame(height: 28)

            HStack {
                Text(formatTime(shown))

                Spacer()

                Text("−\(formatTime(max(progressMaximum - shown, 0)))")
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.white.opacity(0.5))
        }
        .frame(height: 52)
    }

    private var progressMaximum: TimeInterval {
        max(player.duration, TimeInterval(song.durationMS) / 1_000, 1)
    }

    private func formatTime(_ value: TimeInterval) -> String {
        guard value.isFinite else { return "0:00" }
        let seconds = max(0, Int(value))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

private struct NowPlayingAutoMixStatus: View {
    @Environment(\.accessibilityReduceMotion)
    private var accessibilityReduceMotion
    @Environment(PlayerStore.self) private var player

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "waveform")
                .font(.system(size: 9, weight: .semibold))
                .symbolEffect(
                    .variableColor.iterative,
                    options: .repeating.speed(1.2),
                    isActive:
                        !accessibilityReduceMotion
                            && player.isAutoMixTransitioning
                )

            Text("Mixing")
                .fontWeight(.medium)

            ProgressView(
                value:
                    player.autoMixTransitionProgress
                        ?? 0
            )
            .progressViewStyle(.linear)
            .tint(.white)
            .frame(width: 30)

            Text("\(progressPercent)%")
                .monospacedDigit()
                .frame(minWidth: 24, alignment: .trailing)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(
            .white.opacity(0.16),
            in: .rect(cornerRadius: 7)
        )
        .foregroundStyle(.white.opacity(0.86))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Auto mix in progress")
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        if let songName =
            player.autoMixIncomingSongName {
            return "Transitioning to \(songName)，\(progressPercent)%"
        }
        return "\(progressPercent)%"
    }

    private var progressPercent: Int {
        Int(
            (
                player.autoMixTransitionProgress
                    ?? 0
            ) * 100
        )
    }
}

private struct NowPlayingQualityMenu: View {
    @Environment(PlayerStore.self) private var player
    @Environment(AppSettings.self) private var settings

    var body: some View {
        Menu {
            if player.availablePlaybackQualities.isEmpty {
                Text("Loading qualities")
            } else {
                Picker("Quality", selection: qualityBinding) {
                    ForEach(player.availablePlaybackQualities) { quality in
                        Text(quality.title).tag(quality)
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "waveform")
                    .font(.system(size: 9, weight: .semibold))
                Text(displayedQualityTitle)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                .white.opacity(0.12),
                in: .rect(cornerRadius: 7)
            )
            .contentShape(.rect)
        }
        .tint(.white)
        .accessibilityLabel("Audio quality")
        .accessibilityValue(displayedQualityTitle)
        .accessibilityHint("Tap to change audio quality")
    }

    private var displayedQualityTitle: String {
        player.effectivePlaybackQuality?.title ?? "Quality"
    }

    private var qualityBinding: Binding<MusicQuality> {
        Binding(
            get: { settings.quality },
            set: { quality in
                guard settings.quality != quality else { return }
                settings.quality = quality
                Task {
                    await player.reloadCurrentSongForQualityChange()
                }
            }
        )
    }
}

struct NowPlayingTransportControls: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(PlayerStore.self) private var player

    var body: some View {
        HStack {
            Spacer()

            Button {
                Task { await player.previous() }
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 34, weight: .medium))
                    .frame(width: 64, height: 64)
                    .contentShape(.circle)
            }
            .buttonStyle(
                NowPlayingTransportButtonStyle(
                    reducesMotion: accessibilityReduceMotion
                )
            )
            .accessibilityLabel("Previous")

            Spacer()

            Button {
                player.togglePlayback()
            } label: {
                Group {
                    if player.isLoading {
                        ProgressView()
                            .controlSize(.large)
                            .tint(.white)
                    } else {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 48, weight: .medium))
                            .contentTransition(
                                accessibilityReduceMotion
                                    ? .identity
                                    : .symbolEffect(
                                        .replace.downUp.wholeSymbol,
                                        options: .speed(1.6)
                                    )
                            )
                            .animation(
                                accessibilityReduceMotion
                                    ? nil
                                    : .snappy(duration: 0.2, extraBounce: 0),
                                value: player.isPlaying
                            )
                    }
                }
                .frame(width: 64, height: 64)
                .contentShape(.circle)
            }
            .buttonStyle(
                NowPlayingTransportButtonStyle(
                    reducesMotion: accessibilityReduceMotion
                )
            )
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")

            Spacer()

            Button {
                Task { await player.next() }
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 34, weight: .medium))
                    .frame(width: 64, height: 64)
                    .contentShape(.circle)
            }
            .buttonStyle(
                NowPlayingTransportButtonStyle(
                    reducesMotion: accessibilityReduceMotion
                )
            )
            .accessibilityLabel("Next")

            Spacer()
        }
        .frame(height: 82)
    }
}

struct NowPlayingVolumeControl: View {
    @Environment(PlayerStore.self) private var player
    @Environment(AppSettings.self) private var settings
    @ObservedObject private var remote = RemoteControl.shared
    @State private var volume = Double(AudioPlayer.shared.volume)

    @ViewBuilder
    var body: some View {
        if settings.playerVolumeControlMode != .hidden {
            volumeSlider
                .foregroundStyle(.white.opacity(0.62))
                .font(.system(size: 14))
                .frame(height: 42)
        }
    }

    @ViewBuilder
    private var volumeSlider: some View {
        switch remote.playingElsewhere != nil ? .independent : settings.playerVolumeControlMode {
        case .hidden:
            EmptyView()
        case .independent:
            ElasticSlider(
                value: Binding(
                    get: { volume },
                    set: { volume = $0; player.setVolume($0) }
                ),
                in: 0...1,
                leadingLabel: { Image(systemName: "speaker.fill").padding(.trailing, 10) },
                trailingLabel: { Image(systemName: "speaker.wave.3.fill").padding(.leading, 10) }
            )
            .sliderStyle(.playerVolume)
            .accessibilityLabel("Player volume")
            .onReceive(AudioPlayer.shared.$volume.removeDuplicates()) { v in
                if abs(Double(v) - volume) > 0.001 { volume = Double(v) }
            }
        case .system:
            SystemVolumeSlider()
                .accessibilityLabel("System volume")
        }
    }
}

private final class AlignedSystemVolumeView: MPVolumeView {
    override func volumeSliderRect(forBounds bounds: CGRect) -> CGRect {
        bounds
    }
}

private struct SystemVolumeSlider: UIViewRepresentable {
    func makeUIView(context: Context) -> AlignedSystemVolumeView {
        let volumeView = AlignedSystemVolumeView(
            frame: CGRect(x: 0, y: 0, width: 200, height: 32)
        )
        volumeView.backgroundColor = .clear
        volumeView.showsVolumeSlider = true
        volumeView.showsRouteButton = false
        volumeView.tintColor = .white
        return volumeView
    }

    func updateUIView(
        _ volumeView: AlignedSystemVolumeView,
        context: Context
    ) {
        volumeView.showsVolumeSlider = true
        volumeView.tintColor = .white
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: AlignedSystemVolumeView,
        context: Context
    ) -> CGSize? {
        CGSize(
            width: proposal.width ?? 200,
            height: proposal.height ?? 32
        )
    }
}

extension RemoteControl {
    var playingElsewhere: Device? {
        guard let device = activeDevice, activeHostID != deviceID else { return nil }
        return device
    }

    static func title(_ device: Device) -> String {
        device.type == "web" ? device.name.replacingOccurrences(of: #"\s*\(.*\)$"#, with: "", options: .regularExpression) : device.name
    }

    static func detail(_ device: Device) -> String {
        switch device.type {
        case "ios": return "Swing Music for iOS"
        case "android": return "Swing Music for Android"
        default:
            guard let open = device.name.firstIndex(of: "("), device.name.hasSuffix(")") else { return device.name }
            return String(device.name[device.name.index(after: open)..<device.name.index(before: device.name.endIndex)])
        }
    }
}

struct PlayOnButton: View {
    @ObservedObject private var remote = RemoteControl.shared
    @State private var showsSheet = false

    var body: some View {
        if remote.checking {
            ProgressView()
                .tint(.white.opacity(0.72))
                .frame(width: 44, height: 44)
        } else if remote.available {
            Button { showsSheet = true } label: {
                if let device = remote.playingElsewhere {
                    HStack(spacing: 8) {
                        Image(systemName: "airplayaudio")
                        Text(RemoteControl.title(device))
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(height: 40)
                    .background(.white.opacity(0.16), in: .capsule)
                    .contentShape(.capsule)
                } else {
                    Image(systemName: "airplayaudio")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                        .contentShape(.circle)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Play On")
            .sheet(isPresented: $showsSheet) {
                PlayOnSheet()
            }
            .onChange(of: remote.offerPlayHere) { _, offered in
                guard offered else { return }
                remote.offerPlayHere = false
                showsSheet = true
            }
        } else {
            AirPlayButton()
                .frame(width: 40, height: 40)
                .tint(.white.opacity(0.72))
        }
    }
}

struct PlayOnSheet: View {
    @ObservedObject private var remote = RemoteControl.shared
    @Environment(\.dismiss) private var dismiss
    @State private var switching: String?
    @State private var routePickerTrigger = 0
    @State private var reconnecting = false
    @State private var contentHeight: CGFloat = 0
    @State private var detent: PresentationDetent = .medium

    private var others: [RemoteControl.Device] {
        remote.devices.filter { $0.id != remote.deviceID && ($0.selectable != false || $0.id == remote.activeHostID) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    deviceRow(id: remote.deviceID, systemImage: "iphone", title: "This \(UIDevice.current.model)", detail: nil)
                    Button { routePickerTrigger += 1 } label: {
                        HStack(spacing: 14) {
                            tile("airplayaudio", background: .blue, foreground: .white)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("AirPlay & Bluetooth")
                                Text("Speakers, headphones and TVs")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .background {
                        AirPlayButton(hidden: true, trigger: routePickerTrigger) {
                            let id = remote.deviceID
                            switching = id
                            DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                                if switching == id { switching = nil }
                            }
                        }
                            .frame(width: 1, height: 1)
                    }
                }

                if remote.subscribed {
                    Section {
                        ForEach(others) { device in
                            deviceRow(
                                id: device.id,
                                systemImage: device.type == "web" ? "laptopcomputer" : "iphone",
                                title: RemoteControl.title(device),
                                detail: RemoteControl.detail(device)
                            )
                        }
                    } header: {
                        Text("Swing Music Devices")
                    } footer: {
                        Text("Devices signed in to your Swing Music account appear here.")
                    }

                    Section {
                        Button("Disconnect This \(UIDevice.current.model)") { remote.setEnabled(false) }
                            .foregroundStyle(.tint)
                    } footer: {
                        Text("Play independently, without syncing with your other devices.")
                    }
                } else {
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Not Connected")
                            Text("This \(UIDevice.current.model) plays on its own. Your other devices can't see or control it, and it won't follow them.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Button {
                            reconnecting = true
                            remote.setEnabled(true)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { reconnecting = false }
                        } label: {
                            HStack {
                                Text("Reconnect")
                                Spacer()
                                if reconnecting { ProgressView() }
                            }
                        }
                        .foregroundStyle(.tint)
                        .disabled(reconnecting)
                    } header: {
                        Text("Swing Music Devices")
                    }
                }
            }
            // Open as tall as the content, up to full height.
            .onScrollGeometryChange(for: CGFloat.self) { geo in
                geo.contentSize.height + geo.contentInsets.top + geo.contentInsets.bottom
            } action: { _, height in
                // Only grow: the bottom inset changes with the sheet's height and would loop.
                let h = max(contentHeight, height.rounded(.up))
                guard h != contentHeight else { return }
                contentHeight = h
                if detent != .large { detent = .height(h) }
            }
            .navigationTitle("Play On")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) { dismiss() }
                }
            }
        }
        // The Now Playing row's dimmed style would otherwise carry into the sheet.
        .foregroundStyle(Color.primary)
        .tint(.blue)
        .presentationDetents(contentHeight > 0 ? [.height(contentHeight), .large] : [.medium, .large], selection: $detent)
        .onChange(of: remote.activeHostID) { _, id in
            if id == switching { switching = nil }
        }
        .onChange(of: remote.subscribed) { _, on in
            if on { reconnecting = false }
        }
    }

    private func isSelected(_ id: String) -> Bool {
        id == remote.deviceID ? remote.playingElsewhere == nil : id == remote.activeHostID
    }

    private func deviceRow(id: String, systemImage: String, title: String, detail: String?) -> some View {
        Button {
            guard switching == nil, !isSelected(id) else { return }
            switching = id
            remote.transfer(to: id)
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                if switching == id { switching = nil }
            }
        } label: {
            HStack(spacing: 14) {
                tile(systemImage, background: .white.opacity(0.08), foreground: Color.primary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    if let detail {
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if switching == id {
                    ProgressView()
                } else if isSelected(id) {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.blue)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(switching != nil && switching != id)
    }

    private func tile(_ systemImage: String, background: Color, foreground: Color) -> some View {
        Image(systemName: systemImage)
            .font(.body)
            .foregroundStyle(foreground)
            .frame(width: 36, height: 36)
            .background(background, in: .rect(cornerRadius: 8))
    }
}

struct NowPlayingPageSelector: View {
    @Environment(\.accessibilityReduceMotion)
    private var accessibilityReduceMotion
    @Environment(PlayerStore.self) private var player

    @Binding var page: NowPlayingPage

    var body: some View {
        Group {
            if player.currentSong?.isPodcastProgram == true {
                HStack {
                    Spacer()

                    pageButton(
                        page: .queue,
                        systemImage: "list.bullet",
                        accessibilityLabel: "Queue",
                        badgeSystemImage:
                            page == .queue
                                ? nil
                                : player.queueModeBadgeSystemImage
                    )

                    Spacer()
                }
            } else {
                HStack {
                    pageButton(
                        page: .lyrics,
                        systemImage: "quote.bubble",
                        accessibilityLabel: "Lyrics"
                    )

                    Spacer()

                    PlayOnButton()

                    Spacer()

                    pageButton(
                        page: .queue,
                        systemImage: "list.bullet",
                        accessibilityLabel: "Queue",
                        badgeSystemImage:
                            page == .queue
                                ? nil
                                : player.queueModeBadgeSystemImage
                    )
                }
            }
        }
        .padding(.horizontal, 32)
        .foregroundStyle(.white.opacity(0.72))
        .frame(height: 50)
    }

    private func pageButton(
        page destination: NowPlayingPage,
        systemImage: String,
        accessibilityLabel: String,
        badgeSystemImage: String? = nil
    ) -> some View {
        let isSelected = page == destination

        return Button {
            let targetPage: NowPlayingPage =
                isSelected ? .artwork : destination
            withAnimation(
                accessibilityReduceMotion
                    ? nil
                    : NowPlayingPageTransition
                        .selectionAnimation(
                            from: page,
                            to: targetPage
                        )
            ) {
                page = targetPage
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: systemImage)
                    .symbolVariant(isSelected ? .fill : .none)
                    .font(.title3)
                    .frame(width: 44, height: 44)
                    .foregroundStyle(
                        isSelected
                            ? .black.opacity(0.68)
                            : .white.opacity(0.72)
                    )
                    .background(
                        .white.opacity(isSelected ? 0.68 : 0),
                        in: .circle
                    )

                if let badgeSystemImage {
                    Image(systemName: badgeSystemImage)
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(
                            isSelected
                                ? .white.opacity(0.9)
                                : .black.opacity(0.74)
                        )
                        .frame(width: 15, height: 15)
                        .background(
                            isSelected
                                ? .black.opacity(0.58)
                                : .white.opacity(0.82),
                            in: .circle
                        )
                        .offset(x: 3, y: 1)
                }
            }
            .frame(width: 44, height: 44)
            .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
