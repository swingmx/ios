import SwiftUI

@main
struct SwingMusicApp: App {
    @StateObject private var state = AppState()

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
            .onShake { state.beginBugReport() }
            .sheet(isPresented: $state.showBugReport) {
                if let report = state.currentBugReport {
                    BugReportSheet(report: report)
                }
            }
        }
    }
}
