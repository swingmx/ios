import SwiftUI
import UIKit
import Combine
import CoreText

private enum MeloXLayout {
    static let fontSize: CGFloat = 36
    static let lineSpacing: CGFloat = 25
    static let selectedLineTopRelativePercent: CGFloat = 12
    static let backgroundVocalsTopSpacing: CGFloat = 2
    static let backgroundVocalsFontCoefficient: CGFloat = 0.75
    static let backgroundVocalsDeselectedScale = 0.9
    static let deselectedScale = 0.98
    static let nearestLineBlurRadius = 1.0
    static let blurRadiusStepPerLine = 0.75
    static let maximumNonFocusedBlurRadius = 4.0
    static let scrollLead = 0.35
    static let wordLead = 0.15
    static let selectedTextOpacity = 1.0
    static let selectedUpcomingTextOpacity = 0.35
    static let deselectedTextOpacity = 0.175
}

@inline(__always) private func clamp01(_ x: Double) -> Double { min(max(x, 0), 1) }

private struct CubicBezier {
    private let cx, bx, ax, cy, by, ay: Double
    init(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) {
        cx = 3 * x1; bx = 3 * (x2 - x1) - cx; ax = 1 - cx - bx
        cy = 3 * y1; by = 3 * (y2 - y1) - cy; ay = 1 - cy - by
    }
    private func sx(_ t: Double) -> Double { ((ax * t + bx) * t + cx) * t }
    private func sy(_ t: Double) -> Double { ((ay * t + by) * t + cy) * t }
    private func dx(_ t: Double) -> Double { (3 * ax * t + 2 * bx) * t + cx }
    func callAsFunction(_ x: Double) -> Double {
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }
        var t = x
        for _ in 0..<8 {
            let e = sx(t) - x
            if abs(e) < 1e-6 { return sy(t) }
            let d = dx(t)
            if abs(d) < 1e-6 { break }
            t -= e / d
        }
        var lo = 0.0, hi = 1.0
        t = x
        for _ in 0..<32 {
            let v = sx(t)
            if abs(v - x) < 1e-6 { break }
            if x > v { lo = t } else { hi = t }
            t = (lo + hi) / 2
        }
        return sy(t)
    }
}

private let easeOut = CubicBezier(0, 0, 0.58, 1)
private let bezIn = CubicBezier(0.2, 0.4, 0.58, 1.0)
private let bezOut = CubicBezier(0.3, 0.0, 0.58, 1.0)

private func empEasing(_ x: Double) -> Double {
    x < 0.5 ? bezIn(clamp01(x / 0.5)) : 1 - bezOut(clamp01((x - 0.5) / 0.5))
}

struct AMLLSpring {
    var mass = 1.0, damping = 10.0, stiffness = 100.0
    private(set) var position: Double
    private(set) var target: Double
    private var from: Double
    private var v0 = 0.0
    private var t = 0.0
    private var resting = true
    private var queued: (position: Double, time: Double)?

    init(_ p: Double) { position = p; target = p; from = p }

    var arrived: Bool { resting && queued == nil }

    private func value(_ t: Double) -> Double {
        let delta = target - from
        if damping / (2 * (stiffness * mass).squareRoot()) >= 1 {
            let w = -(stiffness / mass).squareRoot()
            let left = -w * delta - v0
            return target - (delta + t * left) * exp(t * w)
        }
        let df = (4 * mass * stiffness - damping * damping).squareRoot()
        let left = (damping * delta - 2 * mass * v0) / df
        let dfm = 0.5 * df / mass
        let dm = -0.5 * damping / mass
        return target - (cos(t * dfm) * delta + sin(t * dfm) * left) * exp(t * dm)
    }

    private func velocity(_ t: Double) -> Double {
        if resting { return 0 }
        let h = 0.001
        return (value(t + h) - value(max(0, t - h))) / (t >= h ? 2 * h : h + t)
    }

    private mutating func reset() {
        let v = velocity(t)
        from = position; v0 = v; t = 0; resting = false
    }

    mutating func setPosition(_ p: Double) {
        target = p; position = p; from = p; v0 = 0; t = 0; resting = true; queued = nil
    }

    mutating func setTarget(_ p: Double, delay: Double = 0) {
        if delay > 0 { queued = (p, delay); return }
        queued = nil
        guard p != target else { return }
        target = p
        reset()
    }

    mutating func setParams(mass: Double? = nil, damping: Double? = nil, stiffness: Double? = nil) {
        if let mass { self.mass = mass }
        if let damping { self.damping = damping }
        if let stiffness { self.stiffness = stiffness }
        if !resting { reset() }
    }

    mutating func update(_ dt: Double) {
        if !resting {
            t += dt
            position = value(t)
        }
        if var q = queued {
            q.time -= dt
            if q.time <= 0 { queued = nil; setTarget(q.position) } else { queued = q }
        }
        if !resting, abs(target - position) < 0.01, abs(velocity(t)) < 0.01 {
            setPosition(target)
        }
    }
}

private enum LayerBlur {
    private static let filterClass = NSClassFromString("CAFilter") as? NSObject.Type

    static func set(_ layer: CALayer, radius: CGFloat) {
        if radius < 0.05 {
            if layer.filters != nil { layer.filters = nil }
            return
        }
        if layer.filters == nil {
            guard let cls = filterClass,
                  cls.responds(to: NSSelectorFromString("filterWithType:")),
                  let f = cls.perform(NSSelectorFromString("filterWithType:"), with: "gaussianBlur")?
                      .takeUnretainedValue() as? NSObject
            else { return }
            f.setValue("gaussianBlur", forKey: "name")
            f.setValue(radius, forKey: "inputRadius")
            layer.filters = [f]
        } else {
            layer.setValue(radius, forKeyPath: "filters.gaussianBlur.inputRadius")
        }
    }
}

enum AMLLFont {
    static func bold(_ size: CGFloat) -> UIFont {
        UIFont.systemFont(ofSize: size, weight: .bold)
    }

    static func semibold(_ size: CGFloat) -> UIFont {
        UIFont.systemFont(ofSize: size, weight: .semibold)
    }
}

private enum TextImage {
    static func attributes(_ font: UIFont, color: UIColor? = nil) -> [NSAttributedString.Key: Any] {
        var a: [NSAttributedString.Key: Any] = [.font: font]
        if let color { a[.foregroundColor] = color }
        return a
    }

    static func render(_ s: String, font: UIFont, size: CGSize, pad: CGFloat) -> CGImage? {
        let fmt = UIGraphicsImageRendererFormat.preferred()
        fmt.opaque = false
        let r = UIGraphicsImageRenderer(size: CGSize(width: size.width + pad * 2, height: size.height + pad * 2), format: fmt)
        return r.image { _ in
            let leading = (size.height - font.lineHeight) / 2
            (s as NSString).draw(at: CGPoint(x: pad, y: pad + leading), withAttributes: attributes(font, color: .white))
        }.cgImage
    }

    static func width(_ s: String, font: UIFont) -> CGFloat {
        ceil((s as NSString).size(withAttributes: attributes(font)).width)
    }
}

