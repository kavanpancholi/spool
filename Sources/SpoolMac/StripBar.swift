import AppKit
import SpoolCore
import SwiftUI

struct BarTile: Identifiable, Equatable {
  let id: WindowID
  let pid: pid_t
  let focused: Bool
}

enum BarMetrics {
  static let icon: CGFloat = 34
  static let spacing: CGFloat = 6
  static let padding: CGFloat = 8
  static let dot: CGFloat = 4
  static let dotGap: CGFloat = 4
  static let margin: CGFloat = 6
  static let cornerRadius: CGFloat = 16

  static var pillHeight: CGFloat { padding * 2 + icon + dotGap + dot }
  static var reserve: CGFloat { pillHeight + margin }
  static var pitch: CGFloat { icon + spacing }

  static func width(for count: Int) -> CGFloat {
    padding * 2 + CGFloat(count) * icon + CGFloat(max(0, count - 1)) * spacing
  }

  static func tileCenter(_ index: Int) -> CGFloat {
    padding + CGFloat(index) * pitch + icon / 2
  }
}

final class BarModel: ObservableObject {
  @Published var tiles: [BarTile] = []
  var onSelect: (WindowID) -> Void = { _ in }
  var onMove: (WindowID, Int) -> Void = { _, _ in }
  var onHover: (WindowID?, CGFloat) -> Void = { _, _ in }
}

struct BarView: View {
  @ObservedObject var model: BarModel
  @State private var dragging: WindowID?
  @State private var offset: CGFloat = 0

  var body: some View {
    HStack(spacing: BarMetrics.spacing) {
      ForEach(Array(model.tiles.enumerated()), id: \.element.id) { index, tile in
        TileView(tile: tile)
          .offset(x: dragging == tile.id ? offset : 0)
          .zIndex(dragging == tile.id ? 1 : 0)
          .onHover { inside in
            model.onHover(inside && dragging == nil ? tile.id : nil, BarMetrics.tileCenter(index))
          }
          .onTapGesture { model.onSelect(tile.id) }
          .gesture(
            DragGesture(minimumDistance: 5)
              .onChanged { value in
                dragging = tile.id
                offset = value.translation.width
                model.onHover(nil, 0)
              }
              .onEnded { value in
                let steps = Int((value.translation.width / BarMetrics.pitch).rounded())
                let target = min(model.tiles.count - 1, max(0, index + steps))
                dragging = nil
                offset = 0
                if target != index { model.onMove(tile.id, target) }
              }
          )
      }
    }
    .padding(BarMetrics.padding)
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: BarMetrics.cornerRadius, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: BarMetrics.cornerRadius, style: .continuous)
        .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
    )
    .animation(.easeOut(duration: 0.15), value: model.tiles)
  }
}

private struct TileView: View {
  let tile: BarTile

  var body: some View {
    VStack(spacing: BarMetrics.dotGap) {
      Image(nsImage: NSRunningApplication(processIdentifier: tile.pid)?.icon ?? NSImage())
        .resizable()
        .interpolation(.high)
        .frame(width: BarMetrics.icon, height: BarMetrics.icon)
        .background(
          RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(Color.white.opacity(tile.focused ? 0.22 : 0))
            .padding(-3)
        )
      Circle()
        .fill(tile.focused ? Color.white : Color.gray.opacity(0.7))
        .frame(width: BarMetrics.dot, height: BarMetrics.dot)
    }
    .contentShape(Rectangle())
  }
}

private struct TooltipView: View {
  let text: String

  var body: some View {
    Text(text)
      .font(.system(size: 12, weight: .medium))
      .lineLimit(1)
      .padding(.horizontal, 10)
      .padding(.vertical, 5)
      .background(.regularMaterial, in: Capsule())
      .fixedSize()
  }
}

final class BarController {
  var onSelect: (WindowID) -> Void = { _ in }
  var onMove: (WindowID, Int) -> Void = { _, _ in }
  var label: (WindowID) -> String = { _ in "" }

  private var bars: [String: (panel: NSPanel, model: BarModel)] = [:]
  private let tooltip = BarController.makePanel(ignoresMouse: true)

  func update(_ entries: [(display: Display, tiles: [BarTile])]) {
    let wanted = Set(entries.filter { !$0.tiles.isEmpty }.map(\.display.uuid))
    for (uuid, bar) in bars where !wanted.contains(uuid) {
      bar.panel.orderOut(nil)
      bars[uuid] = nil
    }
    for (display, tiles) in entries where !tiles.isEmpty {
      let bar = bars[display.uuid] ?? makeBar(for: display.uuid)
      if bar.model.tiles != tiles { bar.model.tiles = tiles }
      let width = BarMetrics.width(for: tiles.count)
      let visible = display.cocoaVisibleFrame
      let frame = NSRect(
        x: (visible.midX - width / 2).rounded(),
        y: visible.minY + BarMetrics.margin,
        width: width,
        height: BarMetrics.pillHeight
      )
      if bar.panel.frame != frame { bar.panel.setFrame(frame, display: true) }
      if !bar.panel.isVisible { bar.panel.orderFrontRegardless() }
    }
  }

  func hideAll() {
    bars.values.forEach { $0.panel.orderOut(nil) }
    bars.removeAll()
    tooltip.orderOut(nil)
  }

  private func makeBar(for uuid: String) -> (panel: NSPanel, model: BarModel) {
    let model = BarModel()
    let panel = Self.makePanel(ignoresMouse: false)
    panel.contentView = NSHostingView(rootView: BarView(model: model))
    model.onSelect = { [weak self] id in
      self?.tooltip.orderOut(nil)
      self?.onSelect(id)
    }
    model.onMove = { [weak self] id, index in self?.onMove(id, index) }
    model.onHover = { [weak self, weak panel] id, x in
      guard let self, let panel else { return }
      self.showTooltip(for: id, above: panel, atX: x)
    }
    bars[uuid] = (panel, model)
    return (panel, model)
  }

  private func showTooltip(for id: WindowID?, above panel: NSPanel, atX x: CGFloat) {
    guard let id else {
      tooltip.orderOut(nil)
      return
    }
    let host = NSHostingView(rootView: TooltipView(text: label(id)))
    let size = host.fittingSize
    tooltip.contentView = host
    tooltip.setFrame(
      NSRect(x: (panel.frame.minX + x - size.width / 2).rounded(), y: panel.frame.maxY + 6, width: size.width, height: size.height),
      display: true
    )
    tooltip.orderFrontRegardless()
  }

  private static func makePanel(ignoresMouse: Bool) -> NSPanel {
    let panel = NSPanel(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
    panel.isFloatingPanel = true
    panel.level = .floating
    panel.backgroundColor = .clear
    panel.isOpaque = false
    panel.hasShadow = !ignoresMouse
    panel.ignoresMouseEvents = ignoresMouse
    panel.hidesOnDeactivate = false
    panel.becomesKeyOnlyIfNeeded = true
    panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
    return panel
  }
}
