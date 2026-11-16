import AppKit
import SpoolCore
import SwiftUI

final class ModifierHold {
  var onHold: (() -> Void)?
  var onRelease: (() -> Void)?

  private var tap: CFMachPort?
  private var source: CFRunLoopSource?
  private var timer: Timer?
  private var shown = false
  private let wanted: CGEventFlags = [.maskControl, .maskAlternate]
  private let tracked: CGEventFlags = [.maskControl, .maskAlternate, .maskShift, .maskCommand]

  func start() {
    guard tap == nil else { return }
    let types: [CGEventType] = [.flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown, .scrollWheel]
    let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
    let callback: CGEventTapCallBack = { _, type, event, refcon in
      if let refcon {
        let hold = Unmanaged<ModifierHold>.fromOpaque(refcon).takeUnretainedValue()
        hold.handle(type, event.flags)
      }
      return Unmanaged.passUnretained(event)
    }
    guard let tap = CGEvent.tapCreate(
      tap: .cgSessionEventTap,
      place: .tailAppendEventTap,
      options: .listenOnly,
      eventsOfInterest: mask,
      callback: callback,
      userInfo: Unmanaged.passUnretained(self).toOpaque()
    ) else { return }
    self.tap = tap
    source = CFMachPortCreateRunLoopSource(nil, tap, 0)
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
  }

  func stop() {
    cancel()
    if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
    if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
    tap = nil
    source = nil
  }

  func cancel() {
    timer?.invalidate()
    timer = nil
    if shown {
      shown = false
      onRelease?()
    }
  }

  private func handle(_ type: CGEventType, _ flags: CGEventFlags) {
    switch type {
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
      if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
    case .flagsChanged:
      cancel()
      guard flags.intersection(tracked) == wanted else { return }
      timer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { [weak self] _ in
        guard let self else { return }
        self.timer = nil
        self.shown = true
        self.onHold?()
      }
    default:
      cancel()
    }
  }
}

final class CheatsheetPanel {
  private lazy var panel: NSPanel = {
    let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
    panel.level = .popUpMenu
    panel.backgroundColor = .clear
    panel.isOpaque = false
    panel.hasShadow = true
    panel.ignoresMouseEvents = true
    panel.hidesOnDeactivate = false
    panel.isReleasedWhenClosed = false
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
    return panel
  }()

  func show(_ entries: [CheatsheetEntry], on screen: NSScreen?) {
    let host = NSHostingView(rootView: CheatsheetView(entries: entries))
    let size = host.fittingSize
    panel.contentView = host
    let visible = (screen ?? NSScreen.main)?.visibleFrame ?? .zero
    panel.setFrame(NSRect(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2, width: size.width, height: size.height), display: true)
    panel.alphaValue = 0
    panel.orderFrontRegardless()
    NSAnimationContext.runAnimationGroup { $0.duration = 0.12; panel.animator().alphaValue = 1 }
  }

  func hide() {
    guard panel.isVisible else { return }
    panel.orderOut(nil)
  }
}

private struct CheatsheetView: View {
  let entries: [CheatsheetEntry]

  var body: some View {
    let half = (entries.count + 1) / 2
    VStack(alignment: .leading, spacing: 12) {
      Text("Spool shortcuts").font(.headline)
      HStack(alignment: .top, spacing: 28) {
        column(Array(entries.prefix(half)))
        column(Array(entries.dropFirst(half)))
      }
    }
    .padding(20)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    .fixedSize()
  }

  private func column(_ items: [CheatsheetEntry]) -> some View {
    Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 5) {
      ForEach(items, id: \.title) { entry in
        GridRow {
          Text(entry.keys.joined(separator: "  "))
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .monospacedDigit()
          Text(entry.title).font(.system(size: 12))
        }
      }
    }
  }
}
