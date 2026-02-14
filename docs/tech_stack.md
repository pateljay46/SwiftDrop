# SwiftDrop - Technology Stack

## Frontend Framework
**Flutter**
- Cross-platform UI (Android, Windows, Linux, iOS)
- Single codebase for all platforms
- Native performance with platform channels

## Discovery Technologies

### WiFi/LAN Discovery
**mDNS (Zeroconf)**
- Service type: `_swiftdrop._tcp`
- Flutter package: `multicast_dns`
- Fallback: UDP broadcast
- Platform channels to native NSD (Network Service Discovery)

### Bluetooth Discovery
**Bluetooth Low Energy (BLE)**
- Advertisement broadcasting
- Payload: device name, app version, short ID
- Flutter packages:
  - `flutter_blue_plus`
  - `flutter_reactive_ble`

## Transport Technologies

### WiFi/LAN Transport
**TCP Server**
- Dart's native `dart:io` library
- Alternative: `shelf` server framework
- TLS-wrapped connections
- Chunked file streaming

### WebRTC (Optional)
**Peer-to-peer connection**
- ICE candidates for NAT traversal
- Optional STUN server
- For future cross-network expansion

### Bluetooth Transport
**RFCOMM Socket**
- Bluetooth Classic protocol
- Chunked streaming
- Fallback when WiFi unavailable

## Security & Encryption

**Dart Crypto Libraries:**
- `pointycastle` - comprehensive crypto library
- `cryptography` package - modern crypto APIs

**Algorithms:**
- AES-256 for data encryption
- ECDH for key exchange
- Ephemeral session keys

**Process:**
1. Exchange public keys
2. Generate ECDH shared secret
3. Derive AES session key
4. Encrypt all file chunks

## Local Storage

**Database:**
- **Hive** or **Isar** (Flutter local databases)
- NoSQL key-value store
- Fast and lightweight

**Stored Data:**
- Trusted device list
- Transfer history
- User settings
- Paired encryption keys

## Platform-Specific Requirements

### Android
**Permissions needed:**
- `BLUETOOTH`
- `BLUETOOTH_SCAN`
- `NEARBY_DEVICES`
- `ACCESS_NETWORK_STATE`
- `READ_EXTERNAL_STORAGE` / `WRITE_EXTERNAL_STORAGE`

**Services:**
- Foreground service for background transfers

### Windows/Linux
**Requirements:**
- Network discovery capabilities
- Auto firewall rule configuration
- Native file system access

## Development Tools
- Flutter SDK (latest stable)
- Dart 3.0+
- Platform-specific build tools (Android Studio, Visual Studio)

## Network Stack Summary

| Layer | Technology |
|-------|-----------|
| UI | Flutter |
| Discovery | mDNS, BLE |
| Transport | TCP, RFCOMM, WebRTC |
| Security | TLS, AES-256, ECDH |
| Storage | Hive/Isar |

## Why These Choices?

**Flutter:** Single codebase, fast development, native performance

**mDNS:** Standard for local network discovery, used by AirDrop/Nearby Share

**TCP:** Reliable, fast, perfect for local networks

**Bluetooth LE:** Low power, good for discovery; RFCOMM for actual transfer

**AES-256:** Industry standard encryption, secure and fast

**Hive/Isar:** Fast local storage without SQL overhead
