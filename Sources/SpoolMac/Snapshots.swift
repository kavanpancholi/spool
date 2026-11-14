import AppKit
import OSLog
import ScreenCaptureKit
import SpoolCore

struct Snapshot {
  let image: CGImage
  let scale: CGFloat
}

final class Snapshots {
  private(set) var windows: [WindowID: Snapshot] = [:]
  private(set) var wallpapers: [String: Snapshot] = [:]
  private var capturing = false
  private var requestedPermission = false
  private var gaveUp = false
  private let log = Logger(subsystem: "io.github.kavanpancholi.spool", category: "snapshots")

  var isAvailable: Bool {
    guard #available(macOS 14, *), !gaveUp else { return false }
    return CGPreflightScreenCaptureAccess()
  }

  func requestPermissionOnce() {
    guard !requestedPermission, !CGPreflightScreenCaptureAccess() else { return }
    requestedPermission = true
    CGRequestScreenCaptureAccess()
  }

  func forget(_ id: WindowID) {
    windows[id] = nil
  }

  func clear() {
    windows.removeAll()
    wallpapers.removeAll()
    gaveUp = false
  }

  func refresh(_ targets: [(id: WindowID, cgID: CGWindowID)], displays: [Display]) {
    guard #available(macOS 14, *), isAvailable, !capturing else { return }
    capturing = true
    Task { @MainActor [weak self] in
      let (windows, wallpapers) = await Self.capture(targets, displays: displays)
      guard let self else { return }
      if windows.isEmpty && wallpapers.isEmpty && !targets.isEmpty {
        self.gaveUp = true
        self.log.error("Snapshots failed; smooth slides are off until Spool restarts")
      }
      self.windows.merge(windows) { _, new in new }
      self.wallpapers.merge(wallpapers) { _, new in new }
      self.capturing = false
    }
  }

  @available(macOS 14, *)
  private static func capture(
    _ targets: [(id: WindowID, cgID: CGWindowID)],
    displays: [Display]
  ) async -> ([WindowID: Snapshot], [String: Snapshot]) {
    guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false) else {
      return ([:], [:])
    }
    let byID = Dictionary(content.windows.map { ($0.windowID, $0) }, uniquingKeysWith: { first, _ in first })

    var windows: [WindowID: Snapshot] = [:]
    for target in targets {
      guard let window = byID[target.cgID], window.frame.width > 0, window.frame.height > 0 else { continue }
      let center = CGPoint(x: window.frame.midX, y: window.frame.midY)
      let scale = displays.first { $0.frame.contains(center) }?.scale ?? displays.map(\.scale).max() ?? 2
      let configuration = SCStreamConfiguration()
      configuration.width = Int(window.frame.width * scale)
      configuration.height = Int(window.frame.height * scale)
      configuration.showsCursor = false
      configuration.ignoreShadowsSingleWindow = true
      let filter = SCContentFilter(desktopIndependentWindow: window)
      if let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) {
        windows[target.id] = Snapshot(image: image, scale: scale)
      }
    }

    var wallpapers: [String: Snapshot] = [:]
    let ownPID = ProcessInfo.processInfo.processIdentifier
    let appWindows = content.windows.filter { $0.windowLayer == 0 || $0.owningApplication?.processID == ownPID }
    for display in displays {
      guard let screen = content.displays.first(where: { $0.displayID == display.id }) else { continue }
      let visible = display.visibleFrame
      let configuration = SCStreamConfiguration()
      configuration.sourceRect = CGRect(
        x: visible.minX - display.frame.minX,
        y: visible.minY - display.frame.minY,
        width: visible.width,
        height: visible.height
      )
      configuration.width = Int(visible.width * display.scale)
      configuration.height = Int(visible.height * display.scale)
      configuration.showsCursor = false
      let filter = SCContentFilter(display: screen, excludingWindows: appWindows)
      if let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) {
        wallpapers[display.uuid] = Snapshot(image: image, scale: display.scale)
      }
    }
    return (windows, wallpapers)
  }
}
