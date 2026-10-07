import Foundation

/// Moves files to the Trash and remembers enough to put them back.
final class TrashService {
    struct Entry {
        let original: URL
        let trashed: URL
    }

    private(set) var history: [Entry] = []

    static let desktopURL: URL =
        FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0].resolvingSymlinksInPath()

    /// Only plain items that live directly on the Desktop are fair game.
    static func isDesktopItem(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        let parent = url.deletingLastPathComponent().resolvingSymlinksInPath()
        return parent.path == desktopURL.path && FileManager.default.fileExists(atPath: url.path)
    }

    func trash(_ url: URL) -> Result<Void, Error> {
        do {
            var resulting: NSURL?
            try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
            if let r = resulting as URL? {
                history.append(Entry(original: url, trashed: r))
                if history.count > 50 { history.removeFirst() }
            }
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    var lastEntry: Entry? { history.last }

    /// Puts the most recently tossed file back where it came from.
    func undoLast() -> Result<URL, Error>? {
        guard let entry = history.popLast() else { return nil }
        do {
            try FileManager.default.moveItem(at: entry.trashed, to: entry.original)
            return .success(entry.original)
        } catch {
            return .failure(error)
        }
    }
}
