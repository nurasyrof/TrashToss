import CoreGraphics

// CGPoint doubles as a 2D vector throughout the physics code.
extension CGPoint {
    static func + (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }
    static func - (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x - b.x, y: a.y - b.y) }
    static func * (a: CGPoint, s: CGFloat) -> CGPoint { CGPoint(x: a.x * s, y: a.y * s) }
    static func += (a: inout CGPoint, b: CGPoint) { a = a + b }

    var length: CGFloat { hypot(x, y) }
    func dot(_ o: CGPoint) -> CGFloat { x * o.x + y * o.y }
}

func closestPoint(onSegment a: CGPoint, _ b: CGPoint, to p: CGPoint) -> CGPoint {
    let ab = b - a
    let len2 = ab.dot(ab)
    if len2 == 0 { return a }
    let t = max(0, min(1, (p - a).dot(ab) / len2))
    return a + ab * t
}

func clamp<T: Comparable>(_ v: T, _ lo: T, _ hi: T) -> T { min(max(v, lo), hi) }

func rand(_ lo: CGFloat, _ hi: CGFloat) -> CGFloat { CGFloat.random(in: lo...hi) }
