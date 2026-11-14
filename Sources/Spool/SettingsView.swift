import ServiceManagement
import SpoolCore
import SpoolMac
import SwiftUI

struct SettingsView: View {
  @ObservedObject var store: SettingsStore
  let failedShortcuts: [Shortcut]

  var body: some View {
    TabView {
      GeneralTab(store: store).tabItem { Label("General", systemImage: "gearshape") }
      InputTab(store: store).tabItem { Label("Mouse & Trackpad", systemImage: "computermouse") }
      LayoutTab(store: store).tabItem { Label("Layout", systemImage: "rectangle.split.3x1") }
      AppsTab(store: store).tabItem { Label("Apps", systemImage: "square.stack") }
      DisplaysTab(store: store).tabItem { Label("Displays", systemImage: "display.2") }
      ShortcutsTab(failed: failedShortcuts).tabItem { Label("Shortcuts", systemImage: "keyboard") }
    }
    .frame(width: 560, height: 480)
  }
}

private struct GeneralTab: View {
  @ObservedObject var store: SettingsStore
  @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
  @State private var loginError: String?

  var body: some View {
    Form {
      Toggle("Enable Spool", isOn: $store.settings.enabled)
      Toggle("Launch at login", isOn: $launchAtLogin)
        .onChange(of: launchAtLogin) { enabled in
          do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
          } catch {
            loginError = error.localizedDescription
            launchAtLogin = SMAppService.mainApp.status == .enabled
          }
        }
      if let loginError {
        Text(loginError).foregroundStyle(.red).font(.caption)
      }
      Toggle("Animate the strip", isOn: $store.settings.animate)
      Toggle("Show window bar at the bottom", isOn: $store.settings.showBar)
      Toggle("Smooth slides across screens (uses Screen Recording)", isOn: $store.settings.smoothSlides)
      Toggle("One strip across all displays", isOn: $store.settings.spanDisplays)
      if store.settings.spanDisplays && !store.settings.smoothSlides {
        Text("macOS draws a window on one display at a time while “Displays have separate Spaces” is on. Turn on smooth slides so windows glide across the seam instead of jumping.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Picker("Centre focused window", selection: $store.settings.centerMode) {
        Text("Never").tag(CenterMode.never)
        Text("When it does not fit").tag(CenterMode.onOverflow)
        Text("Always").tag(CenterMode.always)
      }
    }
    .formStyle(.grouped)
  }
}

private struct InputTab: View {
  @ObservedObject var store: SettingsStore

  var body: some View {
    Form {
      Section {
        Toggle("Thumb wheel scrolls the strip", isOn: $store.settings.thumbWheel.enabled)
        LabeledContent("Speed") {
          Slider(value: $store.settings.thumbWheel.speed, in: 0.5...10)
        }
        Toggle("Reverse direction", isOn: $store.settings.thumbWheel.inverted)
        Picker("Hold to scroll the app instead", selection: $store.settings.thumbWheel.passthroughModifier) {
          Text("Nothing").tag(ModifierKey.none)
          Text("⌥ Option").tag(ModifierKey.option)
          Text("⌘ Command").tag(ModifierKey.command)
          Text("⌃ Control").tag(ModifierKey.control)
        }
        Toggle("Snap to the nearest window", isOn: $store.settings.thumbWheel.snapToColumns)
        LabeledContent("Snap delay: \(String(format: "%.2f", store.settings.thumbWheel.snapDelay))s") {
          Slider(value: $store.settings.thumbWheel.snapDelay, in: 0.15...1.5)
        }
        .disabled(!store.settings.thumbWheel.snapToColumns)
      } header: {
        Text("Mouse thumb wheel")
      } footer: {
        Text("Works with the Logitech MX Master thumb wheel and any mouse that scrolls sideways. The main wheel always scrolls the app.")
      }

      Section("Apps where the thumb wheel scrolls the app") {
        AppListEditor(bundleIDs: $store.settings.thumbWheel.passthroughBundleIDs)
      }

      Section {
        Picker("Swipe fingers", selection: $store.settings.trackpad.fingers) {
          Text("Off").tag(0)
          Text("Three fingers").tag(3)
          Text("Four fingers").tag(4)
        }
        LabeledContent("Speed") {
          Slider(value: $store.settings.trackpad.speed, in: 0.3...3)
        }
        Toggle("Reverse direction", isOn: $store.settings.trackpad.inverted)
      } header: {
        Text("Trackpad")
      } footer: {
        Text("Turn off “Swipe between full-screen apps” in System Settings → Trackpad for the same finger count, or macOS switches Spaces too.")
      }
    }
    .formStyle(.grouped)
  }
}

