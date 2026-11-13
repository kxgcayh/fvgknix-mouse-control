# IGNIX receiver protocol notes

Captured on Nov 13, 2026 with read-only tools: nothing was written to the mouse's settings.
Receiver: LXDDZ "2.4G Wireless Device", vendor id 0x1D57, product id 0xFA60. The mouse reports itself as device 174 (0xAE).

## Tools

| Tool | What it does |
| --- | --- |
| `build/ignix-probe` (`tools/probe.swift`) | Prints the config interface's input reports straight from the mouse, no driver. `--features` dumps the feature reports. |
| `node tools/driver-read.mjs` | Talks to WebDriver For Mac on `127.0.0.1:10086` and sends only the site's read requests (`0xF0 …`). `--listen` sends nothing. |

Build the probe with `make probe`. The terminal needs Input Monitoring.

## HID interfaces

The receiver has four HID interfaces. Only the config interface carries vendor data.

| Usage page / usage | What it is |
| --- | --- |
| 1 / 2 | Mouse: 5 buttons, 16-bit X and Y, wheel, pan. 7-byte input report, no report id. |
| 1 / 6 (two) | Keyboards, used for keyboard-shortcut buttons |
| 1 / 0x80 | **Config interface**: report ids 1 (system control), 2 (consumer), 3 (4-byte vendor input), and feature reports 4–0x0C, 0x10, 0xA0, 0x22 (7–63 bytes) |

## Battery and DPI level: input report 3 (known)

The mouse sends input report 3 on the config interface by itself. No driver and no request are needed.

| Payload | Meaning | When |
| --- | --- | --- |
| `ae 41 01 59` | Status: device 0xAE, kind 0x41, battery status 1, battery **89%** | Every 2 seconds |
| `ae 10 03 00` | DPI level changed on the mouse, now level 3 | On each press of the mouse's DPI button |

- Kind 0x40 or 0x41 is a status report; the vendor site treats both the same. The meaning of battery status values (1 here, while not charging) is unconfirmed; the site defaults it to 2.
- Three DPI-button presses gave levels 3, 4 and 5. How levels map to DPI values isn't known yet: that table is stored in the mouse.

## Feature reports: GET_REPORT is useless

GET_REPORT on any feature id returns the same stale USB control buffer. Its contents change over time and once held the receiver's name string ("LXDDZ 2.4G Wire…"). The settings can't be read this way.

## Vendor site ↔ driver frames (from the site's code and live capture)

Frames are hex strings over a WebSocket. `conn` is 0x80 wired, 0x81 2.4 GHz, 0x82–0x85 other modes.

| Direction | Frame | Meaning |
| --- | --- | --- |
| driver → site | `conn 01 <HID report>` | The driver relays HID reports as is: mouse movement, and report 3 above (`81 01 03 ae 41 01 59`). |
| site → driver | `f0 conn dev cmd 00` | Read request. cmd 0x0B version, 0x0A whole profile, 0x04 DPI, 0x06 report rate, 0x05 lighting, 0x08 buttons. |
| driver → site | `conn dev cmd …` | Reply to a read. **None came back for device 174.** |
| driver → site | `conn dev 50 00 00` / `… 50 01 00` | Write acknowledged / failed |

Driver quirks: Node's built-in WebSocket can't connect, and the driver sometimes sends a data frame before its handshake reply.

## Unknowns

- ~~How a read request reaches the mouse.~~ Solved; see "Reading settings" below. WebDriver For Mac never sends read requests: it drops them, so the read format came from how the vendor's Windows driver behaves.
- ~~Which sensor device 174 has.~~ Not needed: this firmware stores plain DPI numbers (see below).
- The onboard button map (report 0x08).

The write side is known; see below.

## DPI write (decoded from the site's code and the driver binary)

The site builds a 60-byte DPI frame and prefixes `conn dev`. The driver drops that prefix and sends the rest as
**feature report 0x04** with `IOHIDDeviceSetReport(device, feature, 0, bytes, bytes[1])`, after recomputing the checksum.

