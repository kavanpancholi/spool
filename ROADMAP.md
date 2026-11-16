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
- [ ] Display staircase: while Spool runs, move side-by-side displays corner to corner so a part-visible window cannot spill onto the next screen. Pointer still crosses at the real edge. Put back when Spool stops or System Settings is open

## Phase 2: columns

- [ ] Stacks: several windows in one column, stack and pop out
- [ ] Consume or expel: join the stack on one side, or leave it as a new column
- [ ] Swap a window with the same row of the next column
- [ ] Taller/shorter, equalise heights, preset stack heights
- [ ] Tabbed columns with a tab bar
- [ ] Native macOS window tabs take one column
- [ ] Pin a window to the left or right edge
- [ ] Drag a window by its title bar to reorder: a band shows where it lands, holding near the screen edge scrolls the strip
- [ ] Keep original height mode
- [ ] Set width to a percentage or point value, grow into free space
- [ ] Per-display default and preset widths
- [ ] Toggle a window between tiled and floating, focus floating windows

## Phase 3: polish

- [ ] Session restore: order, widths and stacks per display and Space
- [ ] Focus border and inactive window dimming
- [ ] Focus follows mouse with a delay and a scroll limit, mouse follows focus
- [ ] Per-app rules: fixed slot
- [ ] Rules match title or title regex, and set display, start width, open without focus, keep own size, force tiled
- [ ] Centre modes: never, on overflow, always, centre the visible group
- [ ] Go back to the previous window
- [ ] Recent windows switcher (⌃⌥Tab) across every display, with snapshots
- [ ] Shortcut cheatsheet when ⌃⌥ is held
- [ ] Shortcut recorder with AZERTY, QWERTZ and Dvorak, several bindings per action
- [ ] Mod key setting, Hyper key support
- [ ] Per-edge outer gaps, reserved top and bottom for SketchyBar
- [ ] Animate width changes, reorders, opening and closing on the snapshot overlay, not only slides
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
