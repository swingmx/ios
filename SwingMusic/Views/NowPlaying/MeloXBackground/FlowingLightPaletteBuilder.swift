import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

enum FlowingLightPaletteBuilder {
    private static let context = CIContext(options: [.workingColorSpace: NSNull()])
    private static let colorSpace = CGColorSpaceCreateDeviceRGB()

    static func palette(from image: UIImage) -> ArtworkFlowingLightPalette {
        guard let ci = CIImage(image: image) else { return .fallback }
        let prepared = downsampled(ci)
        let extent = prepared.extent.integral
        guard !extent.isEmpty, !extent.isInfinite else { return .fallback }

        let dimension = ArtworkFlowingLightPalette.gridDimension
        let cellWidth = extent.width / CGFloat(dimension)
        let cellHeight = extent.height / CGFloat(dimension)
        let colors = (0 ..< dimension).flatMap { row in
            (0 ..< dimension).map { column in
                let cell = CGRect(
                    x: extent.minX + CGFloat(column) * cellWidth,
                    y: extent.minY + CGFloat(dimension - row - 1) * cellHeight,
                    width: cellWidth,
                    height: cellHeight
                )
                return averageColor(of: prepared, extent: cell)
            }
        }
        return ArtworkFlowingLightPalette(colorsRGB: colors)
    }

    private static func downsampled(_ image: CIImage) -> CIImage {
        let maximumDimension = max(image.extent.width, image.extent.height)
        guard maximumDimension > 160 else { return image }

        let scale = 160 / maximumDimension
        let filter = CIFilter.lanczosScaleTransform()
        filter.inputImage = image
        filter.scale = Float(scale)
        filter.aspectRatio = 1
        return filter.outputImage ?? image
    }

    private static func averageColor(of image: CIImage, extent: CGRect) -> SIMD3<Double> {
        let filter = CIFilter.areaAverage()
        filter.inputImage = image
        filter.extent = extent
        guard let outputImage = filter.outputImage else {
            return SIMD3<Double>(0.5, 0.5, 0.5)
        }

        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(
            outputImage,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: colorSpace
        )

        return SIMD3<Double>(
            Double(pixel[0]) / 255,
            Double(pixel[1]) / 255,
            Double(pixel[2]) / 255
        )
    }
}