private final class AMLLSyllable {
    let text: String
    let start: Double
    let end: Double
    var width: CGFloat
    var charOffsets: [CGFloat] = []
    var frameX: CGFloat = 0
    var frameY: CGFloat = 0
    var stripOffset: CGFloat = 0
    var emphasis: AMLLEmphasis?
    var charBase = 0

    let layer = CALayer()
    let mask = CAGradientLayer()
    var charLayers: [CALayer] = []
    var floatP = 0.0
    var floatDur: Double { max(1, end - start) }

    init(text: String, start: Double, end: Double, width: CGFloat) {
        self.text = text; self.start = start; self.end = end; self.width = width
    }
}

private final class AMLLEmphasis {
    let start: Double
    let du: Double
    let amount: Double
    let blur: Double
    let charCount: Int

    init(start: Double, duration: Double, charCount: Int, isLastWord: Bool) {
        var du = max(1, duration)
        var amount = du / 2
        amount = amount > 1 ? amount.squareRoot() : pow(amount, 3)
        var blur = du / 3
        blur = blur > 1 ? blur.squareRoot() : pow(blur, 3)
        amount *= 0.6
        blur *= 0.5
        if isLastWord {
            amount *= 1.6
            blur *= 1.5
            du *= 1.2
        }
        self.start = start
        self.du = du
        self.amount = min(1.2, amount)
        self.blur = min(0.8, blur)
        self.charCount = max(1, charCount)
    }
}

private final class AMLLLineNode {
    let isBG: Bool
    let duet: Bool
    let font: UIFont
    let em: CGFloat
    let lineHeight: CGFloat
    let fadeWidth: CGFloat
    let syllables: [AMLLSyllable]
    let size: CGSize
    let stripWidth: CGFloat
    let start: Double
    let pad: CGFloat

    let layer = CALayer()
    var scale: AMLLSpring
    var gradient = false
    var enabled = false
    var built = false
    private var brightAlpha = 1.0
    private var darkAlpha = 0.2
    private var targetBright = 1.0
    private var targetDark = 0.2
    private var appliedBright = -1.0
    private var appliedDark = -1.0

    init(words: [AMLLWord], isBG: Bool, duet: Bool, fontSize: CGFloat, maxWidth: CGFloat) {
        self.isBG = isBG
        self.duet = duet
        font = isBG ? AMLLFont.semibold(fontSize) : AMLLFont.bold(fontSize)
        em = fontSize
        lineHeight = ceil(max(font.lineHeight, fontSize * 1.2))
        fadeWidth = lineHeight * 0.5
        pad = ceil(fontSize * 0.35)
        start = words.first?.start ?? 0
        scale = AMLLSpring(100)
        if isBG { scale.setParams(mass: 1, damping: 20, stiffness: 50) } else { scale.setParams(mass: 2, damping: 25, stiffness: 100) }

        var chunks: [[AMLLWord]] = [[]]
        for w in words {
            chunks[chunks.count - 1].append(w)
            if w.text.hasSuffix(" ") { chunks.append([]) }
        }
        chunks.removeAll { $0.isEmpty }

        let spaceW = TextImage.width(" ", font: font)
        var sylls: [AMLLSyllable] = []
        var rows: [[AMLLSyllable]] = [[]]
        var rowWidths: [CGFloat] = [0]
        var x: CGFloat = 0
        var strip: CGFloat = 0
        let lastText = words.last?.text.trimmingCharacters(in: .whitespaces) ?? ""

        let font = self.font
        for (ci, chunk) in chunks.enumerated() {
            let parts = chunk.map { w -> AMLLSyllable in
                let t = w.text.trimmingCharacters(in: .whitespaces)
                return AMLLSyllable(text: t, start: w.start, end: w.end, width: TextImage.width(t, font: font))
            }.filter { !$0.text.isEmpty }
            guard !parts.isEmpty else { continue }
            let mergedText = parts.map(\.text).joined()
            let ct = CTLineCreateWithAttributedString(NSAttributedString(string: mergedText, attributes: TextImage.attributes(font)))
            let chunkW = CGFloat(CTLineGetTypographicBounds(ct, nil, nil, nil))
            let totalU = mergedText.utf16.count
            let off: (Int) -> CGFloat = { u in u >= totalU ? chunkW : CTLineGetOffsetForStringIndex(ct, u, nil) }
            var inChunk: [CGFloat] = []
            var u = 0
            for p in parts {
                let a = off(u)
                var k = u
                p.charOffsets = p.text.map { ch -> CGFloat in
                    defer { k += String(ch).utf16.count }
                    return off(k) - a
                }
                u += p.text.utf16.count
                p.width = off(u) - a
                inChunk.append(a)
            }
            if x + chunkW > maxWidth, x > 0 {
                rows.append([]); rowWidths.append(0); x = 0
            }
            let merged = parts.map(\.text).joined()
            let mStart = parts.map(\.start).min() ?? 0
            let mEnd = parts.map(\.end).max() ?? 0
            let should: (String, Double) -> Bool = { s, d in d >= 1 && s.count <= 7 && s.count > 1 }
            let emp = parts.contains { should($0.text, $0.end - $0.start) } || should(merged, mEnd - mStart)
            let emphasis = emp ? AMLLEmphasis(
                start: mStart, duration: mEnd - mStart, charCount: merged.count,
                isLastWord: ci == chunks.count - 1 || (!lastText.isEmpty && merged.contains(lastText))
            ) : nil
            var charBase = 0
            for (pi, p) in parts.enumerated() {
                p.frameX = x + inChunk[pi]
                p.stripOffset = strip + inChunk[pi]
                p.emphasis = emphasis
                p.charBase = charBase
                charBase += p.text.count
                rows[rows.count - 1].append(p)
                sylls.append(p)
            }
            x += chunkW
            strip += chunkW
            rowWidths[rowWidths.count - 1] = x
            x += spaceW
        }

        let lh = lineHeight
        var maxRow: CGFloat = 0
        for (r, row) in rows.enumerated() {
            let shift = duet ? max(0, maxWidth - rowWidths[r]) : 0
            for s in row { s.frameX += shift; s.frameY = CGFloat(r) * lh }
            maxRow = max(maxRow, rowWidths[r])
        }
        syllables = sylls
        stripWidth = strip
        size = CGSize(width: maxWidth, height: CGFloat(max(1, rows.count)) * lh)

        let m = margin
        let full = CGSize(width: size.width + m * 2, height: size.height + m * 2)
        layer.anchorPoint = CGPoint(x: duet ? (full.width - m) / full.width : m / full.width, y: 0.5)
        layer.bounds = CGRect(origin: .zero, size: full)
    }

    var margin: CGFloat { ceil(em * 0.7) }

