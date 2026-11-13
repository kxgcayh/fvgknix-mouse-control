// The mouse's DPI table (feature report 0x04), see docs/protocol.md. Pure data: no device access here.

import Foundation

struct DPITable: Codable, Equatable {
  static let reportID: UInt8 = 0x04
  static let length = 0x38
  static let minDPI = 100
  static let maxDPI = 30000
  static let step = 50

  /// The 56-byte read reply, kept so a write changes only the DPI values.
  var raw: [UInt8]

  /// Reply layout: 2 sensX, 3 sensY, 4 enabled mask, 5-6 x2 flags, 7-14 DPI low bytes, 15-22 high bytes,
  /// 23 current level, 24-47 LED colours, 48 indicator type, 49-50 checksum of bytes 2-48.
  init?(reply: [UInt8]) {
    guard reply.count >= 51, reply[0] == Self.reportID, reply[1] == UInt8(Self.length) else { return nil }
    let sum = reply[2...48].reduce(0) { $0 + Int($1) } & 0xFFFF
    guard sum == Int(reply[49]) << 8 | Int(reply[50]) else { return nil }
    raw = Array(reply.prefix(Self.length))
  }

  var enabledMask: UInt8 { raw[4] }
  var enabledCount: Int { (0..<8).filter { enabledMask & (1 << $0) != 0 }.count }
  var currentLevel: Int { Int(raw[23]) }

  /// DPI of each enabled level, level 1 first. Stored as plain 16-bit numbers on this firmware.
  var values: [Int] { (0..<enabledCount).map { Int(raw[15 + $0]) << 8 | Int(raw[7 + $0]) } }

  static func isValid(_ dpi: Int) -> Bool { (minDPI...maxDPI).contains(dpi) && dpi % step == 0 }

  /// The write frame for new values: the reply with the profile byte inserted at offset 2 and a fresh checksum
  /// (16-bit big-endian sum of bytes 3-49 at 50-51), padded to 56 bytes. Everything except the DPI values is kept.
  func writeFrame(values newValues: [Int]) -> [UInt8]? {
    guard newValues.count == enabledCount, newValues.allSatisfy(Self.isValid) else { return nil }
    var reply = raw
    for (i, dpi) in newValues.enumerated() {
      reply[7 + i] = UInt8(dpi & 0xFF)
      reply[15 + i] = UInt8(dpi >> 8)
    }
    var frame: [UInt8] = [Self.reportID, UInt8(Self.length), 0x01] + Array(reply[2...48])
    let sum = frame[3...49].reduce(0) { $0 + Int($1) } & 0xFFFF
    frame += [UInt8(sum >> 8), UInt8(sum & 0xFF)]
    frame += [UInt8](repeating: 0, count: Self.length - frame.count)
    return frame
  }
}

/// The app writes this to ask the helper for a DPI change; the helper reports back in IgnixStatus.
struct DPIRequest: Codable {
  var id = UUID()
  var values: [Int]

  static var url: URL { Ignix.configURL.deletingLastPathComponent().appendingPathComponent("dpi-request.json") }
  static let notification = "local.ignix-remap.dpi"

  func send() throws {
    try FileManager.default.createDirectory(at: Self.url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try JSONEncoder().encode(self).write(to: Self.url, options: .atomic)
    CFNotificationCenterPostNotification(
      CFNotificationCenterGetDarwinNotifyCenter(), CFNotificationName(Self.notification as CFString), nil, nil, true)
  }

  static func take() -> DPIRequest? {
    guard let data = try? Data(contentsOf: url) else { return nil }
    try? FileManager.default.removeItem(at: url)
    return try? JSONDecoder().decode(DPIRequest.self, from: data)
  }
}

/// The table as first read from the mouse, before FVGKNIX Control ever wrote to it. Never overwritten.
enum DPIBackup {
  static var url: URL { Ignix.configURL.deletingLastPathComponent().appendingPathComponent("dpi-backup.json") }

  static func load() -> DPITable? {
    guard let data = try? Data(contentsOf: url) else { return nil }
    return try? JSONDecoder().decode(DPITable.self, from: data)
  }

  static func saveIfMissing(_ table: DPITable) {
    guard !FileManager.default.fileExists(atPath: url.path) else { return }
    try? JSONEncoder().encode(table).write(to: url, options: .atomic)
  }
}
