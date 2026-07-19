import SwiftUI

// MARK: - Shadow style enum

enum ShadowStyle: String, CaseIterable, Identifiable {
    case morning  = "morning"
    case bamboo   = "bamboo"
    case dappled  = "dappled"
    case xuanPaper = "xuanPaper"
    case none     = "none"

    var id: String { rawValue }
    static let storageKey = "poem_shadow_style"
    static let visibleCases = allCases.filter { $0 != .none && $0 != .dappled }

    var displayName: String {
        switch self {
        case .morning: return "晨光"
        case .bamboo:  return "竹影"
        case .dappled: return "斑驳"
        case .xuanPaper: return "宣紙"
        case .none:    return "无"
        }
    }

    var subtitle: String {
        switch self {
        case .morning: return "窗边斜照"
        case .bamboo:  return "疏影横斜"
        case .dappled: return "树影婆娑"
        case .xuanPaper: return "紙纖微明"
        case .none:    return ""
        }
    }

    var paperOpacity: Double {
        switch self {
        case .morning:
            return 0.72
        case .bamboo:
            return 0.68
        case .dappled:
            return 0.72
        case .xuanPaper:
            return 0.58
        case .none:
            return 0
        }
    }
}

// MARK: - Background image enum

enum PoemBackground: String, CaseIterable, Identifiable {
    case none       = "bg_none"
    case boat       = "bg_boat"
    case waterfall  = "bg_waterfall"
    case plum       = "bg_plum"
    case bamboo     = "bg_bamboo"
    case moon       = "bg_moon"
    case lotus      = "bg_lotus"
    case bridge     = "bg_bridge"
    case pavilion   = "bg_pavilion"
    case peaks      = "bg_peaks"
    case willow     = "bg_willow"

    var id: String { rawValue }
    static let storageKey = "poem_background"
    static let defaultBackground = PoemBackground.boat
    private static let didMigrateDefaultToBoatKey = "poem_background_default_boat_migrated"

    var displayName: String {
        switch self {
        case .none:      return "無"
        case .boat:      return "渡舟"
        case .waterfall: return "山瀑"
        case .plum:      return "梅花"
        case .bamboo:    return "翠竹"
        case .moon:      return "月夜"
        case .lotus:     return "荷花"
        case .bridge:    return "拱橋"
        case .pavilion:  return "山亭"
        case .peaks:     return "雲峰"
        case .willow:    return "垂柳"
        }
    }

    var imageName: String? {
        self == .none ? nil : rawValue
    }

    var landscapeImageName: String? {
        self == .none ? nil : "\(rawValue)_landscape"
    }

    /// All image backgrounds (excluding .none)
    static var imageBackgrounds: [PoemBackground] {
        allCases.filter { $0 != .none }
    }

    static func migrateDefaultToBoatIfNeeded(selectedBgRaw: inout String) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: didMigrateDefaultToBoatKey) else { return }
        if PoemBackground(rawValue: selectedBgRaw) == PoemBackground.none {
            selectedBgRaw = defaultBackground.rawValue
        }
        defaults.set(true, forKey: didMigrateDefaultToBoatKey)
    }

    static func migrateAppPaperDefaultToBoatIfNeeded(selectedBgRaw: inout String) {
        let defaults = UserDefaults.standard
        let key = "poem_background_default_boat_app_migrated_v2"
        guard !defaults.bool(forKey: key) else { return }
        let selectedBackground = PoemBackground(rawValue: selectedBgRaw)
        if selectedBackground == nil || selectedBackground == PoemBackground.none {
            selectedBgRaw = defaultBackground.rawValue
        }
        defaults.set(true, forKey: key)
    }
}

// MARK: - Main view

struct DappledShadowView: View {
    @AppStorage(ShadowStyle.storageKey) private var styleRaw = ShadowStyle.morning.rawValue

    private var style: ShadowStyle {
        ShadowStyle(rawValue: styleRaw) ?? .morning
    }

    var body: some View {
        if style != .none {
            TimelineView(.animation) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                Canvas { context, size in
                    ShadowRenderer.draw(style: style, context: &context, size: size, t: t)
                }
            }
            .allowsHitTesting(false)
        }
    }
}

// MARK: - Shared renderer

