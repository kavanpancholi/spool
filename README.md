# Spool

A free, open-source scrolling window manager for macOS.

Windows sit side by side on one long horizontal strip, like
[niri](https://github.com/YaLTeR/niri) and [PaperWM](https://github.com/paperwm/PaperWM).
New windows open next to the focused one and keep their width. The strip
scrolls to follow focus.

Spool scrolls the strip with a mouse **thumb wheel**, such as the one on the
Logitech MX Master, with no modifier key held. The main wheel keeps scrolling
the app under the pointer.

> Status: early. Phase 1 of the [roadmap](ROADMAP.md) is being built and tested.

## Requirements

- macOS 13 Ventura or later, Apple silicon
- Accessibility permission (Spool moves windows and reads scroll and swipe input)
- Screen Recording permission, only if you turn on smooth slides across
  screens, which use window snapshots while the strip moves

## Build and run

```sh
make test   # unit tests
make run    # builds build/Spool.app and opens it
make install  # copies it to ~/Applications
```

Spool lives in the menu bar. It needs Accessibility, and starts on its own
as soon as you grant it. Smooth slides across screens are off by default;
turning them on in Settings also asks for Screen Recording.

## Mouse and trackpad

- **Thumb wheel**: scrolls the strip under the pointer. Once you stop, the
  strip eases to the nearest window edge, then focuses the leftmost fully
  visible window. The snap delay is in Settings. Hold ⌥ to scroll the app instead. Spreadsheets and design
  tools can be added to a list where the thumb wheel always scrolls the app.
- **Trackpad**: a three-finger (or four-finger) horizontal swipe moves the
  strip with your fingers. Turn off "Swipe between full-screen apps" for the
  same finger count in System Settings → Trackpad → More Gestures.
- **Logi Options+**: leave the thumb wheel set to "Horizontal scroll" (the
  default). If you remapped it to a gesture or app action, Spool never sees it.

## Keyboard shortcuts

All use ⌃⌥ (Control-Option). Hold ⌃⌥ for a moment to see them on screen.

| Action | Keys |
| --- | --- |
| Focus left, down, up, right | ⌃⌥ H J K L or arrows |
| Focus first or last window | ⌃⌥⌘ ← → |
| Focus window 1 to 9 | ⌃⌥ 1 … 9 |
| Back to the previous window | ⌃⌥⇥ |
| Move window | ⌃⌥⇧ H L or ← → |
| Move window to start or end | ⌃⌥⇧⌘ ← → |
| Stack into the left or right column, or take out of a stack | ⌃⌥ [ ] |
| Move window up or down in its stack | ⌃⌥⇧ K J or ↑ ↓ |
| Cycle preset widths | ⌃⌥R |
| Full width | ⌃⌥F |
| Centre column | ⌃⌥C |
| Wider or narrower | ⌃⌥ = - |
| Send to next display | ⌃⌥N |
| Float or tile window | ⌃⌥T |
| Pause or start Spool | ⌃⌥Q |

## How it works

- The focused window gets a border in your accent colour. Settings → Layout
  can turn it off, change its width, or dim the other windows.

- Off-screen windows are parked in a bottom corner, away from other
  displays. Spool never minimises or hides them.
- With Screen Recording allowed, the strip slides as one picture: Spool shows
  snapshots of the windows while it moves, clipped at each screen edge, then
  moves the real windows once it stops.
- Windows keep their size and slide off screen edges. While Spool runs, it
  tells macOS your side-by-side displays sit corner to corner, so a window
  sliding off one screen has no neighbour to jump onto. The pointer still
  crosses at the edges you set in System Settings, and opening System Settings
  shows your real layout. macOS puts it back when Spool stops, even after a
  crash. Turn it off with "Keep windows from spilling onto other displays".
- After a scroll the strip glides to the nearest window edge and focuses the
  leftmost window that is fully on screen.
- Each display, and each macOS Space, has its own strip. Or turn on "One
  strip across all displays" for a single strip over side-by-side screens.
  With "Displays have separate Spaces" off, real windows slide over the seam.
  With it on, smooth slides carry the motion and the strip never rests with a
  window across the seam. Drag a window onto
  another display, or press ⌃⌥N, to move it to that display's strip.
- macOS permission and password prompts get their own column next to the
  focused window, at their own size, so tiled windows never hide them.
- A bar at the bottom of the main display shows the windows of every
  display, grouped in display order with a divider. Click a tile to jump to
  the window, drag it to reorder, or drag it past the divider to move the
  window to another display. Hover for the title. Minimised windows stay in
  the bar, dimmed; click one to restore it. Turn it off in
  Settings → General.
- Dialogs, open and save panels, fixed-size windows, windows without close
  or minimise buttons, and apps on your float list float.
  Native full-screen windows are left alone.
- When Spool quits it moves parked windows back on screen.

## Credits

Spool takes ideas from [Defi](https://github.com/qeude/Defi),
[Paneru](https://github.com/karinushka/paneru), niri and PaperWM.

## Licence

MIT
