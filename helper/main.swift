// ignix-remap: applies the button mapping from ~/Library/Application Support/IGNIX/config.json
// (edited by the FVGKNIX Control app, see shared/IgnixConfig.swift) to the IGNIX mouse.
//
// An event tap rewrites or swallows mouse clicks and posts key presses for shortcuts.
// A HID listener on its own thread tracks which buttons are held on the IGNIX receiver, so with
// "only this mouse" on, other mice and the trackpad keep their normal buttons.
// The app posts a Darwin notification after saving, and the helper reloads the file.
//
// Needs Accessibility (event tap) and Input Monitoring (HID listener).

import ApplicationServices
import Foundation
import IOKit.hid

let vendorID = 0x1D57
let productID = 0xFA60

func log(_ message: String) {
  FileHandle.standardError.write("\(Date()) \(message)\n".data(using: .utf8)!)
}

// MARK: - Config

var config = IgnixConfig.defaults

func describe(_ config: IgnixConfig) -> String {
  let parts = (1...Ignix.buttonCount).compactMap { n -> String? in
    let action = config.action(for: n)
    switch action.kind {
    case .standard: return nil
    case .disabled: return "button \(n) off"
    case .shortcut: return "button \(n) -> \(action.shortcutText)"
    case .button: return "button \(n) -> button \(action.button ?? 0)"
    }
  }
  return (parts.isEmpty ? "no remaps" : parts.joined(separator: ", "))
    + (config.onlyThisMouse ? "" : " (all mice)")
}

func reloadConfig() {
  let loaded = IgnixConfig.load()
  if !loaded.keepsLeftClick { log("No button sends Left click, so button 1 stays Left click.") }
  config = loaded.effective
  log("Mapping: \(describe(config))")
}

// MARK: - Which buttons are held on the IGNIX receiver

final class HeldButtons: @unchecked Sendable {
  private var lock = os_unfair_lock()
  private var held = Set<Int64>()

  func set(_ button: Int64, down: Bool) {
    os_unfair_lock_lock(&lock); defer { os_unfair_lock_unlock(&lock) }
    if down { held.insert(button) } else { held.remove(button) }
  }
  func contains(_ button: Int64) -> Bool {
    os_unfair_lock_lock(&lock); defer { os_unfair_lock_unlock(&lock) }
    return held.contains(button)
  }
}

let held = HeldButtons()

// MARK: - Battery and DPI level (input report 3 on the config interface, see docs/protocol.md)

/// Only touched on deviceQueue (helper/MouseSettings.swift).
var status = IgnixStatus.load()
var lastStatusWrite = Date.distantPast
let configUsage = 0x80
let statusReportBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)

func handleStatusReport(_ id: UInt32, _ bytes: [UInt8]) {
  // The buffer starts with the report id. Payload: [device id, kind, a, b].
  let payload = bytes.first == UInt8(truncatingIfNeeded: id) ? Array(bytes.dropFirst()) : bytes
  guard id == 3, payload.count >= 4 else { return }
  var next = status
  switch payload[1] {
  case 0x40, 0x41: next.batteryStatus = Int(payload[2]); next.batteryLevel = Int(payload[3])
  case 0x10: next.dpiLevel = Int(payload[2])
  default: return
  }
  let now = Date()
  next.lastSeen = now
  // The mouse repeats its status every 2 s; write on a change, else refresh lastSeen every 30 s.
  var unchanged = next
  unchanged.lastSeen = status.lastSeen
  if unchanged == status && now.timeIntervalSince(lastStatusWrite) < 30 { return }
  if next.dpiLevel != status.dpiLevel { log("DPI level \(next.dpiLevel ?? 0)") }
  status = next
  lastStatusWrite = now
  status.save()
}

