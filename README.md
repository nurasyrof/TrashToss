# TrashToss

A tiny macOS toy that turns "Move to Trash" into a game. A bin with a face sits on your wallpaper. Fling a desktop file at it and the file flies in an arc. Land it in the bin and the file goes to the Trash and you score points.

## How to play

- **Throw**: grab a file on the desktop, flick it toward the bin, and let go while your hand is still moving.
- **Dunk**: drop a file straight onto the bin. It's always safe, but it doesn't build your combo.
- **Move the bin**: drag it anywhere. Click it to poke it. Right-click it for the menu.
- Slow drags still go to Finder as usual, so you can keep rearranging icons.

The bin sits just above the desktop icons and below every app window, so it only shows up when you're looking at the desktop.

## Scoring

| Shot | Points |
| --- | --- |
| In the bin | +100 |
| Swish (clean, touches nothing) | +100 |
| Bank shot (off the open lid) | +150 |
| Rim-in | +50 |
| Bounce pass (off the floor) | +200 |
| Long shot / From downtown | +100 / +250 |

Each make in a row raises the multiplier (×2, ×3 … up to ×10). At ×5 the bin catches fire. A miss resets the combo, and the missed file stays on your desktop.

## Menu bar

The 🗑 menu has: undo the last toss (puts the file back), practice shot with a paper ball, catch slow drags too, throw power, sound, reset position, and reset score.

## Build

Requires macOS 13+ and the Swift toolchain (Command Line Tools are enough).

```bash
./build.sh --run
```

This produces `build/TrashToss.app`, an ad-hoc signed agent app with no Dock icon. The first file you toss triggers macOS's Desktop folder access prompt.

## How it works

- A transparent overlay window sits at desktop-icon level. TrashToss polls the mouse, which needs no Accessibility permission. When a Finder drag that started on the desktop is moving fast, the overlay becomes a drop target and catches the release. The release velocity becomes the throw.
- Physics runs at 120 Hz with gravity and capsule collisions against the bin walls, rim and lid.
- Files go to the Trash with `FileManager.trashItem`. Nothing is ever deleted permanently.

To check the rendering without screen-recording access, run `TrashToss --snapshot <dir>`. It fires practice shots and writes PNG frames.
