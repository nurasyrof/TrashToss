import AppKit

enum HitKind { case rim, lid, wall, floor }

final class Projectile {
    enum State { case flying, sinking, fading }

    static let radius: CGFloat = 22
    static let size: CGFloat = 60

    /// nil for practice paper balls.
    let url: URL?
    let icon: NSImage?
    var pos: CGPoint
    var vel: CGPoint
    var angle: CGFloat = 0
    var spin: CGFloat
    var state = State.flying
    var stateTime: CGFloat = 0
    var age: CGFloat = 0
    var restTime: CGFloat = 0
    var shot = Game.Shot()
    var trail: [CGPoint] = []
    var lastHit: [HitKind: CGFloat] = [:]
    var dead = false

    init(url: URL?, pos: CGPoint, vel: CGPoint) {
        self.url = url
        self.pos = pos
        self.vel = vel
        self.spin = clamp(-vel.x / 160, -14, 14) + rand(-2, 2)
        if let url {
            let img = NSWorkspace.shared.icon(forFile: url.path)
            img.size = NSSize(width: Self.size, height: Self.size)
            icon = img
        } else {
            icon = nil
        }
    }

    var scale: CGFloat {
        switch state {
        case .flying: return 1
        case .sinking: return max(0.55, 1 - stateTime * 1.2)
        case .fading: return 1
        }
    }

    var alpha: CGFloat {
        switch state {
        case .flying, .sinking: return 1
        case .fading: return max(0, 1 - stateTime / 0.6)
        }
    }
}

struct Particle {
    enum Kind { case confetti, spark, flame }
    var kind: Kind
    var pos: CGPoint
    var vel: CGPoint
    var color: NSColor
    var size: CGFloat
    var life: CGFloat
    var age: CGFloat = 0
    var rot: CGFloat = 0
    var spin: CGFloat = 0
}

struct Popup {
    var text: String
    var pos: CGPoint
    var vel: CGPoint = CGPoint(x: 0, y: 70)
    var color: NSColor
    var fontSize: CGFloat
    var life: CGFloat = 1.3
    var delay: CGFloat = 0
    var age: CGFloat = 0
}

/// The whole simulation: bin, projectiles, effects. Coordinates are overlay view coords (y up).
final class Scene {
    let bin = BinState()
    let game: Game

    var projectiles: [Projectile] = []
    var particles: [Particle] = []
    var popups: [Popup] = []
    var speech: (text: String, remaining: CGFloat)?

    var binOrigin: CGPoint = .zero
    var bounds: CGRect = .zero
    var floorY: CGFloat = 0
    var armed = false
    var cursor: CGPoint = .zero
    var hudPulse: CGFloat = 0
    var heat: CGFloat = 0 // seconds of flame effect left

    /// Moves the file to the Trash; returns false when it couldn't.
    var trashHandler: ((URL) -> Bool)?

    let gravity: CGFloat = 2400
    private var fireAccumulator: CGFloat = 0

    var geometry: BinGeometry { BinGeometry(origin: binOrigin) }

    init(game: Game) {
        self.game = game
    }

    // MARK: - Spawning

    func throwItems(_ urls: [URL?], from point: CGPoint, velocity: CGPoint) {
        for (i, url) in urls.enumerated() {
            let jitter = i == 0 ? CGPoint.zero : CGPoint(x: rand(-10, 10), y: rand(-10, 10))
            let vj = i == 0 ? 1 : rand(0.92, 1.06)
            let p = Projectile(url: url, pos: point + jitter, vel: velocity * vj)
            p.shot.distance = (point - geometry.mouth).length
            p.shot.isPractice = url == nil
            projectiles.append(p)
        }
        openLid(toward: point)
        if urls.count > 1 {
            say(["Multi-toss!", "Ooh, a buffet!", "All at once?!"].randomElement()!, seconds: 1.4)
        }
    }

    /// Dropped straight on the bin: no physics needed, it just goes in.
    func dunk(_ urls: [URL]) {
        let g = geometry
        openLid(toward: cursor)
        bin.lidOpen = max(bin.lidOpen, 0.8)
        for (i, url) in urls.enumerated() {
            let p = Projectile(url: url, pos: CGPoint(x: g.cx + CGFloat(i % 3 - 1) * 20, y: g.topY + 30), vel: CGPoint(x: 0, y: -500))
            p.shot.isDunk = true
            projectiles.append(p)
            score(p, g)
        }
    }

    func practiceShot() {
        let g = geometry
        let fromLeft = Bool.random()
        let start = CGPoint(
            x: clamp(g.cx + (fromLeft ? -1 : 1) * rand(450, 750), bounds.minX + 40, bounds.maxX - 40),
            y: clamp(g.topY + rand(-60, 120), floorY + 60, bounds.maxY - 80))
        let target = g.mouth + CGPoint(x: rand(-55, 55), y: 0)
        let t = rand(0.75, 1.0)
        let v = CGPoint(x: (target.x - start.x) / t, y: (target.y - start.y) / t + 0.5 * gravity * t)
        throwItems([nil], from: start, velocity: v)
    }

