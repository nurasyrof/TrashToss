import AVFoundation

/// Short sound effects from macOS's built-in sounds. Players are preloaded off the main
/// thread, since NSSound can stall the run loop for over a second, which freezes the animation.
enum Sounds {
    static var enabled: Bool {
        get { !UserDefaults.standard.bool(forKey: "muted") }
        set { UserDefaults.standard.set(!newValue, forKey: "muted") }
    }

    private static let files: [String: String] = {
        var f: [String: String] = [:]
        for n in ["Tink", "Pop", "Bottle", "Purr", "Funk", "Glass", "Hero", "Basso"] {
            f[n] = "/System/Library/Sounds/\(n).aiff"
        }
        f["trash"] = "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/finder/move to trash.aif"
        return f
    }()

    private static let poolSize = 3
    private static var pools: [String: [AVAudioPlayer]] = [:]
    private static var lastPlayed: [String: Double] = [:]

    static func preload() {
        DispatchQueue.global(qos: .utility).async {
            var loaded: [String: [AVAudioPlayer]] = [:]
            for (name, path) in files {
                let url = URL(fileURLWithPath: path)
                loaded[name] = (0..<poolSize).compactMap { _ in
                    let p = try? AVAudioPlayer(contentsOf: url)
                    p?.prepareToPlay()
                    return p
                }
            }
            DispatchQueue.main.async { pools = loaded }
        }
    }

    static func play(_ name: String, volume: Float = 1) {
        guard enabled, let pool = pools[name], !pool.isEmpty else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if let last = lastPlayed[name], now - last < 0.05 { return }
        lastPlayed[name] = now
        let player = pool.first { !$0.isPlaying } ?? pool[0]
        player.currentTime = 0
        player.volume = volume
        player.play()
    }
}
