# SwiftDrop

**Zero-configuration, encrypted file sharing across Android, Windows, and Linux.**

Discover nearby devices automatically via mDNS and transfer files with end-to-end AES-256-GCM encryption — no IP addresses, no cloud uploads, no setup required. Just tap and send.

---

## Features

- **Zero Configuration** — Devices find each other automatically on the same WiFi/LAN using mDNS (Zeroconf) with UDP broadcast fallback.
- **End-to-End Encryption** — Every transfer is secured with ECDH P-256 key exchange and AES-256-GCM encryption. Session keys are ephemeral.
- **Cross-Platform** — Android, Windows, and Linux from a single Flutter codebase.
- **Chunked Streaming** — Files are streamed in chunks (default 64 KB). No full-file buffering — memory stays flat even for large transfers.
- **Integrity Verification** — SHA-256 checksums per chunk and per file, with automatic retry on corruption.
- **Device Pairing** — First-time connections show a 6-digit pairing code derived from the shared ECDH secret. Trusted devices auto-connect.
- **Transfer History** — Local Hive storage tracks transfer history, trusted devices, and user settings.
- **Dark Theme** — Material 3 dark-first design with electric blue accent.

## Architecture

```
┌─────────────────────┐
│   Flutter UI Layer   │  Riverpod state management
└──────────┬──────────┘
┌──────────▼──────────┐
│ Transfer Controller  │  State machine + queue
└──────────┬──────────┘
┌──────────▼──────────┐
│   Discovery Layer    │  mDNS + UDP broadcast
└──────────┬──────────┘
┌──────────▼──────────┐
│   Transport Layer    │  TCP + custom wire protocol
└──────────┬──────────┘
┌──────────▼──────────┐
│  Encryption Layer    │  ECDH + AES-256-GCM
└─────────────────────┘
```

Each layer has a single responsibility and can be tested in isolation. See [docs/architecture.md](docs/architecture.md) for details.

## Wire Protocol

Custom binary protocol over TCP:

```
[Length 4B][Type 1B][SeqNo 4B][Payload ...]
```

14 message types covering handshake, file metadata, chunked transfer with ACK/NACK, completion verification, error reporting, and cancellation.

## Getting Started

### Prerequisites

| Tool | Version |
|------|---------|
| Flutter SDK | 3.38+ |
| Dart SDK | 3.10+ |
| Android Studio | for Android builds |
| Visual Studio 2022 | for Windows builds (Desktop C++ workload) |
| GTK 3, pkg-config, ninja-build | for Linux builds |

### Clone & Install

```bash
git clone https://github.com/your-username/swiftdrop.git
cd swiftdrop
flutter pub get
```

### Run (Debug)

```bash
# Android (device or emulator)
flutter run -d android

# Windows
flutter run -d windows

# Linux
flutter run -d linux
```

### Run Tests

```bash
flutter test
```

268+ tests covering encryption, transport, discovery, controller, storage, performance benchmarks, stress tests, edge cases, and end-to-end integration.

### Build Release

```bash
# Android APK
flutter build apk --release

# Android App Bundle (Play Store)
flutter build appbundle --release

# Windows
flutter build windows --release

# Linux
flutter build linux --release
```

## Project Structure

```
lib/
├── core/
│   ├── constants.dart             # Protocol-wide constants
│   ├── controller/                # Transfer orchestration & state machine
│   ├── discovery/                 # mDNS/UDP device discovery
│   ├── encryption/                # ECDH key exchange, AES-256-GCM
│   ├── platform/                  # Permissions, lifecycle, platform services
│   └── transport/                 # TCP server/client, wire protocol, chunked streaming
├── models/                        # Shared data models
├── providers/                     # Top-level Riverpod providers
├── storage/                       # Hive local storage (settings, history, trust)
└── ui/
    ├── screens/                   # Home, transfers, settings, permissions
    ├── theme/                     # Material 3 dark theme
    ├── utils/                     # Haptic feedback, desktop window config
    └── widgets/                   # Device card, transfer tile, common widgets

test/
├── core/
│   ├── controller/                # Transfer controller & record tests
│   ├── discovery/                 # Discovery service & device model tests
│   ├── encryption/                # Encryption roundtrip tests
│   ├── platform/                  # Permission, lifecycle, platform tests
│   └── transport/                 # Protocol codec, connection, performance,
│                                  #   stress, edge case, version negotiation
├── integration/                   # E2E loopback transfer tests
└── storage/                       # Storage service & model tests

docs/
├── architecture.md                # System architecture
├── PRD.md                         # Product requirements document
├── Sprint .md                     # Development roadmap (8 sprints)
└── tech_stack.md                  # Technology stack details
```

## Supported Platforms

| Platform | Status | Min Version |
|----------|--------|-------------|
| Android  | ✅ Ready | API 24 (Android 7.0) |
| Windows  | ✅ Ready | Windows 10+ |
| Linux    | ✅ Ready | GTK 3+ |
| iOS      | 🔜 Phase 2 | — |

## Configuration

Settings are persisted locally via Hive:

| Setting | Description | Default |
|---------|-------------|---------|
| Device Name | Display name visible to nearby devices | OS hostname |
| Save Location | Where received files are stored | Downloads |
| Auto-Accept | Skip accept dialog for trusted devices | Off |

## Security Model

1. **Discovery** — No sensitive data in mDNS advertisements (only device name, type, short ID).
2. **Transport** — Custom binary protocol over TCP with application-level encryption.
3. **Encryption** — ECDH P-256 key exchange → HKDF-SHA256 session key derivation → AES-256-GCM per-chunk encryption with unique IVs.
4. **Pairing** — SHA-256 hash of shared secret produces a 6-digit confirmation code on first connection.
5. **No Open Ports** — TCP server only listens during active transfers; closed immediately after.

## Performance Targets

| Metric | Target |
|--------|--------|
| 100 MB transfer (WiFi) | < 10 seconds |
| Handshake latency | < 200 ms |
| Memory usage (large files) | Flat (stream-only) |
| Transfer success rate | > 95% |

## Known Limitations

- **WiFi/LAN only** — Bluetooth and WebRTC transports are planned for future releases.
- **Single file transfers** — Multi-file / folder transfer is queued sequentially.
- **No cross-network** — Both devices must be on the same local network.
- **Android foreground service** — Background transfers require a persistent notification.

## Technology Stack

| Component | Technology |
|-----------|-----------|
| Framework | Flutter 3.38 / Dart 3.10 |
| State Management | Riverpod 3.2 |
| Encryption | PointyCastle 4.0 (ECDH, AES-256-GCM, HKDF) |
| Checksums | crypto 3.0 (SHA-256) |
| Local Storage | Hive 2.2 |
| Discovery | multicast_dns 0.3 + UDP broadcast fallback |
| Networking | dart:io (TCP ServerSocket/Socket) |
| Permissions | permission_handler 12.0 |
| File Picking | file_picker 8.3 |

## License

This project is proprietary software. All rights reserved.
