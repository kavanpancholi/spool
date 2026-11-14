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

## Build and run

```sh
make test   # unit tests
make run    # builds build/Spool.app and opens it
make install  # copies it to ~/Applications
```

Spool lives in the menu bar. On first launch it asks for Accessibility
permission and starts as soon as you grant it.

## Mouse and trackpad

- **Thumb wheel**: scrolls the strip under the pointer, then snaps to the
  nearest window and focuses the leftmost one. Hold ⌥ to scroll the app instead. Spreadsheets and design
  tools can be added to a list where the thumb wheel always scrolls the app.
- **Trackpad**: a three-finger (or four-finger) horizontal swipe moves the
  strip with your fingers. Turn off "Swipe between full-screen apps" for the
  same finger count in System Settings → Trackpad → More Gestures.
- **Logi Options+**: leave the thumb wheel set to "Horizontal scroll" (the
  default). If you remapped it to a gesture or app action, Spool never sees it.

## Keyboard shortcuts

All use ⌃⌥ (Control-Option).

| Action | Keys |
| --- | --- |
| Focus left, down, up, right | ⌃⌥ H J K L or arrows |
| Focus first or last window | ⌃⌥⌘ ← → |
| Focus window 1 to 9 | ⌃⌥ 1 … 9 |
| Move window | ⌃⌥⇧ H L or ← → |
| Move window to start or end | ⌃⌥⇧⌘ ← → |
| Cycle preset widths | ⌃⌥R |
| Full width | ⌃⌥F |
| Centre column | ⌃⌥C |
| Wider or narrower | ⌃⌥ = - |
| Send to next display | ⌃⌥N |
| Float or tile window | ⌃⌥T |
| Pause or start Spool | ⌃⌥Q |

## How it works

- Off-screen windows are parked in a bottom corner, away from other
  displays. Spool never minimises or hides them.
- A window slides past an edge shared with another display until most of it
  would be on that display. Then it parks, because macOS would otherwise move
  it onto that display and resize it.
- After a scroll the strip glides to the nearest window edge and focuses the
  leftmost window that is fully on screen.
- Each display, and each macOS Space, has its own strip. Drag a window onto
  another display, or press ⌃⌥N, to move it to that display's strip.
- macOS permission and password prompts are brought to the front so tiled
  windows never hide them.
- A bar at the bottom of the main display shows its windows in strip
  order. Click a tile to jump to the window, drag tiles to reorder, hover for
  the title. Turn it off in Settings → General.
- Dialogs, sheets, fixed-size windows and apps on your float list float.
  Native full-screen windows are left alone.
- When Spool quits it moves parked windows back on screen.

## Credits

Spool takes ideas from [Defi](https://github.com/qeude/Defi),
[Paneru](https://github.com/karinushka/paneru), niri and PaperWM.

## Licence

MIT
