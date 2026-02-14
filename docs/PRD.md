# SwiftDrop - Product Requirements Document

## Product Vision
A zero-configuration, cross-network file sharing app that automatically discovers nearby devices and selects the fastest transfer method - no IP addresses, no setup, just tap and send.

## Core Problem
**Current pain points:**
- Manual IP/port configuration
- Firewall complications
- Slow Bluetooth-only solutions
- Platform fragmentation
- Cloud upload/download delays

**Our solution:**
- Auto device discovery
- Smart transport selection
- End-to-end encryption
- One-tap experience

## Target Users
- Anyone sharing files between their devices
- Users on same WiFi, hotspot, or offline scenarios
- Cross-platform users (Android ↔ Windows ↔ Linux)

## Target Platforms
**Phase 1:** Android (primary), Windows, Linux  
**Phase 2:** iOS

## Functional Requirements

### 1. Device Discovery
- Auto-discover devices on same WiFi/LAN using mDNS
- Discover devices via Bluetooth LE when WiFi unavailable
- Real-time device list updates
- Show: device name, type icon, signal strength, connection type

### 2. Smart Transport Selection
System automatically chooses fastest available method:
1. WiFi Direct (if supported)
2. Same WiFi/LAN (TCP)
3. WebRTC P2P
4. Bluetooth fallback

User never manually selects transport.

### 3. File Transfer
**Supports:**
- Files up to 10GB+
- Multiple files and folders
- Progress tracking
- Cancel/resume (WiFi only)
- Background transfers

**Transfer features:**
- Chunked streaming
- Checksum validation
- Auto-retry failed chunks

### 4. Security
**All transfers include:**
- AES-256 encryption
- Ephemeral session keys
- ECDH key exchange
- Device pairing verification

**Pairing modes:**
- Auto for trusted devices
- 6-digit code confirmation
- QR code pairing

### 5. User Flow

**Sender:**
Open app → Tap "Send" → Select file → Choose device → Confirm pairing → Transfer

**Receiver:**
Notification → Accept/Decline → View progress → Save location

## Non-Functional Requirements

**Performance:**
- 100MB file < 10 seconds over WiFi
- Handshake latency < 200ms

**Security:**
- No plaintext data transmission
- No metadata leakage
- No permanently open public ports

**Scalability:**
- Display up to 10 nearby devices
- Support multiple concurrent transfers

**Battery:**
- Optimized background operation
- Stop discovery when idle

## MVP Scope (Phase 1)
**Build first:**
- WiFi/LAN only (skip Bluetooth initially)
- mDNS discovery
- TCP transfer with AES encryption
- Single file transfer
- Progress bar

## Future Features
- Cross-internet sharing with cloud relay
- QR-based quick connect
- UWB direction finding
- Clipboard sharing
- Text messaging

## Success Metrics
- Transfer success rate > 95%
- Average setup time < 5 seconds
- User satisfaction score > 4.5/5
- Zero configuration errors

## Known Risks

| Risk | Mitigation |
|------|-----------|
| Firewall blocking | Auto-configure firewall rules |
| Android background limits | Use foreground service |
| iOS Bluetooth restrictions | Native implementation |
| Large file memory issues | Stream-only approach |