    func say(_ text: String, seconds: CGFloat = 2.2) {
        speech = (text, seconds)
    }

    private func openLid(toward point: CGPoint) {
        if bin.lidOpen < 0.25 {
            // Lid hinges on the far side so it works as a backboard.
            bin.hingeRight = point.x < geometry.cx
        }
        bin.lidTarget = 1
    }

    // MARK: - Simulation

    /// Advances the world. Returns true while anything needs redrawing.
    func step(_ dt: CGFloat) -> Bool {
        let g = geometry
        let flying = projectiles.contains { $0.state == .flying }

        if (armed || flying) && bin.lidTarget == 0 { openLid(toward: cursor) }
        if !armed && !flying && bin.lidTarget == 1 { bin.lidTarget = 0 }
        bin.setEager(armed || flying)
        bin.lookAt = projectiles.first(where: { $0.state == .flying })?.pos ?? (armed ? cursor : nil)
        let blinked = bin.step(dt)

        for p in projectiles { update(p, dt, g) }
        projectiles.removeAll { $0.dead }

        updateEffects(dt, g)

        return blinked || armed || !projectiles.isEmpty || !particles.isEmpty || !popups.isEmpty
            || speech != nil || hudPulse > 0 || heat > 0 || !bin.isSettled
    }

    private func update(_ p: Projectile, _ dt: CGFloat, _ g: BinGeometry) {
        p.age += dt
        p.stateTime += dt
        for k in p.lastHit.keys { p.lastHit[k]! += dt }

        switch p.state {
        case .sinking:
            p.vel.y -= gravity * dt * 0.5
            p.pos += p.vel * dt
            p.pos.x = clamp(p.pos.x, g.topLeft.x + 26, g.topRight.x - 26)
            p.angle += p.spin * dt * 0.4
            if p.stateTime > 0.45 { p.dead = true }
            return
        case .fading:
            p.vel.y -= gravity * dt
            p.pos += p.vel * dt
            if p.pos.y < floorY + Projectile.radius {
                p.pos.y = floorY + Projectile.radius
                p.vel = CGPoint(x: p.vel.x * 0.6, y: abs(p.vel.y) * 0.3)
            }
            if p.stateTime > 0.6 { p.dead = true }
            return
        case .flying:
            break
        }

        if p.vel.length > 900 {
            p.trail.append(p.pos)
            if p.trail.count > 10 { p.trail.removeFirst() }
        } else if !p.trail.isEmpty {
            p.trail.removeFirst()
        }

        let r = Projectile.radius
        let substeps = 5
        let h = dt / CGFloat(substeps)
        let (lidA, lidB) = bin.lidSegment(g)

        for _ in 0..<substeps {
            let prev = p.pos
            p.vel.y -= gravity * h
            p.pos += p.vel * h
            p.angle += p.spin * h

            collide(p, g.topLeft, g.bottomLeft, thick: 2, e: 0.35, .wall, g)
            collide(p, g.topRight, g.bottomRight, thick: 2, e: 0.35, .wall, g)
            collide(p, g.bottomLeft, g.bottomRight, thick: 2, e: 0.35, .wall, g)
            collide(p, g.topLeft, g.topLeft, thick: BinGeometry.rimRadius, e: 0.55, .rim, g)
            collide(p, g.topRight, g.topRight, thick: BinGeometry.rimRadius, e: 0.55, .rim, g)
            collide(p, lidA, lidB, thick: 5, e: 0.72, .lid, g)

            // Through the opening, heading down = in the bin.
            let inner = BinGeometry.rimRadius * 0.6
            if prev.y >= g.topY && p.pos.y < g.topY && p.vel.y < 0
                && p.pos.x > g.topLeft.x + inner && p.pos.x < g.topRight.x - inner
                && bin.lidOpen > 0.55 {
                score(p, g)
                return
            }

            // Screen floor and sides.
            if p.pos.y - r < floorY {
                p.pos.y = floorY + r
                if p.vel.y < 0 {
                    if -p.vel.y > 220 { hit(.floor, p, speed: -p.vel.y) }
                    p.vel.y = -p.vel.y * 0.45
                    p.spin = p.vel.x / -r * 0.6
                }
                p.vel.x *= pow(0.25, h)
            }
            if p.pos.x - r < bounds.minX { p.pos.x = bounds.minX + r; p.vel.x = abs(p.vel.x) * 0.5 }
            if p.pos.x + r > bounds.maxX { p.pos.x = bounds.maxX - r; p.vel.x = -abs(p.vel.x) * 0.5 }
        }

        let resting = p.pos.y - r <= floorY + 2 && p.vel.length < 90
        p.restTime = resting ? p.restTime + dt : 0
        if p.restTime > 0.3 || p.age > 6 { miss(p) }
    }

