import SwiftUI

struct AdaptiveDetailBackground: View {
    let image: UIImage?

    var blendHeight: CGFloat = 0.45
    @Environment(\.colorScheme) var colorScheme

    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {

                (isDark ? Color.black : Color(.systemBackground))

                if let image {

                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: isDark ? 440 : 620)
                        .clipped()
                        .blur(radius: isDark ? 70 : 110, opaque: true)
                        .saturation(isDark ? 1.0 : 1.3)
                        .opacity(isDark ? 0.6 : 0.7)
                        .mask(
                            LinearGradient(
                                stops: isDark
                                    ? [.init(color: .black, location: 0),
                                       .init(color: .black, location: 0.45),
                                       .init(color: .clear, location: 1)]
                                    : [.init(color: .black, location: 0),
                                       .init(color: .black, location: 0.08),
                                       .init(color: .clear, location: 0.95)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(maxHeight: .infinity, alignment: .top)
                        .ignoresSafeArea()

                    if isDark {
                        LinearGradient(
                            colors: [.black.opacity(0.35), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: geo.size.height * 0.3)
                        .frame(maxHeight: .infinity, alignment: .top)
                    }
                }
            }
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.8), value: image != nil)
    }
}