    func build() {
        guard !built else { return }
        built = true
        for s in syllables {
            let sz = CGSize(width: s.width, height: lineHeight)
            s.layer.anchorPoint = .zero
            s.layer.frame = CGRect(x: s.frameX - pad + margin, y: s.frameY - pad + margin, width: sz.width + pad * 2, height: sz.height + pad * 2)
            s.layer.contentsScale = UIScreen.main.scale
            if s.emphasis != nil {
                for (k, ch) in s.text.enumerated() {
                    let cx = k < s.charOffsets.count ? s.charOffsets[k] : 0
                    let cw = TextImage.width(String(ch), font: font)
                    let cl = CALayer()
                    cl.contentsScale = UIScreen.main.scale
                    cl.contents = TextImage.render(String(ch), font: font, size: CGSize(width: cw, height: lineHeight), pad: pad)
                    cl.frame = CGRect(x: cx, y: 0, width: cw + pad * 2, height: lineHeight + pad * 2)
                    cl.shadowColor = UIColor.white.cgColor
                    cl.shadowOffset = .zero
                    cl.shadowOpacity = 0
                    s.layer.addSublayer(cl)
                    s.charLayers.append(cl)
                }
            } else {
                s.layer.contents = TextImage.render(s.text, font: font, size: sz, pad: pad)
            }
            s.mask.frame = s.layer.bounds
            s.mask.startPoint = CGPoint(x: 0, y: 0.5)
            s.mask.endPoint = CGPoint(x: 1, y: 0.5)
            layer.addSublayer(s.layer)
        }
        appliedBright = -1
        appliedDark = -1
        lastEdge = .nan
        applyColors()
        updateWords(time: lastT, dt: 0, force: true)
    }

    func teardown() {
        guard built else { return }
        built = false
        masksOn = false
        for s in syllables {
            s.layer.removeFromSuperlayer()
            s.layer.contents = nil
            s.layer.mask = nil
            s.charLayers.forEach { $0.removeFromSuperlayer() }
            s.charLayers = []
        }
    }

    private func edge(at t: Double) -> CGFloat {
        var e = -fadeWidth / 2
        for (j, s) in syllables.enumerated() {
            if t < s.start { return e }
            let endE = j == syllables.count - 1 ? stripWidth + fadeWidth / 2 : syllables[j + 1].stripOffset
            if t < s.end, s.end > s.start {
                return e + (endE - e) * CGFloat((t - s.start) / (s.end - s.start))
            }
            e = endE
        }
        return e
    }

    private var lastEdge: CGFloat = .nan
    private var lastT = 0.0
    private var emphasisLive = false

    func updateWords(time t: Double, dt: Double, force: Bool = false) {
        lastT = t
        guard built else { return }
        let em = self.em
        emphasisLive = false
        if enabled {
            let e = edge(at: t)
            if force || lastEdge.isNaN || abs(e - lastEdge) > 0.2 {
                lastEdge = e
                for s in syllables {
                    let w = s.layer.bounds.width
                    let local = e - s.stripOffset + pad
                    s.mask.startPoint = CGPoint(x: (local - fadeWidth / 2) / w, y: 0.5)
                    s.mask.endPoint = CGPoint(x: (local + fadeWidth / 2) / w, y: 0.5)
                }
            }
        }
        let up = 0.05 * (isBG ? 2 : 1)
        for s in syllables {
            if enabled {
                s.floatP = clamp01((t - s.start) / s.floatDur)
            } else if s.floatP > 0 {
                s.floatP = max(0, s.floatP - dt / s.floatDur)
            }
            let y = -easeOut(s.floatP) * up * Double(em)
            s.layer.transform = CATransform3DMakeTranslation(0, CGFloat(y), 0)

            if let emp = s.emphasis, !s.charLayers.isEmpty {
                for (k, cl) in s.charLayers.enumerated() {
                    let i = s.charBase + k
                    let n = Double(emp.charCount)
                    let wordDe = emp.start + (emp.du / 2.5 / n) * Double(i)
                    let tt = t
                    let x = clamp01((tt - wordDe) / emp.du)
                    let active = enabled || x > 0 && x < 1
                    let transX = active ? empEasing(x) : 0
                    if transX > 0.0005 { emphasisLive = true }
                    let glow = transX * emp.blur
                    let sc = 1 + transX * 0.1 * emp.amount
                    let ox = -transX * 0.03 * emp.amount * (n / 2 - Double(i)) * Double(em)
                    var oy = -transX * 0.025 * emp.amount * Double(em)
                    let fx = clamp01((tt - (wordDe - 0.4)) / (emp.du * 1.4))
                    if active, fx > 0, fx < 1 { oy -= sin(fx * .pi) * 0.05 * Double(em) * (isBG ? 2 : 1) }
                    cl.transform = CATransform3DTranslate(CATransform3DMakeScale(CGFloat(sc), CGFloat(sc), 1), CGFloat(ox), CGFloat(oy), 0)
                    let op = Float(min(1, glow))
                    if abs(cl.shadowOpacity - op) > 0.005 {
                        cl.shadowOpacity = op
                        cl.shadowRadius = CGFloat(min(0.3, emp.blur * 0.3)) * em * 0.6
                    }
                }
            }
        }
    }

    var needsWordUpdates: Bool {
        enabled || emphasisLive || syllables.contains { $0.floatP > 0 }
    }

    func update(dt: Double) {
        scale.update(dt)
        let sc = scale.position / 100
        let factor = clamp01((sc - MeloXLayout.deselectedScale) / (1 - MeloXLayout.deselectedScale))
        let lo = MeloXLayout.deselectedTextOpacity
        let dynDark = lo + factor * (MeloXLayout.selectedUpcomingTextOpacity - lo)
        let dynBright = lo + factor * (MeloXLayout.selectedTextOpacity - lo)
        targetBright = gradient ? dynBright : dynDark
        targetDark = dynDark

        let f: (Double) -> Double = { 1 - exp(-$0 * max(dt, 0.001)) }
        let bs = targetBright > brightAlpha ? 50.0 : 7.0
        brightAlpha = abs(targetBright - brightAlpha) < 0.001 ? targetBright : brightAlpha + (targetBright - brightAlpha) * f(bs)
        let ds = targetDark > darkAlpha ? 50.0 : 7.0
        darkAlpha = abs(targetDark - darkAlpha) < 0.001 ? targetDark : darkAlpha + (targetDark - darkAlpha) * f(ds)

        applyColors()
    }

    func snapAlpha() {
        let sc = scale.position / 100
        let factor = clamp01((sc - MeloXLayout.deselectedScale) / (1 - MeloXLayout.deselectedScale))
        let lo = MeloXLayout.deselectedTextOpacity
        darkAlpha = lo + factor * (MeloXLayout.selectedUpcomingTextOpacity - lo)
        brightAlpha = gradient ? lo + factor * (MeloXLayout.selectedTextOpacity - lo) : darkAlpha
        applyColors()
    }

    var alphaSettled: Bool { brightAlpha == targetBright && darkAlpha == targetDark && scale.arrived }

    private var masksOn = false

    private func applyColors() {
        guard built, abs(appliedBright - brightAlpha) > 0.002 || abs(appliedDark - darkAlpha) > 0.002 else { return }
        appliedBright = brightAlpha
        appliedDark = darkAlpha
        let needsMask = gradient || abs(brightAlpha - darkAlpha) > 0.002
        if needsMask {
            let colors = [UIColor(white: 1, alpha: brightAlpha).cgColor, UIColor(white: 1, alpha: darkAlpha).cgColor]
            for s in syllables {
                s.mask.colors = colors
                if !masksOn { s.mask.frame = s.layer.bounds; s.layer.mask = s.mask; s.layer.opacity = 1 }
            }
            if !masksOn { masksOn = true; lastEdge = .nan; updateWords(time: lastT, dt: 0, force: true) }
        } else {
            for s in syllables {
                if masksOn { s.layer.mask = nil }
                s.layer.opacity = Float(darkAlpha)
            }
            masksOn = false
        }
    }