func startHIDListener() {
  let thread = Thread {
    let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    IOHIDManagerSetDeviceMatchingMultiple(manager, [
      [kIOHIDVendorIDKey: vendorID, kIOHIDProductIDKey: productID,
       kIOHIDPrimaryUsagePageKey: kHIDPage_GenericDesktop, kIOHIDPrimaryUsageKey: kHIDUsage_GD_Mouse],
      [kIOHIDVendorIDKey: vendorID, kIOHIDProductIDKey: productID,
       kIOHIDPrimaryUsagePageKey: kHIDPage_GenericDesktop, kIOHIDPrimaryUsageKey: configUsage],
    ] as CFArray)
    IOHIDManagerRegisterDeviceMatchingCallback(manager, { _, _, _, device in
      let usage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsageKey as CFString) as? Int
      guard usage == configUsage else { log("IGNIX receiver connected"); return }
      IOHIDDeviceRegisterInputReportCallback(device, statusReportBuffer, 64, { _, _, _, _, id, report, length in
        let bytes = Array(UnsafeBufferPointer(start: report, count: length))
        deviceQueue.async { handleStatusReport(id, bytes) }
      }, nil)
      deviceQueue.async {
        configDevice = device
        sleep(1) // let the receiver settle after connecting
        refreshDPI()
      }
    }, nil)
    IOHIDManagerRegisterInputValueCallback(manager, { _, _, _, value in
      let element = IOHIDValueGetElement(value)
      guard IOHIDElementGetUsagePage(element) == UInt32(kHIDPage_Button) else { return }
      // HID buttons are 1-based; macOS button numbers are 0-based.
      held.set(Int64(IOHIDElementGetUsage(element)) - 1, down: IOHIDValueGetIntegerValue(value) != 0)
    }, nil)
    IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
    let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    if result != kIOReturnSuccess {
      log("Can't read the IGNIX receiver (IOReturn \(result)). Grant Input Monitoring, or turn off \"only this mouse\".")
    }
    CFRunLoopRun()
  }
  thread.name = "hid"
  thread.start()
}

// The HID report and the CGEvent arrive on different paths, so give the HID side a moment to catch up.
func pressCameFromIGNIX(_ button: Int64) -> Bool {
  if !config.onlyThisMouse { return true }
  let deadline = Date().addingTimeInterval(0.03)
  repeat {
    if held.contains(button) { return true }
    usleep(1000)
  } while Date() < deadline
  return false
}

// MARK: - Event tap

enum Phase { case down, up, dragged }

func phase(of type: CGEventType) -> Phase? {
  switch type {
  case .leftMouseDown, .rightMouseDown, .otherMouseDown: .down
  case .leftMouseUp, .rightMouseUp, .otherMouseUp: .up
  case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged: .dragged
  default: nil
  }
}

/// The event type for `phase` on a 0-based macOS button number.
func eventType(_ phase: Phase, button: Int64) -> CGEventType {
  switch (phase, button) {
  case (.down, 0): .leftMouseDown
  case (.up, 0): .leftMouseUp
  case (.dragged, 0): .leftMouseDragged
  case (.down, 1): .rightMouseDown
  case (.up, 1): .rightMouseUp
  case (.dragged, 1): .rightMouseDragged
  case (.down, _): .otherMouseDown
  case (.up, _): .otherMouseUp
  case (.dragged, _): .otherMouseDragged
  }
}

let keySource = CGEventSource(stateID: .hidSystemState)
/// Buttons whose press was remapped, with the action used, so the release and drags follow it
/// even if the config reloads mid-press.
var active: [Int64: ButtonAction] = [:]
var tap: CFMachPort?

func flags(for action: ButtonAction) -> CGEventFlags {
  var flags: CGEventFlags = []
  for modifier in action.modifiers ?? [] {
    switch modifier {
    case .control: flags.insert(.maskControl)
    case .option: flags.insert(.maskAlternate)
    case .shift: flags.insert(.maskShift)
    case .command: flags.insert(.maskCommand)
    }
  }
  // Real arrow keys carry the fn and numeric-pad flags, and Mission Control's Space shortcuts expect them.
  // Other navigation and function keys carry fn.
  let key = action.keyCode ?? 0
  if (0x7B...0x7E).contains(key) { flags.formUnion([.maskSecondaryFn, .maskNumericPad]) }
  let fnKeys: Set<UInt16> = [0x73, 0x77, 0x74, 0x79, 0x75, 0x72, // home end pgup pgdn fwd-delete help
    0x7A, 0x78, 0x63, 0x76, 0x60, 0x61, 0x62, 0x64, 0x65, 0x6D, 0x67, 0x6F] // F1-F12
  if fnKeys.contains(key) { flags.insert(.maskSecondaryFn) }
  return flags
}

