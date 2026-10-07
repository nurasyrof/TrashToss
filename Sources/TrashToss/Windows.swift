import AppKit

/// Level just above Finder's desktop icons but below every normal app window,
/// so the bin lives "on the wallpaper".
private let desktopIconLevel = Int(CGWindowLevelForKey(.desktopIconWindow))

private func makeDesktopPanel(frame: NSRect, levelOffset: Int) -> NSPanel {
    let w = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    w.isOpaque = false
    w.backgroundColor = .clear
    w.hasShadow = false
    w.level = NSWindow.Level(rawValue: desktopIconLevel + levelOffset)
    w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
    w.isReleasedWhenClosed = false
    w.hidesOnDeactivate = false
    return w
}

/// Transparent full-screen window that draws everything. Click-through except while
/// it is catching a fling.
func makeOverlayWindow(screen: NSScreen, view: OverlayView) -> NSPanel {
    let w = makeDesktopPanel(frame: screen.frame, levelOffset: 2)
    w.ignoresMouseEvents = true
    w.contentView = view
    return w
}

protocol BinWindowDelegate: DropHandler {
    func binMoved()
    func binMoveEnded()
    func binPoked()
    func binMenu() -> NSMenu
}

/// Invisible hit area over the bin: drag to move it, click to poke it, drop files on it to dunk.
func makeBinWindow(origin: CGPoint, delegate: BinWindowDelegate) -> NSPanel {
    let w = makeDesktopPanel(frame: NSRect(origin: origin, size: BinGeometry.windowSize), levelOffset: 1)
    w.ignoresMouseEvents = false
    let view = BinHitView(frame: NSRect(origin: .zero, size: BinGeometry.windowSize))
    view.delegate = delegate
    w.contentView = view
    return w
}

final class BinHitView: NSView {
    weak var delegate: BinWindowDelegate?
    private var startMouse: CGPoint = .zero
    private var startOrigin: CGPoint = .zero
    private var moved = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        // Nearly-invisible fill so the window server routes clicks here.
        NSColor(white: 0, alpha: 0.004).setFill()
        bounds.fill()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        startMouse = NSEvent.mouseLocation
        startOrigin = window?.frame.origin ?? .zero
        moved = false
    }

    override func mouseDragged(with event: NSEvent) {
        let d = NSEvent.mouseLocation - startMouse
        if d.length > 3 {
            if !moved { NSCursor.closedHand.push() }
            moved = true
        }
        guard moved else { return }
        window?.setFrameOrigin(startOrigin + d)
        delegate?.binMoved()
    }

    override func mouseUp(with event: NSEvent) {
        if moved {
            NSCursor.pop()
            delegate?.binMoveEnded()
        } else {
            delegate?.binPoked()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let menu = delegate?.binMenu() else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        delegate?.canAccept(sender) == true ? .generic : []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        delegate?.canAccept(sender) == true ? .generic : []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        delegate?.handleDrop(sender, at: .zero, direct: true) ?? false
    }
}
