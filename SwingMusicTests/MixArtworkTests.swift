import Foundation
import SwiftUI
import Testing
@testable import Swing_Music_Client

struct MixArtworkTests {
    private typealias C = MixArtworkColors
    private let trackMix = try! JSONDecoder().decode(Mix.self, from: Fixtures.trackMixResponse)
    private let artistMix = try! JSONDecoder().decode(Mix.self, from: Fixtures.artistMixResponse)

    // MARK: Colors (same rules as the web client's utils/colortools)

    @Test func serverColorsAreParsed() {
        #expect(C.parse("rgb(200, 150, 100)") == C.RGB(r: 200, g: 150, b: 100))
        #expect(C.parse("#ac8e68") == C.RGB(r: 172, g: 142, b: 104))
        #expect(C.parse("nope") == nil)
        #expect(C.parse(nil) == nil)
    }

    @Test func lightColorsGetDarkText() {
        let light = C.RGB(r: 200, g: 150, b: 100)

        #expect(C.brightness(light) == 62)
        #expect(C.textColor(for: light) == C.RGB(r: 40, g: 30, b: 20))
        #expect(C.typeColor(for: light) == C.RGB(r: 109, g: 69, b: 16))
    }

    @Test func darkColorsGetLightText() {
        let dark = C.RGB(r: 20, g: 30, b: 40)

        #expect(C.brightness(dark) == 11)
        #expect(C.textColor(for: dark) == C.RGB(r: 208, g: 210, b: 212))
        #expect(C.typeColor(for: dark) == C.RGB(r: 172, g: 142, b: 104))
    }

    @Test func cssGradientAnglesMapToSwiftUIPoints() {
        let (upStart, upEnd) = C.gradientPoints(cssDegrees: 0)
        #expect(abs(upStart.x - 0.5) < 0.001 && abs(upStart.y - 1) < 0.001)
        #expect(abs(upEnd.x - 0.5) < 0.001 && abs(upEnd.y) < 0.001)

        let (rightStart, rightEnd) = C.gradientPoints(cssDegrees: 90)
        #expect(abs(rightStart.x) < 0.001 && abs(rightStart.y - 0.5) < 0.001)
        #expect(abs(rightEnd.x - 1) < 0.001 && abs(rightEnd.y - 0.5) < 0.001)
    }

    // MARK: Images

    @Test func trackMixImagesComeFromTheEndpointForTheirType() {
        let paths = trackMix.offlineImageURLs.map(\.path)

        #expect(!trackMix.hasOwnImage)
        #expect(paths == ["/img/thumbnail/medium/al1.webp", "/img/artist/medium/ar1.webp", "/img/artist/medium/ar2.webp"])
        #expect(trackMix.backgroundURLs.map(\.path) == ["/img/thumbnail/medium/al1.webp"])
    }

    @Test func artistMixesUseTheirOwnImage() {
        #expect(artistMix.hasOwnImage)
        #expect(artistMix.coverURLs.map(\.path) == ["/img/mix/medium/lany.webp", "/img/thumbnail/medium/lany.webp"])
        #expect(artistMix.offlineImageURLs == artistMix.coverURLs)
    }

    @Test func imagesWithoutAFileHaveNoURL() {
        #expect(Mix.imageURL(for: Mix.MixImageRef(image: nil, color: nil)) == nil)
    }

    // MARK: Labels

    @Test func coverLabelsMatchTheWebClient() {
        #expect(trackMix.typeLabel == "Track Mix")
        #expect(trackMix.coverTitle == "Think Fast")
        #expect(artistMix.typeLabel == "Artist Mix")
    }
}
