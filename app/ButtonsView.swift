// Buttons tab: pick a button on the mouse drawing, then choose what it does.

import AppKit
import SwiftUI

struct ButtonsView: View {
  @EnvironmentObject var model: Model
  @AppStorage("selectedButton") private var selection = 4

  private var dpiText: String? {
    guard let level = model.status.dpiLevel else { return nil }
    return model.status.currentDPI.map { "Level \(level) · \(String($0))" } ?? "Level \(level)"
  }

  private var diagram: some View {
    MouseDiagram(selection: $selection, config: model.config, dpiText: dpiText)
  }

  private var controls: some View {
    VStack(spacing: Theme.gap) {
      ButtonInspector(button: selection, action: model.binding(for: selection),
                      lockedOut: selection == 1 && !model.config.keepsLeftClick)
      OptionsPanel()
    }
  }

  var body: some View {
    ScrollView {
      // Side by side when there's room, stacked when the window is narrow.
      ViewThatFits(in: .horizontal) {
        HStack(alignment: .top, spacing: Theme.gap) {
          diagram.frame(minWidth: 400, maxWidth: .infinity).frame(height: 440)
          controls.frame(width: 360)
        }
        VStack(spacing: Theme.gap) {
          diagram.frame(height: 360)
          controls.frame(maxWidth: 460)
        }
      }
      .padding(Theme.pad)
    }
  }
}

/// Settings for the selected button.
struct ButtonInspector: View {
  let button: Int
  @Binding var action: ButtonAction
  /// Button 1 was taken off Left click and nothing else sends one.
  let lockedOut: Bool

  private var name: String { Ignix.buttonNames[button]! }

  private var kind: Binding<ButtonAction.Kind> {
    Binding(get: { action.kind }, set: { kind in
      switch kind {
      case .standard: action = .standard
      case .disabled: action = .disabled
      case .shortcut: action = ButtonAction(kind: .shortcut)
      case .button: action = .acts(as: button == 1 ? 2 : 1)
      }
    })
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      VStack(alignment: .leading, spacing: 2) {
        PanelTitle(name)
        Text("Button \(button)").font(.callout).foregroundStyle(.secondary)
      }

      Picker("Action", selection: kind) {
        Text("Normal").tag(ButtonAction.Kind.standard)
        Text("Shortcut").tag(ButtonAction.Kind.shortcut)
        Text("Button").tag(ButtonAction.Kind.button)
        Text("Off").tag(ButtonAction.Kind.disabled)
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .frame(maxWidth: .infinity)

      switch action.kind {
      case .standard:
        hint("Does what it normally does.")
      case .disabled:
        hint("Does nothing when pressed.")
      case .shortcut:
        ShortcutRecorder(action: $action)
        if let name = SystemShortcuts.turnedOff(for: action) {
          VStack(alignment: .leading, spacing: 8) {
            Label("\(name) is turned off in System Settings, so this won't do anything.",
                  systemImage: "exclamationmark.triangle.fill")
              .font(.callout).foregroundStyle(.orange)
              .fixedSize(horizontal: false, vertical: true)
            Button("Open Keyboard Shortcuts") {
              NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!)
            }
            .glassButton()
          }
        } else if SystemShortcuts.isReserved(action) {
          hint("This is a macOS shortcut. The mouse sends it like a keyboard would.")
        } else {
          hint("Click the field, then press the keys. Esc cancels. Shortcuts macOS keeps for itself, like ⌃←, can't be recorded: use Choose.")
        }
      case .button:
        Picker("Acts as", selection: Binding(get: { action.button ?? 1 }, set: { action = .acts(as: $0) })) {
          ForEach(1...Ignix.buttonCount, id: \.self) { target in
            Text(Ignix.buttonNames[target]!).tag(target)
          }
        }
      }

      if lockedOut {
        Label("No button sends Left click, so this one stays Left click until another does.",
              systemImage: "exclamationmark.triangle.fill")
          .font(.callout)
          .foregroundStyle(.orange)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(18)
    .frame(maxWidth: .infinity, alignment: .leading)
    .glassPanel()
  }

  private func hint(_ text: String) -> some View {
    Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
  }
}

/// Settings that apply to every button, and a place to try them.
struct OptionsPanel: View {
  @EnvironmentObject var model: Model

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Toggle(isOn: $model.config.onlyThisMouse) {
        VStack(alignment: .leading, spacing: 2) {
          Text("Only remap this mouse")
          Text(model.config.onlyThisMouse
               ? "Other mice and the trackpad keep their normal buttons."
               : "Every mouse and the trackpad use this mapping.")
            .font(.callout).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .toggleStyle(.switch)

      VStack(alignment: .leading, spacing: 6) {
        Text("Try it").font(.callout).foregroundStyle(.secondary)
        TestPad().frame(height: 56)
      }

      HStack {
        if let error = model.saveError {
          Text(error).font(.callout).foregroundStyle(.red)
        }
        Spacer()
        Button("Reset to defaults") { model.resetToDefaults() }
          .glassButton()
          .disabled(model.config == .defaults)
      }
    }
    .padding(18)
    .frame(maxWidth: .infinity, alignment: .leading)
    .glassPanel()
  }
}
