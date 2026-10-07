import CoreGraphics
import Foundation

/// Score, combo and lifetime stats. Persisted in UserDefaults.
final class Game {
    private let defaults = UserDefaults.standard

    private(set) var score: Int { didSet { defaults.set(score, forKey: "score") } }
    private(set) var bestStreak: Int { didSet { defaults.set(bestStreak, forKey: "bestStreak") } }
    private(set) var totalTrashed: Int { didSet { defaults.set(totalTrashed, forKey: "totalTrashed") } }
    private(set) var streak = 0

    var onChange: (() -> Void)?

    static let maxMultiplier = 10
    var multiplier: Int { min(1 + streak, Self.maxMultiplier) }
    var onFire: Bool { multiplier >= 5 }

    init() {
        score = defaults.integer(forKey: "score")
        bestStreak = defaults.integer(forKey: "bestStreak")
        totalTrashed = defaults.integer(forKey: "totalTrashed")
    }

    struct Shot {
        var isDunk = false
        var touchedRim = false
        var touchedLid = false
        var touchedFloor = false
        var distance: CGFloat = 0
        var isPractice = false
    }

    struct Result {
        let points: Int
        let multiplier: Int
        let callouts: [String]
    }

    func scored(_ shot: Shot) -> Result {
        if shot.isDunk {
            // Dunks are safe but don't build the combo.
            let pts = 100 * multiplier
            score += pts
            totalTrashed += 1
            onChange?()
            return Result(points: pts, multiplier: multiplier, callouts: ["DUNK!"])
        }

        var bonus = 0
        var callouts: [String] = []
        if shot.touchedFloor { bonus += 200; callouts.append("BOUNCE PASS!") }
        if shot.touchedLid { bonus += 150; callouts.append("BANK SHOT!") }
        if shot.touchedRim && !shot.touchedLid { bonus += 50; callouts.append("RIM-IN!") }
        if !shot.touchedRim && !shot.touchedLid && !shot.touchedFloor { bonus += 100; callouts.append("SWISH!") }
        if shot.distance > 900 { bonus += 250; callouts.append("FROM DOWNTOWN!") }
        else if shot.distance > 500 { bonus += 100; callouts.append("LONG SHOT!") }

        let mult = multiplier
        let pts = (100 + bonus) * mult
        // Practice balls show what the shot would be worth but leave the real game alone.
        if shot.isPractice { return Result(points: pts, multiplier: mult, callouts: callouts) }
        score += pts
        totalTrashed += 1
        streak += 1
        bestStreak = max(bestStreak, streak)
        if multiplier == 5 && mult == 4 { callouts.append("ON FIRE!") }
        if multiplier == Self.maxMultiplier && mult < Self.maxMultiplier { callouts.append("MAX COMBO!") }
        onChange?()
        return Result(points: pts, multiplier: mult, callouts: callouts)
    }

    /// Returns the streak that was lost.
    @discardableResult
    func missed() -> Int {
        let lost = streak
        streak = 0
        onChange?()
        return lost
    }

    func undoTrash() {
        totalTrashed = max(0, totalTrashed - 1)
        onChange?()
    }

    func reset() {
        score = 0
        streak = 0
        bestStreak = 0
        totalTrashed = 0
        onChange?()
    }
}
