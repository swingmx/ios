import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) var state
    @AppStorage("albumArtTapAction") private var albumArtTapAction = "album"
    @AppStorage("musixmatchWordByWord") private var musixmatchWordByWord = true
    @AppStorage(Net.allowInsecureTLSKey) private var allowInsecureTLS = false
    @AppStorage(ShakeToReport.key) private var shakeToReport = false
    // Mirrors of the player's settings: the player itself changes 20 times a second, too often to observe here.
    @State private var audioQuality = AudioPlayer.shared.audioQuality
    @State private var crossfade = Int(AudioPlayer.shared.crossfadeDuration)
    @State private var canTranscode = API.shared.canTranscode
    @State private var serverVersion = API.shared.serverVersion
    @State private var confirmLogout = false
    @ObservedObject private var equalizer = Equalizer.shared
    @ObservedObject private var downloads = DownloadManager.shared

    var body: some View {
        @Bindable var state = state
        ScrollViewReader { proxy in
        List {
            Section {
                HStack(spacing: 16) {
                    UserAvatar(size: 56, symbol: "person.circle.fill")
                        .foregroundStyle(.blue)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(state.user?.username ?? "Swing Music")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.primary)
                        Text(API.shared.base)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()

                    Button { confirmLogout = true } label: {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(.red)
                            .frame(width: 44, height: 44)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Log Out")
                    .alert("Log out of \(state.user?.username ?? "your account")?", isPresented: $confirmLogout) {
                        Button("Cancel", role: .cancel) {}
                        Button("Log Out", role: .destructive) { state.logout() }
                    }
                }
                .padding(.vertical, 8)
            }

            Section(header: Text("Appearance")) {
                Picker(selection: $state.appearanceMode) {
                    ForEach(AppState.AppearanceMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                } label: {
                    HStack {
                        Image(systemName: "circle.lefthalf.filled")
                            .foregroundStyle(.blue)
                            .frame(width: 28)
                        Text("Theme")
                    }
                }
            }

            Section(header: Text("Playback")) {
                Picker(selection: Binding(
                    get: { canTranscode ? audioQuality : .lossless },
                    set: { audioQuality = $0; AudioPlayer.shared.audioQuality = $0 }
                )) {
                    ForEach(AudioPlayer.AudioQuality.allCases, id: \.self) { q in
                        Text(q.label).tag(q)
                    }
                } label: {
                    HStack {
                        Image(systemName: "waveform")
                            .foregroundStyle(.blue)
                            .frame(width: 28)
                        Text("Audio Quality")
                    }
                }
                .disabled(!canTranscode)
                .task {
                    await API.shared.loadCapabilities()
                    canTranscode = API.shared.canTranscode
                    serverVersion = API.shared.serverVersion
                }

                Picker(selection: Binding(
                    get: { crossfade },
                    set: { crossfade = $0; AudioPlayer.shared.crossfadeDuration = Double($0) }
                )) {
                    Text("Off").tag(0)
                    Text("2s").tag(2)
                    Text("4s").tag(4)
                    Text("6s").tag(6)
                    Text("8s").tag(8)
                    Text("12s").tag(12)
                } label: {
                    HStack {
                        Image(systemName: "arrow.triangle.swap")
                            .foregroundStyle(.blue)
                            .frame(width: 28)
                        Text("Crossfade")
                    }
                }

                NavigationLink {
                    EqualizerView()
                } label: {
                    HStack {
                        Image(systemName: "slider.vertical.3")
                            .foregroundStyle(.blue)
                            .frame(width: 28)
                        Text("Equalizer")
                        Spacer()
                        Text(equalizer.enabled ? "On" : "Off")
                            .foregroundStyle(.secondary)
                    }
                }

                Picker(selection: $albumArtTapAction) {
                    Text("Open Album").tag("album")
                    Text("Show Lyrics").tag("lyrics")
                } label: {
                    HStack {
                        Image(systemName: "hand.tap")
                            .foregroundStyle(.blue)
                            .frame(width: 28)
                        Text("Tap Artwork")
                    }
                }

                Toggle(isOn: $musixmatchWordByWord) {
                    HStack {
                        Image(systemName: "text.word.spacing")
                            .foregroundStyle(.blue)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Word-by-Word Lyrics")
                            Text("Fetches word timings from Musixmatch when the server has none.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .tint(.green)
            }

            Section(header: Text("Storage")) {
                HStack {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(.green)
                        .frame(width: 28)
                    Text("Downloads")
                    Spacer()
                    Text("\(downloads.downloadedTracks.count) songs · \(downloads.totalSize)")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 13))
                }

                if !downloads.downloadedTracks.isEmpty {
                    Button(role: .destructive) {
                        DownloadManager.shared.removeAll()
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                                .foregroundStyle(.red)
                                .frame(width: 28)
                            Text("Remove All Downloads")
                                .foregroundColor(.red)
                        }
                    }
                }
            }

            Section(
                header: Text("Connection"),
                footer: Text("Only enable this if your server uses a self-signed certificate")
            ) {
                Toggle(isOn: $allowInsecureTLS) {
                    HStack {
                        Image(systemName: "lock.trianglebadge.exclamationmark")
                            .foregroundStyle(.orange)
                            .frame(width: 28)
                        Text("Allow Self-Signed Certificates")
                    }
                }
                .tint(.green)
            }

            Section {
                Toggle(isOn: $shakeToReport) {
                    HStack {
                        Image(systemName: "iphone.radiowaves.left.and.right")
                            .foregroundStyle(.orange)
                            .frame(width: 28)
                        Text("Shake to Report")
                    }
                }
                .tint(.green)
                Button {
                    state.beginBugReport()
                } label: {
                    HStack {
                        Image(systemName: "ladybug.fill")
                            .foregroundStyle(.orange)
                            .frame(width: 28)
                        Text("Report a Problem")
                            .foregroundStyle(.primary)
                    }
                }
                .id("lastRow")
            } header: {
                Text("Support")
            } footer: {
                VStack(alignment: .leading, spacing: 24) {
                    if shakeToReport {
                        Text("Tip: shake your device anywhere in the app to report a problem.")
                    }
                    Text("Swing Music v\(serverVersion ?? "–") · \(AppInfo.versionString)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                }
            }

        }
        #if DEBUG
        .task {
            if UserDefaults.standard.bool(forKey: "captureLogout") {
                try? await Task.sleep(nanoseconds: 800_000_000)
                confirmLogout = true
            }
            guard UserDefaults.standard.bool(forKey: "captureBottom") else { return }
            try? await Task.sleep(nanoseconds: 800_000_000)
            proxy.scrollTo("lastRow", anchor: .center)
        }
        #endif
        }
        .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 100) }
        .listRowBackground(Color(.secondarySystemGroupedBackground))
        .scrollContentBackground(.hidden)
        .background { AmbientBackground() }
        .navigationTitle("Settings")
    }
}

enum AppInfo {
    static var shortVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }
    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }
    static var releaseChannel: String? {
        let c = Bundle.main.object(forInfoDictionaryKey: "SMReleaseChannel") as? String
        return (c?.isEmpty == false) ? c : nil
    }
    static var versionString: String {
        if let channel = releaseChannel {
            return "\(shortVersion) (\(channel) \(build))"
        }
        return "\(shortVersion) (\(build))"
    }
}
