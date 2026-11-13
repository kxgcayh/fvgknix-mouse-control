// Button mapping shared by the helper (helper/main.swift) and the settings app (app/).
// Stored as JSON at ~/Library/Application Support/IGNIX/config.json.
// Buttons are numbered 1-5 like the mouse labels them; macOS numbers them from 0.

import Foundation

enum Ignix {
  static let buttonCount = 5
  static let buttonNames = [1: "Left click", 2: "Right click", 3: "Middle click", 4: "Back (side)", 5: "Forward (side)"]
  static let helperLabel = "local.ignix-remap"
  /// Darwin notification the app posts after saving; the helper reloads the file on it.
  static let reloadNotification = "local.ignix-remap.reload"

  static var configURL: URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Application Support/IGNIX/config.json")
  }
}

enum Modifier: String, Codable, CaseIterable {
  case control, option, shift, command

  var symbol: String {
    switch self {
    case .control: "⌃"
    case .option: "⌥"
    case .shift: "⇧"
    case .command: "⌘"
    }
  }
}

struct ButtonAction: Codable, Equatable {
  enum Kind: String, Codable, CaseIterable {
    case standard   // the button does what it normally does
    case disabled
    case shortcut   // keyCode + modifiers
    case button     // acts as another mouse button
  }

  var kind: Kind = .standard
  var keyCode: UInt16?
  var modifiers: [Modifier]?
  /// Shown in the app, e.g. "←". Recorded with the shortcut because key names depend on the keyboard layout.
  var keyLabel: String?
  /// Target for .button, 1-5.
  var button: Int?

  static let standard = ButtonAction()
  static let disabled = ButtonAction(kind: .disabled)
  static func shortcut(_ keyCode: UInt16, _ modifiers: [Modifier], _ label: String) -> ButtonAction {
    ButtonAction(kind: .shortcut, keyCode: keyCode, modifiers: modifiers, keyLabel: label)
  }
  static func acts(as button: Int) -> ButtonAction { ButtonAction(kind: .button, button: button) }

  var shortcutText: String {
    let mods = Modifier.allCases.filter { modifiers?.contains($0) == true }.map(\.symbol).joined()
    return mods + (keyLabel ?? keyCode.map { "key \($0)" } ?? "")
  }

  /// The mouse button this action produces, if any.
  func producedButton(from source: Int) -> Int? {
    switch kind {
    case .standard: source
    case .button: button
    case .disabled, .shortcut: nil
    }
  }
}

/// What the helper last heard from the mouse (input report 3, see docs/protocol.md), for the app to show.
/// Saved at ~/Library/Application Support/IGNIX/status.json.
struct IgnixStatus: Codable, Equatable {
  var batteryLevel: Int?
  var batteryStatus: Int?
  /// Only known after the mouse's DPI button is pressed once; kept across restarts.
  var dpiLevel: Int?
  /// When the mouse last sent anything. It reports every 2 seconds while awake.
  var lastSeen: Date?
  /// DPI of each enabled level, read from the mouse at helper start and after each write.
  var dpiValues: [Int]?
  /// Outcome of the last DPI write, for the app.
  var dpiWrite: DPIWriteResult?

  struct DPIWriteResult: Codable, Equatable {
    var requestID: UUID
    var ok: Bool
    var message: String
    var time: Date
  }

  var currentDPI: Int? {
    guard let level = dpiLevel, let values = dpiValues, values.indices.contains(level - 1) else { return nil }
    return values[level - 1]
  }

  static var url: URL { Ignix.configURL.deletingLastPathComponent().appendingPathComponent("status.json") }

  static func load() -> IgnixStatus {
    guard let data = try? Data(contentsOf: url) else { return IgnixStatus() }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return (try? decoder.decode(IgnixStatus.self, from: data)) ?? IgnixStatus()
  }

  func save() {
    try? FileManager.default.createDirectory(at: Self.url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try? encoder.encode(self).write(to: Self.url, options: .atomic)
  }
}

struct IgnixConfig: Codable, Equatable {
  /// When true, only the IGNIX receiver is remapped; other mice and the trackpad stay normal.
  var onlyThisMouse = true
  /// Keyed by button number as a string ("1"..."5"); missing buttons are standard.
  var buttons: [String: ButtonAction] = [:]

  static let defaults = IgnixConfig(buttons: [
    "4": .shortcut(0x7B, [.control], "←"),
    "5": .shortcut(0x7C, [.control], "→"),
  ])

  func action(for button: Int) -> ButtonAction { buttons[String(button)] ?? .standard }

  mutating func set(_ action: ButtonAction, for button: Int) {
    buttons[String(button)] = action == .standard ? nil : action
  }

  /// True when some button still sends a left click, so the mouse can't lock the user out.
  var keepsLeftClick: Bool {
    (1...Ignix.buttonCount).contains { action(for: $0).producedButton(from: $0) == 1 }
  }

  /// What the helper applies: button 1 falls back to Left click when nothing else sends one.
  var effective: IgnixConfig {
    guard !keepsLeftClick else { return self }
    var copy = self
    copy.set(.standard, for: 1)
    return copy
  }

  static func load() -> IgnixConfig {
    guard let data = try? Data(contentsOf: Ignix.configURL) else { return .defaults }
    return (try? JSONDecoder().decode(IgnixConfig.self, from: data)) ?? .defaults
  }

  func save() throws {
    let url = Ignix.configURL
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(self).write(to: url, options: .atomic)
    CFNotificationCenterPostNotification(
      CFNotificationCenterGetDarwinNotifyCenter(),
      CFNotificationName(Ignix.reloadNotification as CFString), nil, nil, true)
  }
}
