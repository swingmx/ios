import SwiftUI

enum LyricLineFitting {
    static func validWidth(_ width: CGFloat?) -> CGFloat? {
        guard let width, width.isFinite, width > 0 else {
            return nil
        }
        return width
    }

    static func fittingScale(
        for layout: Text.Layout,
        constrainedWidth: CGFloat?,
        trailingSafety: CGFloat
    ) -> CGFloat {
        1
    }

    static func drawingTransform(
        for line: Text.Layout.Line,
        scale: CGFloat,
        centersLine: Bool
    ) -> CGAffineTransform? {
        let bounds = line.typographicBounds.rect
        guard bounds.width.isFinite,
              bounds.width > 0,
              bounds.minX.isFinite,
              bounds.midY.isFinite else {
            return nil
        }

        let scale = min(max(scale, 0), 1)
        let translationX: CGFloat
        if centersLine {
            guard scale < 1 else { return nil }
            translationX = bounds.midX * (1 - scale)
        } else {
            translationX = -bounds.minX * scale
        }
        let translationY = bounds.midY * (1 - scale)

        guard scale < 1
                || abs(translationX) > 0.001
                || abs(translationY) > 0.001 else {
            return nil
        }
        return CGAffineTransform(
            a: scale,
            b: 0,
            c: 0,
            d: scale,
            tx: translationX,
            ty: translationY
        )
    }
}
