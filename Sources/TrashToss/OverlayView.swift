import AppKit

/// Receives Finder drags (from the overlay or the bin itself) and hands them to the app.
protocol DropHandler: AnyObject {
    func canAccept(_ info: NSDraggingInfo) -> Bool
    func handleDrop(_ info: NSDraggingInfo, at viewPoint: CGPoint, direct: Bool) -> Bool
}

func desktopFileURLs(_ info: NSDraggingInfo) -> [URL] {
    let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                                   options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    return urls.filter(TrashService.isDesktopItem)
}

func roundedFont(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    let f = NSFont.systemFont(ofSize: size, weight: weight)
    guard let d = f.fontDescriptor.withDesign(.rounded) else { return f }
    return NSFont(descriptor: d, size: size) ?? f
}

/// Full-screen transparent view that paints the bin, flying files and effects.
final class OverlayView: NSView {
    let scene: Scene
    weak var dropHandler: DropHandler?
    private var lastPaint: CGRect = .zero

    init(scene: Scene) {
        self.scene = scene
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isOpaque: Bool { false }

    func invalidate(full: Bool = false) {
        if full {
            needsDisplay = true
            lastPaint = scene.paintRect()
            return
        }
        let now = scene.paintRect()
        setNeedsDisplay(now.union(lastPaint).insetBy(dx: -4, dy: -4))
        lastPaint = now
    }

    // MARK: - Dragging destination

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        dropHandler?.canAccept(sender) == true ? .generic : []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        dropHandler?.canAccept(sender) == true ? .generic : []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pt = convert(sender.draggingLocation, from: nil)
        return dropHandler?.handleDrop(sender, at: pt, direct: false) ?? false
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.clear(dirtyRect)
        let g = scene.geometry

        drawParticles(ctx, kind: .flame)

        ctx.saveGState()
        applyBinTransform(ctx, g)
        if scene.bin.lidOpen > 0.12 { drawInterior(ctx, g) }
        for p in scene.projectiles where p.state == .sinking { drawProjectile(ctx, p) }
        drawBody(ctx, g)
        drawFace(ctx, g)
        drawRim(ctx, g)
        drawLid(ctx, g)
        ctx.restoreGState()

        for p in scene.projectiles where p.state != .sinking {
            drawTrail(ctx, p)
            drawProjectile(ctx, p)
        }
        drawParticles(ctx, kind: .confetti)
        drawParticles(ctx, kind: .spark)
        drawHUD(ctx, g)
        drawSpeech(ctx, g)
        for p in scene.popups where p.age >= p.delay { drawPopup(ctx, p) }
    }

    private func applyBinTransform(_ ctx: CGContext, _ g: BinGeometry) {
        let pivot = CGPoint(x: g.cx, y: g.bottomY)
        let s = scene.bin.squash * 0.02
        ctx.translateBy(x: pivot.x, y: pivot.y)
        ctx.rotate(by: scene.bin.wobble * 0.02)
        ctx.scaleBy(x: 1 + s, y: 1 - s)
        ctx.translateBy(x: -pivot.x, y: -pivot.y)
    }

    private static let bodyDark = NSColor(srgbRed: 0.10, green: 0.47, blue: 0.40, alpha: 1)
    private static let bodyMid = NSColor(srgbRed: 0.24, green: 0.74, blue: 0.60, alpha: 1)
    private static let bodyLight = NSColor(srgbRed: 0.42, green: 0.86, blue: 0.72, alpha: 1)
    private static let outline = NSColor(srgbRed: 0.05, green: 0.27, blue: 0.23, alpha: 1)
    private static let ink = NSColor(srgbRed: 0.08, green: 0.14, blue: 0.13, alpha: 1)