    var contentStatic: Bool { !masksOn && alphaSettled && !needsWordUpdates }
}

private final class AMLLGroupNode {
    let main: AMLLLineNode
    let bg: AMLLLineNode?
    let start: Double
    let end: Double
    let em: CGFloat
    let padX: CGFloat
    let isCredits: Bool
    let width: CGFloat
    let inset: CGFloat
    var fixedHeight: CGFloat?

    let layer = CALayer()
    let bgWrapper = CALayer()
    var posY = AMLLSpring(0)
    var bgSlide = AMLLSpring(0)
    var isActive = false
    var targetOpacity = 1.0
    var opacity = 1.0
    var targetBlur = 0.0
    var blur = 0.0
    var bgOpacity = 1.0
    private var appliedScale: CGFloat = 1
    static var rasterBudget = 1
    private var appliedBlur = -1.0

    init(main: AMLLLineNode, bg: AMLLLineNode?, start: Double, end: Double, em: CGFloat, padX: CGFloat, width: CGFloat, isCredits: Bool = false) {
        self.main = main; self.bg = bg; self.start = start; self.end = end
        self.em = em; self.padX = padX; self.isCredits = isCredits; self.width = width
        inset = em * 0.7
        layer.anchorPoint = .zero
        layer.backgroundColor = UIColor.black.withAlphaComponent(0.002).cgColor
        let mainX = main.duet ? width - padX : padX
        main.layer.position = CGPoint(x: mainX + inset, y: main.size.height / 2 + inset)
        layer.addSublayer(main.layer)
        if let bg {
            let bm = bg.margin
            let bfull = CGSize(width: bg.size.width + bm * 2, height: bg.size.height + bm * 2)
            bgWrapper.anchorPoint = CGPoint(x: bg.duet ? (bfull.width - bm) / bfull.width : bm / bfull.width, y: bm / bfull.height)
            bgWrapper.bounds = CGRect(origin: .zero, size: bfull)
            bgWrapper.position = CGPoint(x: mainX + inset, y: main.size.height + MeloXLayout.backgroundVocalsTopSpacing + inset)
            bg.layer.position = CGPoint(x: bm + (bg.duet ? bg.size.width : 0), y: bm + bg.size.height / 2)
            bgWrapper.addSublayer(bg.layer)
            bgWrapper.opacity = 0
            layer.addSublayer(bgWrapper)
        }
        posY.setParams(mass: 0.9, damping: 15, stiffness: 90)
        bgSlide.setParams(mass: 0.9, damping: 15, stiffness: 90)
    }

    func height(playing: Bool) -> CGFloat {
        if let fixedHeight { return fixedHeight }
        var h = main.size.height + MeloXLayout.lineSpacing
        if let bg { h += MeloXLayout.backgroundVocalsTopSpacing + bg.size.height }
        return h
    }

    func setTransform(top: Double, force: Bool, delay: Double, active: Bool, opacity: Double, blur: Double, playing: Bool) {
        isActive = active
        targetOpacity = opacity
        targetBlur = min(5, blur)
        let mainScale: Double = (!active && playing) ? MeloXLayout.deselectedScale * 100 : 100
        let bgScale: Double = mainScale
        main.gradient = active
        bg?.gradient = active
        let slide: Double = 0
        if force {
            posY.setPosition(top)
            renderPosition(top, delay: 0, animated: false)
            bgSlide.setPosition(slide)
            main.scale.setPosition(mainScale)
            bg?.scale.setPosition(bgScale)
            self.opacity = opacity
            self.blur = targetBlur
            main.snapAlpha()
            bg?.snapAlpha()
        } else {
            posY.setTarget(top, delay: delay)
            renderPosition(top, delay: delay, animated: true)
            bgSlide.setTarget(slide, delay: delay)
            main.scale.setTarget(mainScale)
            bg?.scale.setTarget(bgScale)
        }
    }

    private var renderedY: CGFloat?

    private func renderPosition(_ top: Double, delay: Double, animated: Bool) {
        let newY = CGFloat(top) - inset
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        guard animated, let old = renderedY else {
            layer.removeAnimation(forKey: "y")
            layer.removeAllAnimations()
            layer.position = CGPoint(x: -inset, y: newY)
            renderedY = newY
            return
        }
        guard abs(old - newY) > 0.1 else { return }
        layer.position = CGPoint(x: -inset, y: newY)
        renderedY = newY
        let a = CASpringAnimation(keyPath: "position.y")
        a.isAdditive = true
        a.fromValue = old - newY
        a.toValue = 0
        a.mass = CGFloat(posY.mass)
        a.stiffness = CGFloat(posY.stiffness)
        a.damping = CGFloat(posY.damping)
        a.duration = a.settlingDuration
        a.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil) + max(0, delay)
        a.fillMode = .backwards
        a.isRemovedOnCompletion = true
        animationSerial &+= 1
        layer.add(a, forKey: "y\(animationSerial)")
    }

    private var animationSerial = 0

    func enable() { main.enabled = true; bg?.enabled = true }
    func disable() { main.enabled = false; bg?.enabled = false }

    func isInSight(viewHeight: CGFloat, playing: Bool) -> Bool {
        let t = CGFloat(posY.position)
        let h = height(playing: playing)
        let ov = viewHeight * 0.5
        return !(t > viewHeight + h + ov || t < -h - ov)
    }

    func update(dt: Double, time: Double, viewHeight: CGFloat, playing: Bool) {
        posY.update(dt)
        bgSlide.update(dt)
        let k = 1 - exp(-8 * dt)
        opacity += (targetOpacity - opacity) * k
        blur += (targetBlur - blur) * k
        if abs(opacity - targetOpacity) < 0.002 { opacity = targetOpacity }
        if abs(blur - targetBlur) < 0.01 { blur = targetBlur }

        let visible = isInSight(viewHeight: viewHeight, playing: playing)
        layer.isHidden = !visible
        if visible {
            main.build(); bg?.build()
        } else {
            main.teardown(); bg?.teardown()
            return
        }

        let p = inset
        let b = CGRect(x: 0, y: 0, width: width + p * 2, height: height(playing: playing) + p * 2)
        if layer.bounds != b { layer.bounds = b }
        if renderedY == nil { renderPosition(posY.position, delay: 0, animated: false) }
        _ = p
        if layer.opacity != Float(opacity) { layer.opacity = Float(opacity) }
        let r = (blur * 4).rounded() / 4
        if r != appliedBlur { appliedBlur = r; LayerBlur.set(layer, radius: CGFloat(r)) }

        main.update(dt: dt)
        let sc = CGFloat(main.scale.position / 100)
        if abs(sc - appliedScale) > 0.0005 {
            appliedScale = sc
            let px = inset + (main.duet ? width - padX : padX)
            let py = inset + main.size.height / 2
            var t = CATransform3DMakeTranslation(px, py, 0)
            t = CATransform3DScale(t, sc, sc, 1)
            t = CATransform3DTranslate(t, -px, -py, 0)
            layer.transform = t
        }
        if main.needsWordUpdates { main.updateWords(time: time, dt: dt) }
        defer {
            let still = !isActive && main.contentStatic && (bg?.contentStatic ?? true)
                && blur == targetBlur && bgSlide.arrived && (bg == nil || bgOpacity == 0 || bgOpacity == 1)
            if layer.shouldRasterize != still {
                if !still {
                    layer.shouldRasterize = false
                } else if AMLLGroupNode.rasterBudget > 0 {
                    AMLLGroupNode.rasterBudget -= 1
                    layer.rasterizationScale = UIScreen.main.scale
                    layer.shouldRasterize = true
                }
            }
        }
        if let bg {
            bg.update(dt: dt)
            if bg.needsWordUpdates { bg.updateWords(time: time, dt: dt) }
            let slide = bgSlide.position
            let p = clamp01(1 - abs(slide) / 80)
            let s = CGFloat(0.8 + p * 0.2)
            var tr = CATransform3DMakeTranslation(0, CGFloat(slide / 100) * bg.size.height, 0)
            tr = CATransform3DScale(tr, s, s, 1)
            bgWrapper.transform = tr
            let target = 1.0
            bgOpacity += (target - bgOpacity) * (1 - exp(-10 * dt))
            if abs(bgOpacity - target) < 0.002 { bgOpacity = target }
            bgWrapper.opacity = Float(bgOpacity)
        }
    }

    var settled: Bool {
        posY.arrived && bgSlide.arrived && opacity == targetOpacity && blur == targetBlur
            && main.alphaSettled && (bg?.alphaSettled ?? true) && !main.needsWordUpdates && !(bg?.needsWordUpdates ?? false)
    }
}

