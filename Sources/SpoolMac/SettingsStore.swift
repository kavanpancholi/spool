import Combine
import Foundation
import OSLog
import SpoolCore

public final class SettingsStore: ObservableObject {
  @Published public var settings: SpoolSettings {
    didSet { if settings != oldValue { save() } }
  }

  private let url: URL
  private let log = Logger(subsystem: "io.github.kavanpancholi.spool", category: "settings")

  public init(url: URL = SettingsStore.defaultURL) {
    self.url = url
    if let data = try? Data(contentsOf: url) {
      do {
        settings = try JSONDecoder().decode(SpoolSettings.self, from: data)
      } catch {
        Logger(subsystem: "io.github.kavanpancholi.spool", category: "settings")
          .error("Settings file unreadable, using defaults: \(error.localizedDescription, privacy: .public)")
        settings = SpoolSettings()
      }
    } else {
      settings = SpoolSettings()
    }
  }

  public static var defaultURL: URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    return base.appendingPathComponent("Spool/settings.json")
  }

  private func save() {
    do {
      try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      try encoder.encode(settings).write(to: url, options: .atomic)
    } catch {
      log.error("Saving settings failed: \(error.localizedDescription, privacy: .public)")
    }
  }
}
