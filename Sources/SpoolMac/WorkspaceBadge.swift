import AppKit
import SwiftUI

final class WorkspaceBadge {
  private var hideWork: DispatchWorkItem?
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

  func show(index: Int, count: Int, on frame: CGRect) {
    let host = NSHostingView(rootView: WorkspaceBadgeView(index: index, count: count))
    let size = host.fittingSize
    panel.contentView = host
    let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
    let center = CGPoint(x: frame.midX, y: primaryHeight - frame.midY)
    panel.setFrame(NSRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height), display: true)
    panel.alphaValue = 1
    panel.orderFrontRegardless()
    hideWork?.cancel()
    let work = DispatchWorkItem { [weak self] in
      guard let panel = self?.panel else { return }
      NSAnimationContext.runAnimationGroup({ $0.duration = 0.2; panel.animator().alphaValue = 0 }) { panel.orderOut(nil) }
    }
    hideWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: work)
  }

  func hide() {
    hideWork?.cancel()
    panel.orderOut(nil)
  }
}

private struct WorkspaceBadgeView: View {
  let index: Int
  let count: Int

  var body: some View {
    VStack(spacing: 6) {
      ForEach(0..<count, id: \.self) { slot in
        Capsule()
          .fill(slot == index ? Color.primary : Color.secondary.opacity(0.35))
          .frame(width: 34, height: slot == index ? 10 : 6)
      }
    }
    .padding(14)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    .fixedSize()
  }
}
