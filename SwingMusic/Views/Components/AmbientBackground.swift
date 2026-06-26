import SwiftUI

struct AmbientBackground: View {
    @EnvironmentObject var state: AppState
    @Environment(\.colorScheme) var colorScheme

    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {

                (isDark ? Color.black : Color(.systemGray5))

                if let img = state.currentBGImage {

                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: 520)
                        .clipped()

                        .blur(radius: isDark ? 80 : 120, opaque: true)
                        .saturation(isDark ? 1.0 : 1.2)
                        .opacity(isDark ? 0.5 : 0.5)
                        .mask(
                            LinearGradient(
                                stops: [
                                    .init(color: .black, location: 0),
                                    .init(color: .black, location: 0.12),
                                    .init(color: .clear, location: 0.92)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(maxHeight: .infinity, alignment: .top)
                        .animation(.easeInOut(duration: 1.0), value: state.currentBGImage != nil)

                    LinearGradient(
                        colors: isDark
                            ? [.black.opacity(0.35), .clear]
                            : [Color(.systemGray5).opacity(0.1),
                               Color(.systemGray5).opacity(0.45),
                               Color(.systemGray5).opacity(0.9)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: geo.size.height * (isDark ? 0.3 : 0.55))
                    .frame(maxHeight: .infinity, alignment: .top)
                }
            }
        }
        .ignoresSafeArea()
    }
}
