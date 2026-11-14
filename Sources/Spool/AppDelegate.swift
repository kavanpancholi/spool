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
    permissions.needsScreenRecording = { [store] in
      if #available(macOS 14, *) { return store.settings.smoothSlides }
      return false
    }
    rebuildMenu()

    if permissions.allGranted {
      if store.settings.enabled { manager.start() }
    } else {
      showPermissions()
    }
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

    if permissions.allGranted {
      let toggle = NSMenuItem(title: running ? "Pause Spool" : "Start Spool", action: #selector(toggleEnabled), keyEquivalent: "q")
      toggle.keyEquivalentModifierMask = [.control, .option]
      toggle.target = self
      menu.addItem(toggle)
      let rearrange = NSMenuItem(title: "Re-arrange Windows", action: #selector(rearrange), keyEquivalent: "")
      rearrange.target = self
      rearrange.isEnabled = running
      menu.addItem(rearrange)
    } else {
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
    let below: CGFloat = button.isFlipped ? button.bounds.height + 5 : -5
    menu.popUp(positioning: nil, at: NSPoint(x: 0, y: below), in: button)
  }

  @objc private func toggleEnabled() {
    manager.perform(.toggleEnabled)
  }

  @objc private func rearrange() {
    manager.rearrange()
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
      guard self.permissions.allGranted else {
        if self.permissionsWindow?.isVisible == false { self.permissionsWindow?.orderFrontRegardless() }
        return
      }
      timer.invalidate()
      self.permissionsWindow?.close()
      self.rebuildMenu()
      if self.store.settings.enabled && !self.manager.isRunning { self.manager.start() }
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