private final class AMLLInterludeDots {
    let layer = CALayer()
    let dots = [CALayer(), CALayer(), CALayer()]
    var interlude: (start: Double, end: Double)?
    var anchor = Int.min
    let dotSize: CGFloat
    let size: CGSize
    var x: CGFloat = 0
    var posY = AMLLSpring(0)

    init(em: CGFloat, width: CGFloat) {
        dotSize = 12
        let gap: CGFloat = 8
        size = CGSize(width: dotSize * 3 + gap * 2, height: 40)
        layer.bounds = CGRect(origin: .zero, size: size)
        for (i, d) in dots.enumerated() {
            d.backgroundColor = UIColor.white.cgColor
            d.cornerRadius = dotSize / 2
            d.frame = CGRect(x: CGFloat(i) * (dotSize + gap), y: (size.height - dotSize) / 2, width: dotSize, height: dotSize)
            d.opacity = 0
            layer.addSublayer(d)
        }
        layer.opacity = 0
        posY.setParams(mass: 0.9, damping: 15, stiffness: 90)
    }

    private static func easeInOutBack(_ x: Double) -> Double {
        let c1 = 1.70158, c2 = c1 * 1.525
        return x < 0.5
            ? (pow(2 * x, 2) * ((c2 + 1) * 2 * x - c2)) / 2
            : (pow(2 * x - 2, 2) * ((c2 + 1) * (x * 2 - 2) + c2) + 2) / 2
    }

    func update(time: Double, dt: Double) {
        posY.update(dt)
        guard let iv = interlude else {
            layer.opacity = max(0, layer.opacity - Float(dt / 0.25))
            return
        }
        layer.opacity = min(1, layer.opacity + Float(dt / 0.25))
        let total = (iv.end - iv.start) * 1000
        let cur = (time - iv.start) * 1000
        var scale = 1.0
        var global = 1.0
        var o = [0.0, 0.0, 0.0]
        if cur <= total, cur >= 0 {
            let breathe = total / ceil(total / 1500)
            scale *= sin(1.5 * .pi - (cur / breathe) * 2) / 20 + 1
            if cur < 2000 { scale *= cur / 2000 >= 1 ? 1 : 1 - pow(2, -10 * cur / 2000) }
            if cur < 500 { global = 0 } else if cur < 1000 { global *= (cur - 500) / 500 }
            if total - cur < 750 { scale *= 1 - Self.easeInOutBack((750 - (total - cur)) / 750 / 2) }
            if total - cur < 375 { global *= clamp01((total - cur) / 375) }
            let dd = max(0, total - 750)
            scale = max(0, scale)
            o[0] = min(max(0.25, (cur * 3 / dd) * 0.75), 1)
            o[1] = min(max(0.25, ((cur - dd / 3) * 3 / dd) * 0.75), 1)
            o[2] = min(max(0.25, ((cur - dd / 3 * 2) * 3 / dd) * 0.75), 1)
        } else {
            scale = 0
        }
        for i in 0..<3 { dots[i].opacity = Float(clamp01(global * o[i])) }
        layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer.position = CGPoint(x: x + size.width / 2, y: CGFloat(posY.position) + size.height / 2)
        layer.transform = CATransform3DMakeScale(CGFloat(scale), CGFloat(scale), 1)
    }
}

final class AMLLPlayerUIView: UIView, UIScrollViewDelegate {
    static let overflow: CGFloat = 28

    var bottomInset: CGFloat = 0 { didSet { if oldValue != bottomInset { needsLayout = true } } }

    private var source: [AMLLLine] = []
    private var credits: [String] = []
    private var groups: [AMLLGroupNode] = []
    private var creditsGroup: AMLLGroupNode?
    private var dots: AMLLInterludeDots?
    private var builtWidth: CGFloat = 0
    private var em: CGFloat = 30

    private var hot = Set<Int>()
    private var buffered = Set<Int>()
    private var scrollToIndex = 0
    private var targetAlignIndex = -1
    private var lastInterlude = false
    private var isSeeking = false
    private var needsLayout = false
    private var forceNext = true

    private var scrollOffset: CGFloat = 0
    private var isUserScrolling = false
    private var scrollStart: CGFloat = 0
    private var scrollMin: CGFloat = 0
    private var scrollMax: CGFloat = 0
    private var scrollResetWork: DispatchWorkItem?

    private let player = AudioPlayer.shared
    private var anchorTime = 0.0
    private var anchorHost = CACurrentMediaTime()
    private var playing = false
    private var bag = Set<AnyCancellable>()
    private var link: CADisplayLink?
    private var lastTick: CFTimeInterval = 0
    private var idleFrames = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        clipsToBounds = false
        anchorTime = player.time
        playing = player.playing

        player.$time.receive(on: RunLoop.main).sink { [weak self] t in self?.receiveTime(t) }.store(in: &bag)
        player.$playing.receive(on: RunLoop.main).sink { [weak self] p in self?.receivePlaying(p) }.store(in: &bag)

