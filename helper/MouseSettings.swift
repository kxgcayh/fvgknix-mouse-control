// Reads and writes the mouse's onboard settings over the receiver's config interface (see docs/protocol.md).
// Everything runs on `deviceQueue`, including status updates, so reads, writes and report-3 events never interleave.

import Foundation
import IOKit.hid

let deviceQueue = DispatchQueue(label: "ignix.device")
/// The receiver's config interface (usage 0x80), set when it's matched. Only touched on deviceQueue.
var configDevice: IOHIDDevice?

/// Read request from the vendor's Windows driver: SetReport(0xA0, [a0 cmd len 0…]), wait for `a0 01`,
/// then GetReport(cmd). The first request after a pause usually doesn't become ready, so retry.
func readSetting(_ cmd: UInt8, length: Int) -> [UInt8]? {
  guard let device = configDevice else { return nil }
  for _ in 1...3 {
    usleep(100_000)
    var request: [UInt8] = [0xA0, cmd, UInt8(length), 0, 0, 0, 0, 0]
    guard IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, 0xA0, &request, request.count) == kIOReturnSuccess
    else { usleep(500_000); continue }
    var ready = false
    for _ in 0..<10 {
      usleep(100_000)
      var status = [UInt8](repeating: 0, count: 8)
      status[0] = 0xA0
      var statusLength = CFIndex(status.count)
      if IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 0xA0, &status, &statusLength) == kIOReturnSuccess,
         status[0] == 0xA0, status[1] == 1 {
        ready = true
        break
      }
    }
    guard ready else { usleep(500_000); continue }
    var data = [UInt8](repeating: 0, count: length)
    data[0] = cmd
    var dataLength = CFIndex(length)
    if IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, CFIndex(cmd), &data, &dataLength) == kIOReturnSuccess,
       data[0] == cmd, data[1] == UInt8(length) {
      return data
    }
  }
  return nil
}

func readDPITable() -> DPITable? {
  readSetting(DPITable.reportID, length: DPITable.length).flatMap(DPITable.init(reply:))
}

/// Reads the table into the status, and keeps the first table ever read as the backup.
@discardableResult
func refreshDPI() -> DPITable? {
  guard let table = readDPITable() else { log("Couldn't read the DPI table"); return nil }
  DPIBackup.saveIfMissing(table)
  status.dpiValues = table.values
  status.dpiLevel = table.currentLevel
  status.save()
  log("DPI table \(table.values.map(String.init).joined(separator: "/")), level \(table.currentLevel)")
  return table
}

/// Writes new DPI values, then reads the table back and only reports success if it matches.
func writeDPI(_ request: DPIRequest) {
  func finish(_ ok: Bool, _ message: String) {
    log("DPI write: \(message)")
    status.dpiWrite = .init(requestID: request.id, ok: ok, message: message, time: Date())
    status.save()
  }
  guard let device = configDevice else { return finish(false, "The mouse's receiver isn't connected.") }
  guard let current = refreshDPI() else { return finish(false, "Couldn't read the current DPI table, so nothing was written.") }
  guard var frame = current.writeFrame(values: request.values) else {
    return finish(false, "Invalid values: \(current.enabledCount) levels of \(DPITable.minDPI)–\(DPITable.maxDPI) DPI, in steps of \(DPITable.step).")
  }
  if current.values == request.values { return finish(true, "Already set.") }
  for attempt in 1...3 {
    let result = IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, CFIndex(DPITable.reportID), &frame, frame.count)
    usleep(500_000)
    if result == kIOReturnSuccess, let after = refreshDPI(), after.values == request.values {
      return finish(true, "Saved to the mouse and verified.")
    }
    log("DPI write attempt \(attempt) not confirmed (IOReturn 0x\(String(UInt32(bitPattern: result), radix: 16)))")
  }
  finish(false, "The mouse didn't confirm the new values. Its table is unchanged or partly changed; read it again before retrying.")
}