    private func collide(_ p: Projectile, _ a: CGPoint, _ b: CGPoint, thick: CGFloat, e: CGFloat, _ kind: HitKind, _ g: BinGeometry) {
        let c = closestPoint(onSegment: a, b, to: p.pos)
        let d = p.pos - c
        let dist = d.length
        let minD = Projectile.radius + thick
        guard dist < minD, dist > 0.0001 else { return }
        let n = d * (1 / dist)
        p.pos = c + n * minD
        let vn = p.vel.dot(n)
        guard vn < 0 else { return }
        let vt = p.vel - n * vn
        p.vel = vt * 0.9 - n * (vn * e)
        p.spin = clamp(p.spin + (vt.x * n.y - vt.y * n.x) / Projectile.radius * 0.5, -20, 20)
        if -vn > 90 { hit(kind, p, speed: -vn) }
    }

    private func hit(_ kind: HitKind, _ p: Projectile, speed: CGFloat) {
        if let t = p.lastHit[kind], t < 0.08 { return }
        p.lastHit[kind] = 0
        let vol = Float(clamp(speed / 1400, 0.2, 1))
        switch kind {
        case .rim:
            p.shot.touchedRim = true
            Sounds.play("Tink", volume: vol)
            bin.kick(wobble: (p.pos.x < geometry.cx ? 1 : -1) * clamp(speed / 300, 0.5, 4))
            bin.show(.dizzy, for: 0.7)
            sparks(at: p.pos, count: 6)
        case .lid:
            p.shot.touchedLid = true
            Sounds.play("Pop", volume: vol)
            bin.kick(lid: -clamp(speed / 500, 0.5, 4))
        case .wall:
            p.shot.touchedRim = true
            Sounds.play("Bottle", volume: vol * 0.7)
            bin.kick(wobble: (p.pos.x < geometry.cx ? 1 : -1) * clamp(speed / 400, 0.3, 3))
        case .floor:
            if p.pos.y < geometry.topY { p.shot.touchedFloor = true }
            Sounds.play("Purr", volume: vol * 0.5)
        }
    }

    private func score(_ p: Projectile, _ g: BinGeometry) {
        p.state = .sinking
        p.stateTime = 0
        p.trail.removeAll()
        p.vel = CGPoint(x: p.vel.x * 0.15, y: min(p.vel.y * 0.4, -250))

        if let url = p.url, trashHandler?(url) != true {
            popups.append(Popup(text: "Couldn't trash it", pos: g.mouth + CGPoint(x: 0, y: 40), color: .systemRed, fontSize: 18))
            bin.show(.sad, for: 1.2)
            Sounds.play("Basso")
            return
        }

        let result = game.scored(p.shot)
        let mouth = g.mouth + CGPoint(x: 0, y: 30)
        popups.append(Popup(text: "+\(result.points)", pos: mouth, color: .systemYellow, fontSize: 34))
        if result.multiplier > 1 {
            popups.append(Popup(text: "×\(result.multiplier) COMBO", pos: mouth + CGPoint(x: 0, y: -26), color: .systemOrange, fontSize: 16, delay: 0.08))
        }
        for (i, c) in result.callouts.enumerated() {
            let side: CGFloat = i % 2 == 0 ? -1 : 1
            popups.append(Popup(text: c, pos: mouth + CGPoint(x: side * 70, y: 40 + CGFloat(i) * 30),
                                vel: CGPoint(x: side * 20, y: 90), color: calloutColor(c), fontSize: 22,
                                life: 1.6, delay: 0.12 + CGFloat(i) * 0.1))
        }
        if p.shot.isPractice {
            popups.append(Popup(text: "practice", pos: mouth + CGPoint(x: 0, y: -48), color: .white, fontSize: 12, delay: 0.1))
        }

        confetti(at: g.mouth, count: 18 + result.multiplier * 4)
        bin.kick(squash: 4)
        bin.show(.happy, for: 1.3)
        hudPulse = 1
        if game.onFire { heat = 6 }

        Sounds.play("trash")
        if result.callouts.contains("SWISH!") { Sounds.play("Glass", volume: 0.6) }
        if result.callouts.contains("ON FIRE!") || result.callouts.contains("MAX COMBO!") { Sounds.play("Hero", volume: 0.8) }
    }

