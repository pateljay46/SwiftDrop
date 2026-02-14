# SwiftDrop — Wire Protocol Specification (v1)

## Overview

This document defines the binary message format used between SwiftDrop devices
for handshake, file metadata exchange, chunked data transfer, and
acknowledgements over TCP.

All messages are length-prefixed and follow a common envelope format.

---

## Message Envelope

Every message on the wire uses this structure:

```
┌──────────┬──────────┬──────────┬──────────────────────┐
│  Length   │  Type    │  SeqNo   │  Payload             │
│  4 bytes  │  1 byte  │  4 bytes │  variable            │
│  uint32BE │  uint8   │  uint32BE│                      │
└──────────┴──────────┴──────────┴──────────────────────┘
```

| Field    | Size    | Description                                       |
|----------|---------|---------------------------------------------------|
| Length   | 4 bytes | Total message length **excluding** the Length field |
| Type     | 1 byte  | Message type identifier (see below)                |
| SeqNo    | 4 bytes | Sequence number (0 for non-sequenced messages)     |
| Payload  | varies  | Type-specific payload                              |

---

## Message Types

| Value | Name              | Direction         | Description                             |
|-------|-------------------|-------------------|-----------------------------------------|
| 0x01  | HANDSHAKE_INIT    | Sender → Receiver | Initiates key exchange                  |
| 0x02  | HANDSHAKE_REPLY   | Receiver → Sender | Responds with public key                |
| 0x03  | HANDSHAKE_CONFIRM | Sender → Receiver | Confirms pairing code match             |
| 0x10  | FILE_META         | Sender → Receiver | File metadata before transfer           |
| 0x11  | FILE_ACCEPT       | Receiver → Sender | Receiver accepts the transfer           |
| 0x12  | FILE_REJECT       | Receiver → Sender | Receiver declines the transfer          |
| 0x20  | CHUNK_DATA        | Sender → Receiver | Encrypted file chunk                    |
| 0x21  | CHUNK_ACK         | Receiver → Sender | Chunk received and validated            |
| 0x22  | CHUNK_NACK        | Receiver → Sender | Chunk failed validation, retransmit     |
| 0x30  | TRANSFER_COMPLETE | Sender → Receiver | All chunks sent successfully            |
| 0x31  | TRANSFER_VERIFIED | Receiver → Sender | Final checksum matches, file saved      |
| 0xF0  | ERROR             | Either direction  | Error with code and message             |
| 0xFF  | CANCEL            | Either direction  | Transfer cancelled by user              |

---

## Message Payloads

### HANDSHAKE_INIT (0x01)

```
┌──────────────────┬────────────────┬──────────────────┐
│ Protocol Version │ Public Key Len │ Public Key       │
│ 2 bytes uint16BE │ 2 bytes uint16 │ variable         │
├──────────────────┼────────────────┼──────────────────┤
│ Device Name Len  │ Device Name    │ Device ID        │
│ 1 byte uint8     │ variable UTF-8 │ 16 bytes (UUID)  │
└──────────────────┴────────────────┴──────────────────┘
```

| Field            | Size     | Description                               |
|------------------|----------|-------------------------------------------|
| Protocol Version | 2 bytes  | Current: `0x0001`                         |
| Public Key Len   | 2 bytes  | Length of ECDH public key (65 for P-256)  |
| Public Key       | variable | Uncompressed EC public key bytes          |
| Device Name Len  | 1 byte   | Length of device name in bytes             |
| Device Name      | variable | UTF-8 encoded device name                 |
| Device ID        | 16 bytes | Unique device UUID                        |

### HANDSHAKE_REPLY (0x02)

Same structure as HANDSHAKE_INIT.

### HANDSHAKE_CONFIRM (0x03)

```
┌────────────────┐
│ Pairing Hash   │
│ 32 bytes       │
└────────────────┘
```

SHA-256 of the shared secret. Receiver verifies it matches their computed hash.

### FILE_META (0x10)

```
┌──────────────┬──────────────┬──────────┬──────────────┐
│ File Name Len│ File Name    │ File Size│ Chunk Size   │
│ 2 bytes      │ variable     │ 8 bytes  │ 4 bytes      │
│ uint16BE     │ UTF-8        │ uint64BE │ uint32BE     │
├──────────────┼──────────────┼──────────┴──────────────┤
│ Chunk Count  │ File Checksum                          │
│ 4 bytes      │ 32 bytes (SHA-256)                     │
│ uint32BE     │                                        │
└──────────────┴────────────────────────────────────────┘
```

| Field          | Size     | Description                           |
|----------------|----------|---------------------------------------|
| File Name Len  | 2 bytes  | Length of file name in bytes           |
| File Name      | variable | UTF-8 encoded file name               |
| File Size      | 8 bytes  | Total file size in bytes               |
| Chunk Size     | 4 bytes  | Chunk size in bytes (default: 65536)   |
| Chunk Count    | 4 bytes  | Total number of chunks                 |
| File Checksum  | 32 bytes | SHA-256 hash of entire file            |

