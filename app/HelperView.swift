// Helper tab: what the background helper needs, as a checklist, with the button that fixes each item.

import SwiftUI

struct HelperView: View {
  @EnvironmentObject var model: Model

  private enum Check { case ok, failed, unknown }

  private var installed: Check { model.helper == .notInstalled ? .failed : .ok }
  private var running: Check {
    switch model.helper {
    case .running, .needsInputMonitoring: .ok
    case .needsAccessibility: .unknown   // launched, but it waits for the permission before doing anything
    case .stopped: .failed
    case .notInstalled: .unknown
    }
  }
  private var accessibility: Check {
    switch model.helper {
    case .running, .needsInputMonitoring: .ok
    case .needsAccessibility: .failed
    case .stopped, .notInstalled: .unknown
    }
  }
  private var inputMonitoring: Check {
    switch model.helper {
    case .needsInputMonitoring: return .failed
    case .running:
      // Hearing the mouse proves it; otherwise it's only checked when "Only remap this mouse" is on.
      return model.status.lastSeen != nil || model.config.onlyThisMouse ? .ok : .unknown
    default: return .unknown
    }
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Theme.gap) {
        VStack(alignment: .leading, spacing: 0) {
          VStack(alignment: .leading, spacing: 2) {
            PanelTitle(model.helper.text)
            Text("The helper runs in the background. It remaps the buttons and talks to the mouse; this app only changes its settings.")
              .font(.callout).foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }
          .padding(.bottom, 12)

          row("Installed", installed, failed: "Run make helper in the source folder.")
          Divider()
          row("Running", running, failed: "It should start by itself at login.") {
            if model.helper != .notInstalled {
              Button("Restart helper") { model.restartHelper() }.glassButton()
            }
          }
          Divider()
          row("Accessibility", accessibility, ok: "Lets it change button presses.",
              failed: "Needed to change button presses. Turn on ignix-remap, then restart the helper.") {
            Button("Open settings") { openPrivacyPane("Privacy_Accessibility") }.glassButton()
          }
          Divider()
          row("Input Monitoring", inputMonitoring, ok: "Lets it hear the mouse: battery, DPI and which mouse was pressed.",
              failed: "Needed to hear the mouse. Turn on ignix-remap, then restart the helper.") {
            Button("Open settings") { openPrivacyPane("Privacy_ListenEvent") }.glassButton()
          }
        }
        .padding(18)
        .glassPanel()

        Text("If a permission looks on but isn't working, remove ignix-remap from that list and add ~/.local/bin/ignix-remap again. macOS forgets it when the helper is rebuilt.")
          .font(.callout).foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
          .padding(.horizontal, 18)
      }
      .padding(Theme.pad)
      .frame(maxWidth: 680)
      .frame(maxWidth: .infinity)
    }
  }

  private func row(_ title: String, _ check: Check, ok: String? = nil, failed: String,
                   @ViewBuilder action: () -> some View = { EmptyView() }) -> some View {
    HStack(spacing: 12) {
      Group {
        switch check {
        case .ok: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .unknown: Image(systemName: "minus.circle").foregroundStyle(.secondary)
        }
      }
      .font(.title3)
      .frame(width: 24)
      .accessibilityLabel(check == .ok ? "OK" : check == .failed ? "Needs attention" : "Not checked")

      VStack(alignment: .leading, spacing: 2) {
        Text(title)
        if let detail = check == .failed ? failed : (check == .ok ? ok : "Can't be checked until the items above are fixed.") {
          Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
      }
      Spacer(minLength: 12)
      action()
    }
    .padding(.vertical, 10)
  }
}