enum ShadowRenderer {
    static func draw(style: ShadowStyle, context: inout GraphicsContext, size: CGSize, t: TimeInterval, scale: CGFloat = 1) {
        switch style {
        case .morning:
            drawMorning(context: &context, size: size, t: t * 0.06, scale: scale)
        case .bamboo:
            drawBamboo(context: &context, size: size, t: t * 0.05, scale: scale)
        case .dappled:
            drawDappled(context: &context, size: size, t: t * 0.04, scale: scale)
        case .xuanPaper:
            drawXuanPaper(context: &context, size: size, t: t * 0.02, scale: scale)
        case .none:
            break
        }
    }

    // MARK: - Style 1: 晨光 (Morning light)
    // Broad diagonal light band with soft shadow masses

    private static func drawMorning(context: inout GraphicsContext, size: CGSize, t: Double, scale: CGFloat) {
        let w = size.width
        let h = size.height

        for band in morningBands {
            let sway  = sin(t * band.freq + band.phase) * band.amp
            let drift = cos(t * band.freq * 0.7 + band.phase * 1.3) * band.amp * 0.5
            let alpha = band.alpha + sin(t * band.flicker + band.phase) * 0.012

            var xform = CGAffineTransform.identity
            xform = xform.translatedBy(
                x: w * CGFloat(band.cx) + CGFloat(sway) * w,
                y: h * CGFloat(band.cy) + CGFloat(drift) * h
            )
            xform = xform.rotated(by: CGFloat(band.angle + sin(t * 0.25 + band.phase) * 0.015))

            let rect = CGRect(
                x: -w * CGFloat(band.bw) / 2,
                y: -h * CGFloat(band.bh) / 2,
                width:  w * CGFloat(band.bw),
                height: h * CGFloat(band.bh)
            )
            let path = Path(rect).applying(xform)

            context.drawLayer { lctx in
                lctx.addFilter(.blur(radius: CGFloat(band.blur) * scale))
                lctx.fill(path, with: .color(shadowColor.opacity(alpha)))
            }
        }
    }

    // MARK: - Style 2: 竹影 (Bamboo / branch shadows)
    // Many parallel diagonal stripes of varying width — like palm fronds or bamboo

    private static func drawBamboo(context: inout GraphicsContext, size: CGSize, t: Double, scale: CGFloat) {
        let w = size.width
        let h = size.height

        for stripe in bambooStripes {
            let sway  = sin(t * stripe.freq + stripe.phase) * stripe.amp
            let drift = cos(t * stripe.freq * 0.6 + stripe.phase * 0.8) * stripe.amp * 0.4
            let alpha = stripe.alpha + sin(t * stripe.flicker + stripe.phase) * 0.015

            var xform = CGAffineTransform.identity
            xform = xform.translatedBy(
                x: w * CGFloat(stripe.cx) + CGFloat(sway) * w,
                y: h * CGFloat(stripe.cy) + CGFloat(drift) * h
            )
            xform = xform.rotated(by: CGFloat(stripe.angle + sin(t * 0.20 + stripe.phase) * 0.025))

            let rect = CGRect(
                x: -w * CGFloat(stripe.bw) / 2,
                y: -h * CGFloat(stripe.bh) / 2,
                width:  w * CGFloat(stripe.bw),
                height: h * CGFloat(stripe.bh)
            )
            let path = Path(rect).applying(xform)

            context.drawLayer { lctx in
                lctx.addFilter(.blur(radius: CGFloat(stripe.blur) * scale))
                lctx.fill(path, with: .color(shadowColor.opacity(alpha)))
            }
        }
    }

    // MARK: - Style 3: 斑驳 (Dappled leaf shadows)
    // Many small elliptical leaf shapes, denser pattern

    private static func drawDappled(context: inout GraphicsContext, size: CGSize, t: Double, scale: CGFloat) {
        let w = size.width
        let h = size.height

        for leaf in dappledLeaves {
            let cx = CGFloat(leaf.bx) * w + CGFloat(sin(t * leaf.fx + leaf.px)) * CGFloat(leaf.sx) * w
            let cy = CGFloat(leaf.by) * h + CGFloat(cos(t * leaf.fy + leaf.py)) * CGFloat(leaf.sy) * h
            let angle  = CGFloat(leaf.rot + sin(t * 0.5 + leaf.px) * 0.15)
            let alpha  = max(0, leaf.a + sin(t * leaf.ff + leaf.py) * 0.03)

            let xform = CGAffineTransform(translationX: cx, y: cy).rotated(by: angle)
            let path  = Path(ellipseIn: CGRect(
                x: -CGFloat(leaf.w) * scale / 2,
                y: -CGFloat(leaf.h) * scale / 2,
                width:  CGFloat(leaf.w) * scale,
                height: CGFloat(leaf.h) * scale
            )).applying(xform)

            context.drawLayer { lctx in
                lctx.addFilter(.blur(radius: CGFloat(leaf.blur) * scale))
                lctx.fill(path, with: .color(shadowColor.opacity(alpha)))
            }
        }
    }

