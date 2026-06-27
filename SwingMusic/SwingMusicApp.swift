import SwiftUI

@main
struct SwingMusicApp: App {
    @StateObject private var state = AppState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                if state.authed {
                    ContentView()
                } else {
                    LoginView()
                }
            }
            .environmentObject(state)
            .preferredColorScheme(state.appearanceMode.colorScheme)
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await ScrobbleQueue.shared.flush() } }
            }
            .onShake { state.beginBugReport() }
            .sheet(isPresented: $state.showBugReport) {
                if let report = state.currentBugReport {
                    BugReportSheet(report: report)
                }
            }
        }
    }
}
