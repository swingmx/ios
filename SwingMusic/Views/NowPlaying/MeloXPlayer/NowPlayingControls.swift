import SwiftUI

struct NowPlayingProgressControl: View {
    @Environment(PlayerStore.self) private var player

    let song: Song

    @State private var scrubValue: Double = 0
    @State private var isScrubbing = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 4.0, paused: !player.isPlaying || isScrubbing)) { context in
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

// The playing device's volume: this phone's system volume, or the remote device's while controlling it.
struct NowPlayingVolumeControl: View {
    @ObservedObject private var remote = RemoteControl.shared
    @State private var volume = SystemVolume.shared.value
    // The system volume reports each step back a moment later; ignore those while dragging.
    @State private var setAt = Date.distantPast

    private var elsewhere: Bool { remote.playingElsewhere != nil }

    var body: some View {
        ElasticSlider(
            value: Binding(
                get: { volume },
                set: { v in
                    volume = v
                    setAt = Date()
                    if elsewhere { remote.setVolume(v) } else { SystemVolume.shared.set(v) }
                }
            ),
            in: 0...1,
            leadingLabel: { Image(systemName: "speaker.fill").padding(.trailing, 10) },
            trailingLabel: { Image(systemName: "speaker.wave.3.fill").padding(.leading, 10) }
        )
        .sliderStyle(.playerVolume)
        .accessibilityLabel("Volume")
        .foregroundStyle(.white.opacity(0.62))
        .font(.system(size: 14))
        .frame(height: 42)
        .onAppear {
            SystemVolume.shared.wake()
            volume = elsewhere ? remote.volume : SystemVolume.shared.value
        }
        .onChange(of: elsewhere) { _, e in volume = e ? remote.volume : SystemVolume.shared.value }
        .onReceive(SystemVolume.shared.$level) { v in
            if !elsewhere { follow(v) }
        }
        .onReceive(remote.$volume) { v in
            if elsewhere { follow(v) }
        }
    }

    private func follow(_ v: Double) {
        guard Date().timeIntervalSince(setAt) > 0.5, abs(v - volume) > 0.001 else { return }
        // Buttons and other devices change it in steps; glide between them instead of jumping.
        withAnimation(.smooth(duration: 0.25)) { volume = v }
    }
}

extension RemoteControl {
    var playingElsewhere: Device? {
        guard isController, let device = activeDevice else { return nil }
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
                    if remote.subscribed {
                        ForEach(others) { device in
                            deviceRow(
                                id: device.id,
                                systemImage: device.type == "web" ? "laptopcomputer" : "iphone",
                                title: RemoteControl.title(device),
                                detail: RemoteControl.detail(device)
                            )
                        }
                    }
                } header: {
                    titleRow
                }

                Section {
                    NowPlayingVolumeControl()
                } header: {
                    Text("Volume · \(remote.playingElsewhere.map { $0.type == "web" ? RemoteControl.detail($0) : RemoteControl.title($0) } ?? "This \(UIDevice.current.model)")")
                }

                if remote.subscribed {
                    Section {
                        Button("Detach This \(UIDevice.current.model)") { remote.setEnabled(false) }
                            .foregroundStyle(.tint)
                    } footer: {
                        Text("Play independently, without syncing with your other devices.")
                    }
                } else {
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Detached")
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
                                Text("Reattach")
                                Spacer()
                                if reconnecting { ProgressView() }
                            }
                        }
                        .foregroundStyle(.tint)
                        .disabled(reconnecting)
                    }
                }
            }
            // Open as tall as the content, up to full height.
            .onScrollGeometryChange(for: CGFloat.self) { geo in
                // The sheet adds the home indicator area to a custom height itself.
                geo.contentSize.height + geo.contentInsets.top
            } action: { _, height in
                // Only grow: the bottom inset changes with the sheet's height and would loop.
                let h = max(contentHeight, height.rounded(.up))
                guard h != contentHeight else { return }
                contentHeight = h
                if detent != .large { detent = .height(h) }
            }
            .contentMargins(.top, 16, for: .scrollContent)
            .toolbar(.hidden, for: .navigationBar)
        }
        // The Now Playing row's dimmed style would otherwise carry into the sheet.
        .foregroundStyle(Color.primary)
        .tint(.blue)
        .preferredColorScheme(.dark)
        .presentationDetents(contentHeight > 0 ? [.height(contentHeight), .large] : [.medium, .large], selection: $detent)
        .onChange(of: remote.activeHostID) { _, id in
            if id == switching { switching = nil }
        }
        .onChange(of: remote.subscribed) { _, on in
            if on { reconnecting = false }
        }
    }

    // A section header, so the title lines up with the row icons below it.
    private var titleRow: some View {
        HStack {
            Text("Play On")
                .font(.title3.weight(.bold))
                .foregroundStyle(Color.primary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            // No frame or glass around the glyph, so its right edge mirrors the title's left edge.
            Button(role: .close) { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.title3.weight(.semibold))
                    .padding(10)
                    .contentShape(.rect)
                    .padding(-10)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .textCase(nil)
        .padding(.bottom, 6)
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