        scroller.delegate = self
        scroller.showsVerticalScrollIndicator = false
        scroller.alwaysBounceVertical = true
        scroller.backgroundColor = .clear
        scroller.contentInsetAdjustmentBehavior = .never
        addSubview(scroller)
        scroller.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(onTap(_:))))
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit { link?.invalidate() }

    private var now: Double {
        if debugFakePlay { return playing ? anchorTime + (CACurrentMediaTime() - anchorHost) : anchorTime }
        return player.smoothTime()
    }

    private var lastReceived: (t: Double, host: CFTimeInterval)?

    private func receiveTime(_ t: Double) {
        if debugFakePlay { return }
        let hostNow = CACurrentMediaTime()
        if let last = lastReceived {
            let expected = last.t + (playing ? hostNow - last.host : 0)
            if abs(t - expected) > 0.35 { isSeeking = true }
        }
        lastReceived = (t, hostNow)
        wake()
    }

    #if DEBUG
    private let debugFakePlay = UserDefaults.standard.bool(forKey: "debugFakePlay")
    #else
    private let debugFakePlay = false
    #endif

    private func receivePlaying(_ p: Bool) {
        if debugFakePlay {
            if !playing { anchorTime = UserDefaults.standard.double(forKey: "captureSeek"); anchorHost = CACurrentMediaTime() }
            playing = true; needsLayout = true; wake(); return
        }
        anchorTime = now
        anchorHost = CACurrentMediaTime()
        playing = p
        needsLayout = true
        wake()
    }

    func setContent(lines: [AMLLLine], credits: [String]) {
        guard lines.map(\.id) != source.map(\.id) || credits != self.credits else { return }
        source = lines
        self.credits = credits
        builtWidth = 0
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if scroller.frame != bounds { scroller.frame = bounds; syncScroller() }
        if bounds.width > 0, abs(bounds.width - builtWidth) > 0.5 { rebuild() }
    }

    private func rebuild() {
        builtWidth = bounds.width
        groups.forEach { $0.layer.removeFromSuperlayer() }
        creditsGroup?.layer.removeFromSuperlayer()
        dots?.layer.removeFromSuperlayer()

        let W = bounds.width
        em = W - Self.overflow * 2 > 500 ? MeloXLayout.fontSize * 1.3 : MeloXLayout.fontSize
        let padX: CGFloat = Self.overflow
        let hasDuet = source.contains { $0.opposite }
        let lineW = W - padX * 2
        let mainW = hasDuet ? lineW * 0.85 : lineW

        groups = source.map { l in
            let main = AMLLLineNode(words: l.words, isBG: false, duet: l.opposite, fontSize: em, maxWidth: mainW)
            let bg = l.bg.isEmpty ? nil : AMLLLineNode(words: l.bg, isBG: true, duet: l.opposite, fontSize: max(10, em * MeloXLayout.backgroundVocalsFontCoefficient), maxWidth: mainW)
            return AMLLGroupNode(main: main, bg: bg, start: l.start, end: l.end, em: em, padX: padX, width: W)
        }
        for g in groups {
            g.layer.compositingFilter = "plusL"
            layer.addSublayer(g.layer)
        }

        if credits.isEmpty {
            creditsGroup = nil
        } else {
            let g = AMLLCreditsGroup.make(lines: credits, em: em, padX: padX, width: W)
            creditsGroup = g
            layer.addSublayer(g.layer)
        }

        let d = AMLLInterludeDots(em: em, width: W)
        dots = d
        layer.addSublayer(d.layer)

        hot = []; buffered = []; scrollToIndex = 0; targetAlignIndex = -1
        isSeeking = true
        forceNext = true
        setCurrentTime(now)
        calcLayout(force: true)
        forceNext = false
        print("🎤 AMLL frame im Fenster: \(convert(bounds, to: nil)), clips: \(clipsToBounds)")
        print("🎤 AMLL rebuild: Font \(AMLLFont.bold(10).fontName), \(groups.count) Zeilen, Größe \(bounds.size), Schrift \(em), aktiv \(scrollToIndex), y0 \(groups.first.map { $0.posY.position } ?? -1)")
        wake()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            if link == nil {
                let l = CADisplayLink(target: AMLLWeakTarget(self), selector: #selector(AMLLWeakTarget.tick(_:)))
                l.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
                l.add(to: .main, forMode: .common)
                link = l
                lastTick = 0
            }
        } else {
            link?.invalidate()
            link = nil
        }
    }

    private func wake() {
        idleFrames = 0
        link?.isPaused = false
    }

    fileprivate func tick(_ link: CADisplayLink) {
        let dt = lastTick == 0 ? 1.0 / 60 : min(0.1, link.timestamp - lastTick)
        lastTick = link.timestamp
        guard !groups.isEmpty else { return }
        let t = now

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        AMLLGroupNode.rasterBudget = 1
        setCurrentTime(t)
        if needsLayout { needsLayout = false; calcLayout(force: false) }
        let h = bounds.height
        var allSettled = true
        for g in groups {
            g.update(dt: dt, time: t + MeloXLayout.wordLead, viewHeight: h, playing: playing)
            if !g.settled { allSettled = false }
        }
        creditsGroup?.update(dt: dt, time: t, viewHeight: h, playing: playing)
        dots?.update(time: t, dt: dt)
        CATransaction.commit()

        if !playing, !isUserScrolling, allSettled, dots?.interlude == nil {
            idleFrames += 1
            if idleFrames > 30 { link.isPaused = true; lastTick = 0 }
        } else {
            idleFrames = 0
        }
    }

    private func setCurrentTime(_ t: Double) {
        let seeking = isSeeking
        isSeeking = false
        let lead = t + MeloXLayout.scrollLead
        var next = hot
        var added = Set<Int>(), removedHot = Set<Int>(), removedBuf = Set<Int>()
        for id in hot {
            let g = groups[id]
            if lead < g.start || g.end <= t { next.remove(id); removedHot.insert(id) }
        }
        for (id, g) in groups.enumerated() where g.start <= lead && g.end > t && !next.contains(id) {
            next.insert(id); added.insert(id)
        }
        for id in buffered where !next.contains(id) { removedBuf.insert(id) }
        hot = next

        var layout = false
        if seeking {
            buffered = hot
            if let m = buffered.min() {
                scrollToIndex = m
            } else {
                scrollToIndex = groups.firstIndex { $0.start >= lead } ?? groups.count
            }
            for id in removedHot.union(removedBuf) { groups[id].disable() }
            for id in hot { groups[id].enable() }
            scrollOffset = 0
            isUserScrolling = false
            layout = true
            seekLayout = true
        } else if !added.isEmpty {
            for id in added { buffered.insert(id); groups[id].enable() }
            for id in removedBuf { buffered.remove(id); groups[id].disable() }
            // A line ending within the lead stops holding the scroll, so the new line scrolls into place
            // before it starts. It is still in `hot`, so it stays highlighted until it ends.
            for id in buffered where !added.contains(id) && groups[id].end <= lead { buffered.remove(id) }
            if let m = buffered.min() { scrollToIndex = m }
            layout = true
        } else if !removedBuf.isEmpty, removedBuf == buffered {
            for id in buffered where !hot.contains(id) { buffered.remove(id); groups[id].disable() }
            layout = true
        } else if !removedHot.isEmpty {
            // A line released early above has now ended: dim it.
            for id in removedHot where !buffered.contains(id) { groups[id].disable() }
            layout = true
        }

        if buffered.isEmpty, let last = groups.last, t >= last.end {
            let target = creditsGroup != nil ? groups.count : groups.count - 1
            if scrollToIndex != target { scrollToIndex = target; layout = true }
        }
        if layout { needsLayout = true }
        lastTime = t
    }

    private var lastTime = 0.0
    private var seekLayout = false

    private func computeInterlude(_ time: Double) -> (start: Double, end: Double, anchor: Int, duet: Bool)? {
        let t = time + 0.02
        func check(_ k: Int) -> (Double, Double, Int, Bool)? {
            guard k >= -1, k < groups.count - 1 else { return nil }
            let gapStart = k == -1 ? 0 : groups[k].end
            let next = groups[k + 1]
            let gapEnd = max(gapStart, next.start - 0.25)
            guard gapEnd - gapStart >= 4 else { return nil }
            if gapEnd > t, gapStart < t {
                return (max(gapStart, t), gapEnd, k, next.main.duet)
            }
            return nil
        }
        return check(scrollToIndex - 1) ?? check(scrollToIndex) ?? check(scrollToIndex + 1)
    }

    private func calcLayout(force: Bool) {
        guard !groups.isEmpty else { return }
        let seeking = seekLayout
        seekLayout = false
        let interlude = computeInterlude(lastTime)
        let hasInterlude = interlude != nil

        if targetAlignIndex != scrollToIndex || lastInterlude != hasInterlude {
            lastInterlude = hasInterlude
            var params: (Double, Double)?
            if seeking || hasInterlude {
                params = (90, 15)
            } else if scrollToIndex > 0, scrollToIndex < groups.count {
                let interval = (groups[scrollToIndex].start - groups[scrollToIndex - 1].start) * 1000
                let ci = min(max(interval, 100), 800)
                let ratio = pow(1 - (ci - 100) / 700, 0.2)
                let st = 170 + ratio * 50
                params = (st, st.squareRoot() * 2.2)
            }
            if let (st, dm) = params {
                for g in groups {
                    g.posY.setParams(damping: dm, stiffness: st)
                    g.bgSlide.setParams(damping: dm, stiffness: st)
                }
                creditsGroup?.posY.setParams(damping: dm, stiffness: st)
            }
        }

        let latest = buffered.max() ?? Int.min
        var presentation: [(active: Bool, opacity: Double, blur: Double)] = []
        presentation.reserveCapacity(groups.count)
        for i in groups.indices {
            let hasBuf = buffered.contains(i)
            let active = hasBuf || hot.contains(i) || (i >= scrollToIndex && i < latest)
            presentation.append((active, hasBuf ? 0.85 : 1, lineBlur(i, active: active, latest: latest)))
            groups[i].isActive = active
        }

        let viewH = max(bounds.height - bottomInset, bounds.height * 0.5)
        let fallback = bounds.height / 5
        let heights = groups.map { $0.height(playing: playing) }
        let dotMargin: CGFloat = 0
        let dotsH = dots?.size.height ?? 0

        let ascender = AMLLFont.bold(em).ascender
        let focusTop = max(60, viewH * MeloXLayout.selectedLineTopRelativePercent / 100 - ascender)
        let dotsAbove: CGFloat = interlude.map { $0.anchor != -1 ? dotsH + MeloXLayout.lineSpacing : 0 } ?? 0
        let dotsInList: CGFloat = interlude == nil ? 0 : dotsH + MeloXLayout.lineSpacing

        var before = heights.prefix(min(scrollToIndex, heights.count)).reduce(0, +)
        if let lastH = heights.last {
            let lastTop = heights.dropLast().reduce(0, +) + dotsInList - dotsAbove + focusTop
            let middle = min(bounds.height / 2, viewH - lastH / 2)
            before = min(before, max(0, lastTop - (middle - lastH / 2)))
        }
        scrollMin = -before
        if isUserScrolling { scrollOffset = scroller.contentOffset.y - before }
        var cur = -scrollOffset - dotsAbove - before + focusTop
        let targetH: CGFloat = scrollToIndex < groups.count
            ? heights[scrollToIndex]
            : (creditsGroup?.height(playing: playing) ?? fallback)
        _ = targetH
        targetAlignIndex = scrollToIndex

        var delay = 0.0
        var base = force ? 0 : 0.05
        var setDots = false
        if interlude == nil { dots?.interlude = nil; dots?.anchor = .min }

        for (i, g) in groups.enumerated() {
            if !setDots, let iv = interlude, i == iv.anchor + 1, let d = dots {
                setDots = true
                cur += dotMargin
                d.x = iv.duet ? bounds.width - Self.overflow - d.size.width : Self.overflow
                if force { d.posY.setPosition(cur) } else { d.posY.setTarget(cur, delay: delay) }
                if d.anchor != iv.anchor { d.anchor = iv.anchor; d.interlude = (iv.start, iv.end) }
                cur += dotsH + MeloXLayout.lineSpacing
            }
            let p = presentation[i]
            g.setTransform(top: cur, force: force, delay: delay, active: p.active, opacity: p.opacity, blur: p.blur, playing: playing)
            cur += heights[i]
            if cur >= 0, !seeking {
                delay += base
                if i >= scrollToIndex { base /= 1.05 }
            }
        }
        scrollMax = cur + scrollOffset - bounds.height / 2
        syncScroller()
        if let c = creditsGroup {
            let b = lineBlur(groups.count, active: scrollToIndex == groups.count, latest: latest)
            _ = b
            c.setTransform(top: cur, force: force, delay: delay, active: false, opacity: 1, blur: 0, playing: false)
        }
    }

    private func lineBlur(_ i: Int, active: Bool, latest: Int) -> Double {
        if isUserScrolling || active { return 0 }
        let d = i < scrollToIndex ? scrollToIndex - i : i - max(scrollToIndex, latest)
        let blur = MeloXLayout.nearestLineBlurRadius + MeloXLayout.blurRadiusStepPerLine * Double(max(d - 1, 0))
        return min(blur, MeloXLayout.maximumNonFocusedBlurRadius)
    }

    private let scroller = UIScrollView()

    private func syncScroller() {
        guard !isUserScrolling, !scroller.isTracking, !scroller.isDecelerating else { return }
        let range = max(0, scrollMax - scrollMin)
        let size = CGSize(width: bounds.width, height: range + bounds.height)
        if scroller.contentSize != size { scroller.contentSize = size }
        let y = min(max(scrollOffset - scrollMin, 0), range)
        if abs(scroller.contentOffset.y - y) > 0.5 { scroller.contentOffset = CGPoint(x: 0, y: y) }
    }

    private func restartScrollReset() {
        scrollResetWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.scroller.isTracking, !self.scroller.isDecelerating else { return }
            self.isUserScrolling = false
            self.scrollOffset = 0
            self.needsLayout = true
            self.wake()
        }
        scrollResetWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
    }

    func scrollViewWillBeginDragging(_ sv: UIScrollView) {
        scrollResetWork?.cancel()
        isUserScrolling = true
        wake()
    }

    func scrollViewDidScroll(_ sv: UIScrollView) {
        guard isUserScrolling else { return }
        scrollOffset = sv.contentOffset.y + scrollMin
        calcLayout(force: true)
        wake()
    }

    func scrollViewDidEndDragging(_ sv: UIScrollView, willDecelerate: Bool) {
        if !willDecelerate { restartScrollReset() }
    }

    func scrollViewDidEndDecelerating(_ sv: UIScrollView) {
        restartScrollReset()
    }

    @objc private func onTap(_ g: UITapGestureRecognizer) {
        let y = g.location(in: self).y
        for grp in groups where !grp.layer.isHidden {
            let top = CGFloat(grp.posY.position)
            if y >= top, y <= top + grp.height(playing: playing) {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                scrollResetWork?.cancel()
                isUserScrolling = false
                scrollOffset = 0
                player.seek(max(0, grp.start))
                return
            }
        }
    }

}

