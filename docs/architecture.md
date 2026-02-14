# SwiftDrop - System Architecture

## High-Level Architecture

```
┌─────────────────────────┐
│     Flutter UI Layer    │  ← User interaction
└──────────┬──────────────┘
           │
┌──────────▼──────────────┐
│ Transfer Controller     │  ← Orchestrates transfers
└──────────┬──────────────┘
           │
┌──────────▼──────────────┐
│   Discovery Layer       │  ← Find nearby devices
└──────────┬──────────────┘
           │
┌──────────▼──────────────┐
│   Transport Layer       │  ← Move data
└──────────┬──────────────┘
           │
┌──────────▼──────────────┐
│   Encryption Layer      │  ← Secure data
└─────────────────────────┘
```

## Layer Responsibilities

### 1. Flutter UI Layer
**What it does:**
- Displays discovered devices
- Shows transfer progress
- Handles user input (select files, choose recipient)
- Manages pairing confirmations

**How it works:**
- Receives device list updates from Discovery Layer
- Sends transfer requests to Controller
- Updates progress bars from Controller events

### 2. Transfer Controller Layer
**What it does:**
- Coordinates entire transfer process
- Manages transfer queue
- Handles error recovery
- Tracks transfer state

**How it works:**
- Receives file + recipient from UI
- Asks Transport Layer to select best method
- Initiates encryption handshake
- Streams file chunks through Transport
- Updates UI with progress

### 3. Discovery Layer
**What it does:**
- Finds nearby devices
- Monitors device availability
- Maintains device list
- Handles network changes

**How it works:**

**WiFi/LAN mode:**
1. Starts mDNS service advertiser (broadcasts: "I'm here")
2. Starts mDNS service browser (listens: "Who's there?")
3. Detects devices advertising `_swiftdrop._tcp` service
4. Updates device list in real-time

**Bluetooth mode:**
1. Starts BLE advertising (broadcasts device info)
2. Scans for BLE advertisements from other devices
3. Collects device names and short IDs
4. Updates device list

**Smart switching:**
- If WiFi available → use mDNS
- If no WiFi → use Bluetooth
- Both can run simultaneously

### 4. Transport Layer
**What it does:**
- Establishes connections
- Transfers encrypted chunks
- Handles retries
- Validates checksums

**How it works:**

**WiFi/LAN (TCP) - Primary method:**
1. Sender starts TCP server on random port
2. Receiver connects to sender's IP:port (from mDNS)
3. TLS handshake for secure channel
4. Stream file in chunks (e.g., 64KB each)
5. Receiver sends ACK for each chunk
6. Checksum validation per chunk

**Bluetooth (RFCOMM) - Fallback:**
1. Establish RFCOMM socket connection
2. Stream chunks over Bluetooth
3. Lower bandwidth, used only when WiFi unavailable

**WebRTC (Future):**
- P2P connection with NAT traversal
- STUN server for finding public IP
- ICE candidates exchange
- Direct connection even across different networks

**Transport selection logic:**
```
if WiFi_Direct_available:
    use WiFi_Direct
elif same_WiFi_network:
    use TCP
elif WebRTC_enabled:
    use WebRTC
else:
    use Bluetooth
```

### 5. Encryption Layer
**What it does:**
- Secures all data in transit
- Manages encryption keys
- Handles key exchange

**How it works:**

**Handshake process:**
1. **Key Exchange:**
   - Each device generates ECDH key pair
   - Exchange public keys
   - Compute shared secret
   
2. **Session Key Derivation:**
   - Use shared secret to derive AES-256 key
   - Key is ephemeral (used once, then discarded)

3. **Encryption:**
   - Each file chunk encrypted with AES-256
   - Use unique IV (initialization vector) per chunk
   - No plaintext data transmitted

**Pairing verification:**
- First transfer: show 6-digit code on both devices
- User confirms codes match
- Device added to trusted list
- Future transfers: auto-accept from trusted devices

## Data Flow Examples

### Scenario 1: Same WiFi Network

```
Device A (Sender)                Device B (Receiver)

1. Start mDNS advertiser    →    Start mDNS browser
2. Broadcast service        ←    Discover Device A
3.                          ←    Show in device list
4. User selects file
5. User taps Device B       →    
6. Start TCP server         →    
7.                          ←    Connect to TCP server
8. Exchange public keys     ↔    Exchange public keys
9. Compute shared secret    ↔    Compute shared secret
10. Generate AES key        ↔    Generate AES key
11. Encrypt chunk #1        →    Decrypt chunk #1
12.                         ←    ACK chunk #1
13. Encrypt chunk #2        →    Decrypt chunk #2
14.                         ←    ACK chunk #2
    ... (repeat) ...
15. Transfer complete       →    Save file
```

### Scenario 2: Bluetooth Only (No WiFi)

```
Device A (Sender)                Device B (Receiver)

1. Start BLE advertising    →    Start BLE scanning
2. Broadcast device info    ←    Detect Device A
3.                          ←    Show in device list
4. User selects file
5. User taps Device B       →    
6. Establish RFCOMM         ↔    Accept connection
7. Exchange keys            ↔    Exchange keys
8. Stream encrypted chunks  →    Decrypt & save chunks
9. Transfer complete        →    Save file
```

## Error Handling Flow

**Connection lost during transfer:**
1. Transport layer detects connection drop
2. Controller marks transfer as "interrupted"
3. Wait for device to reappear
4. Resume from last successful chunk
5. If device doesn't return in 60s → fail transfer

**Corrupted chunk:**
1. Receiver computes chunk checksum
2. Checksum mismatch detected
3. Send NACK to sender
4. Sender retransmits that specific chunk
5. Validate again

