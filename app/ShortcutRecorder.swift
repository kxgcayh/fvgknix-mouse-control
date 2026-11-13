// Records a keyboard shortcut for a button, and the pad that shows what a press sends after remapping.

import AppKit
import SwiftUI

// MARK: - Shortcut recorder

struct Preset: Identifiable {
  let name: String
  let action: ButtonAction
  var id: String { name }
}

let presets: [Preset] = [
  Preset(name: "Space to the left (⌃←)", action: .shortcut(0x7B, [.control], "←")),
  Preset(name: "Space to the right (⌃→)", action: .shortcut(0x7C, [.control], "→")),
  Preset(name: "Mission Control (⌃↑)", action: .shortcut(0x7E, [.control], "↑")),
  Preset(name: "App windows (⌃↓)", action: .shortcut(0x7D, [.control], "↓")),
  Preset(name: "Back (⌘[)", action: .shortcut(0x21, [.command], "[")),
  Preset(name: "Forward (⌘])", action: .shortcut(0x1E, [.command], "]")),
  Preset(name: "Copy (⌘C)", action: .shortcut(0x08, [.command], "C")),
  Preset(name: "Paste (⌘V)", action: .shortcut(0x09, [.command], "V")),
  Preset(name: "Close tab (⌘W)", action: .shortcut(0x0D, [.command], "W")),
]

let specialKeys: [UInt16: String] = [
  0x7B: "←", 0x7C: "→", 0x7D: "↓", 0x7E: "↑", 0x24: "↩", 0x30: "⇥", 0x31: "Space", 0x33: "⌫",
  0x75: "⌦", 0x35: "⎋", 0x73: "Home", 0x77: "End", 0x74: "Page Up", 0x79: "Page Down",
  0x7A: "F1", 0x78: "F2", 0x63: "F3", 0x76: "F4", 0x60: "F5", 0x61: "F6",
  0x62: "F7", 0x64: "F8", 0x65: "F9", 0x6D: "F10", 0x67: "F11", 0x6F: "F12",
]

/// macOS handles some shortcuts before any app sees them (⌃← and ⌃→ switch Spaces), so the recorder can't
/// capture them. They're offered in the Choose menu instead. The helper posts them like a real keyboard would,
/// so they still work: it only needs them to be switched on in System Settings.
enum SystemShortcuts {
  /// Name of the Spaces shortcut this action relies on, if that shortcut is turned off in System Settings.
  static func turnedOff(for action: ButtonAction) -> String? {
    guard action.kind == .shortcut, action.modifiers == [.control] else { return nil }
    let (id, name): (Int, String)
    switch action.keyCode {
    case 0x7B: (id, name) = (79, "Move left a space")
    case 0x7C: (id, name) = (81, "Move right a space")
    case 0x7E: (id, name) = (32, "Mission Control")
    case 0x7D: (id, name) = (33, "Application windows")
    default: return nil
    }
    let hotkeys = UserDefaults(suiteName: "com.apple.symbolichotkeys")?.dictionary(forKey: "AppleSymbolicHotKeys")
    let entry = hotkeys?[String(id)] as? [String: Any]
    return (entry?["enabled"] as? NSNumber)?.boolValue == false ? name : nil
  }

  static func isReserved(_ action: ButtonAction) -> Bool {
    action.kind == .shortcut && action.modifiers == [.control] && [0x7B, 0x7C, 0x7D, 0x7E].contains(action.keyCode)
  }
}

struct ShortcutRecorder: View {
  @Binding var action: ButtonAction
  @State private var recording = false
  @State private var monitor: Any?

  var body: some View {
    HStack(spacing: 4) {
      Button {
        recording ? stop() : start()
      } label: {
        Text(recording ? "Press keys…" : (action.keyCode == nil ? "Record" : action.shortcutText))
          .frame(maxWidth: .infinity)
      }
      .glassButton()
      .help("Click, then press the shortcut. Esc cancels.")

      Menu {
        ForEach(presets) { preset in
          Button(preset.name) { action = preset.action }
        }
      } label: {
        Text("Choose")
      }
      .menuStyle(.borderlessButton)
      .fixedSize()
      .help("Common shortcuts, including the ones macOS keeps for itself, which can't be recorded")
    }
    .onDisappear(perform: stop)
  }

  private func start() {
    recording = true
    monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      if event.keyCode == 0x35 && event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
        stop(); return nil
      }
      var modifiers: [Modifier] = []
      let flags = event.modifierFlags
      if flags.contains(.control) { modifiers.append(.control) }
      if flags.contains(.option) { modifiers.append(.option) }
      if flags.contains(.shift) { modifiers.append(.shift) }
      if flags.contains(.command) { modifiers.append(.command) }
      let label = specialKeys[event.keyCode] ?? event.charactersIgnoringModifiers?.uppercased() ?? "?"
      action = .shortcut(event.keyCode, modifiers, label)
      stop()
      return nil
    }
  }

  private func stop() {
    recording = false
    if let monitor { NSEvent.removeMonitor(monitor) }
    monitor = nil
  }
}

// MARK: - Test pad

/// Shows what arrives after the helper's remap: a click with any button, or the shortcut it sends.
struct TestPad: NSViewRepresentable {
  func makeNSView(context: Context) -> TestPadView { TestPadView() }
  func updateNSView(_ view: TestPadView, context: Context) {}
}

final class TestPadView: NSView {
  private let label = NSTextField(labelWithString: "Click here with any button")
  private var keyMonitor: Any?

  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
    layer?.cornerRadius = 12
    layer?.cornerCurve = .continuous
    label.alignment = .center
    label.textColor = .secondaryLabelColor
    label.translatesAutoresizingMaskIntoConstraints = false
    addSubview(label)
    NSLayoutConstraint.activate([
      label.centerXAnchor.constraint(equalTo: centerXAnchor),
      label.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])
    // Shortcuts from the helper arrive as key presses; show them while the pointer is over the pad.
    keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self, let window = self.window, event.window == window,
            self.bounds.contains(self.convert(window.mouseLocationOutsideOfEventStream, from: nil)) else { return event }
      let mods = event.modifierFlags
      let text = (mods.contains(.control) ? "⌃" : "") + (mods.contains(.option) ? "⌥" : "")
        + (mods.contains(.shift) ? "⇧" : "") + (mods.contains(.command) ? "⌘" : "")
        + (specialKeys[event.keyCode] ?? event.charactersIgnoringModifiers?.uppercased() ?? "?")
      self.show("Got shortcut \(text)")
      return event
    }
  }

  required init?(coder: NSCoder) { fatalError("not used") }

  deinit { if let keyMonitor { NSEvent.removeMonitor(keyMonitor) } }

  override func updateLayer() {
    layer?.backgroundColor = NSColor.white.withAlphaComponent(0.07).cgColor
  }

  private func show(_ text: String) {
    label.stringValue = text
    label.textColor = .labelColor
  }

  private func showClick(_ event: NSEvent) {
    let name = Ignix.buttonNames[event.buttonNumber + 1] ?? "Button \(event.buttonNumber + 1)"
    show("Got \(name.lowercased())")
  }

  override func mouseDown(with event: NSEvent) { showClick(event) }
  override func rightMouseDown(with event: NSEvent) { showClick(event) }
  override func otherMouseDown(with event: NSEvent) { showClick(event) }
  override func menu(for event: NSEvent) -> NSMenu? { nil }
}
