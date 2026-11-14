# Contributing

## Layout

- `Sources/SpoolCore`: pure Swift. Strip model, layout, commands, input
  classification, settings. No AppKit. Every behaviour here has a unit test.
- `Sources/SpoolMac`: Accessibility, event tap, hotkeys, displays and the
  `WindowManager` that wires them to the core.
- `Sources/Spool`: the menu bar app and settings window.

Keep logic in `SpoolCore` whenever it can be tested without moving real
windows.

## Signing for local builds

macOS ties the Accessibility permission to the app's code signature. An ad hoc
signed build gets a new signature on every rebuild, so macOS asks again.

Create a local certificate once:

1. Open Keychain Access.
2. Keychain Access → Certificate Assistant → Create a Certificate…
3. Name: `Spool Development`. Identity Type: Self Signed Root.
   Certificate Type: Code Signing. Create.

`make app` picks it up automatically. To use another identity, set
`SPOOL_SIGN_IDENTITY`.

## Testing on your own desktop

Spool moves every window on screen. Save your work first. ⌃⌥Q pauses it and
moves parked windows back on screen. Quitting from the menu bar does the same.

Logs: `log stream --predicate 'subsystem == "io.github.kavanpancholi.spool"'`.
