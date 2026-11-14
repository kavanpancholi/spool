import Carbon
import SpoolCore

final class HotKeys {
  var onCommand: ((Command) -> Void)?

  private var refs: [EventHotKeyRef] = []
  private var commands: [UInt32: Command] = [:]
  private var handler: EventHandlerRef?
  private static let signature: OSType = 0x5350_4F4C

  init() {
    var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    let callback: EventHandlerUPP = { _, event, refcon in
      guard let event, let refcon else { return OSStatus(eventNotHandledErr) }
      var hotKeyID = EventHotKeyID()
      let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
      )
      guard status == noErr, hotKeyID.signature == HotKeys.signature else { return OSStatus(eventNotHandledErr) }
      let hotKeys = Unmanaged<HotKeys>.fromOpaque(refcon).takeUnretainedValue()
      guard let command = hotKeys.commands[hotKeyID.id] else { return OSStatus(eventNotHandledErr) }
      hotKeys.onCommand?(command)
      return noErr
    }
    InstallEventHandler(GetApplicationEventTarget(), callback, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
  }

  func register(_ shortcuts: [Shortcut]) -> [Shortcut] {
    unregisterAll()
    var failed: [Shortcut] = []
    for (index, shortcut) in shortcuts.enumerated() {
      let id = UInt32(index + 1)
      var ref: EventHotKeyRef?
      let status = RegisterEventHotKey(
        shortcut.keyCode,
        Self.carbonModifiers(shortcut.modifiers),
        EventHotKeyID(signature: Self.signature, id: id),
        GetApplicationEventTarget(),
        0,
        &ref
      )
      if status == noErr, let ref {
        refs.append(ref)
        commands[id] = shortcut.command
      } else {
        failed.append(shortcut)
      }
    }
    return failed
  }

  func unregisterAll() {
    refs.forEach { UnregisterEventHotKey($0) }
    refs.removeAll()
    commands.removeAll()
  }

  private static func carbonModifiers(_ modifiers: ModifierState) -> UInt32 {
    var result: UInt32 = 0
    if modifiers.contains(.command) { result |= UInt32(cmdKey) }
    if modifiers.contains(.shift) { result |= UInt32(shiftKey) }
    if modifiers.contains(.option) { result |= UInt32(optionKey) }
    if modifiers.contains(.control) { result |= UInt32(controlKey) }
    return result
  }
}