    private func miss(_ p: Projectile) {
        p.state = .fading
        p.stateTime = 0
        let lost = p.shot.isPractice ? 0 : game.missed()
        let at = CGPoint(x: clamp(p.pos.x, bounds.minX + 80, bounds.maxX - 80), y: max(p.pos.y + 40, floorY + 70))
        let text = p.shot.touchedRim ? "SO CLOSE" : ["MISS", "AIRBALL", "BRICK"].randomElement()!
        popups.append(Popup(text: text, pos: at, color: .systemRed, fontSize: 26))
        if p.url != nil {
            popups.append(Popup(text: "file is safe", pos: at + CGPoint(x: 0, y: -26), color: .white, fontSize: 12, delay: 0.1))
        }
        if lost >= 3 {
            say("Noooo, my ×\(min(lost + 1, Game.maxMultiplier)) combo!", seconds: 2)
        }
        if !p.shot.isPractice { heat = 0 }
        bin.show(.sad, for: 1.4)
        Sounds.play("Funk", volume: 0.7)
    }

    private func calloutColor(_ text: String) -> NSColor {
        switch text {
        case "SWISH!": return .systemTeal
        case "BANK SHOT!": return .systemPurple
        case "ON FIRE!", "MAX COMBO!": return .systemOrange
        case "DUNK!": return .systemPink
        default: return .systemGreen
        }
    }

    // MARK: - Effects

    private static let confettiColors: [NSColor] = [.systemPink, .systemYellow, .systemTeal, .systemPurple, .systemGreen, .systemOrange, .systemBlue]

    private func confetti(at point: CGPoint, count: Int) {
        for _ in 0..<count {
            let a = rand(.pi * 0.15, .pi * 0.85)
            let s = rand(350, 900)
            particles.append(Particle(kind: .confetti, pos: point, vel: CGPoint(x: cos(a) * s, y: sin(a) * s),
                                      color: Self.confettiColors.randomElement()!, size: rand(5, 9),
                                      life: rand(0.9, 1.5), rot: rand(0, .pi), spin: rand(-12, 12)))
        }
    }

    private func sparks(at point: CGPoint, count: Int) {
        for _ in 0..<count {
            let a = rand(0, .pi * 2)
            let s = rand(150, 420)
            particles.append(Particle(kind: .spark, pos: point, vel: CGPoint(x: cos(a) * s, y: sin(a) * s),
                                      color: .white, size: rand(2, 4), life: rand(0.2, 0.4)))
        }
    }

    private func updateEffects(_ dt: CGFloat, _ g: BinGeometry) {
        if heat > 0 && game.onFire {
            heat -= dt
            fireAccumulator += dt * 40
            while fireAccumulator >= 1 {
                fireAccumulator -= 1
                let x = rand(g.topLeft.x, g.topRight.x)
                particles.append(Particle(kind: .flame, pos: CGPoint(x: x, y: g.topY + 4),
                                          vel: CGPoint(x: rand(-20, 20), y: rand(90, 200)),
                                          color: [.systemOrange, .systemYellow, .systemRed].randomElement()!,
                                          size: rand(6, 12), life: rand(0.35, 0.7)))
            }
        } else {
            heat = 0
        }

        for i in particles.indices {
            particles[i].age += dt
            switch particles[i].kind {
            case .confetti:
                particles[i].vel.y -= 1300 * dt
                particles[i].vel = particles[i].vel * pow(0.35, dt)
            case .spark:
                particles[i].vel = particles[i].vel * pow(0.05, dt)
            case .flame:
                particles[i].vel.x += rand(-200, 200) * dt
            }
            particles[i].pos += particles[i].vel * dt
            particles[i].rot += particles[i].spin * dt
        }
        particles.removeAll { $0.age >= $0.life }

        for i in popups.indices {
            popups[i].age += dt
            if popups[i].age > popups[i].delay {
                popups[i].pos += popups[i].vel * dt
                popups[i].vel = popups[i].vel * pow(0.3, dt)
            }
        }
        popups.removeAll { $0.age >= $0.life + $0.delay }

        if var s = speech {
            s.remaining -= dt
            speech = s.remaining > 0 ? s : nil
        }
        hudPulse = max(0, hudPulse - dt * 3)
    }

    // MARK: - Invalidation

    /// Union of everything currently painted, for partial redraws.
    func paintRect() -> CGRect {
        var r = geometry.paintRect
        for p in projectiles {
            r = r.union(CGRect(x: p.pos.x - 45, y: p.pos.y - 45, width: 90, height: 90))
            for t in p.trail { r = r.union(CGRect(x: t.x - 35, y: t.y - 35, width: 70, height: 70)) }
        }
        for p in particles { r = r.union(CGRect(x: p.pos.x - 12, y: p.pos.y - 12, width: 24, height: 24)) }
        for p in popups { r = r.union(CGRect(x: p.pos.x - 170, y: p.pos.y - 30, width: 340, height: 70)) }
        return r
    }
}
