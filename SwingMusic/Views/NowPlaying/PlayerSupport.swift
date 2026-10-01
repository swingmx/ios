import SwiftUI
import AVKit

struct SheetBlurBackground: View {
    var image: UIImage?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black
                if let img = image {
                    Image(uiImage: img)
                        .resizable().scaledToFill()
                        .frame(width: geo.size.width + 120, height: geo.size.height + 240)
                        .clipped()
                        .blur(radius: 60, opaque: true)
                        .opacity(0.6)
                }
                Color.black.opacity(0.4)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
        .ignoresSafeArea()
    }
}

struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView()
        v.tintColor = .label
        v.activeTintColor = .systemBlue
        v.prioritizesVideoDevices = false
        return v
    }
    func updateUIView(_ v: AVRoutePickerView, context: Context) {}
}
