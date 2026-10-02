import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @AppStorage("albumArtTapAction") private var albumArtTapAction = "album"
    @AppStorage("musixmatchWordByWord") private var musixmatchWordByWord = true
    @AppStorage(Net.allowInsecureTLSKey) private var allowInsecureTLS = false
    @AppStorage(ShakeToReport.key) private var shakeToReport = false

    var body: some View {
        List {
            Section {
                HStack(spacing: 16) {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.blue)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Swing Music")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.primary)
                        Text(API.shared.base)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
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
                    get: { AudioPlayer.shared.audioQuality },
                    set: { AudioPlayer.shared.audioQuality = $0 }
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

                Picker(selection: Binding(
                    get: { Int(AudioPlayer.shared.crossfadeDuration) },
                    set: { AudioPlayer.shared.crossfadeDuration = Double($0) }
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
                        Text(Equalizer.shared.enabled ? "On" : "Off")
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

            }

            Section(header: Text("Storage")) {
                HStack {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(.green)
                        .frame(width: 28)
                    Text("Downloads")
                    Spacer()
                    Text("\(DownloadManager.shared.downloadedTracks.count) songs · \(DownloadManager.shared.totalSize)")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 13))
                }

                if !DownloadManager.shared.downloadedTracks.isEmpty {
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
                footer: Text("Only enable this if your server uses a self-signed certificate (e.g. mkcert or your own CA). It applies solely to your configured server — all other connections stay fully verified.")
            ) {
                Toggle(isOn: $allowInsecureTLS) {
                    HStack {
                        Image(systemName: "lock.trianglebadge.exclamationmark")
                            .foregroundStyle(.orange)
                            .frame(width: 28)
                        Text("Allow Self-Signed Certificates")
                    }
                }
            }

            Section(header: Text("Account")) {
                Button(action: {
                    state.logout()
                }) {
                    HStack {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .foregroundStyle(.red)
                            .frame(width: 28)
                        Text("Log Out")
                            .foregroundColor(.red)
                    }
                }
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
            } header: {
                Text("Support")
            } footer: {
                if shakeToReport {
                    Text("Tip: shake your device anywhere in the app to report a problem.")
                }
            }

            Section(header: Text("About")) {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.blue)
                        .frame(width: 28)
                    Text("Version")
                    Spacer()
                    Text(AppInfo.versionString)
                        .foregroundColor(.secondary)
                }
            }

            Section(header: Text("Thanks to")) {
                ForEach(ThanksTo.projects, id: \.name) { project in
                    Link(destination: project.url) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(project.name).foregroundStyle(.primary)
                                Text(project.note).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
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

enum ThanksTo {
    struct Project { let name: String; let note: String; let url: URL }
    static let projects: [Project] = [
        Project(name: "MeloX", note: "Loose inspiration",
                url: URL(string: "https://github.com/youshen2/MeloX")!),
        Project(name: "Apple Music-like Lyrics (AMLL)", note: "Lyrics animation inspiration",
                url: URL(string: "https://github.com/Steve-xmh/applemusic-like-lyrics")!),
        Project(name: "Spicy Lyrics", note: "Lyrics font & style",
                url: URL(string: "https://github.com/Spikerko/spicy-lyrics")!),
        Project(name: "LDDC", note: "Word-by-word lyrics fetching",
                url: URL(string: "https://github.com/chenmozhijin/LDDC")!),
        Project(name: "LNPopupUI", note: "Mini player",
                url: URL(string: "https://github.com/LeoNatan/LNPopupUI")!),
        Project(name: "MusicBrainz & Wikipedia", note: "Songwriter credits & artist bios",
                url: URL(string: "https://musicbrainz.org")!),
    ]
}
