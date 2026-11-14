import SwiftUI

struct OnboardingView: View {
  let requestPermission: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Label("Spool needs Accessibility permission", systemImage: "hand.raised")
        .font(.title2.bold())
      Text("Spool moves and resizes your windows, and reads your mouse thumb wheel and trackpad swipes. macOS only allows that for apps you approve under Accessibility.")
        .fixedSize(horizontal: false, vertical: true)
      Text("Turn on Spool in System Settings → Privacy & Security → Accessibility. Spool starts on its own once you do.")
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      HStack {
        Spacer()
        Button("Open System Settings", action: requestPermission)
          .keyboardShortcut(.defaultAction)
      }
    }
    .padding(24)
    .frame(width: 460)
  }
}
