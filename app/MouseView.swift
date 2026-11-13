// Mouse tab: battery, current sensitivity and the DPI levels stored in the mouse.

import AppKit
import SwiftUI

struct MouseView: View {
  @EnvironmentObject var model: Model

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Theme.pad) {
        // Re-checked on a timer: "asleep" depends on how long ago the mouse was last heard.
        TimelineView(.periodic(from: .now, by: 10)) { context in
          MouseReadouts(status: model.status, now: context.date)
        }
        DPIPanel()
      }
      .padding(Theme.pad)
      .frame(maxWidth: 780)
      .frame(maxWidth: .infinity)
    }
    // Don't open with a DPI field already focused and its number selected.
    .onAppear { DispatchQueue.main.async { NSApp.keyWindow?.makeFirstResponder(nil) } }
  }
}

struct MouseReadouts: View {
  let status: IgnixStatus
  let now: Date

  /// The mouse reports every 2 seconds while awake; after a minute of silence it's asleep, off or out of range.
  private var asleep: Bool { status.lastSeen.map { now.timeIntervalSince($0) > 60 } ?? true }

  private var batterySymbol: String {
    switch status.batteryLevel ?? 0 {
    case 88...: "battery.100percent"
    case 63..<88: "battery.75percent"
    case 38..<63: "battery.50percent"
    case 13..<38: "battery.25percent"
    default: "battery.0percent"
    }
  }

  private var connection: String {
    guard let seen = status.lastSeen else { return "Waiting for the mouse. The helper needs Input Monitoring to hear it." }
    return asleep ? "Asleep, off or out of range. Last heard \(seen.formatted(.relative(presentation: .named)))." : "Connected"
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline, spacing: 44) {
        readout(title: "Battery",
                value: status.batteryLevel.map { "\($0)%" } ?? "–",
                symbol: batterySymbol,
                tint: (status.batteryLevel ?? 100) <= 15 ? .red : .primary)
        readout(title: "Sensitivity",
                value: status.currentDPI.map { "\(String($0)) DPI" } ?? "–",
                symbol: "scope",
                tint: .primary,
                detail: status.dpiLevel.map { level in
                  status.dpiValues.map { "Level \(level) of \($0.count)" } ?? "Level \(level)"
                } ?? "Press the mouse's DPI button once to show it")
      }
      Label(connection, systemImage: asleep ? "moon.zzz" : "dot.radiowaves.left.and.right")
        .font(.callout)
        .foregroundStyle(.secondary)
    }
    .opacity(asleep && status.lastSeen != nil ? 0.75 : 1)
  }

  private func readout(title: String, value: String, symbol: String, tint: Color, detail: String? = nil) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(title).font(.callout).foregroundStyle(.secondary)
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Image(systemName: symbol).font(.title2).symbolRenderingMode(.hierarchical).foregroundStyle(tint)
        Text(value).font(.system(size: 34, weight: .semibold)).monospacedDigit().foregroundStyle(tint)
      }
      if let detail {
        Text(detail).font(.callout).foregroundStyle(.secondary)
      }
    }
    .accessibilityElement(children: .combine)
  }
}

/// Edits the DPI of each level. The helper writes the table to the mouse and reads it back to verify.
struct DPIPanel: View {
  @EnvironmentObject var model: Model

  private var saved: [Int]? { model.status.dpiValues }
  private var draft: [Int] { model.dpiDraft ?? [] }
  private var changed: Bool { model.dpiDraft != nil && model.dpiDraft != saved }
  private var valid: Bool { !draft.isEmpty && draft.allSatisfy(DPITable.isValid) }
  private var busy: Bool { model.pendingDPIRequest != nil }

  private func binding(_ index: Int) -> Binding<Int> {
    Binding(get: { model.dpiDraft?[index] ?? 0 }, set: { model.dpiDraft?[index] = $0 })
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      VStack(alignment: .leading, spacing: 2) {
        PanelTitle("DPI levels")
        Text("The mouse's DPI button cycles through these. They're stored in the mouse, so they work on any computer.")
          .font(.callout).foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      if saved == nil {
        HStack(spacing: 8) {
          ProgressView().controlSize(.small)
          Text("Reading the levels from the mouse. Move it if it's asleep.").foregroundStyle(.secondary)
        }
        .padding(.vertical, 12)
      } else {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
          ForEach(draft.indices, id: \.self) { index in
            DPICell(level: index + 1, value: binding(index),
                    current: model.status.dpiLevel == index + 1,
                    valid: DPITable.isValid(draft[index]))
          }
        }
        .disabled(busy)

        if !valid {
          Label("Use \(String(DPITable.minDPI)) to \(String(DPITable.maxDPI)), in steps of \(DPITable.step).",
                systemImage: "exclamationmark.triangle.fill")
            .font(.callout).foregroundStyle(.red)
        }

        HStack(spacing: 10) {
          result
          Spacer()
          if let backup = model.backupDPI, backup != saved {
            Button("Restore original") { model.sendDPI(backup) }
              .glassButton()
              .disabled(busy)
              .help("Write back the levels first read from the mouse: \(backup.map(String.init).joined(separator: " / "))")
          }
          Button("Revert") { model.dpiDraft = saved }
            .glassButton()
            .disabled(!changed || busy)
          Button("Save to mouse") { model.sendDPI(draft) }
            .glassButton(prominent: true)
            .keyboardShortcut(.defaultAction)
            .disabled(!changed || !valid || busy)
        }
      }
    }
    .padding(18)
    .frame(maxWidth: .infinity, alignment: .leading)
    .glassPanel()
  }

  @ViewBuilder
  private var result: some View {
    if busy {
      ProgressView().controlSize(.small)
      Text("Writing to the mouse…").foregroundStyle(.secondary)
    } else if let error = model.dpiError {
      Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
    } else if let result = model.status.dpiWrite, Date().timeIntervalSince(result.time) < 120 {
      Label(result.message, systemImage: result.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
        .foregroundStyle(result.ok ? Color.green : Color.red)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}

private struct DPICell: View {
  let level: Int
  @Binding var value: Int
  let current: Bool
  let valid: Bool

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: Theme.cellRadius, style: .continuous)
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text("Level \(level)").font(.callout).foregroundStyle(.secondary)
        Spacer()
        if current {
          Text("In use").font(.caption.weight(.semibold))
        }
      }
      HStack(spacing: 6) {
        TextField("DPI for level \(level)", value: $value, format: .number.grouping(.never))
          .textFieldStyle(.plain)
          .font(.title3.weight(.medium).monospacedDigit())
          .foregroundStyle(valid ? Color.primary : Color.red)
        Stepper("DPI for level \(level)", value: $value, in: DPITable.minDPI...DPITable.maxDPI, step: 100)
          .labelsHidden()
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .background(current ? AnyShapeStyle(Color.accentColor.opacity(0.3)) : AnyShapeStyle(Theme.cellFill), in: shape)
    .overlay(shape.strokeBorder(valid ? (current ? Color.accentColor : Theme.hairline) : Color.red))
  }
}
