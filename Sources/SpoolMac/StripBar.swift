import AppKit
import SpoolCore
import SwiftUI

enum BarTileState: Equatable {
  case tiled
  case minimized
  case noWindows
}

struct BarTile: Identifiable, Equatable {
  let id: WindowID
  let pid: pid_t
  let focused: Bool
  let state: BarTileState
}

struct BarGroup: Equatable {
  let displayID: String
  let tiles: [BarTile]
}

enum BarMetrics {
  static let icon: CGFloat = 34
  static let spacing: CGFloat = 6
  static let padding: CGFloat = 8
  static let groupGap: CGFloat = 25
  static let dot: CGFloat = 4
  static let dotGap: CGFloat = 4
  static let margin: CGFloat = 6
  static let cornerRadius: CGFloat = 16

  static var tileHeight: CGFloat { icon + dotGap + dot }
  static var pillHeight: CGFloat { padding * 2 + tileHeight }
  static var reserve: CGFloat { pillHeight + margin }

  static func layout(_ groups: [BarGroup]) -> BarLayout {
    BarLayout(groupCounts: groups.map(\.tiles.count), icon: icon, spacing: spacing, groupGap: groupGap, padding: padding)
  }
}

final class BarModel: ObservableObject {
  @Published var groups: [BarGroup] = []
  var onSelect: (WindowID) -> Void = { _ in }
  var onMove: (WindowID, String, Int) -> Void = { _, _, _ in }
  var onHover: (WindowID?, CGFloat) -> Void = { _, _ in }
}

struct BarView: View {
  @ObservedObject var model: BarModel
  @State private var drag: TileDrag?

  private struct TileDrag: Equatable {
    let id: WindowID
    let group: Int
    let index: Int
    var x: CGFloat
    var drop: BarDrop
    var released = false
  }

  var body: some View {
    let layout = BarMetrics.layout(model.groups)
    let preview = previewLayout(layout)
    let tileY = BarMetrics.padding + BarMetrics.tileHeight / 2

    ZStack(alignment: .topLeading) {
      RoundedRectangle(cornerRadius: BarMetrics.cornerRadius, style: .continuous)
        .fill(.ultraThinMaterial)
      RoundedRectangle(cornerRadius: BarMetrics.cornerRadius, style: .continuous)
        .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)

      ForEach(Array(model.groups.indices.dropFirst()), id: \.self) { group in
        Rectangle()
          .fill(Color.white.opacity(0.25))
          .frame(width: 1, height: BarMetrics.icon)
          .position(x: (preview.groupBounds(group - 1).upperBound + preview.groupBounds(group).lowerBound) / 2, y: tileY - BarMetrics.dot)
      }

      ForEach(Array(model.groups.enumerated()), id: \.element.displayID) { group, entry in
        if entry.tiles.isEmpty && drag?.drop.group != group {
          RoundedRectangle(cornerRadius: 9, style: .continuous)
            .strokeBorder(Color.white.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            .frame(width: BarMetrics.icon, height: BarMetrics.icon)
            .position(x: layout.center(group: group, index: 0), y: tileY - BarMetrics.dot)
        }
        ForEach(Array(entry.tiles.enumerated()), id: \.element.id) { index, tile in
          tileView(tile, group: group, index: index, layout: layout)
            .position(x: x(of: tile.id, group: group, index: index, preview: preview), y: tileY)
            .transaction { if drag?.id == tile.id && drag?.released == false { $0.animation = nil } }
        }
      }
    }
    .coordinateSpace(name: "bar")
    .frame(width: layout.width, height: BarMetrics.pillHeight)
    .animation(.easeOut(duration: 0.15), value: model.groups)
    .animation(.easeOut(duration: 0.15), value: drag?.drop)
    .animation(.spring(response: 0.3, dampingFraction: 0.72), value: drag?.released)
    .onChange(of: model.groups) { _ in drag = nil }
  }

  private func previewLayout(_ layout: BarLayout) -> BarLayout {
    guard let drag, drag.drop.group != drag.group else { return layout }
    var counts = layout.groupCounts
    counts[drag.group] -= 1
    counts[drag.drop.group] += 1
    return BarLayout(groupCounts: counts, icon: layout.icon, spacing: layout.spacing, groupGap: layout.groupGap, padding: layout.padding)
  }