    // MARK: - Style 4: 宣紙 (Xuan paper)
    // Very soft paper fibers, warm tone, and faint ink breaths.

    private static func drawXuanPaper(context: inout GraphicsContext, size: CGSize, t: Double, scale: CGFloat) {
        let w = size.width
        let h = size.height

        let warmWash = Path(CGRect(origin: .zero, size: size))
        context.fill(warmWash, with: .color(Color(red: 0.96, green: 0.93, blue: 0.86).opacity(0.18)))

        for fiber in xuanFibers {
            let drift = sin(t * fiber.freq + fiber.phase) * fiber.amp
            var xform = CGAffineTransform.identity
            xform = xform.translatedBy(
                x: w * CGFloat(fiber.cx) + CGFloat(drift) * w,
                y: h * CGFloat(fiber.cy)
            )
            xform = xform.rotated(by: CGFloat(fiber.angle))

            let rect = CGRect(
                x: -w * CGFloat(fiber.bw) / 2,
                y: -h * CGFloat(fiber.bh) / 2,
                width: w * CGFloat(fiber.bw),
                height: h * CGFloat(fiber.bh)
            )
            let path = Path(rect).applying(xform)

            context.drawLayer { layer in
                layer.addFilter(.blur(radius: CGFloat(fiber.blur) * scale))
                layer.fill(path, with: .color(paperFiberColor.opacity(fiber.alpha)))
            }
        }

        for bloom in xuanInkBlooms {
            let rect = CGRect(
                x: w * CGFloat(bloom.bx) - CGFloat(bloom.w) * scale / 2,
                y: h * CGFloat(bloom.by) - CGFloat(bloom.h) * scale / 2,
                width: CGFloat(bloom.w) * scale,
                height: CGFloat(bloom.h) * scale
            )
            let path = Path(ellipseIn: rect)

            context.drawLayer { layer in
                layer.addFilter(.blur(radius: CGFloat(bloom.blur) * scale))
                layer.fill(path, with: .color(shadowColor.opacity(bloom.a)))
            }
        }
    }
}

// MARK: - Color

private let shadowColor = Color.black
private let paperFiberColor = Color(red: 0.52, green: 0.45, blue: 0.32)

// MARK: - Band data model

private struct Band {
    let cx, cy: Double
    let bw, bh: Double
    let angle: Double
    let blur: Double
    let alpha: Double
    let freq: Double
    let amp: Double
    let flicker: Double
    let phase: Double
}

// MARK: - Leaf data model

private struct Leaf {
    let bx, by: Double
    let w,  h:  Double
    let rot:    Double
    let fx, fy: Double
    let ff:     Double
    let sx, sy: Double
    let px, py: Double
    let a:      Double
    let blur:   Double
}

// MARK: - Morning bands data

