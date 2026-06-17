import UIKit

enum BlurHash {
    private static var cache: [String: UIImage] = [:]

    static func image(_ hash: String, size: CGSize = CGSize(width: 32, height: 32), punch: Float = 1) -> UIImage? {
        let key = "\(hash)@\(Int(size.width))x\(Int(size.height))"
        if let cached = cache[key] { return cached }
        guard let img = decode(hash, size: size, punch: punch) else { return nil }
        cache[key] = img
        return img
    }

    private static let chars = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz#$%*+,-.:;=?@[]^_{|}~")

    private static func decode83(_ s: Substring) -> Int {
        var value = 0
        for c in s {
            if let idx = chars.firstIndex(of: c) { value = value * 83 + idx }
        }
        return value
    }

    private static func sRGBToLinear(_ value: Int) -> Float {
        let v = Float(value) / 255
        return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }

    private static func linearTosRGB(_ value: Float) -> Int {
        let v = max(0, min(1, value))
        return v <= 0.0031308 ? Int(v * 12.92 * 255 + 0.5) : Int((1.055 * pow(v, 1 / 2.4) - 0.055) * 255 + 0.5)
    }

    private static func decodeDC(_ value: Int) -> (Float, Float, Float) {
        (sRGBToLinear(value >> 16), sRGBToLinear((value >> 8) & 255), sRGBToLinear(value & 255))
    }

    private static func decodeAC(_ value: Int, maximumValue: Float) -> (Float, Float, Float) {
        let quantR = Float(value / (19 * 19))
        let quantG = Float((value / 19) % 19)
        let quantB = Float(value % 19)
        func signPow(_ v: Float, _ exp: Float) -> Float { (v < 0 ? -1 : 1) * pow(abs(v), exp) }
        return (
            signPow((quantR - 9) / 9, 2) * maximumValue,
            signPow((quantG - 9) / 9, 2) * maximumValue,
            signPow((quantB - 9) / 9, 2) * maximumValue
        )
    }

    private static func decode(_ blurHash: String, size: CGSize, punch: Float) -> UIImage? {
        let hash = Array(blurHash)
        guard hash.count >= 6 else { return nil }

        let sizeFlag = decode83(blurHash[blurHash.startIndex..<blurHash.index(blurHash.startIndex, offsetBy: 1)])
        let numY = (sizeFlag / 9) + 1
        let numX = (sizeFlag % 9) + 1

        let quantMax = decode83(blurHash[blurHash.index(blurHash.startIndex, offsetBy: 1)..<blurHash.index(blurHash.startIndex, offsetBy: 2)])
        let maximumValue = Float(quantMax + 1) / 166

        guard hash.count == 4 + 2 * numX * numY else { return nil }

        var colors = [(Float, Float, Float)]()
        for i in 0..<(numX * numY) {
            if i == 0 {
                let value = decode83(String(hash[2..<6])[...])
                colors.append(decodeDC(value))
            } else {
                let start = 4 + i * 2
                let value = decode83(String(hash[start..<start + 2])[...])
                colors.append(decodeAC(value, maximumValue: maximumValue * punch))
            }
        }

        let width = Int(size.width)
        let height = Int(size.height)
        var pixels = [UInt8](repeating: 255, count: width * height * 4)

        for y in 0..<height {
            for x in 0..<width {
                var r: Float = 0, g: Float = 0, b: Float = 0
                for j in 0..<numY {
                    for i in 0..<numX {
                        let basis = cos(Float.pi * Float(x) * Float(i) / Float(width))
                            * cos(Float.pi * Float(y) * Float(j) / Float(height))
                        let color = colors[i + j * numX]
                        r += color.0 * basis
                        g += color.1 * basis
                        b += color.2 * basis
                    }
                }
                let idx = 4 * (x + y * width)
                pixels[idx] = UInt8(linearTosRGB(r))
                pixels[idx + 1] = UInt8(linearTosRGB(g))
                pixels[idx + 2] = UInt8(linearTosRGB(b))
                pixels[idx + 3] = 255
            }
        }

        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        guard let cgImage = CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
        ) else { return nil }

        return UIImage(cgImage: cgImage)
    }
}