### FILE_ACCEPT (0x11)

Empty payload. Receiver is ready.

### FILE_REJECT (0x12)

```
┌────────────────┬──────────────┐
│ Reason Len     │ Reason       │
│ 2 bytes uint16 │ variable     │
└────────────────┴──────────────┘
```

### CHUNK_DATA (0x20)

```
┌──────────────┬──────────────┬──────────┬──────────────┬──────────┐
│ Chunk Index  │ IV           │ Data Len │ Encrypted    │ GCM Tag  │
│ 4 bytes      │ 12 bytes     │ 4 bytes  │ variable     │ 16 bytes │
│ uint32BE     │              │ uint32BE │              │          │
├──────────────┴──────────────┴──────────┴──────────────┼──────────┤
│ Chunk Checksum (over plaintext)                       │          │
│ 32 bytes (SHA-256)                                    │          │
└───────────────────────────────────────────────────────┴──────────┘
```

| Field          | Size     | Description                               |
|----------------|----------|-------------------------------------------|
| Chunk Index    | 4 bytes  | Zero-based chunk number                   |
| IV             | 12 bytes | AES-256-GCM initialization vector         |
| Data Len       | 4 bytes  | Length of encrypted data (excl. tag)       |
| Encrypted Data | variable | AES-256-GCM encrypted chunk data          |
| GCM Tag        | 16 bytes | Authentication tag                        |
| Chunk Checksum | 32 bytes | SHA-256 of **plaintext** chunk (pre-encryption) |

### CHUNK_ACK (0x21)

```
┌──────────────┐
│ Chunk Index  │
│ 4 bytes      │
└──────────────┘
```

### CHUNK_NACK (0x22)

```
┌──────────────┬────────────┐
│ Chunk Index  │ Error Code │
│ 4 bytes      │ 1 byte     │
└──────────────┴────────────┘
```

Error codes:
- `0x01` — Checksum mismatch
- `0x02` — Decryption failure
- `0x03` — Out of sequence

### TRANSFER_COMPLETE (0x30)

```
┌──────────────┐
│ Total Chunks │
│ 4 bytes      │
└──────────────┘
```

### TRANSFER_VERIFIED (0x31)

Empty payload. File checksum verified, file saved successfully.

### ERROR (0xF0)

```
┌────────────┬────────────────┬──────────────┐
│ Error Code │ Message Len    │ Message      │
│ 2 bytes    │ 2 bytes uint16 │ variable     │
└────────────┴────────────────┴──────────────┘
```

Error codes:
- `0x0001` — Protocol version mismatch
- `0x0002` — Pairing rejected
- `0x0003` — Storage full
- `0x0004` — Permission denied
- `0x0005` — Internal error

### CANCEL (0xFF)

Empty payload. Immediately terminates the transfer.

---

## Transfer Flow (Happy Path)

```
Sender                              Receiver
  │                                    │
  │──── HANDSHAKE_INIT ───────────────→│
  │←─── HANDSHAKE_REPLY ──────────────│
  │                                    │
  │  [Both compute shared secret]      │
  │  [Both show 6-digit pairing code]  │
  │  [User confirms on both devices]   │
  │                                    │
  │──── HANDSHAKE_CONFIRM ────────────→│
  │                                    │
  │──── FILE_META ────────────────────→│
  │←─── FILE_ACCEPT ──────────────────│
  │                                    │
  │──── CHUNK_DATA (0) ──────────────→│
  │←─── CHUNK_ACK  (0) ──────────────│
  │──── CHUNK_DATA (1) ──────────────→│
  │←─── CHUNK_ACK  (1) ──────────────│
  │        ...                         │
  │──── CHUNK_DATA (N) ──────────────→│
  │←─── CHUNK_ACK  (N) ──────────────│
  │                                    │
  │──── TRANSFER_COMPLETE ────────────→│
  │←─── TRANSFER_VERIFIED ────────────│
  │                                    │
  │  [Connection closed]               │
```

## Retry Logic

- On CHUNK_NACK: sender retransmits the specified chunk
- Maximum 3 retries per chunk before aborting transfer
- On connection drop: wait 60s, then resume from last ACK'd chunk
- On ERROR: display to user and close connection

## Protocol Versioning

- Protocol version is included in HANDSHAKE_INIT/REPLY
- If versions are incompatible, receiver sends ERROR (0x0001) and closes
- Backward compatibility: newer versions MAY accept older messages
- Current version: `1` (0x0001)

## Byte Order

All multi-byte integers use **big-endian** (network byte order).

## Security Notes

- Public keys are exchanged in plaintext (this is safe for ECDH)
- All file data is encrypted with AES-256-GCM before transmission
- The TCP connection itself is over TLS for defense in depth
- GCM tags provide per-chunk authentication
- Ephemeral keys: new ECDH pair generated per session
