import Foundation
import OSLog
import SpoolCore

final class SessionStore {
  private(set) var session: Session
  private let url: URL
  private var saveTimer: Timer?
  private let log = Logger(subsystem: "io.github.kavanpancholi.spool", category: "session")

  init(url: URL = SessionStore.defaultURL) {
    self.url = url
    let stored = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(Session.self, from: $0) }
    session = stored?.version == Session.currentVersion ? stored! : Session()
  }

  static var defaultURL: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Spool", isDirectory: true)
      .appendingPathComponent("session.json")
  }

  func update(_ strips: [String: SessionStrip], workspaces: [String: SessionWorkspaces]) {
    var next = session
    next.strips.merge(strips) { _, new in new }
    next.workspaces.merge(workspaces) { _, new in new }
    guard next != session else { return }
    session = next
    saveTimer?.invalidate()
    saveTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { [weak self] _ in self?.save() }
  }

  func save() {
    saveTimer?.invalidate()
    saveTimer = nil
    do {
      try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try JSONEncoder().encode(session).write(to: url, options: .atomic)
    } catch {
      log.error("Session save failed: \(error.localizedDescription, privacy: .public)")
    }
  }
}