**Permission denied:**
1. Platform layer catches permission error
2. Controller pauses transfer
3. UI shows permission request dialog
4. User grants permission
5. Resume transfer

## State Management

**Transfer states:**
- `DISCOVERING` - searching for devices
- `READY` - devices found, waiting for user
- `PAIRING` - exchanging keys
- `TRANSFERRING` - sending/receiving data
- `COMPLETED` - transfer successful
- `FAILED` - transfer failed
- `CANCELLED` - user cancelled

**Device states:**
- `AVAILABLE` - visible and ready
- `BUSY` - currently transferring
- `OFFLINE` - connection lost
- `TRUSTED` - previously paired

## Scalability Design

**Multiple concurrent transfers:**
- Each transfer gets own Transport instance
- Separate TCP ports per transfer
- Controller manages queue priority
- Limit: 3 concurrent transfers max

**Multiple visible devices:**
- Discovery layer maintains device map
- Real-time updates via stream
- UI receives filtered/sorted list
- Limit: 10 devices displayed

## Security Architecture

**Defense in depth:**
1. **Discovery:** No sensitive data in advertisements
2. **Transport:** TLS/encrypted channel
3. **Application:** AES-256 encryption
4. **Pairing:** User confirmation for new devices
5. **Storage:** Encrypted key storage

**No open attack surface:**
- TCP server only listens when actively sending
- Server closes after transfer
- No permanent listening ports
- Firewall rules temporary

## Why This Architecture?

**Layered design:**
- Each layer has single responsibility
- Easy to test each component
- Can swap implementations (e.g., different transport)

**Event-driven:**
- Discovery continuously updates device list
- Controller reacts to state changes
- UI updates in real-time

**Mirrors proven systems:**
- Similar to AirDrop architecture
- Similar to Nearby Share design
- Proven patterns for reliability

**Flexible:**
- Easy to add new transport methods
- Can extend discovery mechanisms
- Platform-specific optimizations possible

## Implementation Decisions (Post-Development)

The following decisions were made during development across Sprints 1–8:

### State Management: Riverpod 3.2
- `NotifierProvider` pattern for all mutable state (transfer records, permission state, device list)
- `StreamProvider` for discovery device stream
- `Provider` for lightweight singletons (encryption service, storage)
- Chosen for reactive streams fitting discovery + transfer progress patterns

### Local Storage: Hive 2.2
- NoSQL key-value store — lightweight and fast
- Boxes: `settings` (AppSettings), `trusted_devices` (TrustedDevice), `transfer_history` (TransferHistoryEntry), `device_identity`
- Schema uses `TypeAdapter` with manual `typeId` assignments
- No generated code (no build_runner dependency)

### Wire Protocol (Custom Binary)
- Envelope: `[Length 4B big-endian][Type 1B][SeqNo 4B][Payload ...]`
- 14 message types (0x01–0xFF) across handshake, file meta, chunk transfer, completion, and control categories
- `ProtocolCodec` handles serialization/deserialization with `ByteData` for cross-platform endianness safety
- Designed for minimal overhead — no JSON/Protobuf overhead on high-frequency chunk messages

### Chunk Size: 64 KB Default
- Benchmarked 64 KB, 128 KB, 256 KB, 512 KB in Sprint 7
- 64 KB chosen as default for best balance across platforms
- Configurable per `TransportService` instance
- Larger chunks reduce protocol overhead but increase memory spikes and retry costs

### Encryption Pipeline
- **Key Exchange:** ECDH P-256 (via PointyCastle `ECDomainParameters('prime256v1')`)
- **Session Key:** HKDF-SHA256 with 256-bit output (32 bytes)
- **Chunk Encryption:** AES-256-GCM with 12-byte random IV per chunk
- **Integrity:** SHA-256 per chunk (plaintext) + 16-byte GCM authentication tag
- **Pairing:** SHA-256 of shared secret → 6-digit code display
- Session keys are ephemeral — new key pair per transfer

### Protocol Versioning
- `SwiftDropConstants.protocolVersion = 1` broadcast in mDNS TXT record (`v` key)
- Version included in `HANDSHAKE_INIT` and `HANDSHAKE_REPLY` messages
- Receiver and sender both validate version range (`minSupportedProtocolVersion` to `protocolVersion`)
- Incompatible version → `ErrorMessage` with `ProtocolErrorCode.versionMismatch` sent, connection terminated
- Enables safe future protocol evolution without breaking existing clients

### Discovery: mDNS + UDP Broadcast
- Primary: `multicast_dns` package for `_swiftdrop._tcp` service advertisement
- Fallback: UDP broadcast on port 41234 for networks where mDNS fails
- Android: NSD (Network Service Discovery) integration via `nsd_android` package
- TXT record fields: `dn` (device name), `dt` (device type), `v` (protocol version), `id` (device ID), `tp` (transfer port)
- Device timeout: 15 seconds without heartbeat → removed from list

### Platform Layer
- Android: Runtime permissions (NEARBY_WIFI_DEVICES, location, storage, notifications), foreground service for background transfers
- Windows/Linux: Desktop window constraints (min 400×600), system UI overlay styling
- Lifecycle management: Discovery paused on app background, resumed on foreground
- Haptic feedback: Platform-aware (Android/iOS only) — light tap on device selection, medium on transfer start, heavy on completion

### Testing Strategy
- 270+ tests across 7 categories:
  - Unit: encryption, protocol codec, storage models
  - Integration: transport connection, discovery service
  - Controller: transfer state machine, record management
  - Performance: handshake latency, throughput benchmarks, chunk size comparison
  - Stress: 50 MB transfers, rapid start/stop, concurrency limits
  - Edge cases: disconnect recovery, double-dispose safety, boundary conditions
  - E2E: Full loopback transfers with encryption through TCP
