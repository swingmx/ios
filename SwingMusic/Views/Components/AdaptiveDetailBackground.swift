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
                        .frame(width: geo.size.width, height: 440)
                        .clipped()
                        .blur(radius: 70, opaque: true)
                        .opacity(isDark ? 0.6 : 0.2)
                        .mask(
                            LinearGradient(
                                stops: [
                                    .init(color: .black, location: 0),
                                    .init(color: .black, location: 0.45),
                                    .init(color: .clear, location: 1)
                                ],
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
