import AppKit
import ApplicationServices
import SpoolCore
import SpoolMac
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
  private let store = SettingsStore()
  private var manager: WindowManager!
  private var statusItem: NSStatusItem!
  private var settingsWindow: NSWindow?
  private var onboardingWindow: NSWindow?
  private var permissionTimer: Timer?

  func applicationDidFinishLaunching(_ notification: Notification) {
    if isAnotherInstanceRunning() {
      NSApp.terminate(nil)
      return
    }
    manager = WindowManager(store: store)
    manager.onStateChange = { [weak self] in self?.rebuildMenu() }
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    statusItem.button?.image = NSImage(systemSymbolName: "rectangle.split.3x1", accessibilityDescription: "Spool")
    rebuildMenu()

    if AXIsProcessTrusted() {
      if store.settings.enabled { manager.start() }
    } else {
      showOnboarding()
    }
  }

  func applicationWillTerminate(_ notification: Notification) {
    manager?.stop()
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    showSettings()
    return false
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

    if AXIsProcessTrusted() {
      let toggle = NSMenuItem(title: running ? "Pause Spool" : "Start Spool", action: #selector(toggleEnabled), keyEquivalent: "q")
      toggle.keyEquivalentModifierMask = [.control, .option]
      toggle.target = self
      menu.addItem(toggle)
      let rearrange = NSMenuItem(title: "Re-arrange Windows", action: #selector(rearrange), keyEquivalent: "")
      rearrange.target = self
      rearrange.isEnabled = running
      menu.addItem(rearrange)
    } else {
      let permission = NSMenuItem(title: "Grant Accessibility Permission…", action: #selector(showOnboardingAction), keyEquivalent: "")
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
    statusItem.menu = menu
    statusItem.button?.appearsDisabled = !running
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

  @objc private func showOnboardingAction() {
    showOnboarding()
  }

  private func showOnboarding() {
    if onboardingWindow == nil {
      let view = OnboardingView {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
          NSWorkspace.shared.open(url)
        }
      }
      let window = NSWindow(contentViewController: NSHostingController(rootView: view))
      window.title = "Welcome to Spool"
      window.styleMask = [.titled, .closable]
      window.isReleasedWhenClosed = false
      window.center()
      onboardingWindow = window
    }
    NSApp.activate(ignoringOtherApps: true)
    onboardingWindow?.makeKeyAndOrderFront(nil)

    permissionTimer?.invalidate()
    permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
      guard AXIsProcessTrusted(), let self else { return }
      timer.invalidate()
      self.onboardingWindow?.close()
      self.rebuildMenu()
      if self.store.settings.enabled { self.manager.start() }
    }
  }
}
