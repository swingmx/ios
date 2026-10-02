import SwiftUI

struct AdaptiveDetailBackground: View {
    let image: UIImage?
    var blendHeight: CGFloat = 0.45
    // How far the screen has scrolled down; the image moves up by this much so it stays with the header.
    var scrollOffset: CGFloat = 0
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
                        .saturation(isDark ? 1.35 : 1.45)
                        .opacity(isDark ? 0.75 : 0.8)
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
                        .offset(y: -scrollOffset)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .ignoresSafeArea()

                    if isDark {
                        LinearGradient(
                            colors: [.black.opacity(0.18), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: geo.size.height * 0.25)
                        .frame(maxHeight: .infinity, alignment: .top)
                    }
                }
            }
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.8), value: image != nil)
    }
}

// The detail screens' blurred artwork background, scrolling with the header so the track list
// below it sits on the plain background. Pulling down past the top leaves it anchored in place.
private struct DetailBackground: ViewModifier {
    let image: UIImage?
    @State private var scrolled: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: CGFloat.self) { geo in
                max(0, geo.contentOffset.y + geo.contentInsets.top)
            } action: { _, value in
                scrolled = value
            }
            .background { AdaptiveDetailBackground(image: image, scrollOffset: scrolled) }
    }
}

extension View {
    func detailBackground(_ image: UIImage?) -> some View {
        modifier(DetailBackground(image: image))
    }
}
