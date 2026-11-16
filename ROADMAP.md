# Roadmap

Spool ships in four phases. Each phase is usable on its own.

## Phase 1: daily driver

- [x] Scrolling strip: new windows open right of the focused one, widths kept
- [x] Strip follows focus with a spring animation
- [x] Mouse thumb wheel scrolls the strip with no modifier (MX Master and others)
- [x] Modifier or per-app list passes the thumb wheel through to the app
- [x] Three or four finger trackpad swipe moves the strip
- [x] Focus left/right/up/down, first/last, jump to window 1-9
- [x] Move window left/right, first/last
- [x] Cycle preset widths, wider/narrower, full width, centre column
- [x] Gaps between windows and at screen edges, Dock aware
- [x] One strip per display, send window to next display, exclude a display
- [x] Dialogs, sheets and fixed-size windows float
- [x] Per-app float rules
- [x] Native fullscreen windows left alone
- [x] No focus stealing from background windows
- [x] Recover after sleep, lock and display changes
- [x] Launch at login
- [x] Menu bar item and settings window
- [x] Stop and start the window manager (⌃⌥Q)
- [x] Window bar on the main display with every display's windows: click to focus, drag to reorder or move between displays, hover for title
- [x] Drag a window to another display to move it to that strip
- [x] macOS permission and password prompts get their own column
- [x] One strip across all side-by-side displays
- [x] Window bar hides on full-screen Spaces
- [x] Display staircase: while Spool runs, move side-by-side displays corner to corner so a part-visible window cannot spill onto the next screen. Pointer still crosses at the real edge. Put back when Spool stops or the Displays pane is open

## Phase 2: columns

- [x] Stacks: several windows in one column, stack and pop out
- [x] Consume or expel: join the stack on one side, or leave it as a new column
- [x] Swap a window with the same row of the next column
- [x] Move a window up or down inside its stack
- [x] Taller/shorter, equalise heights, preset stack heights, resize a stacked window with the mouse
- [ ] Tabbed columns with a tab bar
- [ ] Native macOS window tabs take one column
- [ ] Pin a window to the left or right edge
- [x] Drag a window by its title bar to reorder: drop between columns to move it, on a column to stack it
- [ ] While dragging, a band shows where it lands and holding near the screen edge scrolls the strip
- [x] Keep original height per column
- [ ] Set width to a percentage or point value, grow into free space
- [ ] Per-display default and preset widths
- [x] Toggle a window between tiled and floating (⌃⌥T)
- [x] Focus floating windows

## Phase 3: polish

- [ ] Session restore per macOS Space
- [x] Session restore: order, widths and stacks per display
- [x] Focus border and inactive window dimming
- [ ] Focus follows mouse with a delay and a scroll limit, mouse follows focus
- [ ] Per-app rules: fixed slot
- [ ] Rules match title or title regex, and set display, start width, open without focus, keep own size, force tiled
- [ ] Centre modes: never, on overflow, always, centre the visible group
- [x] Go back to the previous window
- [ ] Recent windows switcher across every display, with app icons and titles
- [x] Shortcut cheatsheet when ⌃⌥ is held
- [ ] Shortcut recorder with AZERTY, QWERTZ and Dvorak, several bindings per action
- [ ] Mod key setting, Hyper key support
- [ ] Per-edge outer gaps, reserved top and bottom for SketchyBar
- [ ] Animate width changes, reorders, opening and closing by moving the real windows
- [ ] Spring stiffness and damping settings
- [ ] Mac Setup check that warns about Rectangle, Magnet and similar

## Phase 4: extras

- [ ] Virtual workspaces per display, stacked vertically, with an empty one always ready
- [ ] Overview: zoom out to see every workspace, drag cards to rearrange
- [ ] `spool://` URL scheme
- [ ] `spool` command-line tool
- [ ] Event stream (`spool subscribe --json`) and a SketchyBar example
- [ ] Shortcuts that run a shell command
- [ ] Optional TOML config file with live reload
- [ ] Raycast script commands
- [ ] Sparkle auto-updates
- [ ] Engine self-restart with logs
- [ ] First-run guided tour
