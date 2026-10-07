import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, BinWindowDelegate, NSMenuDelegate {
    private let game = Game()
    private let trash = TrashService()
    private let tracker = DragTracker()
    private lazy var scene = Scene(game: game)

    private var overlay: NSPanel!
    private var overlayView: OverlayView!
    private var binWindow: NSPanel!
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var lastTick: Double = 0
    private var catching = false
    private var wasAnimating = true
    private var inFlight: Set<URL> = []

    private let defaults = UserDefaults.standard

    /// Scales mouse fling speed into throw speed.
    private var throwPower: CGFloat {
        let v = defaults.double(forKey: "throwPower")
        return v > 0 ? CGFloat(v) : 0.7
    }

    /// When on, every desktop drag is caught (slow drops off the bin snap back);
    /// when off, only fast flings are caught and slow drags go to Finder as usual.
    private var alwaysCatch: Bool {
        get { defaults.bool(forKey: "alwaysCatch") }
        set { defaults.set(newValue, forKey: "alwaysCatch") }
    }

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        Sounds.preload()
        overlayView = OverlayView(scene: scene)
        overlayView.dropHandler = self

        let origin = savedBinOrigin() ?? defaultBinOrigin()
        binWindow = makeBinWindow(origin: origin, delegate: self)
        overlay = makeOverlayWindow(screen: screenForBin(origin), view: overlayView)
        syncSceneGeometry()

        scene.trashHandler = { [weak self] url in self?.trashFile(url) ?? false }
        game.onChange = { [weak self] in self?.updateStatusTitle() }

        overlay.orderFrontRegardless()
        binWindow.orderFrontRegardless()

        setupStatusItem()

        if !defaults.bool(forKey: "greeted") {
            defaults.set(true, forKey: "greeted")
            scene.say("Fling desktop files at me!", seconds: 6)
        } else {
            scene.say(["I'm hungry.", "Feed me files!", "Ready when you are."].randomElement()!, seconds: 3)
        }

        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)

        lastTick = ProcessInfo.processInfo.systemUptime
        let t = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t

        DebugSnapshot.runIfRequested(scene: scene, view: overlayView)
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let dt = CGFloat(min(now - lastTick, 1.0 / 30.0))
        lastTick = now

        tracker.tick(now: now)
        updateCatching()

        scene.armed = tracker.armed
        scene.cursor = tracker.cursor - overlay.frame.origin
        let animating = scene.step(dt)
        if animating || wasAnimating {
            overlayView.invalidate()
        }
        wasAnimating = animating
    }

    /// Only intercept drags while they're moving fast, so normal icon rearranging still works.
    private func updateCatching() {
        var want = false
        if tracker.armed && tracker.isDown {
            let speed = tracker.currentSpeed
            if alwaysCatch || speed > 650 { want = true }
            else if speed < 220 { want = false }
            else { want = catching }
        } else if tracker.armed && catching {
            want = true // keep catching through the release moment
        }
        if want != catching {
            catching = want
            overlay.ignoresMouseEvents = !want
        }
    }

    // MARK: - Drops

    func canAccept(_ info: NSDraggingInfo) -> Bool {
        !desktopFileURLs(info).isEmpty
    }

    func handleDrop(_ info: NSDraggingInfo, at viewPoint: CGPoint, direct: Bool) -> Bool {
        let urls = desktopFileURLs(info).filter { !inFlight.contains($0) }
        guard !urls.isEmpty else { return false }

        let point = direct ? scene.geometry.mouth : viewPoint
        if direct || scene.geometry.dunkRect.contains(point) {
            inFlight.formUnion(urls)
            scene.dunk(urls)
            return true
        }

        var v = tracker.releaseVelocity() * throwPower
        if v.length < 200 {
            return false // not a throw; let Finder put it back
        }
        if v.length > 4200 { v = v * (4200 / v.length) }
        inFlight.formUnion(urls)
        scene.throwItems(urls, from: point, velocity: v)
        // Forget in-flight files after they've had time to land.
        DispatchQueue.main.asyncAfter(deadline: .now() + 7) { [weak self] in
            self?.inFlight.subtract(urls)
        }
        return true
    }

    private func trashFile(_ url: URL) -> Bool {
        defer { inFlight.remove(url) }
        switch trash.trash(url) {
        case .success:
            refreshUndoItem()
            return true
        case .failure(let error):
            NSLog("TrashToss: couldn't trash \(url.path): \(error)")
            return false
        }
    }

    // MARK: - Bin window

    func binMoved() {
        syncSceneGeometry()
        overlayView.invalidate()
    }

    func binMoveEnded() {
        let origin = binWindow.frame.origin
        defaults.set(NSStringFromPoint(origin), forKey: "binOrigin")
        let screen = screenForBin(origin)
        if screen.frame != overlay.frame {
            overlay.setFrame(screen.frame, display: false)
        }
        syncSceneGeometry()
        overlayView.invalidate(full: true)
        scene.bin.kick(squash: 2)
        Sounds.play("Bottle", volume: 0.3)
    }

    func binPoked() {
        scene.bin.kick(wobble: CGFloat.random(in: -5...5), squash: 3, lid: 3)
        scene.bin.show(.happy, for: 0.8)
        let quips = ["Hehe, that tickles!", "Feed me files!", "Drag me anywhere.", "Got any old screenshots?",
                     "I accept .zip, .dmg, .png…", "Flick a file at me!", "Nom nom?",
                     "Best streak: ×\(min(game.bestStreak + 1, Game.maxMultiplier))"]
        scene.say(quips.randomElement()!, seconds: 2.2)
        Sounds.play("Pop", volume: 0.4)
    }

    func binMenu() -> NSMenu { buildMenu() }

    private func syncSceneGeometry() {
        let screen = screenForBin(binWindow.frame.origin)
        let base = overlay.frame.origin
        overlayView.frame = NSRect(origin: .zero, size: overlay.frame.size)
        scene.bounds = overlayView.bounds
        scene.binOrigin = binWindow.frame.origin - base
        scene.floorY = screen.visibleFrame.minY - screen.frame.minY
    }

    private func defaultBinOrigin() -> CGPoint {
        let f = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        return CGPoint(x: f.midX - BinGeometry.windowSize.width / 2, y: f.midY - BinGeometry.windowSize.height / 2)
    }

    private func savedBinOrigin() -> CGPoint? {
        guard let s = defaults.string(forKey: "binOrigin") else { return nil }
        let p = NSPointFromString(s)
        let center = p + CGPoint(x: BinGeometry.windowSize.width / 2, y: BinGeometry.windowSize.height / 2)
        return NSScreen.screens.contains { $0.frame.contains(center) } ? p : nil
    }

    private func screenForBin(_ origin: CGPoint) -> NSScreen {
        let center = origin + CGPoint(x: BinGeometry.windowSize.width / 2, y: BinGeometry.windowSize.height / 2)
        return NSScreen.screens.first { $0.frame.contains(center) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    @objc private func screensChanged() {
        if savedBinOrigin() == nil && !NSScreen.screens.contains(where: { $0.frame.intersects(binWindow.frame) }) {
            binWindow.setFrameOrigin(defaultBinOrigin())
        }
        overlay.setFrame(screenForBin(binWindow.frame.origin).frame, display: false)
        syncSceneGeometry()
        overlayView.invalidate(full: true)
    }

    // MARK: - Menu

    private var undoItem: NSMenuItem?

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = buildMenu()
        menu.delegate = self
        statusItem.menu = menu
        updateStatusTitle()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let fresh = buildMenu()
        menu.removeAllItems()
        for item in fresh.items {
            fresh.removeItem(item)
            menu.addItem(item)
        }
    }

    private func updateStatusTitle() {
        guard let button = statusItem?.button else { return }
        button.image = NSImage(systemSymbolName: "trash.fill", accessibilityDescription: "TrashToss")
        button.imagePosition = .imageLeading
        let fmt = NumberFormatter()
        fmt.numberStyle = .decimal
        var title = " " + (fmt.string(from: NSNumber(value: game.score)) ?? "0")
        if game.multiplier > 1 { title += " ×\(game.multiplier)" }
        button.title = title
    }

    private func refreshUndoItem() {
        if let last = trash.lastEntry {
            undoItem?.title = "Undo Toss “\(last.original.lastPathComponent)”"
            undoItem?.isEnabled = true
        }
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let fmt = NumberFormatter()
        fmt.numberStyle = .decimal
        let stats = [
            "Score: \(fmt.string(from: NSNumber(value: game.score)) ?? "0")",
            "Combo: ×\(game.multiplier)   Best streak: \(game.bestStreak)",
            "Files tossed: \(game.totalTrashed)",
        ]
        for s in stats {
            let item = NSMenuItem(title: s, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        menu.addItem(.separator())

        let undo = NSMenuItem(title: "Undo Last Toss", action: #selector(undoLast), keyEquivalent: "z")
        undo.target = self
        undo.isEnabled = trash.lastEntry != nil
        if let last = trash.lastEntry { undo.title = "Undo Toss “\(last.original.lastPathComponent)”" }
        undoItem = undo
        menu.addItem(undo)

        let practice = NSMenuItem(title: "Practice Shot (Paper Ball)", action: #selector(practice), keyEquivalent: "p")
        practice.target = self
        menu.addItem(practice)
        menu.addItem(.separator())

        let catchAll = NSMenuItem(title: "Catch Slow Drags Too", action: #selector(toggleAlwaysCatch), keyEquivalent: "")
        catchAll.target = self
        catchAll.state = alwaysCatch ? .on : .off
        catchAll.toolTip = "Off: only fast flings are caught; slow drags rearrange icons as usual."
        menu.addItem(catchAll)

        let powerMenu = NSMenu()
        for (name, value) in [("Gentle", 0.5), ("Normal", 0.7), ("Strong", 0.9), ("Cannon", 1.15)] {
            let item = NSMenuItem(title: name, action: #selector(setPower(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = value
            item.state = abs(Double(throwPower) - value) < 0.01 ? .on : .off
            powerMenu.addItem(item)
        }
        let power = NSMenuItem(title: "Throw Power", action: nil, keyEquivalent: "")
        power.submenu = powerMenu
        menu.addItem(power)

        let sound = NSMenuItem(title: "Sound Effects", action: #selector(toggleSound), keyEquivalent: "")
        sound.target = self
        sound.state = Sounds.enabled ? .on : .off
        menu.addItem(sound)

        let resetPosition = NSMenuItem(title: "Reset Position", action: #selector(resetPosition), keyEquivalent: "r")
        resetPosition.target = self
        resetPosition.toolTip = "Move the bin back to the center of the screen."
        menu.addItem(resetPosition)

        let reset = NSMenuItem(title: "Reset Score…", action: #selector(resetScore), keyEquivalent: "")
        reset.target = self
        menu.addItem(reset)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit TrashToss", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        return menu
    }

    @objc private func undoLast() {
        guard let result = trash.undoLast() else { return }
        switch result {
        case .success(let url):
            game.undoTrash()
            scene.say("Fine, “\(url.lastPathComponent)” is back.", seconds: 2.5)
            scene.bin.show(.sad, for: 1.2)
        case .failure(let error):
            scene.say("Couldn't put it back: \(error.localizedDescription)", seconds: 3)
        }
    }

    @objc private func practice() { scene.practiceShot() }

    @objc private func toggleAlwaysCatch() { alwaysCatch.toggle() }

    @objc private func setPower(_ sender: NSMenuItem) {
        if let v = sender.representedObject as? Double { defaults.set(v, forKey: "throwPower") }
    }

    @objc private func toggleSound() { Sounds.enabled.toggle() }

    @objc private func resetPosition() {
        binWindow.setFrameOrigin(defaultBinOrigin())
        binMoveEnded()
        scene.say("Back in the middle!", seconds: 1.8)
    }

    @objc private func resetScore() {
        let alert = NSAlert()
        alert.messageText = "Reset your TrashToss score?"
        alert.informativeText = "Score, best streak and toss count go back to zero."
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { game.reset() }
    }
}
