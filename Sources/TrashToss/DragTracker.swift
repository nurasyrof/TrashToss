import AppKit

/// Watches the global mouse by polling (no Accessibility permission needed) to know when a
/// Finder drag that started on the desktop is in progress, and how fast the cursor is moving.
final class DragTracker {
    private(set) var isDown = false
    private(set) var armed = false
    private var desktopOrigin = false
    private var baseline = 0
    private var releaseTime: Double = 0
    private var samples: [(t: Double, p: CGPoint)] = []

    private let dragPasteboard = NSPasteboard(name: .drag)

    var cursor: CGPoint { NSEvent.mouseLocation }

    func tick(now: Double) {
        let down = (NSEvent.pressedMouseButtons & 1) != 0
        let p = NSEvent.mouseLocation

        if down && !isDown {
            isDown = true
            samples.removeAll()
            baseline = dragPasteboard.changeCount
            desktopOrigin = DesktopProbe.isDesktop(at: p)
            armed = false
        } else if !down && isDown {
            isDown = false
            releaseTime = now
        }

        if down {
            samples.append((now, p))
            samples.removeAll { now - $0.t > 0.2 }
            // A new drag session rewrites the drag pasteboard.
            if !armed && desktopOrigin && dragPasteboard.changeCount != baseline {
                armed = true
            }
        } else if armed && now - releaseTime > 0.3 {
            armed = false
        }
    }

    var currentSpeed: CGFloat { isDown ? velocity(window: 0.06).length : 0 }

    /// Cursor velocity just before release, in points per second (screen coords, y up).
    func releaseVelocity() -> CGPoint { velocity(window: 0.07) }

    private func velocity(window: Double) -> CGPoint {
        guard let last = samples.last else { return .zero }
        guard let first = samples.first(where: { last.t - $0.t <= window }), last.t - first.t > 0.012 else {
            return .zero
        }
        return (last.p - first.p) * CGFloat(1 / (last.t - first.t))
    }
}

enum DesktopProbe {
    /// True when no app window sits above the desktop at this point (Cocoa screen coords).
    static func isDesktop(at point: CGPoint) -> Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]],
              let primary = NSScreen.screens.first else { return false }
        let cgPoint = CGPoint(x: point.x, y: primary.frame.maxY - point.y)
        let iconLevel = Int(CGWindowLevelForKey(.desktopIconWindow))
        let me = Int(getpid())

        for w in list {
            guard let layer = w[kCGWindowLayer as String] as? Int,
                  let pid = w[kCGWindowOwnerPID as String] as? Int,
                  let boundsDict = w[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: boundsDict) else { continue }
            // Skip our own windows and system chrome (menu bar, Dock, overlays) above normal level.
            if pid == me || layer > 0 { continue }
            if let alpha = w[kCGWindowAlpha as String] as? Double, alpha <= 0 { continue }
            guard rect.contains(cgPoint) else { continue }
            return layer <= iconLevel
        }
        return true
    }
}
