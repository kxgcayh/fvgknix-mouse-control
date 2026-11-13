// ignix-probe: read-only look at the IGNIX receiver's config interface (usage page 1 / usage 0x80).
// Nothing is ever written to the mouse. See docs/protocol.md for what the bytes mean.
//
//   ignix-probe              print input reports as they arrive (battery and DPI-level events, report 3)
//   ignix-probe --features   GET_REPORT every feature report the descriptor declares. Not useful in practice:
//                            the receiver returns a stale USB buffer whatever id is asked for.
//
// Build: make probe (or swiftc -O tools/probe.swift -o build/ignix-probe). Needs Input Monitoring for the terminal.

import Foundation
import IOKit.hid

let vendorID = 0x1D57
let productID = 0xFA60
let featureReports: [(id: UInt8, size: Int)] = [
  (0x04, 55), (0x05, 14), (0x06, 8), (0x07, 7), (0x08, 58), (0x09, 63),
  (0x0A, 7), (0x0B, 7), (0x0C, 9), (0x10, 7), (0xA0, 7), (0x22, 63),
]

func hex<S: Sequence>(_ bytes: S) -> String where S.Element == UInt8 {
  bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
}

func stamp() -> String {
  let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f.string(from: Date())
}

/// Report 3 payload: [device id, kind, a, b]. 0x40/0x41 = status (a = battery status, b = level %),
/// 0x10 = DPI level changed on the mouse (a = level).
func describe(_ id: UInt32, _ payload: [UInt8]) -> String {
  guard id == 3, payload.count >= 4 else { return "" }
  switch payload[1] {
  case 0x40, 0x41: return "status: device \(payload[0]), battery status \(payload[2]), level \(payload[3])%"
  case 0x10: return "DPI level -> \(payload[2])"
  default: return "unknown kind 0x\(String(format: "%02x", payload[1]))"
  }
}

let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
IOHIDManagerSetDeviceMatching(manager, [
  kIOHIDVendorIDKey: vendorID, kIOHIDProductIDKey: productID,
  kIOHIDPrimaryUsagePageKey: 1, kIOHIDPrimaryUsageKey: 0x80,
] as CFDictionary)
let opened = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
guard let device = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>)?.first else {
  print("IGNIX config interface not found (open: 0x\(String(UInt32(bitPattern: opened), radix: 16)))")
  exit(1)
}
if opened != kIOReturnSuccess {
  print("Can't open the receiver (0x\(String(UInt32(bitPattern: opened), radix: 16))). Grant Input Monitoring to the terminal.")
  exit(1)
}

/// Read commands the vendor's Windows driver uses: report id -> length
/// including the id byte. Only these are allowed, so the probe can't send anything else.
let readCommands: [UInt8: Int] = [0x04: 0x38, 0x05: 0x0F, 0x06: 0x09, 0x08: 0x3B, 0x0B: 0x08, 0x0C: 0x0A]

/// Read request: SetReport(feature 0xA0, [a0 cmd len 00 00 00 00 00]), poll report 0xA0 until byte 1 is 01,
/// then GetReport(feature cmd, len). This is a read: it asks the mouse to stage data, nothing is stored.
func readSetting(_ cmd: UInt8) -> [UInt8]? {
  guard let length = readCommands[cmd] else { return nil }
  for attempt in 1...3 {
    if let data = readOnce(cmd, length) { return data }
    print("  attempt \(attempt): mouse didn't report ready")
    usleep(500_000)
  }
  return nil
}

func readOnce(_ cmd: UInt8, _ length: Int) -> [UInt8]? {
  usleep(100_000) // the Windows driver waits 100 ms before each request
  var request: [UInt8] = [0xA0, cmd, UInt8(length), 0, 0, 0, 0, 0]
  var sent = kIOReturnError
  for _ in 0..<10 {
    sent = IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, 0xA0, &request, request.count)
    if sent == kIOReturnSuccess { break }
    usleep(500_000)
  }
  guard sent == kIOReturnSuccess else { print("request failed: 0x\(String(UInt32(bitPattern: sent), radix: 16))"); return nil }
  // Without a ready status the cmd report holds a stale buffer, so don't return it.
  var ready = false
  for _ in 0..<10 {
    usleep(100_000)
    var status = [UInt8](repeating: 0, count: 8)
    status[0] = 0xA0
    var statusLength = CFIndex(status.count)
    if IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 0xA0, &status, &statusLength) == kIOReturnSuccess,
       status.count > 1, status[0] == 0xA0, status[1] == 1 {
      ready = true
      break
    }
  }
  guard ready else { return nil }
  var data = [UInt8](repeating: 0, count: length)
  data[0] = cmd
  var dataLength = CFIndex(length)
  let result = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, CFIndex(cmd), &data, &dataLength)
  guard result == kIOReturnSuccess else { print("read failed: 0x\(String(UInt32(bitPattern: result), radix: 16))"); return nil }
  // A real reply starts with its own report id and length.
  guard data[0] == cmd, data.count > 1, data[1] == UInt8(length) else { return nil }
  return Array(data.prefix(dataLength))
}

if let index = CommandLine.arguments.firstIndex(of: "--read"), index + 1 < CommandLine.arguments.count {
  let arg = CommandLine.arguments[index + 1]
  guard let cmd = UInt8(arg.replacingOccurrences(of: "0x", with: ""), radix: 16), readCommands[cmd] != nil else {
    print("--read takes one of: \(readCommands.keys.sorted().map { String(format: "%02x", $0) }.joined(separator: " "))")
    exit(1)
  }
  if let data = readSetting(cmd) { print("0x\(String(format: "%02X", cmd)) (\(data.count) bytes): \(hex(data))") }
  exit(0)
}

if CommandLine.arguments.contains("--features") {
  for (id, size) in featureReports {
    var buffer = [UInt8](repeating: 0, count: size + 1)
    buffer[0] = id
    var length = CFIndex(buffer.count)
    let result = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, CFIndex(id), &buffer, &length)
    let text = result == kIOReturnSuccess ? hex(buffer.prefix(length)) : "error 0x\(String(UInt32(bitPattern: result), radix: 16))"
    print("0x\(String(format: "%02X", id)) (\(size) bytes): \(text)")
  }
  exit(0)
}

let reportBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
IOHIDDeviceRegisterInputReportCallback(device, reportBuffer, 64, { _, _, _, _, reportID, report, length in
  // The buffer holds the report id first when the device uses ids.
  let bytes = Array(UnsafeBufferPointer(start: report, count: length))
  let payload = bytes.first == UInt8(truncatingIfNeeded: reportID) ? Array(bytes.dropFirst()) : bytes
  print("\(stamp()) report \(reportID): \(hex(payload))  \(describe(reportID, payload))")
  fflush(stdout)
}, nil)
IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
print("\(stamp()) listening on the config interface (Ctrl+C to stop)")
fflush(stdout)
CFRunLoopRun()
