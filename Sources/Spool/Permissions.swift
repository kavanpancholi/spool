import AppKit
import ApplicationServices
import SwiftUI

final class PermissionsModel: ObservableObject {
  @Published private(set) var accessibility = AXIsProcessTrusted()
  @Published private(set) var screenRecording = CGPreflightScreenCaptureAccess()
  var needsScreenRecording: () -> Bool = { false }

  var allGranted: Bool {
    accessibility && (screenRecording || !needsScreenRecording())
  }

  func refresh() {
    let accessibility = AXIsProcessTrusted()
    let screenRecording = CGPreflightScreenCaptureAccess()
    if accessibility != self.accessibility { self.accessibility = accessibility }
    if screenRecording != self.screenRecording { self.screenRecording = screenRecording }
  }

  func requestAccessibility() {
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    AXIsProcessTrustedWithOptions(options)
    open("Privacy_Accessibility")
  }

  func requestScreenRecording() {
    CGRequestScreenCaptureAccess()
    open("Privacy_ScreenCapture")
  }

  private func open(_ pane: String) {
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
      NSWorkspace.shared.open(url)
    }
  }
}

struct PermissionsView: View {
  @ObservedObject var model: PermissionsModel
  let restart: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Label("Spool needs your permission", systemImage: "hand.raised")
        .font(.title2.bold())
      PermissionRow(
        title: "Accessibility",
        detail: "Moves and resizes your windows, and reads the mouse thumb wheel and trackpad swipes.",
        granted: model.accessibility,
        action: model.requestAccessibility
      )
      if model.needsScreenRecording() {
        PermissionRow(
          title: "Screen Recording",
          detail: "Takes window snapshots so the strip slides smoothly across screens. Nothing is saved or sent anywhere.",
          granted: model.screenRecording,
          action: model.requestScreenRecording
        )
      }
      Text("Spool starts on its own once every row has a tick. If a switch is already on in System Settings but the row still shows a cross, select Spool there, remove it with −, and add it again. Development builds count as a new app after each rebuild.")
        .font(.callout)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      HStack {
        Text("Screen Recording often needs a restart to take effect.")
          .font(.caption)
          .foregroundStyle(.secondary)
        Spacer()
        Button("Restart Spool", action: restart)
      }
    }
    .padding(24)
    .frame(width: 520)
  }
}

private struct PermissionRow: View {
  let title: String
  let detail: String
  let granted: Bool
  let action: () -> Void

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
        .foregroundStyle(granted ? .green : .red)
        .font(.title2)
      VStack(alignment: .leading, spacing: 2) {
        Text(title).font(.headline)
        Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      }
      Spacer()
      if !granted {
        Button("Open Settings", action: action)
      }
    }
  }
}
