// Renders the TrashToss app icon (1024×1024 PNG).
// Usage: swift Support/make-icon.swift <out.png>
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func gradient(_ colors: [CGColor], _ locs: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: space, colors: colors as CFArray, locations: locs)!
}

// MARK: Background tile (macOS icon grid: 824pt tile, centered, with drop shadow)

let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: rgb(0x000000, 0.35))
ctx.addPath(tilePath)
ctx.setFillColor(rgb(0x3B2F8F))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(tilePath)
ctx.clip()
ctx.drawLinearGradient(gradient([rgb(0x7C6CF2), rgb(0x4B3BC4), rgb(0x2A1F7A)], [0, 0.55, 1]),
                       start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
// Soft spotlight behind the bin.
ctx.drawRadialGradient(gradient([rgb(0xFFFFFF, 0.22), rgb(0xFFFFFF, 0)], [0, 1]),
                       startCenter: CGPoint(x: 470, y: 420), startRadius: 0,
                       endCenter: CGPoint(x: 470, y: 420), endRadius: 420, options: [])
// Floor.
ctx.setFillColor(rgb(0x1E1660, 0.55))
ctx.fill(CGRect(x: 100, y: 100, width: 824, height: 120))
ctx.restoreGState()

// MARK: Bin

let s: CGFloat = 2.2
let cx: CGFloat = 470
let bottomY: CGFloat = 200
let topY = bottomY + 150 * s
let topW = 140 * s, botW = 112 * s
let tl = CGPoint(x: cx - topW / 2, y: topY), tr = CGPoint(x: cx + topW / 2, y: topY)
let bl = CGPoint(x: cx - botW / 2, y: bottomY), br = CGPoint(x: cx + botW / 2, y: bottomY)

let bodyDark = rgb(0x1A7866), bodyMid = rgb(0x3DBD99), bodyLight = rgb(0x6BDBB8)
let outline = rgb(0x0D453B), ink = rgb(0x142421)

// Ground shadow.
ctx.setFillColor(rgb(0x000000, 0.3))
ctx.fillEllipse(in: CGRect(x: cx - 170, y: bottomY - 22, width: 340, height: 40))

// Dark opening.
ctx.setFillColor(rgb(0x082420))
ctx.fillEllipse(in: CGRect(x: tl.x + 4, y: topY - 18, width: topW - 8, height: 48))

let body = CGMutablePath()
body.move(to: CGPoint(x: cx, y: topY))
body.addArc(tangent1End: tr, tangent2End: br, radius: 14)
body.addArc(tangent1End: br, tangent2End: bl, radius: 40)
body.addArc(tangent1End: bl, tangent2End: tl, radius: 40)
body.addArc(tangent1End: tl, tangent2End: tr, radius: 14)
body.closeSubpath()

ctx.saveGState()
ctx.addPath(body)
ctx.clip()
ctx.drawLinearGradient(gradient([bodyDark, bodyMid, bodyLight, bodyMid, bodyDark], [0, 0.25, 0.42, 0.7, 1]),
                       start: CGPoint(x: tl.x, y: 0), end: CGPoint(x: tr.x, y: 0), options: [])
ctx.setLineCap(.round)
ctx.setStrokeColor(rgb(0x0D453B, 0.18))
ctx.setLineWidth(12)
for f in [-0.33, 0.33] as [CGFloat] {
    ctx.move(to: CGPoint(x: cx + f * topW, y: topY - 36))
    ctx.addLine(to: CGPoint(x: cx + f * botW, y: bottomY + 30))
}
ctx.strokePath()
ctx.setStrokeColor(rgb(0xFFFFFF, 0.3))
ctx.setLineWidth(14)
ctx.move(to: CGPoint(x: cx - topW * 0.36, y: topY - 44))
ctx.addLine(to: CGPoint(x: cx - botW * 0.36, y: topY - 110))
ctx.strokePath()
ctx.restoreGState()

ctx.addPath(body)
ctx.setStrokeColor(outline)
ctx.setLineWidth(6)
ctx.strokePath()

// Rim.
let rim = CGRect(x: tl.x - 16, y: topY - 13, width: topW + 32, height: 24)
let rimPath = CGPath(roundedRect: rim, cornerWidth: 12, cornerHeight: 12, transform: nil)
ctx.saveGState()
ctx.addPath(rimPath)
ctx.clip()
ctx.drawLinearGradient(gradient([outline, bodyDark, bodyMid, bodyDark, outline], [0, 0.2, 0.45, 0.8, 1]),
                       start: CGPoint(x: rim.minX, y: 0), end: CGPoint(x: rim.maxX, y: 0), options: [])
ctx.restoreGState()
ctx.addPath(rimPath)
ctx.setLineWidth(5)
ctx.strokePath()

// Lid, hinged on the left and swung open.
let hinge = tl + CGPoint(x: -9, y: 13)
let lidAngle: CGFloat = 70 * .pi / 180
let lidLen: CGFloat = 300
ctx.saveGState()
ctx.translateBy(x: hinge.x, y: hinge.y)
ctx.rotate(by: lidAngle)
ctx.setStrokeColor(outline)
ctx.setLineWidth(5)
let knob = CGRect(x: lidLen / 2 - 40, y: 12, width: 80, height: 22)
ctx.addPath(CGPath(roundedRect: knob, cornerWidth: 11, cornerHeight: 11, transform: nil))
ctx.setFillColor(bodyDark)
ctx.drawPath(using: .fillStroke)
let plate = CGRect(x: -20, y: -13, width: lidLen + 30, height: 26)
ctx.addPath(CGPath(roundedRect: plate, cornerWidth: 13, cornerHeight: 13, transform: nil))
ctx.setFillColor(bodyMid)
ctx.drawPath(using: .fillStroke)
ctx.setFillColor(rgb(0xFFFFFF, 0.3))
ctx.fill(CGRect(x: 8, y: 2, width: lidLen - 20, height: 5))
ctx.setFillColor(outline)
ctx.fillEllipse(in: CGRect(x: -9, y: -9, width: 18, height: 18))
ctx.restoreGState()

// Happy face.
let fc = CGPoint(x: cx, y: bottomY + 150 * s * 0.45)
ctx.setFillColor(rgb(0xFF6FA0, 0.6))
for side in [-1, 1] as [CGFloat] {
    ctx.fillEllipse(in: CGRect(x: fc.x + side * 92 - 22, y: fc.y - 18, width: 44, height: 24))
}
ctx.setStrokeColor(ink)
ctx.setLineCap(.round)
ctx.setLineWidth(10)
for side in [-1, 1] as [CGFloat] {
    let ex = fc.x + side * 55, ey = fc.y + 30
    ctx.move(to: CGPoint(x: ex - 20, y: ey - 6))
    ctx.addQuadCurve(to: CGPoint(x: ex + 20, y: ey - 6), control: CGPoint(x: ex, y: ey + 28))
}
ctx.strokePath()
let my = fc.y - 44
let mouth = CGMutablePath()
mouth.move(to: CGPoint(x: fc.x - 48, y: my + 12))
mouth.addQuadCurve(to: CGPoint(x: fc.x + 48, y: my + 12), control: CGPoint(x: fc.x, y: my - 64))
mouth.closeSubpath()
ctx.addPath(mouth)
ctx.setFillColor(ink)
ctx.fillPath()
ctx.setFillColor(rgb(0xFF5C8A))
ctx.fillEllipse(in: CGRect(x: fc.x - 20, y: my - 24, width: 40, height: 20))

// MARK: Paper ball arcing in, with motion trail

let ballCenter = CGPoint(x: 720, y: 690)
let trail: [CGPoint] = [CGPoint(x: 860, y: 640), CGPoint(x: 830, y: 676), CGPoint(x: 796, y: 698), CGPoint(x: 760, y: 704)]
for (i, t) in trail.enumerated() {
    let f = CGFloat(i + 1) / CGFloat(trail.count + 1)
    let r = 46 * f
    ctx.setFillColor(rgb(0xFFFFFF, 0.28 * f))
    ctx.fillEllipse(in: CGRect(x: t.x - r, y: t.y - r, width: r * 2, height: r * 2))
}

ctx.saveGState()
ctx.translateBy(x: ballCenter.x, y: ballCenter.y)
ctx.rotate(by: 0.4)
let bumps: [CGFloat] = [1, 0.84, 0.97, 0.9, 1, 0.8, 0.95, 0.88, 1, 0.83, 0.93, 0.9, 0.98, 0.82, 0.96, 0.87]
let ball = CGMutablePath()
for (i, b) in bumps.enumerated() {
    let a = CGFloat(i) / CGFloat(bumps.count) * .pi * 2
    let pt = CGPoint(x: cos(a) * 62 * b, y: sin(a) * 62 * b)
    if i == 0 { ball.move(to: pt) } else { ball.addLine(to: pt) }
}
ball.closeSubpath()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 18, color: rgb(0x000000, 0.35))
ctx.addPath(ball)
ctx.setFillColor(rgb(0xF6F6F4))
ctx.fillPath()
ctx.setShadow(offset: .zero, blur: 0, color: nil)
ctx.addPath(ball)
ctx.setStrokeColor(rgb(0x9A9A9A))
ctx.setLineWidth(4)
ctx.setLineJoin(.round)
ctx.strokePath()
ctx.setStrokeColor(rgb(0xB5B5B5))
ctx.setLineWidth(3.5)
ctx.move(to: CGPoint(x: -34, y: 16)); ctx.addLine(to: CGPoint(x: 6, y: -8)); ctx.addLine(to: CGPoint(x: 28, y: 26))
ctx.move(to: CGPoint(x: -16, y: -40)); ctx.addLine(to: CGPoint(x: 0, y: -8)); ctx.addLine(to: CGPoint(x: -40, y: -12))
ctx.move(to: CGPoint(x: 16, y: -34)); ctx.addLine(to: CGPoint(x: 34, y: -6))
ctx.strokePath()
ctx.restoreGState()

// Sparkles.
func sparkle(_ c: CGPoint, _ r: CGFloat, _ color: CGColor) {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: c.x, y: c.y + r))
    p.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: c)
    p.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r), control: c)
    p.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), control: c)
    p.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), control: c)
    ctx.addPath(p)
    ctx.setFillColor(color)
    ctx.fillPath()
}
sparkle(CGPoint(x: 690, y: 820), 30, rgb(0xFFD84D))
sparkle(CGPoint(x: 800, y: 500), 22, rgb(0xFFFFFF, 0.9))
sparkle(CGPoint(x: 230, y: 760), 18, rgb(0xFFD84D, 0.85))

// MARK: Write

func + (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png")
let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
CGImageDestinationFinalize(dest)