private final class AMLLWeakTarget: NSObject {
    weak var view: AMLLPlayerUIView?
    init(_ v: AMLLPlayerUIView) { view = v }
    @objc func tick(_ l: CADisplayLink) {
        if let view { view.tick(l) } else { l.invalidate() }
    }
}

private enum AMLLCreditsGroup {
    static func make(lines: [String], em: CGFloat, padX: CGFloat, width: CGFloat) -> AMLLGroupNode {
        let font = AMLLFont.semibold(em * 0.47)
        let lh = ceil(font.lineHeight)
        let maxW = width - padX * 2
        let h = CGFloat(lines.count) * (lh + 4)
        let main = AMLLLineNode(words: [], isBG: false, duet: false, fontSize: 13, maxWidth: maxW)
        let text = CALayer()
        text.contentsScale = UIScreen.main.scale
        let fmt = UIGraphicsImageRendererFormat.preferred()
        fmt.opaque = false
        text.contents = UIGraphicsImageRenderer(size: CGSize(width: maxW, height: h), format: fmt).image { _ in
            for (i, s) in lines.enumerated() {
                (s as NSString).draw(
                    in: CGRect(x: 0, y: CGFloat(i) * (lh + 4), width: maxW, height: lh + 2),
                    withAttributes: TextImage.attributes(font, color: UIColor.white.withAlphaComponent(0.6))
                )
            }
        }.cgImage
        text.frame = CGRect(x: padX + em * 0.7, y: 4 + em * 0.7, width: maxW, height: h)
        let g = AMLLGroupNode(main: main, bg: nil, start: .infinity, end: .infinity, em: em, padX: padX, width: width, isCredits: true)
        g.main.layer.isHidden = true
        g.layer.addSublayer(text)
        g.fixedHeight = h + 8
        return g
    }
}

