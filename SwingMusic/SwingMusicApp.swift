import SwiftUI

@main
struct SwingMusicApp: App {
    @State private var state = AppState()
    @AppStorage(ShakeToReport.key) private var shakeToReport = false
    @Environment(\.scenePhase) private var scenePhase

    @MainActor
    private func reloadAfterServerSwitch() async {
        await state.loadHome()
        await state.loadHomeSections()
        await state.loadPlaylists()
        await state.loadFavorites()
        await state.loadAlbums(force: true)
        await state.loadArtists(force: true)
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if state.authed {
                    ContentView()
                } else {
                    LoginView()
                }
            }
            .environment(state)
            .preferredColorScheme(state.appearanceMode.colorScheme)
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task {
                        if await API.shared.ensureReachable() { await reloadAfterServerSwitch() }
                        await ScrobbleQueue.shared.flush()
                    }
                }
            }
            .task {
                if await API.shared.migrateToSwingServerIfNeeded() {
                    state.logout()
                } else if await API.shared.ensureReachable() {
                    await reloadAfterServerSwitch()
                }
            }
            .onShake { if shakeToReport { state.beginBugReport() } }
            .sheet(isPresented: $state.showBugReport) {
                if let report = state.currentBugReport {
                    BugReportSheet(report: report)
                }
            }
            #if DEBUG
            .background(
                Color.clear
                    .frame(width: 0, height: 0)
                    .task {
                        ComponentExporter.runIfRequested(state: state)
                        DebugCapture.runIfRequested(state: state)
                    }
            )
            #endif
        }
    }
}
