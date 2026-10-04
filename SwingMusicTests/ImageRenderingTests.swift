import Testing
import UIKit
@testable import Swing_Music_Client

struct ImageMemoryCacheTests {
    private func image(_ side: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in }
    }

    @Test func storedImagesComeBackAndCanBeRemoved() {
        let cache = ImageMemoryCache(), img = image(10)

        cache["a"] = img
        #expect(cache["a"] === img)

        cache["a"] = nil
        #expect(cache["a"] == nil)
    }

    // The cost limit is in bytes of decoded bitmap, so the cost has to be pixels × 4.
    @Test func costIsTheDecodedBitmapSize() {
        #expect(ImageMemoryCache.cost(of: image(256)) == 256 * 256 * 4)
    }
}

struct AmbientBlurTests {
    private let red: UIImage = {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 300, height: 300), format: format).image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 300, height: 300))
        }
    }()

    // Alpha of the pixel in the middle of the given row.
    private func alpha(_ image: UIImage, row: Int) -> CGFloat {
        let cg = image.cgImage!
        var px = [UInt8](repeating: 0, count: 4)
        let ctx = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(cg, in: CGRect(x: -cg.width / 2, y: row - cg.height + 1, width: cg.width, height: cg.height))
        return CGFloat(px[3]) / 255
    }

    @Test func itRendersAtAQuarterOfTheDisplayedSize() throws {
        let out = try #require(AmbientBlur.render(red, size: CGSize(width: 400, height: 520), dark: true))

        #expect(out.cgImage?.width == 100)
        #expect(out.cgImage?.height == 130)
    }

    @Test func itIsHalfOpaqueAtTheTopAndFadesOutTowardsTheBottom() throws {
        let out = try #require(AmbientBlur.render(red, size: CGSize(width: 400, height: 520), dark: true))

        #expect(abs(alpha(out, row: 0) - 0.5) < 0.05)
        #expect(alpha(out, row: 128) < 0.05)
    }
}