private let morningBands: [Band] = [
    // Large shadow mass: upper-left
    Band(cx: -0.05, cy: 0.10, bw: 0.85, bh: 0.60,
         angle: -0.50, blur: 50, alpha: 0.14,
         freq: 0.20, amp: 0.006, flicker: 0.14, phase: 0.0),
    // Large shadow mass: lower-right
    Band(cx: 1.05, cy: 0.88, bw: 0.90, bh: 0.55,
         angle: -0.50, blur: 45, alpha: 0.13,
         freq: 0.18, amp: 0.007, flicker: 0.12, phase: 2.0),
    // Edge reinforcement — upper boundary
    Band(cx: 0.25, cy: 0.35, bw: 0.90, bh: 0.08,
         angle: -0.50, blur: 35, alpha: 0.08,
         freq: 0.25, amp: 0.010, flicker: 0.20, phase: 1.2),
    // Edge reinforcement — lower boundary
    Band(cx: 0.70, cy: 0.62, bw: 0.85, bh: 0.07,
         angle: -0.50, blur: 35, alpha: 0.075,
         freq: 0.22, amp: 0.009, flicker: 0.18, phase: 3.5),
    // Branch shadow crossing the light
    Band(cx: 0.50, cy: 0.44, bw: 0.65, bh: 0.025,
         angle: -0.38, blur: 16, alpha: 0.09,
         freq: 0.32, amp: 0.014, flicker: 0.28, phase: 2.8),
    // Thin twig
    Band(cx: 0.58, cy: 0.52, bw: 0.45, bh: 0.015,
         angle: -0.62, blur: 12, alpha: 0.07,
         freq: 0.38, amp: 0.018, flicker: 0.32, phase: 4.5),
    // Small leaf cluster
    Band(cx: 0.44, cy: 0.48, bw: 0.08, bh: 0.05,
         angle: -0.30, blur: 14, alpha: 0.08,
         freq: 0.42, amp: 0.020, flicker: 0.35, phase: 5.5),
    Band(cx: 0.60, cy: 0.40, bw: 0.06, bh: 0.04,
         angle: -0.55, blur: 11, alpha: 0.07,
         freq: 0.36, amp: 0.016, flicker: 0.30, phase: 0.8),
    // Upper corner darkening
    Band(cx: -0.10, cy: -0.10, bw: 0.60, bh: 0.45,
         angle: -0.20, blur: 65, alpha: 0.09,
         freq: 0.12, amp: 0.004, flicker: 0.08, phase: 1.5),
    // Lower corner darkening
    Band(cx: 1.10, cy: 1.10, bw: 0.55, bh: 0.40,
         angle: -0.25, blur: 60, alpha: 0.08,
         freq: 0.14, amp: 0.005, flicker: 0.10, phase: 3.8),
]

// MARK: - Bamboo stripes data
// Parallel diagonal lines at ~-0.55 rad, different widths and spacings

private let bambooStripes: [Band] = [
    // Main branch stripes — thick
    Band(cx: 0.10, cy: 0.15, bw: 1.20, bh: 0.040, angle: -0.55, blur: 14, alpha: 0.13, freq: 0.22, amp: 0.008, flicker: 0.18, phase: 0.0),
    Band(cx: 0.25, cy: 0.28, bw: 1.15, bh: 0.030, angle: -0.52, blur: 12, alpha: 0.11, freq: 0.25, amp: 0.010, flicker: 0.20, phase: 1.5),
    Band(cx: 0.38, cy: 0.40, bw: 1.10, bh: 0.035, angle: -0.58, blur: 15, alpha: 0.12, freq: 0.20, amp: 0.009, flicker: 0.16, phase: 3.0),
    Band(cx: 0.52, cy: 0.52, bw: 1.20, bh: 0.028, angle: -0.53, blur: 11, alpha: 0.10, freq: 0.28, amp: 0.011, flicker: 0.22, phase: 4.5),
    Band(cx: 0.65, cy: 0.63, bw: 1.15, bh: 0.038, angle: -0.56, blur: 16, alpha: 0.13, freq: 0.18, amp: 0.007, flicker: 0.15, phase: 2.0),
    Band(cx: 0.78, cy: 0.75, bw: 1.10, bh: 0.025, angle: -0.50, blur: 10, alpha: 0.09, freq: 0.30, amp: 0.012, flicker: 0.25, phase: 5.5),
    Band(cx: 0.90, cy: 0.85, bw: 1.20, bh: 0.032, angle: -0.54, blur: 13, alpha: 0.11, freq: 0.24, amp: 0.010, flicker: 0.19, phase: 1.0),

    // Thin sub-branch stripes between the main ones
    Band(cx: 0.18, cy: 0.22, bw: 0.80, bh: 0.012, angle: -0.48, blur: 8, alpha: 0.07, freq: 0.35, amp: 0.015, flicker: 0.30, phase: 0.8),
    Band(cx: 0.32, cy: 0.34, bw: 0.70, bh: 0.010, angle: -0.60, blur: 7, alpha: 0.06, freq: 0.38, amp: 0.018, flicker: 0.28, phase: 2.3),
    Band(cx: 0.45, cy: 0.46, bw: 0.75, bh: 0.014, angle: -0.50, blur: 9, alpha: 0.07, freq: 0.32, amp: 0.014, flicker: 0.26, phase: 3.8),
    Band(cx: 0.58, cy: 0.57, bw: 0.65, bh: 0.010, angle: -0.62, blur: 6, alpha: 0.05, freq: 0.40, amp: 0.020, flicker: 0.32, phase: 5.0),
    Band(cx: 0.72, cy: 0.69, bw: 0.80, bh: 0.012, angle: -0.48, blur: 8, alpha: 0.06, freq: 0.34, amp: 0.016, flicker: 0.24, phase: 0.5),
    Band(cx: 0.85, cy: 0.80, bw: 0.60, bh: 0.008, angle: -0.58, blur: 5, alpha: 0.05, freq: 0.42, amp: 0.022, flicker: 0.35, phase: 4.0),

    // Very thin wispy lines
    Band(cx: 0.05, cy: 0.08, bw: 0.90, bh: 0.006, angle: -0.45, blur: 4, alpha: 0.04, freq: 0.45, amp: 0.025, flicker: 0.38, phase: 1.8),
    Band(cx: 0.48, cy: 0.48, bw: 0.50, bh: 0.005, angle: -0.65, blur: 3, alpha: 0.04, freq: 0.48, amp: 0.028, flicker: 0.40, phase: 3.2),
    Band(cx: 0.95, cy: 0.92, bw: 0.70, bh: 0.006, angle: -0.42, blur: 4, alpha: 0.04, freq: 0.44, amp: 0.024, flicker: 0.36, phase: 5.8),
]