    private func horizontalGradient(_ ctx: CGContext, _ rect: CGRect, _ colors: [NSColor], _ locs: [CGFloat]) {
        let cg = colors.map(\.cgColor) as CFArray
        guard let grad = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: cg, locations: locs) else { return }
        ctx.drawLinearGradient(grad, start: CGPoint(x: rect.minX, y: 0), end: CGPoint(x: rect.maxX, y: 0), options: [])
    }

    private func drawInterior(_ ctx: CGContext, _ g: BinGeometry) {
        let r = CGRect(x: g.topLeft.x + 2, y: g.topY - 8, width: BinGeometry.topWidth - 4, height: 22)
        ctx.setFillColor(NSColor(srgbRed: 0.03, green: 0.14, blue: 0.12, alpha: 1).cgColor)
        ctx.fillEllipse(in: r)
    }

    private func bodyPath(_ g: BinGeometry) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: g.cx, y: g.topY))
        path.addArc(tangent1End: g.topRight, tangent2End: g.bottomRight, radius: 6)
        path.addArc(tangent1End: g.bottomRight, tangent2End: g.bottomLeft, radius: 18)
        path.addArc(tangent1End: g.bottomLeft, tangent2End: g.topLeft, radius: 18)
        path.addArc(tangent1End: g.topLeft, tangent2End: g.topRight, radius: 6)
        path.closeSubpath()
        return path
    }

    private func drawBody(_ ctx: CGContext, _ g: BinGeometry) {
        let path = bodyPath(g)
        let bbox = path.boundingBox

        // Ground shadow.
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.25).cgColor)
        ctx.fillEllipse(in: CGRect(x: g.cx - 70, y: g.bottomY - 9, width: 140, height: 16))

        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        horizontalGradient(ctx, bbox, [Self.bodyDark, Self.bodyMid, Self.bodyLight, Self.bodyMid, Self.bodyDark],
                           [0, 0.25, 0.42, 0.7, 1])
        // Vertical ridges.
        ctx.setStrokeColor(Self.outline.withAlphaComponent(0.18).cgColor)
        ctx.setLineWidth(5)
        ctx.setLineCap(.round)
        for f in [-0.33, 0.33] as [CGFloat] {
            let top = CGPoint(x: g.cx + f * BinGeometry.topWidth, y: g.topY - 16)
            let bottom = CGPoint(x: g.cx + f * BinGeometry.bottomWidth, y: g.bottomY + 14)
            ctx.move(to: top)
            ctx.addLine(to: bottom)
        }
        ctx.strokePath()
        // Glossy highlight.
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.28).cgColor)
        ctx.setLineWidth(6)
        ctx.move(to: CGPoint(x: g.cx - BinGeometry.topWidth * 0.36, y: g.topY - 20))
        ctx.addLine(to: CGPoint(x: g.cx - BinGeometry.bottomWidth * 0.36, y: g.topY - 48))
        ctx.strokePath()
        ctx.restoreGState()

        ctx.addPath(path)
        ctx.setStrokeColor(Self.outline.cgColor)
        ctx.setLineWidth(2.5)
        ctx.strokePath()
    }

    private func drawRim(_ ctx: CGContext, _ g: BinGeometry) {
        let r = CGRect(x: g.topLeft.x - 7, y: g.topY - 6, width: BinGeometry.topWidth + 14, height: 11)
        let path = CGPath(roundedRect: r, cornerWidth: 5.5, cornerHeight: 5.5, transform: nil)
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        horizontalGradient(ctx, r, [Self.outline, Self.bodyDark, Self.bodyMid, Self.bodyDark, Self.outline], [0, 0.2, 0.45, 0.8, 1])
        ctx.restoreGState()
        ctx.addPath(path)
        ctx.setStrokeColor(Self.outline.cgColor)
        ctx.setLineWidth(2)
        ctx.strokePath()
    }

    private func drawLid(_ ctx: CGContext, _ g: BinGeometry) {
        let bin = scene.bin
        let (a, b) = bin.lidSegment(g)
        let d = b - a
        let len = d.length
        ctx.saveGState()
        ctx.translateBy(x: a.x, y: a.y)
        ctx.rotate(by: atan2(d.y, d.x))

        // Knob sits on the side that faces up when the lid is closed.
        let up: CGFloat = bin.hingeRight ? -1 : 1
        let knob = CGRect(x: len / 2 - 18, y: up > 0 ? 5 : -15, width: 36, height: 10)
        ctx.addPath(CGPath(roundedRect: knob, cornerWidth: 5, cornerHeight: 5, transform: nil))
        ctx.setFillColor(Self.bodyDark.cgColor)
        ctx.setStrokeColor(Self.outline.cgColor)
        ctx.setLineWidth(2)
        ctx.drawPath(using: .fillStroke)

        let plate = CGRect(x: -10, y: -6, width: len + 14, height: 12)
        let path = CGPath(roundedRect: plate, cornerWidth: 6, cornerHeight: 6, transform: nil)
        ctx.addPath(path)
        ctx.setFillColor(Self.bodyMid.cgColor)
        ctx.drawPath(using: .fillStroke)
        ctx.setFillColor(NSColor.white.withAlphaComponent(0.3).cgColor)
        ctx.fill(CGRect(x: 4, y: up > 0 ? 1 : -3, width: len - 10, height: 2.5))

        ctx.setFillColor(Self.outline.cgColor)
        ctx.fillEllipse(in: CGRect(x: -4, y: -4, width: 8, height: 8))
        ctx.restoreGState()
    }

    private func drawFace(_ ctx: CGContext, _ g: BinGeometry) {
        let bin = scene.bin
        let fc = g.faceCenter
        let eyeY = fc.y + 14
        let ink = Self.ink.cgColor
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        if bin.face == .happy || bin.face == .eager {
            ctx.setFillColor(NSColor.systemPink.withAlphaComponent(0.35).cgColor)
            for s in [-1, 1] as [CGFloat] {
                ctx.fillEllipse(in: CGRect(x: fc.x + s * 42 - 10, y: fc.y - 8, width: 20, height: 11))
            }
        }

        for s in [-1, 1] as [CGFloat] {
            let ex = fc.x + s * 25
            switch bin.face {
            case .happy:
                ctx.setStrokeColor(ink)
                ctx.setLineWidth(4)
                ctx.move(to: CGPoint(x: ex - 9, y: eyeY - 3))
                ctx.addQuadCurve(to: CGPoint(x: ex + 9, y: eyeY - 3), control: CGPoint(x: ex, y: eyeY + 13))
                ctx.strokePath()
            case .dizzy:
                ctx.setStrokeColor(ink)
                ctx.setLineWidth(3.5)
                ctx.move(to: CGPoint(x: ex - 7, y: eyeY - 7)); ctx.addLine(to: CGPoint(x: ex + 7, y: eyeY + 7))
                ctx.move(to: CGPoint(x: ex - 7, y: eyeY + 7)); ctx.addLine(to: CGPoint(x: ex + 7, y: eyeY - 7))
                ctx.strokePath()
            case .idle, .eager, .sad:
                let big: CGFloat = bin.face == .eager ? 1.15 : 1
                let w = 21 * big, h = 25 * big * max(0.1, 1 - bin.blink)
                let eye = CGRect(x: ex - w / 2, y: eyeY - h / 2, width: w, height: h)
                ctx.setFillColor(NSColor.white.cgColor)
                ctx.fillEllipse(in: eye)
                ctx.setStrokeColor(Self.outline.cgColor)
                ctx.setLineWidth(1.5)
                ctx.strokeEllipse(in: eye)
                guard bin.blink < 0.5 else { continue }
                var look = CGPoint(x: 0, y: bin.face == .sad ? -5 : 0)
                if let target = bin.lookAt {
                    let d = target - CGPoint(x: ex, y: eyeY)
                    if d.length > 1 { look = d * (min(d.length, 300) / 300 * 5.5 / d.length) }
                }
                let pr: CGFloat = 5.5 * big
                ctx.setFillColor(ink)
                ctx.fillEllipse(in: CGRect(x: ex + look.x - pr, y: eyeY + look.y - pr, width: pr * 2, height: pr * 2))
                ctx.setFillColor(NSColor.white.cgColor)
                ctx.fillEllipse(in: CGRect(x: ex + look.x - pr * 0.2, y: eyeY + look.y + pr * 0.2, width: pr * 0.6, height: pr * 0.6))
                if bin.face == .sad {
                    ctx.setStrokeColor(ink)
                    ctx.setLineWidth(3)
                    ctx.move(to: CGPoint(x: ex - s * 10, y: eyeY + 19))
                    ctx.addLine(to: CGPoint(x: ex + s * 8, y: eyeY + 14))
                    ctx.strokePath()
                }
            }
        }

        let my = fc.y - 20
        ctx.setStrokeColor(ink)
        ctx.setFillColor(ink)
        ctx.setLineWidth(3.5)
        switch bin.face {
        case .idle:
            ctx.move(to: CGPoint(x: fc.x - 12, y: my + 3))
            ctx.addQuadCurve(to: CGPoint(x: fc.x + 12, y: my + 3), control: CGPoint(x: fc.x, y: my - 7))
            ctx.strokePath()
        case .eager:
            ctx.fillEllipse(in: CGRect(x: fc.x - 12, y: my - 12, width: 24, height: 22))
            ctx.setFillColor(NSColor.systemPink.cgColor)
            ctx.fillEllipse(in: CGRect(x: fc.x - 7, y: my - 11, width: 14, height: 8))
        case .happy:
            let path = CGMutablePath()
            path.move(to: CGPoint(x: fc.x - 22, y: my + 6))
            path.addQuadCurve(to: CGPoint(x: fc.x + 22, y: my + 6), control: CGPoint(x: fc.x, y: my - 30))
            path.closeSubpath()
            ctx.addPath(path)
            ctx.fillPath()
            ctx.setFillColor(NSColor.systemPink.cgColor)
            ctx.fillEllipse(in: CGRect(x: fc.x - 9, y: my - 11, width: 18, height: 9))
        case .dizzy:
            ctx.move(to: CGPoint(x: fc.x - 15, y: my))
            ctx.addCurve(to: CGPoint(x: fc.x + 15, y: my), control1: CGPoint(x: fc.x - 5, y: my + 10), control2: CGPoint(x: fc.x + 5, y: my - 10))
            ctx.strokePath()
        case .sad:
            ctx.move(to: CGPoint(x: fc.x - 13, y: my - 5))
            ctx.addQuadCurve(to: CGPoint(x: fc.x + 13, y: my - 5), control: CGPoint(x: fc.x, y: my + 7))
            ctx.strokePath()
        }
    }

    private func drawTrail(_ ctx: CGContext, _ p: Projectile) {
        guard p.trail.count > 1 else { return }
        let fire = scene.game.onFire
        for (i, t) in p.trail.enumerated() {
            let f = CGFloat(i + 1) / CGFloat(p.trail.count)
            let r = Projectile.radius * f * 0.9
            let color: NSColor = fire ? .systemOrange : .white
            ctx.setFillColor(color.withAlphaComponent(0.22 * f).cgColor)
            ctx.fillEllipse(in: CGRect(x: t.x - r, y: t.y - r, width: r * 2, height: r * 2))
        }
    }

    private func drawProjectile(_ ctx: CGContext, _ p: Projectile) {
        ctx.saveGState()
        ctx.translateBy(x: p.pos.x, y: p.pos.y)
        ctx.rotate(by: p.angle)
        ctx.scaleBy(x: p.scale, y: p.scale)
        ctx.setAlpha(p.alpha)
        if p.state == .flying {
            ctx.setShadow(offset: CGSize(width: 0, height: -5), blur: 10, color: NSColor.black.withAlphaComponent(0.35).cgColor)
        }
        let half = Projectile.size / 2
        let rect = CGRect(x: -half, y: -half, width: Projectile.size, height: Projectile.size)
        if let icon = p.icon {
            icon.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        } else {
            drawPaperBall(ctx)
        }
        ctx.restoreGState()
    }

    private func drawPaperBall(_ ctx: CGContext) {
        let r: CGFloat = 22
        let path = CGMutablePath()
        let bumps: [CGFloat] = [1, 0.84, 0.97, 0.9, 1, 0.8, 0.95, 0.88, 1, 0.83, 0.93, 0.9, 0.98, 0.82, 0.96, 0.87]
        for i in 0..<bumps.count {
            let a = CGFloat(i) / CGFloat(bumps.count) * .pi * 2
            let rr = r * bumps[i]
            let pt = CGPoint(x: cos(a) * rr, y: sin(a) * rr)
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        path.closeSubpath()
        ctx.addPath(path)
        ctx.setFillColor(NSColor(white: 0.96, alpha: 1).cgColor)
        ctx.fillPath()
        ctx.setShadow(offset: .zero, blur: 0, color: nil)
        ctx.addPath(path)
        ctx.setStrokeColor(NSColor(white: 0.6, alpha: 1).cgColor)
        ctx.setLineWidth(1.5)
        ctx.strokePath()
        ctx.setStrokeColor(NSColor(white: 0.72, alpha: 1).cgColor)
        ctx.setLineWidth(1.2)
        ctx.move(to: CGPoint(x: -12, y: 6)); ctx.addLine(to: CGPoint(x: 2, y: -3)); ctx.addLine(to: CGPoint(x: 10, y: 9))
        ctx.move(to: CGPoint(x: -6, y: -14)); ctx.addLine(to: CGPoint(x: 0, y: -3)); ctx.addLine(to: CGPoint(x: -14, y: -4))
        ctx.move(to: CGPoint(x: 6, y: -12)); ctx.addLine(to: CGPoint(x: 12, y: -2))
        ctx.strokePath()
    }

    private func drawParticles(_ ctx: CGContext, kind: Particle.Kind) {
        for p in scene.particles where p.kind == kind {
            let t = p.age / p.life
            let alpha = 1 - t * t
            ctx.setFillColor(p.color.withAlphaComponent(alpha).cgColor)
            switch kind {
            case .confetti:
                ctx.saveGState()
                ctx.translateBy(x: p.pos.x, y: p.pos.y)
                ctx.rotate(by: p.rot)
                ctx.fill(CGRect(x: -p.size / 2, y: -p.size / 4 * abs(cos(p.rot * 1.7)) - 1, width: p.size, height: p.size / 2))
                ctx.restoreGState()
            case .spark, .flame:
                let s = kind == .flame ? p.size * (1 - t * 0.7) : p.size
                ctx.fillEllipse(in: CGRect(x: p.pos.x - s / 2, y: p.pos.y - s / 2, width: s, height: s))
            }
        }
    }

    private func drawHUD(_ ctx: CGContext, _ g: BinGeometry) {
        let game = scene.game
        let fmt = NumberFormatter()
        fmt.numberStyle = .decimal
        var text = "★ " + (fmt.string(from: NSNumber(value: game.score)) ?? "\(game.score)")
        if game.multiplier > 1 { text += "  ×\(game.multiplier)" }
        let color: NSColor = game.onFire ? .systemOrange : .white
        let attrs: [NSAttributedString.Key: Any] = [.font: roundedFont(15, .bold), .foregroundColor: color]
        let str = NSAttributedString(string: text, attributes: attrs)
        let size = str.size()

        ctx.saveGState()
        let pulse = 1 + scene.hudPulse * scene.hudPulse * 0.25
        ctx.translateBy(x: g.hudCenter.x, y: g.hudCenter.y)
        ctx.scaleBy(x: pulse, y: pulse)
        let pill = CGRect(x: -size.width / 2 - 12, y: -size.height / 2 - 4, width: size.width + 24, height: size.height + 8)
        ctx.addPath(CGPath(roundedRect: pill, cornerWidth: pill.height / 2, cornerHeight: pill.height / 2, transform: nil))
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.55).cgColor)
        ctx.fillPath()
        if game.onFire {
            ctx.addPath(CGPath(roundedRect: pill, cornerWidth: pill.height / 2, cornerHeight: pill.height / 2, transform: nil))
            ctx.setStrokeColor(NSColor.systemOrange.cgColor)
            ctx.setLineWidth(1.5)
            ctx.strokePath()
        }
        str.draw(at: CGPoint(x: -size.width / 2, y: -size.height / 2))
        ctx.restoreGState()
    }

    private func drawSpeech(_ ctx: CGContext, _ g: BinGeometry) {
        guard let speech = scene.speech else { return }
        let attrs: [NSAttributedString.Key: Any] = [.font: roundedFont(14, .semibold), .foregroundColor: Self.ink]
        let str = NSAttributedString(string: speech.text, attributes: attrs)
        let size = str.size()
        let alpha = min(1, speech.remaining * 4)
        // Bubble sits on the side away from the lid's hinge.
        let side: CGFloat = scene.bin.hingeRight ? -1 : 1
        let tip = CGPoint(x: g.cx + side * 50, y: g.topY + 24)
        let box = CGRect(x: tip.x + (side < 0 ? -size.width - 10 : -14), y: tip.y + 14,
                         width: size.width + 24, height: size.height + 14)

        ctx.saveGState()
        ctx.setAlpha(alpha)
        ctx.setShadow(offset: CGSize(width: 0, height: -2), blur: 6, color: NSColor.black.withAlphaComponent(0.3).cgColor)
        let path = CGMutablePath()
        path.addRoundedRect(in: box, cornerWidth: 12, cornerHeight: 12)
        path.move(to: CGPoint(x: tip.x - 7, y: box.minY + 1))
        path.addLine(to: tip)
        path.addLine(to: CGPoint(x: tip.x + 7, y: box.minY + 1))
        ctx.addPath(path)
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fillPath()
        ctx.restoreGState()

        ctx.saveGState()
        ctx.setAlpha(alpha)
        str.draw(at: CGPoint(x: box.minX + 12, y: box.minY + 7))
        ctx.restoreGState()
    }

    private func drawPopup(_ ctx: CGContext, _ p: Popup) {
        let t = p.age - p.delay
        let appear = min(1, t / 0.14)
        let scale = appear < 1 ? 0.4 + appear * 0.8 : 1 + max(0, 0.2 - (t - 0.14) * 2)
        let alpha = min(1, max(0, (p.life - t) / 0.35))
        let attrs: [NSAttributedString.Key: Any] = [
            .font: roundedFont(p.fontSize, .heavy),
            .foregroundColor: p.color,
            .strokeColor: NSColor.black.withAlphaComponent(0.75),
            .strokeWidth: -4,
        ]
        let str = NSAttributedString(string: p.text, attributes: attrs)
        let size = str.size()
        ctx.saveGState()
        ctx.setAlpha(alpha)
        ctx.translateBy(x: p.pos.x, y: p.pos.y)
        ctx.scaleBy(x: scale, y: scale)
        ctx.setShadow(offset: CGSize(width: 0, height: -2), blur: 4, color: NSColor.black.withAlphaComponent(0.4).cgColor)
        str.draw(at: CGPoint(x: -size.width / 2, y: -size.height / 2))
        ctx.restoreGState()
    }
}