private struct LayoutTab: View {
  @ObservedObject var store: SettingsStore
  @State private var presetsText = ""

  var body: some View {
    Form {
      Section("Gaps") {
        Stepper("Between windows: \(Int(store.settings.innerGap)) pt", value: $store.settings.innerGap, in: 0...64, step: 2)
        Stepper("At screen edges: \(Int(store.settings.outerGap)) pt", value: $store.settings.outerGap, in: 0...64, step: 2)
      }
      Section {
        TextField("Preset widths (%)", text: $presetsText)
          .onSubmit(savePresets)
        Stepper("Wider/narrower step: \(Int(store.settings.widthStep * 100))%", value: $store.settings.widthStep, in: 0.05...0.25, step: 0.05)
      } header: {
        Text("Widths")
      } footer: {
        Text("Comma separated, for example 33, 50, 66. ⌃⌥R cycles through them. Press Return to save.")
      }
    }
    .formStyle(.grouped)
    .onAppear {
      presetsText = store.settings.widthPresets.map { String(Int(($0 * 100).rounded())) }.joined(separator: ", ")
    }
  }

  private func savePresets() {
    let values = presetsText.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
      .filter { $0 >= 10 && $0 <= 100 }
      .map { $0 / 100 }
    if !values.isEmpty { store.settings.widthPresets = values.sorted() }
  }
}

private struct AppsTab: View {
  @ObservedObject var store: SettingsStore

  var body: some View {
    Form {
      Section {
        AppListEditor(bundleIDs: $store.settings.floatingBundleIDs)
      } header: {
        Text("Always float these apps")
      } footer: {
        Text("Floating windows stay where they are. ⌃⌥T floats or tiles a single window.")
      }
    }
    .formStyle(.grouped)
  }
}

private struct DisplaysTab: View {
  @ObservedObject var store: SettingsStore
  @State private var displays = Display.current()

  var body: some View {
    Form {
      Section("Use Spool on") {
        ForEach(displays, id: \.uuid) { display in
          Toggle(display.name, isOn: Binding(
            get: { !store.settings.excludedDisplayIDs.contains(display.uuid) },
            set: { included in
              store.settings.excludedDisplayIDs.removeAll { $0 == display.uuid }
              if !included { store.settings.excludedDisplayIDs.append(display.uuid) }
            }
          ))
        }
      }
    }
    .formStyle(.grouped)
    .onAppear { displays = Display.current() }
  }
}

private struct ShortcutsTab: View {
  let failed: [Shortcut]

  var body: some View {
    List {
      ForEach(Shortcut.defaults, id: \.self) { shortcut in
        HStack {
          Text(shortcut.command.title)
          Spacer()
          if failed.contains(shortcut) {
            Text("taken by another app").foregroundStyle(.red).font(.caption)
          }
          Text(shortcut.display).monospaced().foregroundStyle(.secondary)
        }
      }
    }
  }
}

struct AppListEditor: View {
  @Binding var bundleIDs: [String]

  var body: some View {
    ForEach(bundleIDs, id: \.self) { id in
      HStack {
        Text(Self.name(for: id))
        Text(id).font(.caption).foregroundStyle(.secondary)
        Spacer()
        Button {
          bundleIDs.removeAll { $0 == id }
        } label: {
          Image(systemName: "minus.circle")
        }
        .buttonStyle(.borderless)
      }
    }
    Menu("Add a running app") {
      ForEach(Self.runningApps(excluding: bundleIDs), id: \.self) { id in
        Button(Self.name(for: id)) { bundleIDs.append(id) }
      }
    }
  }

  static func name(for bundleID: String) -> String {
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
    return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
  }

  static func runningApps(excluding: [String]) -> [String] {
    let ids = NSWorkspace.shared.runningApplications
      .filter { $0.activationPolicy == .regular }
      .compactMap(\.bundleIdentifier)
      .filter { !excluding.contains($0) && $0 != Bundle.main.bundleIdentifier }
    return Array(Set(ids)).sorted { name(for: $0) < name(for: $1) }
  }
}