private struct AMLLPlayerRepresentable: UIViewRepresentable {
    let lines: [AMLLLine]
    let credits: [String]
    let bottomInset: CGFloat

    func makeUIView(context: Context) -> AMLLPlayerUIView {
        let v = AMLLPlayerUIView(frame: .zero)
        v.bottomInset = bottomInset
        v.setContent(lines: lines, credits: credits)
        return v
    }

    func updateUIView(_ v: AMLLPlayerUIView, context: Context) {
        v.bottomInset = bottomInset
        v.setContent(lines: lines, credits: credits)
    }
}

struct NativeAMLLLyricsView: View {
    var bottomInset: CGFloat = 341
    var topInset: CGFloat = 0
    // Whether the lyrics are on screen. Lyrics are only searched for while they are.
    var isActive = true
    var onReady: (() -> Void)? = nil

    @Environment(AppState.self) private var appState
    @StateObject private var engine = AMLLEngine()
    @State private var appLyrics: ParsedLyrics?
    @State private var trackID: String?

    // How long the word-by-word search may run before the app's own search starts alongside it.
    private static let fallbackDelay: Duration = .seconds(4)

    // On screen: the lyrics page is selected and the full player is open.
    private var wanted: Bool { isActive && appState.showPlayer }

    private struct Request: Equatable {
        let trackID: String?
        let active: Bool
        var engineState: AMLLEngine.State = .idle
    }

    private func applyFallback() {
        guard engine.state == .empty, let id = AudioPlayer.shared.current?.id else { return }
        engine.useFallback(appLyrics, trackID: id)
    }

    var body: some View {
        GeometryReader { geo in
            let h = max(geo.size.height, 1)
            let fadeEnd = min(1, max(0.5, (h - bottomInset) / h) + 0.02)
            Group {
                switch engine.state {
                case .ready:
                    AMLLPlayerRepresentable(lines: engine.lines, credits: creditLines, bottomInset: bottomInset)
                        .mask(
                            LinearGradient(stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .black, location: 0.08),
                                .init(color: .black, location: max(0.1, fadeEnd - 0.16)),
                                .init(color: .clear, location: fadeEnd),
                            ], startPoint: .top, endPoint: .bottom)
                            .animation(.smooth(duration: 0.35), value: bottomInset)
                        )
                        .padding(.horizontal, -AMLLPlayerUIView.overflow)
                case .loading:
                    ProgressView().tint(.white.opacity(0.5))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .empty:
                    VStack(spacing: 10) {
                        Image(systemName: "music.note.list").font(.system(size: 30)).foregroundStyle(.white.opacity(0.16))
                        Text("No Lyrics").font(.system(size: 15, weight: .medium)).foregroundStyle(.white.opacity(0.28))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .idle:
                    Color.clear
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .padding(.top, topInset)
        .onReceive(AudioPlayer.shared.$current.map { $0?.id }.removeDuplicates()) { trackID = $0 }
        .task(id: Request(trackID: trackID, active: wanted)) {
            guard let t = AudioPlayer.shared.current, t.id == trackID else { engine.reset(); return }
            if wanted {
                engine.load(for: t)
            } else if engine.loadedID != t.id {
                // Hidden and the track changed: drop the old track's search rather than finish it.
                engine.reset()
            }
        }
        // The app's own search (server, lrclib, Musixmatch) only runs as the fallback: when the
        // word-by-word search finds nothing, or is still going after fallbackDelay.
        .task(id: Request(trackID: trackID, active: wanted, engineState: engine.state)) {
            guard wanted, let t = AudioPlayer.shared.current, t.id == trackID else { return }
            switch engine.state {
            case .empty:
                appState.loadLyrics(for: t)
            case .loading:
                try? await Task.sleep(for: Self.fallbackDelay)
                if !Task.isCancelled { appState.loadLyrics(for: t) }
            case .idle, .ready:
                break
            }
        }
        .onChange(of: engine.state) { _, s in
            applyFallback()
            if s == .ready || s == .empty { onReady?() }
        }
        .onAppear {
            if engine.state == .ready || engine.state == .empty { onReady?() }
        }
        .background(AppLyricsListener { appLyrics = $0; DispatchQueue.main.async { applyFallback() } })
    }

    private var creditLines: [String] {
        var out: [String] = []
        if !engine.writers.isEmpty { out.append("Written by: " + engine.writers.joined(separator: ", ")) }
        if let by = engine.syncedBy {
            out.append("Synced by " + by)
        } else if let p = engine.provider, !p.isEmpty {
            out.append("Lyrics provided by " + p)
        }
        return out
    }
}

private struct AppLyricsListener: View {
    @Environment(AppState.self) private var state
    let onChange: (ParsedLyrics?) -> Void

    var body: some View {
        Color.clear
            .onChange(of: state.lyricsRevision, initial: true) { onChange(state.lyrics) }
    }
}