| Offset | Value | Meaning |
| --- | --- | --- |
| 0 | `04` | Report id |
| 1 | `38` (56) | Length sent |
| 2 | `01` | Profile |
| 3–4 | sensX, sensY | Angle snapping / ripple flags (packed differently on 3395 sensors) |
| 5 | `3f` | Bit mask of enabled DPI levels (6 levels) |
| 6–7 | xDouble, yDouble | Per-level "×2" bits |
| 8–15 | X1–X8 | DPI per level, low byte |
| 16–23 | Y1–Y8 | DPI per level, high byte |
| 24 | level | Current level, 1-based |
| 25–48 | 8 × RGB | LED colour per level |
| 49 | type | LED indication type |
| 50–51 | checksum | Big-endian 16-bit sum of bytes 3–49 |

DPI encoding depends on the sensor. Default: DPI = (Y << 8 | X) × 50 + 50. 3395 sensors: same, or ×100 + 100 when the
level's ×2 bit is set. 3311 sensors use a lookup table (`findDpi3311Index` in the site). Which sensor device 174 has is unknown.

The driver handles report ids 0x04–0x0C this way, each with its own checksum position (0x0B for 0x05, 0x81 for 0x09…).
The Mac driver drops read frames (`f0 …`); it only forwards write frames.

## Reading settings (decoded from the Windows driver, verified on the mouse)

The vendor's Windows driver reads a setting in three steps. `build/ignix-probe --read <cmd>` does the same, limited to the commands below.

1. SetReport feature 0xA0: `a0 <cmd> <len> 00 00 00 00 00` (8 bytes). This asks the mouse to stage the data; it stores nothing.
2. Poll GetReport feature 0xA0 every 100 ms until it returns `a0 01 …` (ready). The first request after a pause usually
   doesn't become ready; sending it again works.
3. GetReport feature `<cmd>`, `<len>` bytes. A valid reply starts with `<cmd> <len>`. Without the ready status the
   report holds a stale buffer, which is what the earlier GET_REPORT attempts returned.

| cmd | len | Setting | Read on Nov 13, 2026 |
| --- | --- | --- | --- |
| 0x0B | 0x08 | Firmware version | `0b 08 01 04 41 ae 22 ae`: version 0x0104, device 0xAE |
| 0x04 | 0x38 | DPI | see below |
| 0x05 | 0x0F | Lighting | `05 0f 00 03 a8 00 ff 00 01 04 01 af 00 00 00` |
| 0x06 | 0x09 | Report rate | `06 09 01 fe 00 00 00 00 00` |
| 0x08 | 0x3B | Onboard buttons | `08 3b 02 00 00 03 00 00 04 00 00 05 00 00 06 00 00 …`: 3 bytes per button |
| 0x0C | 0x0A | Unknown | `0c 0a 01 fe 05 fa 00 00 00 00` |
| 0x0A | 0x80 | Profile | Not tried: longer than the report the descriptor declares |
| 0x09 | 0x83 | Macros | Not tried |

Full raw capture: [`captures/ignix-settings-2026-11-13.txt`](captures/ignix-settings-2026-11-13.txt).

### DPI reply (cmd 0x04)

The reply has no profile byte, so it is one byte shorter at the front than the write frame above.

| Offset | Read | Meaning |
| --- | --- | --- |
| 0–1 | `04 38` | Report id, length |
| 2–3 | `00 01` | sensX, sensY |
| 4 | `3f` | Enabled levels: 1–6 |
| 5–6 | `00 00` | ×2 flags |
| 7–14 | `b0 60 10 c0 40 30 00 00` | DPI low bytes, levels 1–8 |
| 15–22 | `04 09 0e 12 1f 75 00 00` | DPI high bytes, levels 1–8 |
| 23 | `02` | Current level (matches report 3) |
| 24–47 | `ff0000 00ff00 0000ff ffff00 00ffff ff00ff ff4000 ffffff` | LED colour per level (the site's defaults) |
| 48 | `02` | LED indication type |
| 49–50 | `10 88` | Big-endian 16-bit sum of bytes 2–48 (verified) |

DPI is stored as a plain little-endian 16-bit number, unlike the site's ×50 encodings:
**1200, 2400, 3600, 4800, 8000, 30000**; levels 7 and 8 unused. The mouse is on level 2, so 2400 DPI.