  private func x(of id: WindowID, group: Int, index: Int, preview: BarLayout) -> CGFloat {
    guard let drag else { return preview.center(group: group, index: index) }
    if drag.id == id {
      return drag.released ? preview.center(group: drag.drop.group, index: drag.drop.index) : drag.x
    }
    var slot = index
    if group == drag.group && index > drag.index { slot -= 1 }
    if group == drag.drop.group && slot >= drag.drop.index { slot += 1 }
    return preview.center(group: group, index: slot)
  }

  private func tileView(_ tile: BarTile, group: Int, index: Int, layout: BarLayout) -> some View {
    let center = layout.center(group: group, index: index)
    return TileView(tile: tile)
      .zIndex(drag?.id == tile.id ? 1 : 0)
      .onHover { inside in
        model.onHover(inside && drag == nil ? tile.id : nil, center)
      }
      .onTapGesture { model.onSelect(tile.id) }
      .gesture(
        DragGesture(minimumDistance: 5, coordinateSpace: .named("bar"))
          .onChanged { value in
            let x = layout.rubberBand(center + value.translation.width)
            let drop = layout.drop(atX: x, dragging: (group, index))
            if drag == nil { model.onHover(nil, 0) }
            drag = TileDrag(id: tile.id, group: group, index: index, x: x, drop: drop)
          }
          .onEnded { value in
            let drop = layout.drop(atX: center + value.translation.width, dragging: (group, index))
            guard drop.group != group || drop.index != index else {
              drag = nil
              return
            }
            drag?.drop = drop
            drag?.released = true
            model.onMove(tile.id, model.groups[drop.group].displayID, drop.index)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
              if drag?.id == tile.id && drag?.released == true { drag = nil }
            }
          },
        including: tile.state == .tiled ? .all : .subviews
      )
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
        .overlay(alignment: .bottomTrailing) {
          if tile.state == .minimized {
            Image(systemName: "minus.circle.fill")
              .font(.system(size: 13, weight: .semibold))
              .symbolRenderingMode(.palette)
              .foregroundStyle(Color.white, Color.black.opacity(0.75))
              .offset(x: 3, y: 3)
          }
        }
        .background(
          RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(Color.white.opacity(tile.focused ? 0.22 : 0))
            .padding(-3)
        )
      Circle()
        .fill(tile.state == .tiled ? (tile.focused ? Color.white : Color.gray.opacity(0.7)) : Color.clear)
        .overlay(Circle().stroke(Color.gray.opacity(tile.state == .noWindows ? 0.8 : 0), lineWidth: 1))
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
  var onMove: (WindowID, String, Int) -> Void = { _, _, _ in }
  var label: (WindowID) -> String = { _ in "" }

  private let model = BarModel()
  private lazy var panel: NSPanel = {
    let panel = Self.makePanel(ignoresMouse: false)
    panel.contentView = NSHostingView(rootView: BarView(model: model))
    return panel
  }()
  private let tooltip = BarController.makePanel(ignoresMouse: true)

  init() {
    model.onSelect = { [weak self] id in
      self?.tooltip.orderOut(nil)
      self?.onSelect(id)
    }
    model.onMove = { [weak self] id, display, index in self?.onMove(id, display, index) }
    model.onHover = { [weak self] id, x in self?.showTooltip(for: id, atX: x) }
  }

  func update(on display: Display?, groups: [BarGroup]) {
    guard let display, groups.contains(where: { !$0.tiles.isEmpty }) else {
      hideAll()
      return
    }
    if model.groups != groups { model.groups = groups }
    let width = BarMetrics.layout(groups).width
    let visible = display.cocoaVisibleFrame
    let frame = NSRect(
      x: (visible.midX - width / 2).rounded(),
      y: visible.minY + BarMetrics.margin,
      width: width,
      height: BarMetrics.pillHeight
    )
    if panel.frame != frame { panel.setFrame(frame, display: true) }
    if !panel.isVisible { panel.orderFrontRegardless() }
  }

  func hideAll() {
    panel.orderOut(nil)
    tooltip.orderOut(nil)
  }

  private func showTooltip(for id: WindowID?, atX x: CGFloat) {
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
