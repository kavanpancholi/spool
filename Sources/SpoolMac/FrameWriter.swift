import AppKit
import ApplicationServices
import SpoolCore

final class FrameWriter {
  private struct Job {
    let element: AXUIElement
    let pid: pid_t
    let frame: CGRect
  }

  private let lock = NSLock()
  private let wake = DispatchSemaphore(value: 0)
  private var pending: [WindowID: Job] = [:]
  private var written: [WindowID: CGRect] = [:]
  private var lastWrite: [WindowID: Date] = [:]
  private var thread: Thread?

  init() {
    let thread = Thread { [weak self] in self?.run() }
    thread.name = "Spool frame writer"
    thread.qualityOfService = .userInteractive
    self.thread = thread
    thread.start()
  }

  func submit(_ element: AXUIElement, pid: pid_t, id: WindowID, frame: CGRect) {
    lock.lock()
    let unchanged = pending[id] == nil && written[id] == frame
    if !unchanged { pending[id] = Job(element: element, pid: pid, frame: frame) }
    lock.unlock()
    if !unchanged { wake.signal() }
  }

  func forget(_ id: WindowID) {
    lock.lock()
    pending[id] = nil
    written[id] = nil
    lastWrite[id] = nil
    lock.unlock()
  }

  func invalidate(_ id: WindowID) {
    lock.lock()
    written[id] = nil
    lock.unlock()
  }

  func isBusy(_ id: WindowID, within interval: TimeInterval) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    if pending[id] != nil { return true }
    guard let last = lastWrite[id] else { return false }
    return Date().timeIntervalSince(last) < interval
  }

  private func run() {
    while true {
      wake.wait()
      lock.lock()
      let batch = pending
      pending.removeAll()
      let previous = written
      lock.unlock()
      guard !batch.isEmpty else { continue }

      var enhancedApps: [pid_t: AXUIElement] = [:]
      for job in batch.values where enhancedApps[job.pid] == nil {
        let app = AXUIElementCreateApplication(job.pid)
        if AX.bool(app, "AXEnhancedUserInterface") {
          AX.set(app, "AXEnhancedUserInterface", false)
          enhancedApps[job.pid] = app
        }
      }

      for (id, job) in batch {
        let old = previous[id]
        let resized = old?.size != job.frame.size
        if old?.origin != job.frame.origin || resized {
          AX.setPosition(job.element, job.frame.origin)
        }
        if resized {
          AX.setSize(job.element, job.frame.size)
          AX.setPosition(job.element, job.frame.origin)
        }
        lock.lock()
        written[id] = job.frame
        lastWrite[id] = Date()
        lock.unlock()
      }

      for app in enhancedApps.values {
        AX.set(app, "AXEnhancedUserInterface", true)
      }
    }
  }
}
