# Roadmap

Spool ships in four phases. Each phase is usable on its own.

## Phase 1: daily driver

- [ ] Scrolling strip: new windows open right of the focused one, widths kept
- [ ] Strip follows focus with a spring animation
- [ ] Mouse thumb wheel scrolls the strip with no modifier (MX Master and others)
- [ ] Modifier or per-app list passes the thumb wheel through to the app
- [ ] Three or four finger trackpad swipe moves the strip
- [ ] Focus left/right/up/down, first/last, jump to window 1-9
- [ ] Move window left/right, first/last
- [ ] Cycle preset widths, wider/narrower, full width, centre column
- [ ] Gaps between windows and at screen edges, Dock aware
- [ ] One strip per display, send window to next display, exclude a display
- [ ] Dialogs, sheets and fixed-size windows float
- [ ] Per-app float rules
- [ ] Native fullscreen windows left alone
- [ ] No focus stealing from background windows
- [ ] Recover after sleep, lock and display changes
- [ ] Launch at login
- [ ] Menu bar item and settings window
- [ ] Stop and start the window manager (⌃⌥Q)
- [ ] Window bar on the main display with every display's windows: click to focus, drag to reorder or move between displays, hover for title
- [ ] Drag a window to another display to move it to that strip
- [ ] macOS permission and password prompts get their own column
- [ ] One strip across all side-by-side displays

## Phase 2: columns

- [ ] Stacks: several windows in one column, stack and pop out
- [ ] Taller/shorter, equalise heights
- [ ] Tabbed columns with a tab bar
- [ ] Native macOS window tabs take one column
- [ ] Pin a window to the left or right edge
- [ ] Drag a window onto another column to reorder
- [ ] Keep original height mode

## Phase 3: polish

- [ ] Session restore: order, widths and stacks per display and Space
- [ ] Focus border and inactive window dimming
- [ ] Focus follows mouse, mouse follows focus
- [ ] Per-app rules: fixed slot
- [ ] Centre modes: never, on overflow, always
- [ ] Shortcut recorder with AZERTY, QWERTZ and Dvorak, several bindings per action
- [ ] Mac Setup check that warns about Rectangle, Magnet and similar

## Phase 4: extras

- [ ] `spool://` URL scheme
- [ ] `spool` command-line tool
- [ ] Raycast script commands
- [ ] Sparkle auto-updates
- [ ] Engine self-restart with logs
- [ ] First-run guided tour
