import CoreGraphics
import Foundation

/// Static layout of the bin, expressed relative to the bin window's origin (in overlay view coords).
struct BinGeometry {
    static let windowSize = CGSize(width: 220, height: 230)
    static let bodyBottomOffset: CGFloat = 44
    static let bodyHeight: CGFloat = 150
    static let topWidth: CGFloat = 140
    static let bottomWidth: CGFloat = 112
    static let rimRadius: CGFloat = 7
    static let lidLength: CGFloat = 150

    let origin: CGPoint

    var cx: CGFloat { origin.x + Self.windowSize.width / 2 }
    var bottomY: CGFloat { origin.y + Self.bodyBottomOffset }
    var topY: CGFloat { bottomY + Self.bodyHeight }
    var topLeft: CGPoint { CGPoint(x: cx - Self.topWidth / 2, y: topY) }
    var topRight: CGPoint { CGPoint(x: cx + Self.topWidth / 2, y: topY) }
    var bottomLeft: CGPoint { CGPoint(x: cx - Self.bottomWidth / 2, y: bottomY) }
    var bottomRight: CGPoint { CGPoint(x: cx + Self.bottomWidth / 2, y: bottomY) }
    var faceCenter: CGPoint { CGPoint(x: cx, y: bottomY + Self.bodyHeight * 0.45) }
    var hudCenter: CGPoint { CGPoint(x: cx, y: origin.y + 18) }
    var mouth: CGPoint { CGPoint(x: cx, y: topY + 4) }

    /// Dropping straight onto this area counts as a dunk.
    var dunkRect: CGRect {
        CGRect(x: topLeft.x, y: bottomY, width: Self.topWidth, height: Self.bodyHeight + 70)
    }

    /// Everything the bin might paint (open lid, wobble, HUD), used for dirty-rect invalidation.
    var paintRect: CGRect {
        CGRect(origin: origin, size: Self.windowSize).insetBy(dx: -110, dy: -10)
            .union(CGRect(x: cx - 200, y: topY, width: 400, height: Self.lidLength + 60))
    }
}

enum BinFace {
    case idle, eager, happy, dizzy, sad
}

/// Animated state of the bin: lid spring, wobble, squash and facial expression.
final class BinState {
    var hingeRight = true
    var lidOpen: CGFloat = 0
    var lidVel: CGFloat = 0
    var lidTarget: CGFloat = 0

    var wobble: CGFloat = 0
    var wobbleVel: CGFloat = 0
    var squash: CGFloat = 0
    var squashVel: CGFloat = 0

    private(set) var face: BinFace = .idle
    private var faceTimer: Double = 0
    var lookAt: CGPoint?

    private var blinkCountdown: Double = 3
    private(set) var blink: CGFloat = 0 // 0 = open, 1 = closed

    static let maxLidAngle: CGFloat = 112 * .pi / 180

    func show(_ f: BinFace, for seconds: Double) {
        face = f
        faceTimer = seconds
    }

    /// Resting face depends on whether a throw is being lined up.
    func setEager(_ eager: Bool) {
        if faceTimer <= 0 { face = eager ? .eager : .idle }
    }

    var isSettled: Bool {
        abs(lidOpen - lidTarget) < 0.002 && abs(lidVel) < 0.01
            && abs(wobble) < 0.001 && abs(wobbleVel) < 0.01
            && abs(squash) < 0.001 && abs(squashVel) < 0.01
            && faceTimer <= 0 && blink == 0
    }

    /// Returns true when a blink just started (so the view knows to redraw).
    @discardableResult
    func step(_ dt: CGFloat) -> Bool {
        // Underdamped springs give the lid and body a bit of cartoon bounce.
        lidVel += (-220 * (lidOpen - lidTarget) - 15 * lidVel) * dt
        lidOpen = clamp(lidOpen + lidVel * dt, -0.06, 1.12)

        wobbleVel += (-320 * wobble - 7 * wobbleVel) * dt
        wobble += wobbleVel * dt

        squashVel += (-420 * squash - 11 * squashVel) * dt
        squash += squashVel * dt

        if faceTimer > 0 {
            faceTimer -= Double(dt)
            if faceTimer <= 0 { face = .idle }
        }

        var blinked = false
        blinkCountdown -= Double(dt)
        if blinkCountdown <= 0 {
            blink = 1
            blinkCountdown = Double.random(in: 2.5...6)
            blinked = true
        } else if blink > 0 {
            blink = max(0, blink - dt * 7)
        }
        return blinked
    }

    var lidAngle: CGFloat { lidOpen * Self.maxLidAngle }

    /// Lid as a segment from hinge to free end. Closed, it lies across the opening.
    func lidSegment(_ g: BinGeometry) -> (CGPoint, CGPoint) {
        let a = lidAngle
        let hinge = hingeRight ? g.topRight + CGPoint(x: 4, y: 6) : g.topLeft + CGPoint(x: -4, y: 6)
        let dir = hingeRight ? CGPoint(x: -cos(a), y: sin(a)) : CGPoint(x: cos(a), y: sin(a))
        return (hinge, hinge + dir * BinGeometry.lidLength)
    }

    func kick(wobble w: CGFloat = 0, squash s: CGFloat = 0, lid l: CGFloat = 0) {
        wobbleVel += w
        squashVel += s
        lidVel += l
    }
}
