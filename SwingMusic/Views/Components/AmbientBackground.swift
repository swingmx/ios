import SwiftUI

struct AmbientBackground: View {
    @EnvironmentObject var state: AppState
    @Environment(\.colorScheme) var colorScheme

    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        ZStack {
            (isDark ? Color.black : Color(.systemGroupedBackground))

            if let img = state.currentBGImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .blur(radius: 80, opaque: true)
                    .opacity(isDark ? 0.35 : 0.15)
                    .animation(.easeInOut(duration: 1.0), value: state.currentBGImage != nil)

                LinearGradient(
                    colors: isDark
                        ? [.black.opacity(0.4), .black.opacity(0.7), .black.opacity(0.9)]
                        : [Color(.systemGroupedBackground).opacity(0.6), Color(.systemGroupedBackground).opacity(0.85)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .ignoresSafeArea()
    }
}
