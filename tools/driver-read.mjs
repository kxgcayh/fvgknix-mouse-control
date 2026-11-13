// Read-only capture against WebDriver For Mac (ws://127.0.0.1:10086), with no website involved.
// Logs every frame from the driver, and sends only the site's read requests: [0xF0, conn, deviceId, cmd, 0].
// The site never writes with 0xF0; writes start with the connection byte instead.
//
//   node tools/driver-read.mjs            read version, profile, DPI, rate, lighting, buttons once
//   node tools/driver-read.mjs --listen   only log frames (press the mouse's DPI button, watch battery)
//   --origin <url>                         send an Origin header, in case the driver only accepts its own web page
//
// Node's built-in WebSocket fails the driver's handshake, so this speaks the protocol over a plain socket.

import net from 'node:net';
import crypto from 'node:crypto';

const READS = { 11: 'version', 10: 'profile', 4: 'dpi', 6: 'report rate', 5: 'lighting', 8: 'buttons' };
const listenOnly = process.argv.includes('--listen');
const originIndex = process.argv.indexOf('--origin');
const origin = originIndex > 0 ? process.argv[originIndex + 1] : null;
const hex = (bytes) => bytes.map((b) => b.toString(16).padStart(2, '0')).join('');
const bytes = (frame) => (frame.match(/../g) ?? []).map((b) => parseInt(b, 16));
const stamp = () => new Date().toTimeString().slice(0, 8);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const socket = net.connect(10086, '127.0.0.1');
let handshakeDone = false;
let buffer = Buffer.alloc(0);
let device = null;

socket.on('connect', () => {
  const key = crypto.randomBytes(16).toString('base64');
  socket.write(`GET / HTTP/1.1\r\nHost: localhost:10086\r\nConnection: Upgrade\r\nUpgrade: websocket\r\n`
    + `Sec-WebSocket-Version: 13\r\nSec-WebSocket-Key: ${key}\r\n${origin ? `Origin: ${origin}\r\n` : ''}\r\n`);
});
socket.on('error', () => { console.error('Could not reach 127.0.0.1:10086. Is WebDriver For Mac running?'); process.exit(1); });
socket.on('close', () => process.exit(0));

/** Sends a masked text frame, as clients must. */
function send(text) {
  const payload = Buffer.from(text);
  const mask = crypto.randomBytes(4);
  const header = Buffer.from([0x81, 0x80 | payload.length]); // frames here are always < 126 bytes
  socket.write(Buffer.concat([header, mask, payload.map((b, i) => b ^ mask[i % 4])]));
}

socket.on('data', (chunk) => {
  buffer = Buffer.concat([buffer, chunk]);
  if (!handshakeDone) {
    const end = buffer.indexOf('\r\n\r\n');
    if (end < 0) return;
    // The driver can push a data frame before its handshake reply; drop anything before the status line.
    const status = buffer.indexOf('HTTP/1.1 101');
    if (status < 0 || status > end) { console.error('Handshake refused:', JSON.stringify(buffer.subarray(0, end).toString())); process.exit(1); }
    handshakeDone = true;
    buffer = buffer.subarray(end + 4);
    console.log(`${stamp()} connected${listenOnly ? ', listening only (Ctrl+C to stop)' : ''}`);
  }
  // Server frames are unmasked: [FIN+opcode, len (126 -> 16-bit, 127 -> 64-bit), payload]
  while (buffer.length >= 2) {
    let length = buffer[1] & 0x7f, offset = 2;
    if (length === 126) { if (buffer.length < 4) return; length = buffer.readUInt16BE(2); offset = 4; }
    if (length === 127) { if (buffer.length < 10) return; length = Number(buffer.readBigUInt64BE(2)); offset = 10; }
    if (buffer.length < offset + length) return;
    const opcode = buffer[0] & 0x0f;
    const payload = buffer.subarray(offset, offset + length);
    buffer = buffer.subarray(offset + length);
    if (opcode === 0x1 || opcode === 0x2) onFrame(opcode === 0x1 ? payload.toString() : payload.toString('hex'));
    if (opcode === 0x8) socket.end();
  }
});

async function onFrame(frame) {
  const b = bytes(frame);
  console.log(`${stamp()} driver -> ${frame}  (${b.length} bytes)`);
  // Attach frame: [conn 0x80-0x85, 1, 0, deviceId, 0x40|0x41, batteryStatus, batteryLevel]
  const attach = b.length === 7 && b[0] >= 0x80 && b[0] <= 0x85 && (b[4] === 0x40 || b[4] === 0x41);
  if (!attach || device) return;
  device = { conn: b[0], id: b[3] };
  console.log(`   attach: conn 0x${b[0].toString(16)}, device ${b[3]}, battery status ${b[5]}, level ${b[6]}`);
  if (listenOnly) return;
  for (const [cmd, name] of Object.entries(READS)) {
    const request = hex([0xf0, device.conn, device.id, Number(cmd), 0]);
    console.log(`${stamp()} read   -> ${request}  (${name})`);
    send(request);
    await sleep(600);
  }
  await sleep(1500);
  socket.end();
  setTimeout(() => process.exit(0), 500); // the driver doesn't always close its side
}

setTimeout(() => { if (!device) { console.error('No attach frame within 10 s.'); process.exit(1); } }, 10_000);
