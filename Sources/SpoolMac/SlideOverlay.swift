import AppKit
import QuartzCore
import SpoolCore

final class SlideOverlay {
  private struct Surface {
    let window: NSWindow
    let root: CALayer
    var tiles: [WindowID: CALayer]
  }

  private var surfaces: [String: Surface] = [:]

  func isShowing(_ display: Display) -> Bool {
    surfaces[display.uuid]?.window.isVisible == true
  }

  func show(on display: Display, wallpaper: CGImage) {
    let surface = surfaces[display.uuid] ?? Self.makeSurface()
    surface.window.setFrame(display.cocoaVisibleFrame, display: false)
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    surface.root.frame = CGRect(origin: .zero, size: display.visibleFrame.size)
    surface.root.contents = wallpaper
    CATransaction.commit()
    surface.window.orderFrontRegardless()
    surfaces[display.uuid] = surface
  }

  func update(on display: Display, frames: [(id: WindowID, frame: CGRect, image: CGImage?)]) {
    guard var surface = surfaces[display.uuid] else { return }
    let origin = display.visibleFrame.origin
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    let wanted = Set(frames.map(\.id))
    for (id, layer) in surface.tiles where !wanted.contains(id) {
      layer.removeFromSuperlayer()
      surface.tiles[id] = nil
    }
    for entry in frames {
      let layer = surface.tiles[entry.id] ?? Self.makeTile(in: surface.root)
      layer.frame = entry.frame.offsetBy(dx: -origin.x, dy: -origin.y)
      if let image = entry.image {
        layer.contents = image
        layer.backgroundColor = nil
      } else {
        layer.contents = nil
        layer.backgroundColor = NSColor(white: 0.16, alpha: 1).cgColor
      }
      surface.tiles[entry.id] = layer
    }
    CATransaction.commit()
    surfaces[display.uuid] = surface
  }

  func hide(_ displayID: String) {
    surfaces[displayID]?.window.orderOut(nil)
  }

  func hideAll() {
    surfaces.values.forEach { $0.window.orderOut(nil) }
    surfaces.removeAll()
  }

  private static func makeSurface() -> Surface {
    let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
    window.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue - 1)
    window.isOpaque = true
    window.hasShadow = false
    window.ignoresMouseEvents = true
    window.isReleasedWhenClosed = false
    window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
    let view = NSView()
    view.wantsLayer = true
    let root = CALayer()
    root.isGeometryFlipped = true
    root.contentsGravity = .resize
    view.layer = root
    window.contentView = view
    return Surface(window: window, root: root, tiles: [:])
  }

  private static func makeTile(in root: CALayer) -> CALayer {
    let layer = CALayer()
    layer.contentsGravity = .resize
    layer.cornerRadius = 10
    layer.masksToBounds = false
    root.addSublayer(layer)
    return layer
  }
}
