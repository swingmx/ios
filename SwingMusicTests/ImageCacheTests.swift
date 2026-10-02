import Testing
import UIKit
@testable import Swing_Music_Client

struct ImageCacheTests {
    private let original = URL(string: "http://server/img/thumbnail/original/al1.webp")!
    private let large = URL(string: "http://server/img/thumbnail/al1.webp")!
    private let medium = URL(string: "http://server/img/thumbnail/medium/al1.webp")!

    private func image(_ side: CGFloat) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { _ in }
    }

    @Test func aCachedSmallerSizeIsOnlyAFallbackForTheRequestedOne() {
        let small = image(256)

        let result = Img.cachedImage(for: [original, large, medium],
                                     memory: { _ in nil }, disk: { $0 == medium ? small : nil })

        #expect(result.exact == nil)
        #expect(result.preview === small)
    }

    @Test func theRequestedSizeWinsWhenItIsCached() {
        let full = image(1200), small = image(256)

        let result = Img.cachedImage(for: [original, medium],
                                     memory: { $0 == medium ? small : nil }, disk: { $0 == original ? full : nil })

        #expect(result.exact === full)
        #expect(result.preview == nil)
    }

    @Test func memoryIsCheckedBeforeDisk() {
        let inMemory = image(1200), onDisk = image(1200)

        let result = Img.cachedImage(for: [original], memory: { _ in inMemory }, disk: { _ in onDisk })

        #expect(result.exact === inMemory)
    }

    @Test func fallbacksFollowThePreferenceOrder() {
        let big = image(512), small = image(256)

        let result = Img.cachedImage(for: [original, large, medium],
                                     memory: { _ in nil }, disk: { $0 == large ? big : $0 == medium ? small : nil })

        #expect(result.preview === big)
    }

    @Test func nothingCachedMeansNothingToShow() {
        let result = Img.cachedImage(for: [original, medium], memory: { _ in nil }, disk: { _ in nil })

        #expect(result.exact == nil && result.preview == nil)
        #expect(Img.cachedImage(for: [], memory: { _ in nil }, disk: { _ in nil }).exact == nil)
    }
}
