import AppKit
import SpoolCore

struct DecoratedWindow {
  let id: WindowID
  let cgID: CGWindowID
  let frame: CGRect
  let cornerRadius: CGFloat
}

final class Decorations {
  private var border: NSPanel?
  private var borderTarget: CGWindowID?
  private var dims: [WindowID: (panel: NSPanel, target: CGWindowID)] = [:]

  func update(focused: DecoratedWindow?, others: [DecoratedWindow], settings: SpoolSettings, reorder: Bool) {
    if settings.focusBorder, let focused {
      let width = CGFloat(max(1, settings.borderWidth))
      let panel = border ?? makeBorder()
      border = panel
      (panel.contentView as? BorderView)?.apply(width: width, radius: focused.cornerRadius)
      place(panel, over: focused.frame.insetBy(dx: -width, dy: -width), cgID: focused.cgID, force: reorder || borderTarget != focused.cgID)
      borderTarget = focused.cgID
    } else {
      border?.orderOut(nil)
      borderTarget = nil
    }

    let wanted = settings.dimInactive ? others : []
    let ids = Set(wanted.map(\.id))
    for (id, entry) in dims where !ids.contains(id) {
      entry.panel.orderOut(nil)
      dims[id] = nil
    }
    for window in wanted {
      let existing = dims[window.id]
      let panel = existing?.panel ?? makeDim()
      panel.contentView?.layer?.backgroundColor = NSColor.black.withAlphaComponent(min(0.8, max(0, settings.dimAmount))).cgColor
      panel.contentView?.layer?.cornerRadius = window.cornerRadius
      place(panel, over: window.frame, cgID: window.cgID, force: reorder || existing?.target != window.cgID)
      dims[window.id] = (panel, window.cgID)
    }
  }

  func hideAll() {
    border?.orderOut(nil)
    borderTarget = nil
    dims.values.forEach { $0.panel.orderOut(nil) }
    dims.removeAll()
  }

  private func place(_ panel: NSPanel, over quartzFrame: CGRect, cgID: CGWindowID, force: Bool) {
    let frame = Self.cocoa(quartzFrame)
    if panel.frame != frame { panel.setFrame(frame, display: true) }
    if force || !panel.isVisible { panel.order(.above, relativeTo: Int(cgID)) }
  }

  private static func cocoa(_ rect: CGRect) -> NSRect {
    let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
    return NSRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
  }

  private func makeBorder() -> NSPanel {
    let panel = Self.makePanel()
    panel.contentView = BorderView()
    return panel
  }

  private func makeDim() -> NSPanel {
    let panel = Self.makePanel()
    let view = NSView()
    view.wantsLayer = true
    view.layer?.cornerCurve = .circular
    panel.contentView = view
    return panel
  }

  private static func makePanel() -> NSPanel {
    let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
    panel.level = .normal
    panel.backgroundColor = .clear
    panel.isOpaque = false
    panel.hasShadow = false
    panel.ignoresMouseEvents = true
    panel.hidesOnDeactivate = false
    panel.isReleasedWhenClosed = false
    panel.animationBehavior = .none
    panel.collectionBehavior = [.transient, .ignoresCycle, .fullScreenNone]
    return panel
  }
}

private final class BorderView: NSView {
  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
    layer?.borderColor = NSColor.controlAccentColor.cgColor
  }

  required init?(coder: NSCoder) { nil }

  func apply(width: CGFloat, radius: CGFloat) {
    layer?.borderWidth = width
    layer?.cornerRadius = radius + width
    layer?.cornerCurve = .circular
    layer?.borderColor = NSColor.controlAccentColor.cgColor
  }
}
