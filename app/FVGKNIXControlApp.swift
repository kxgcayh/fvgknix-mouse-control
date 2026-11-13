// FVGKNIX Control: settings window for the ignix-remap helper.
// It edits ~/Library/Application Support/IGNIX/config.json (see shared/IgnixConfig.swift) and tells the
// helper to reload. It needs no permissions itself; the helper does the remapping.

import AppKit
import SwiftUI

@main
struct FVGKNIXControlApp: App {
  @StateObject private var model = Model()

  var body: some Scene {
    Window("FVGKNIX Control", id: "main") {
      ContentView().environmentObject(model).preferredColorScheme(.dark)
    }
    .windowResizability(.contentMinSize)
    .defaultSize(width: 880, height: 640)
  }
}

// MARK: - Model

enum HelperState: Equatable {
  case running, needsAccessibility, needsInputMonitoring, stopped, notInstalled

  var text: String {
    switch self {
    case .running: "Helper running"
    case .needsAccessibility: "Helper waiting for Accessibility permission"
    case .needsInputMonitoring: "Helper can't tell this mouse apart: Input Monitoring is off"
    case .stopped: "Helper not running"
    case .notInstalled: "Helper not installed: run make helper in the source folder"
    }
  }
  var color: Color { self == .running ? .green : .orange }
}

@MainActor
final class Model: ObservableObject {
  @Published var config = IgnixConfig.load() {
    didSet { if config != oldValue { save() } }
  }
  @Published var helper: HelperState = .stopped
  @Published var status = IgnixStatus.load()
  @Published var saveError: String?
  private var timer: Timer?

  init() {
    dpiDraft = status.dpiValues
    refreshHelper()
    timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.refreshHelper() }
    }
  }

  func binding(for button: Int) -> Binding<ButtonAction> {
    Binding(get: { self.config.action(for: button) }, set: { self.config.set($0, for: button) })
  }

  func save() {
    do { try config.save(); saveError = nil } catch { saveError = "Couldn't save: \(error.localizedDescription)" }
  }

  func resetToDefaults() { config = .defaults }

  func restartHelper() {
    run("/bin/launchctl", ["kickstart", "-k", "gui/\(getuid())/\(Ignix.helperLabel)"])
    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.refreshHelper() }
  }

  /// Values being edited; nil until the helper has read the table. Follows the mouse until the user edits.
  @Published var dpiDraft: [Int]?
  @Published var pendingDPIRequest: UUID?
  @Published var dpiError: String?
  var backupDPI: [Int]? { DPIBackup.load()?.values }

  func sendDPI(_ values: [Int]) {
    let request = DPIRequest(values: values)
    do {
      try request.send()
      pendingDPIRequest = request.id
      dpiError = nil
    } catch {
      dpiError = "Couldn't send the request: \(error.localizedDescription)"
    }
  }

  func refreshHelper() {
    let latest = IgnixStatus.load()
    if latest != status {
      let followMouse = dpiDraft == nil || dpiDraft == status.dpiValues
      status = latest
      if followMouse { dpiDraft = latest.dpiValues }
      if let result = latest.dpiWrite, result.requestID == pendingDPIRequest {
        pendingDPIRequest = nil
        if result.ok { dpiDraft = latest.dpiValues }
      }
    }
    let home = FileManager.default.homeDirectoryForCurrentUser
    let plist = home.appendingPathComponent("Library/LaunchAgents/\(Ignix.helperLabel).plist")
    guard FileManager.default.fileExists(atPath: plist.path) else { helper = .notInstalled; return }
    let hasPID = run("/bin/launchctl", ["list", Ignix.helperLabel]).contains("\"PID\"")
    let log = (try? String(contentsOf: home.appendingPathComponent("Library/Logs/ignix-remap.log"), encoding: .utf8)) ?? ""
    // Only the lines since the helper last started (or tried to) describe its current state.
    let lines = log.split(separator: "\n").suffix(40)
    let sinceStart = lines.last(where: { $0.contains("ignix-remap running") || $0.contains("Waiting for Accessibility") })
      .flatMap { start in lines.lastIndex(of: start).map { Array(lines[$0...]) } } ?? []
    if sinceStart.first?.contains("Waiting for Accessibility") == true {
      helper = .needsAccessibility
    } else if !hasPID {
      helper = .stopped
    } else if config.onlyThisMouse && sinceStart.contains(where: { $0.contains("Grant Input Monitoring") }) {
      helper = .needsInputMonitoring
    } else {
      helper = .running
    }
  }

  @discardableResult
  private func run(_ path: String, _ args: [String]) -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = args
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = Pipe()
    guard (try? process.run()) != nil else { return "" }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return String(decoding: data, as: UTF8.self)
  }
}

func openPrivacyPane(_ pane: String) {
  NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!)
}

// MARK: - Window

enum Tab: String, CaseIterable {
  case mouse = "Mouse", buttons = "Buttons", helper = "Helper"
}

struct ContentView: View {
  @EnvironmentObject var model: Model
  @AppStorage("tab") private var tab = Tab.buttons

  var body: some View {
    // Each tab scrolls on its own, so the window can be any height.
    Group {
      switch tab {
      case .mouse: MouseView()
      case .buttons: ButtonsView()
      case .helper: HelperView()
      }
    }
    .frame(minWidth: 720, maxWidth: .infinity, minHeight: 520, maxHeight: .infinity)
    .background(WindowBackdrop().ignoresSafeArea())
    .toolbar {
      ToolbarItem(placement: .principal) {
        Picker("Section", selection: $tab) {
          ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
      }
      HelperStatusItem(tab: $tab)
    }
  }
}

/// The helper's state at the right of the toolbar. Its right edge lines up with the content's padding.
struct HelperStatusItem: ToolbarContent {
  @EnvironmentObject var model: Model
  @Binding var tab: Tab

  private var button: some View {
    Button { tab = .helper } label: {
      Label {
        Text(model.helper == .running ? "Helper running" : "Helper needs attention")
      } icon: {
        Image(systemName: model.helper == .running ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
          .foregroundStyle(model.helper.color)
      }
      .labelStyle(.titleAndIcon)
    }
    .help(model.helper.text)
  }

  var body: some ToolbarContent {
    if #available(macOS 26.0, *) {
      // The toolbar keeps its own edge inset; drawing the capsule ourselves lets the trailing space
      // make up the rest of Theme.pad.
      ToolbarItem(placement: .primaryAction) {
        button
          .buttonStyle(.plain)
          .padding(.horizontal, 12)
          .padding(.vertical, 6)
          .glassEffect(.regular, in: .capsule)
          .padding(.trailing, Theme.pad - 4)
      }
      .sharedBackgroundVisibility(.hidden)
    } else {
      ToolbarItem(placement: .primaryAction) { button }
    }
  }
}
