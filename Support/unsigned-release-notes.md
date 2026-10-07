Fling desktop files into a bin that lives on your wallpaper. Make the shot and the file goes to the Trash. Miss and it stays put.

## Install

1. Download **TrashToss-*.dmg** below, open it, and drag **TrashToss** into **Applications**.
2. Open TrashToss from Applications. This preview isn't notarized by Apple yet, so macOS will block it the first time.
3. Go to **System Settings → Privacy & Security**, scroll down, and click **Open Anyway** next to the TrashToss message. Confirm with **Open**.
4. The bin appears in the middle of your desktop, and a 🗑 appears in the menu bar. The first file you toss asks for Desktop folder access.

Prefer Terminal? This does the same as step 3:

```
xattr -dr com.apple.quarantine /Applications/TrashToss.app
```

## How to play

- Grab a file on the desktop, flick it toward the bin, and let go while you're still moving.
- Drop a file straight on the bin for a dunk.
- Drag the bin to move it. Right-click it, or use the 🗑 menu, for undo, practice shots, throw power and more.
- Misses never delete anything, and **Undo Last Toss** brings a file back from the Trash.

Requires macOS 13 or later. Runs on Apple Silicon and Intel.
