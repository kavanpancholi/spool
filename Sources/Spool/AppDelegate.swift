import AppKit
import ApplicationServices
import SpoolCore
import SpoolMac
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
  private let store = SettingsStore()
  private var manager: WindowManager!
  private var statusItem: NSStatusItem!
  private var menu = NSMenu()
  private var settingsWindow: NSWindow?
  private var permissionsWindow: NSWindow?
  private var permissionTimer: Timer?
  private let permissions = PermissionsModel()
  private var signalSources: [DispatchSourceSignal] = []

  func applicationDidFinishLaunching(_ notification: Notification) {
    if isAnotherInstanceRunning() {
      NSApp.terminate(nil)
      return
    }
    manager = WindowManager(store: store)
    quitCleanlyOnSignals()
    manager.onStateChange = { [weak self] in self?.rebuildMenu() }
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    statusItem.autosaveName = "Spool"
    statusItem.button?.image = NSImage(systemSymbolName: "rectangle.split.3x1", accessibilityDescription: "Spool")
    statusItem.button?.target = self
    statusItem.button?.action = #selector(openMenu)
    statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    rebuildMenu()

    if permissions.accessibility && store.settings.enabled { manager.start() }
    if !permissions.allGranted { showPermissions() }
  }

  func applicationWillTerminate(_ notification: Notification) {
    manager?.stop()
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    showSettings()
    return false
  }

  private func quitCleanlyOnSignals() {
    for signalNumber in [SIGTERM, SIGINT, SIGHUP] {
      signal(signalNumber, SIG_IGN)
      let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
      source.setEventHandler { NSApp.terminate(nil) }
      source.resume()
      signalSources.append(source)
    }
  }

  private func isAnotherInstanceRunning() -> Bool {
    guard let id = Bundle.main.bundleIdentifier else { return false }
    return NSRunningApplication.runningApplications(withBundleIdentifier: id).contains {
      $0.processIdentifier != getpid()
    }
  }


  private func rebuildMenu() {
    let menu = NSMenu()
    let running = manager?.isRunning == true
    let state = NSMenuItem(title: running ? "Spool is running" : "Spool is paused", action: nil, keyEquivalent: "")
    state.isEnabled = false
    menu.addItem(state)

    if permissions.accessibility {
      let toggle = NSMenuItem(title: running ? "Pause Spool" : "Start Spool", action: #selector(toggleEnabled), keyEquivalent: "q")
      toggle.keyEquivalentModifierMask = [.control, .option]
      toggle.target = self
      menu.addItem(toggle)
      let rearrange = NSMenuItem(title: "Re-arrange Windows", action: #selector(rearrange), keyEquivalent: "")
      rearrange.target = self
      rearrange.isEnabled = running
      menu.addItem(rearrange)
      let width = NSMenuItem(title: "Set Width", action: nil, keyEquivalent: "")
      width.submenu = widthMenu()
      width.isEnabled = running
      menu.addItem(width)
    }
    if !permissions.allGranted {
      let permission = NSMenuItem(title: "Permissions…", action: #selector(showPermissionsAction), keyEquivalent: "")
      permission.target = self
      menu.addItem(permission)
    }

    menu.addItem(.separator())
    let settings = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
    settings.target = self
    menu.addItem(settings)
    menu.addItem(.separator())
    let quit = NSMenuItem(title: "Quit Spool", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
    menu.addItem(quit)
    self.menu = menu
    statusItem.button?.appearsDisabled = !running
  }

  @objc private func openMenu() {
    guard let button = statusItem.button else { return }
    rebuildMenu()
    let below: CGFloat = button.isFlipped ? button.bounds.height + 5 : -5
    menu.popUp(positioning: nil, at: NSPoint(x: 0, y: below), in: button)
  }

  @objc private func toggleEnabled() {
    manager.perform(.toggleEnabled)
  }

  @objc private func rearrange() {
    manager.rearrange()
  }

  private func widthMenu() -> NSMenu {
    let submenu = NSMenu()
    for preset in store.settings.widthPresets + [.fraction(1)] {
      let item = NSMenuItem(title: preset.label, action: #selector(setWidth(_:)), keyEquivalent: "")
      item.representedObject = preset.label
      item.target = self
      submenu.addItem(item)
    }
    submenu.addItem(.separator())
    let grow = NSMenuItem(title: Command.growIntoFreeSpace.title, action: #selector(growIntoFreeSpace), keyEquivalent: "g")
    grow.keyEquivalentModifierMask = [.control, .option]
    grow.target = self
    submenu.addItem(grow)
    let custom = NSMenuItem(title: "Custom…", action: #selector(customWidth), keyEquivalent: "")
    custom.target = self
    submenu.addItem(custom)
    return submenu
  }

  @objc private func setWidth(_ sender: NSMenuItem) {
    guard let label = sender.representedObject as? String, let preset = WidthPreset(parsing: label) else { return }
    manager.perform(.setWidth(preset))
  }

  @objc private func growIntoFreeSpace() {
    manager.perform(.growIntoFreeSpace)
  }

  @objc private func customWidth() {
    let alert = NSAlert()
    alert.messageText = "Width of the focused window"
    alert.informativeText = "A percentage of the screen, like 40%, or points, like 1200pt."
    let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
    field.placeholderString = "40% or 1200pt"
    alert.accessoryView = field
    alert.addButton(withTitle: "Set")
    alert.addButton(withTitle: "Cancel")
    alert.window.initialFirstResponder = field
    let front = NSWorkspace.shared.frontmostApplication
    NSApp.activate(ignoringOtherApps: true)
    let response = alert.runModal()
    front?.activate()
    guard response == .alertFirstButtonReturn, let preset = WidthPreset(parsing: field.stringValue) else { return }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
      self?.manager.perform(.setWidth(preset))
    }
  }


  @objc func showSettings() {
    if settingsWindow == nil {
      let view = SettingsView(store: store, failedShortcuts: manager.failedShortcuts)
      let window = NSWindow(contentViewController: NSHostingController(rootView: view))
      window.title = "Spool Settings"
      window.styleMask = [.titled, .closable, .miniaturizable]
      window.isReleasedWhenClosed = false
      window.center()
      settingsWindow = window
    }
    NSApp.activate(ignoringOtherApps: true)
    settingsWindow?.makeKeyAndOrderFront(nil)
  }

  @objc private func showPermissionsAction() {
    showPermissions()
  }

  private func showPermissions() {
    if permissionsWindow == nil {
      let view = PermissionsView(model: permissions) { [weak self] in self?.restart() }
      let window = NSWindow(contentViewController: NSHostingController(rootView: view))
      window.title = "Spool Permissions"
      window.styleMask = [.titled, .closable]
      window.isReleasedWhenClosed = false
      window.center()
      permissionsWindow = window
    }
    NSApp.activate(ignoringOtherApps: true)
    permissionsWindow?.makeKeyAndOrderFront(nil)

    permissionTimer?.invalidate()
    permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
      guard let self else { return }
      self.permissions.refresh()
      if self.permissions.accessibility && self.store.settings.enabled && !self.manager.isRunning {
        self.manager.start()
        self.rebuildMenu()
      }
      guard self.permissions.allGranted || self.permissionsWindow?.isVisible == false else { return }
      timer.invalidate()
      self.permissionsWindow?.close()
      self.rebuildMenu()
    }
  }

  private func restart() {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", Bundle.main.bundlePath]
    try? process.run()
    NSApp.terminate(nil)
  }
}
