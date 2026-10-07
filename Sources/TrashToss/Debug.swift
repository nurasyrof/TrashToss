import AppKit

/// `TrashToss --snapshot <dir>` fires practice shots and writes PNG frames of the bin area,
/// for checking the rendering without screen-recording access.
enum DebugSnapshot {
    static func runIfRequested(scene: Scene, view: OverlayView) {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count else { return }
        let dir = URL(fileURLWithPath: args[i + 1])
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        scene.say("Fling desktop files at me!", seconds: 30)
        for k in 0..<4 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5 + Double(k) * 1.6) { scene.practiceShot() }
        }
        for n in 0..<40 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3 + Double(n) * 0.18) {
                let g = scene.geometry
                let rect = CGRect(x: g.cx - 450, y: g.bottomY - 80, width: 900, height: 600).intersection(view.bounds)
                guard let rep = view.bitmapImageRepForCachingDisplay(in: rect) else { return }
                view.cacheDisplay(in: rect, to: rep)
                // Composite over a gray "wallpaper" so transparency reads.
                let img = NSImage(size: rect.size)
                img.lockFocus()
                NSColor(srgbRed: 0.35, green: 0.42, blue: 0.55, alpha: 1).setFill()
                CGRect(origin: .zero, size: rect.size).fill()
                rep.draw(in: CGRect(origin: .zero, size: rect.size))
                img.unlockFocus()
                guard let tiff = img.tiffRepresentation, let bmp = NSBitmapImageRep(data: tiff),
                      let png = bmp.representation(using: .png, properties: [:]) else { return }
                try? png.write(to: dir.appendingPathComponent(String(format: "frame%02d.png", n)))
                if n == 39 { NSApp.terminate(nil) }
            }
        }
    }
}