func postKey(_ action: ButtonAction, down: Bool) {
  guard let key = action.keyCode else { return }
  let event = CGEvent(keyboardEventSource: keySource, virtualKey: key, keyDown: down)
  event?.flags = flags(for: action)
  event?.post(tap: .cghidEventTap)
}

let callback: CGEventTapCallBack = { _, type, event, _ in
  if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
    if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
    return Unmanaged.passUnretained(event)
  }
  guard let phase = phase(of: type) else { return Unmanaged.passUnretained(event) }
  let button = event.getIntegerValueField(.mouseEventButtonNumber)

  let action: ButtonAction
  if phase == .down {
    let configured = config.action(for: Int(button) + 1)
    guard configured.kind != .standard, pressCameFromIGNIX(button) else { return Unmanaged.passUnretained(event) }
    action = configured
    active[button] = action
  } else {
    guard let current = active[button] else { return Unmanaged.passUnretained(event) }
    action = current
    if phase == .up { active[button] = nil }
  }

  switch action.kind {
  case .standard:
    return Unmanaged.passUnretained(event)
  case .disabled:
    return nil
  case .shortcut:
    if phase != .dragged { postKey(action, down: phase == .down) }
    return nil
  case .button:
    // Rewrite the click in place, so it keeps its position and click count.
    let target = Int64((action.button ?? 1) - 1)
    event.type = eventType(phase, button: target)
    event.setIntegerValueField(.mouseEventButtonNumber, value: target)
    return Unmanaged.passUnretained(event)
  }
}

// MARK: - Start

// Show the system prompt once per install (scripts/install-helper.sh deletes the stamp), not on every launchd restart.
let promptStamp = NSHomeDirectory() + "/Library/Caches/ignix-remap.prompted"
let shouldPrompt = !FileManager.default.fileExists(atPath: promptStamp)
let trusted = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): shouldPrompt] as CFDictionary)
// A running process doesn't see a permission granted after it started, so exit and let launchd
// restart it (ThrottleInterval 10s) until the grant takes effect.
if !trusted {
  if shouldPrompt { FileManager.default.createFile(atPath: promptStamp, contents: nil) }
  log("Waiting for Accessibility permission (System Settings > Privacy & Security > Accessibility).")
  sleep(5)
  exit(1)
}

var mask: UInt64 = 0
for type: CGEventType in [.leftMouseDown, .leftMouseUp, .leftMouseDragged,
                          .rightMouseDown, .rightMouseUp, .rightMouseDragged,
                          .otherMouseDown, .otherMouseUp, .otherMouseDragged] {
  mask |= 1 << type.rawValue
}
guard let created = CGEvent.tapCreate(
  tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
  eventsOfInterest: mask, callback: callback, userInfo: nil)
else {
  log("Couldn't create the event tap. Check Accessibility permission.")
  exit(1)
}
tap = created

CFNotificationCenterAddObserver(
  CFNotificationCenterGetDarwinNotifyCenter(), nil, { _, _, _, _, _ in reloadConfig() },
  Ignix.reloadNotification as CFString, nil, .deliverImmediately)
CFNotificationCenterAddObserver(
  CFNotificationCenterGetDarwinNotifyCenter(), nil, { _, _, _, _, _ in
    deviceQueue.async { if let request = DPIRequest.take() { writeDPI(request) } }
  },
  DPIRequest.notification as CFString, nil, .deliverImmediately)

startHIDListener()
CFRunLoopAddSource(CFRunLoopGetCurrent(), CFMachPortCreateRunLoopSource(nil, created, 0), .commonModes)
CGEvent.tapEnable(tap: created, enable: true)
log("ignix-remap running")
reloadConfig()
CFRunLoopRun()