// MARK: - Xuan paper data

private let xuanFibers: [Band] = [
    Band(cx: 0.18, cy: 0.12, bw: 0.88, bh: 0.006, angle: -0.02, blur: 4, alpha: 0.075, freq: 0.18, amp: 0.003, flicker: 0, phase: 0.0),
    Band(cx: 0.62, cy: 0.20, bw: 0.70, bh: 0.004, angle: 0.03, blur: 5, alpha: 0.060, freq: 0.16, amp: 0.002, flicker: 0, phase: 1.2),
    Band(cx: 0.42, cy: 0.34, bw: 1.00, bh: 0.005, angle: -0.015, blur: 5, alpha: 0.065, freq: 0.14, amp: 0.002, flicker: 0, phase: 2.4),
    Band(cx: 0.76, cy: 0.49, bw: 0.82, bh: 0.004, angle: 0.025, blur: 4, alpha: 0.055, freq: 0.15, amp: 0.003, flicker: 0, phase: 3.5),
    Band(cx: 0.30, cy: 0.66, bw: 0.95, bh: 0.006, angle: -0.025, blur: 6, alpha: 0.065, freq: 0.17, amp: 0.002, flicker: 0, phase: 4.1),
    Band(cx: 0.68, cy: 0.82, bw: 0.78, bh: 0.005, angle: 0.018, blur: 5, alpha: 0.060, freq: 0.13, amp: 0.003, flicker: 0, phase: 5.0),

    Band(cx: 0.14, cy: 0.46, bw: 0.006, bh: 0.90, angle: 0.02, blur: 5, alpha: 0.045, freq: 0.12, amp: 0.002, flicker: 0, phase: 0.7),
    Band(cx: 0.36, cy: 0.52, bw: 0.004, bh: 0.72, angle: -0.015, blur: 4, alpha: 0.040, freq: 0.14, amp: 0.002, flicker: 0, phase: 1.8),
    Band(cx: 0.58, cy: 0.48, bw: 0.005, bh: 0.86, angle: 0.012, blur: 5, alpha: 0.042, freq: 0.13, amp: 0.002, flicker: 0, phase: 2.9),
    Band(cx: 0.83, cy: 0.54, bw: 0.004, bh: 0.70, angle: -0.02, blur: 4, alpha: 0.038, freq: 0.15, amp: 0.002, flicker: 0, phase: 3.7),

    Band(cx: -0.08, cy: 0.06, bw: 0.52, bh: 0.36, angle: -0.2, blur: 62, alpha: 0.09, freq: 0.08, amp: 0.001, flicker: 0, phase: 0.4),
    Band(cx: 1.08, cy: 1.02, bw: 0.60, bh: 0.42, angle: -0.15, blur: 70, alpha: 0.08, freq: 0.08, amp: 0.001, flicker: 0, phase: 2.1)
]

