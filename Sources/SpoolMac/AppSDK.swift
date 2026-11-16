import AppKit

enum AppSDK {
  private static var cache: [String: Int] = [:]

  static func majorVersion(of pid: pid_t) -> Int? {
    guard let url = NSRunningApplication(processIdentifier: pid)?.executableURL else { return nil }
    if let cached = cache[url.path] { return cached }
    guard let major = read(url) else { return nil }
    cache[url.path] = major
    return major
  }

  private static func read(_ url: URL) -> Int? {
    guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
    defer { try? handle.close() }
    guard let header = try? handle.read(upToCount: 4096), header.count >= 8 else { return nil }
    let magic = header.loadBigEndian(at: 0)
    if magic == 0xCAFE_BABE {
      let count = Int(header.loadBigEndian(at: 4))
      var fallback: UInt64?
      for index in 0..<min(count, 16) {
        let base = 8 + index * 20
        guard header.count >= base + 20 else { break }
        let cpu = header.loadBigEndian(at: base)
        let offset = UInt64(header.loadBigEndian(at: base + 8))
        if cpu == 0x0100_000C { fallback = offset; break }
        fallback = fallback ?? offset
      }
      guard let offset = fallback else { return nil }
      try? handle.seek(toOffset: offset)
      guard let slice = try? handle.read(upToCount: 65536) else { return nil }
      return sdkMajor(slice)
    }
    try? handle.seek(toOffset: 0)
    guard let slice = try? handle.read(upToCount: 65536) else { return nil }
    return sdkMajor(slice)
  }

  private static func sdkMajor(_ data: Data) -> Int? {
    guard data.count >= 32, data.loadLittleEndian(at: 0) == 0xFEED_FACF else { return nil }
    let commands = Int(data.loadLittleEndian(at: 16))
    var offset = 32
    for _ in 0..<commands {
      guard data.count >= offset + 8 else { return nil }
      let command = data.loadLittleEndian(at: offset)
      let size = Int(data.loadLittleEndian(at: offset + 4))
      if command == 0x32, data.count >= offset + 20 {
        return Int(data.loadLittleEndian(at: offset + 16) >> 16)
      }
      if command == 0x24, data.count >= offset + 16 {
        return Int(data.loadLittleEndian(at: offset + 12) >> 16)
      }
      guard size > 0 else { return nil }
      offset += size
    }
    return nil
  }
}

private extension Data {
  func loadBigEndian(at offset: Int) -> UInt32 {
    self[startIndex + offset..<startIndex + offset + 4].reduce(0) { $0 << 8 | UInt32($1) }
  }

  func loadLittleEndian(at offset: Int) -> UInt32 {
    self[startIndex + offset..<startIndex + offset + 4].reversed().reduce(0) { $0 << 8 | UInt32($1) }
  }
}
