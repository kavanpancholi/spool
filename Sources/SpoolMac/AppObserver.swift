import AppKit
import ApplicationServices

enum WindowEvent {
  case created
  case destroyed
  case focusChanged
  case moved
  case resized
  case minimized
  case restored
}

final class AppObserver {
  let pid: pid_t
  let app: AXUIElement
  private var observer: AXObserver?
  private let handler: (WindowEvent, AXUIElement, pid_t) -> Void

  private static let appNotifications = [
    kAXWindowCreatedNotification,
    kAXFocusedWindowChangedNotification,
    kAXMainWindowChangedNotification,
  ]

  private static let windowNotifications = [
    kAXUIElementDestroyedNotification,
    kAXWindowMovedNotification,
    kAXWindowResizedNotification,
    kAXWindowMiniaturizedNotification,
    kAXWindowDeminiaturizedNotification,
  ]

  init?(pid: pid_t, handler: @escaping (WindowEvent, AXUIElement, pid_t) -> Void) {
    self.pid = pid
    self.app = AXUIElementCreateApplication(pid)
    self.handler = handler
    AXUIElementSetMessagingTimeout(app, 1.0)

    var created: AXObserver?
    let callback: AXObserverCallback = { _, element, notification, refcon in
      guard let refcon else { return }
      let observer = Unmanaged<AppObserver>.fromOpaque(refcon).takeUnretainedValue()
      observer.dispatch(notification as String, element)
    }
    guard AXObserverCreate(pid, callback, &created) == .success, let created else { return nil }
    observer = created

    let refcon = Unmanaged.passUnretained(self).toOpaque()
    var registered = 0
    for name in Self.appNotifications where AXObserverAddNotification(created, app, name as CFString, refcon) == .success {
      registered += 1
    }
    guard registered > 0 else { return nil }
    CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .defaultMode)
  }

  deinit {
    if let observer {
      CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
    }
  }

  func watch(_ window: AXUIElement) {
    guard let observer else { return }
    let refcon = Unmanaged.passUnretained(self).toOpaque()
    for name in Self.windowNotifications {
      AXObserverAddNotification(observer, window, name as CFString, refcon)
    }
  }

  private func dispatch(_ notification: String, _ element: AXUIElement) {
    let event: WindowEvent
    switch notification {
    case kAXWindowCreatedNotification: event = .created
    case kAXUIElementDestroyedNotification: event = .destroyed
    case kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification: event = .focusChanged
    case kAXWindowMovedNotification: event = .moved
    case kAXWindowResizedNotification: event = .resized
    case kAXWindowMiniaturizedNotification: event = .minimized
    case kAXWindowDeminiaturizedNotification: event = .restored
    default: return
    }
    handler(event, element, pid)
  }
}