private let xuanInkBlooms: [Leaf] = [
    Leaf(bx:0.18, by:0.76, w:110, h:70, rot:0, fx:0, fy:0, ff:0, sx:0, sy:0, px:0, py:0, a:0.025, blur:34),
    Leaf(bx:0.72, by:0.28, w:90, h:54, rot:0, fx:0, fy:0, ff:0, sx:0, sy:0, px:0, py:0, a:0.020, blur:30),
    Leaf(bx:0.46, by:0.58, w:70, h:44, rot:0, fx:0, fy:0, ff:0, sx:0, sy:0, px:0, py:0, a:0.018, blur:26)
]

// MARK: - Dappled leaves data
// Many ellipses simulating dense tree-shadow pattern

private let dappledLeaves: [Leaf] = [
    // Large soft background shadows (canopy mass)
    Leaf(bx:0.20, by:0.15, w:120, h:60, rot: 0.30, fx:0.25, fy:0.22, ff:0.80, sx:0.015, sy:0.010, px:0.00, py:1.50, a:0.10, blur:20),
    Leaf(bx:0.75, by:0.20, w:100, h:50, rot:-0.40, fx:0.28, fy:0.25, ff:0.85, sx:0.012, sy:0.008, px:2.00, py:0.50, a:0.09, blur:18),
    Leaf(bx:0.50, by:0.70, w:110, h:55, rot: 0.60, fx:0.22, fy:0.20, ff:0.75, sx:0.014, sy:0.012, px:3.50, py:2.80, a:0.10, blur:22),

    // Medium leaf shapes
    Leaf(bx:0.15, by:0.10, w:55, h:22, rot: 0.45, fx:0.35, fy:0.30, ff:1.00, sx:0.018, sy:0.012, px:0.50, py:1.20, a:0.14, blur:8),
    Leaf(bx:0.35, by:0.08, w:48, h:18, rot:-0.70, fx:0.40, fy:0.35, ff:1.10, sx:0.016, sy:0.010, px:1.80, py:0.30, a:0.12, blur:7),
    Leaf(bx:0.55, by:0.15, w:60, h:24, rot: 0.20, fx:0.32, fy:0.28, ff:0.95, sx:0.020, sy:0.014, px:3.20, py:2.10, a:0.15, blur:9),
    Leaf(bx:0.78, by:0.12, w:42, h:16, rot: 1.10, fx:0.45, fy:0.40, ff:1.20, sx:0.014, sy:0.008, px:0.90, py:4.20, a:0.11, blur:6),
    Leaf(bx:0.92, by:0.22, w:50, h:20, rot:-0.35, fx:0.38, fy:0.33, ff:1.05, sx:0.017, sy:0.011, px:2.50, py:0.80, a:0.13, blur:7),

    Leaf(bx:0.08, by:0.30, w:58, h:22, rot: 0.55, fx:0.30, fy:0.27, ff:0.90, sx:0.019, sy:0.013, px:1.10, py:3.50, a:0.14, blur:8),
    Leaf(bx:0.28, by:0.25, w:44, h:16, rot:-0.80, fx:0.48, fy:0.42, ff:1.25, sx:0.013, sy:0.007, px:4.50, py:1.00, a:0.11, blur:5),
    Leaf(bx:0.48, by:0.32, w:52, h:20, rot: 1.40, fx:0.36, fy:0.32, ff:1.00, sx:0.016, sy:0.010, px:0.60, py:2.90, a:0.13, blur:7),
    Leaf(bx:0.68, by:0.28, w:46, h:18, rot: 0.15, fx:0.42, fy:0.38, ff:1.15, sx:0.015, sy:0.012, px:3.70, py:0.60, a:0.12, blur:6),
    Leaf(bx:0.88, by:0.35, w:62, h:26, rot:-0.45, fx:0.28, fy:0.25, ff:0.85, sx:0.022, sy:0.015, px:1.40, py:4.60, a:0.14, blur:10),

    Leaf(bx:0.12, by:0.45, w:50, h:20, rot: 0.70, fx:0.38, fy:0.34, ff:1.08, sx:0.017, sy:0.011, px:2.80, py:1.30, a:0.13, blur:7),
    Leaf(bx:0.32, by:0.42, w:56, h:22, rot:-0.25, fx:0.34, fy:0.30, ff:0.92, sx:0.019, sy:0.013, px:0.30, py:3.20, a:0.14, blur:8),
    Leaf(bx:0.52, by:0.48, w:40, h:15, rot: 0.90, fx:0.46, fy:0.40, ff:1.18, sx:0.013, sy:0.009, px:4.10, py:0.40, a:0.11, blur:5),
    Leaf(bx:0.72, by:0.45, w:54, h:20, rot:-1.00, fx:0.32, fy:0.28, ff:0.88, sx:0.018, sy:0.012, px:1.70, py:2.60, a:0.13, blur:7),
    Leaf(bx:0.90, by:0.50, w:48, h:18, rot: 0.35, fx:0.40, fy:0.36, ff:1.12, sx:0.015, sy:0.010, px:3.00, py:1.10, a:0.12, blur:6),

    Leaf(bx:0.05, by:0.60, w:58, h:24, rot:-0.60, fx:0.30, fy:0.26, ff:0.82, sx:0.020, sy:0.014, px:0.50, py:4.80, a:0.14, blur:9),
    Leaf(bx:0.22, by:0.58, w:42, h:16, rot: 1.20, fx:0.44, fy:0.39, ff:1.22, sx:0.014, sy:0.008, px:2.20, py:0.70, a:0.11, blur:5),
    Leaf(bx:0.42, by:0.62, w:64, h:26, rot: 0.10, fx:0.26, fy:0.23, ff:0.78, sx:0.022, sy:0.016, px:4.30, py:2.40, a:0.15, blur:10),
    Leaf(bx:0.62, by:0.55, w:46, h:17, rot:-0.85, fx:0.42, fy:0.37, ff:1.10, sx:0.016, sy:0.010, px:1.00, py:3.60, a:0.12, blur:6),
    Leaf(bx:0.82, by:0.62, w:52, h:20, rot: 0.50, fx:0.34, fy:0.30, ff:0.95, sx:0.018, sy:0.012, px:3.50, py:1.50, a:0.13, blur:7),

    Leaf(bx:0.15, by:0.75, w:56, h:22, rot:-0.30, fx:0.36, fy:0.32, ff:1.02, sx:0.017, sy:0.011, px:0.80, py:2.00, a:0.13, blur:7),
    Leaf(bx:0.38, by:0.78, w:48, h:18, rot: 0.75, fx:0.40, fy:0.35, ff:1.08, sx:0.015, sy:0.010, px:2.60, py:4.30, a:0.12, blur:6),
    Leaf(bx:0.58, by:0.72, w:60, h:24, rot:-0.50, fx:0.28, fy:0.25, ff:0.85, sx:0.021, sy:0.015, px:4.00, py:0.90, a:0.14, blur:9),
    Leaf(bx:0.78, by:0.76, w:44, h:16, rot: 1.05, fx:0.46, fy:0.41, ff:1.20, sx:0.013, sy:0.008, px:1.30, py:3.10, a:0.11, blur:5),
    Leaf(bx:0.95, by:0.70, w:54, h:21, rot: 0.00, fx:0.32, fy:0.28, ff:0.90, sx:0.019, sy:0.013, px:3.80, py:1.80, a:0.13, blur:8),

    Leaf(bx:0.10, by:0.88, w:50, h:20, rot: 0.65, fx:0.38, fy:0.34, ff:1.05, sx:0.016, sy:0.011, px:2.00, py:0.50, a:0.12, blur:7),
    Leaf(bx:0.30, by:0.92, w:62, h:25, rot:-0.40, fx:0.26, fy:0.22, ff:0.80, sx:0.023, sy:0.016, px:0.40, py:3.80, a:0.14, blur:10),
    Leaf(bx:0.55, by:0.88, w:45, h:17, rot: 0.95, fx:0.44, fy:0.39, ff:1.15, sx:0.014, sy:0.009, px:4.60, py:2.20, a:0.11, blur:5),
    Leaf(bx:0.75, by:0.90, w:58, h:22, rot:-0.15, fx:0.30, fy:0.27, ff:0.88, sx:0.020, sy:0.014, px:1.50, py:4.50, a:0.13, blur:8),
    Leaf(bx:0.92, by:0.85, w:40, h:15, rot: 1.30, fx:0.50, fy:0.44, ff:1.30, sx:0.012, sy:0.007, px:3.20, py:0.20, a:0.10, blur:4),
]
