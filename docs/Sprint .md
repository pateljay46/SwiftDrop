Plan: SwiftDrop Development Roadmap
TL;DR — An 8-sprint (16-week) roadmap for a solo developer to build the SwiftDrop MVP: zero-config, encrypted file sharing across Android, Windows, and Linux. Architecture is built bottom-up (encryption → transport → discovery → controller → UI). Riverpod manages reactive state. All three platforms are developed simultaneously using Flutter's cross-platform capabilities, with platform-specific adaptations handled in a dedicated sprint.

Sprint 1 (Weeks 1–2): Project Setup & Encryption Layer
Goals: Scaffold the project, establish conventions, implement the foundational encryption layer.

Run flutter create swiftdrop and set up the folder structure mirroring the architecture layers:
lib/core/encryption/, lib/core/transport/, lib/core/discovery/, lib/core/controller/, lib/ui/, lib/storage/
Add core dependencies to pubspec.yaml: flutter_riverpod, pointycastle, multicast_dns, hive (or isar), file_picker, path_provider
Configure linting (analysis_options.yaml), set up platform targets (Android, Windows, Linux)
Define the wire protocol (gap in docs): specify message format for handshake, metadata exchange (file name, size, chunk count, checksum), chunk transfer, ACK/NACK. Document in docs/wire_protocol.md
Implement EncryptionService:
ECDH key pair generation
Public key exchange serialization
Shared secret computation
AES-256 session key derivation (HKDF)
Chunk encryption/decryption with unique IV per chunk
Unit tests for encryption layer: key exchange roundtrip, encrypt/decrypt integrity, IV uniqueness
Deliverable: A buildable Flutter project with a fully tested encryption layer and a documented wire protocol.

Sprint 2 (Weeks 3–4): Discovery Layer (mDNS)
Goals: Devices can find each other on the same WiFi/LAN automatically.

Implement DiscoveryService using multicast_dns package:
Advertise _swiftdrop._tcp service with device name, app version, unique device ID
Browse/listen for other SwiftDrop services on the network
Real-time device list as a Riverpod StreamProvider
Build DeviceModel: name, IP address, port, device type icon, connection type, signal strength, availability state
Handle network change events (WiFi connect/disconnect) — restart discovery on network transitions
Platform-specific mDNS work:
Android: NSD (Network Service Discovery) via platform channel if multicast_dns is unreliable
Windows: Test with Bonjour; implement UDP broadcast fallback if needed
Linux: Verify Avahi compatibility; add fallback
Add timeout/cleanup logic: remove devices not seen in 30s
Integration tests: two emulators/devices discovering each other
Deliverable: Open the app on two devices on the same network → they see each other within seconds.

Sprint 3 (Weeks 5–6): Transport Layer (TCP)
Goals: Files can be streamed over TCP between two devices with encryption.

Implement TransportService (TCP):
Sender: start ServerSocket on random available port, advertise port via mDNS TXT record
Receiver: connect to sender's IP:port from discovered service info
Implement wire protocol messages:
HANDSHAKE_INIT → exchange ECDH public keys
FILE_META → file name, size, chunk count, total checksum
CHUNK_DATA → chunk index, encrypted data, chunk checksum
CHUNK_ACK / CHUNK_NACK → confirmation or retransmit request
TRANSFER_COMPLETE → final validation
Chunked streaming implementation:
Read file as stream (never buffer entire file in memory)
Default chunk size: 64KB (configurable, benchmark later)
Encrypt each chunk via EncryptionService before sending
Receiver decrypts and validates checksum per chunk
Auto-retry logic: retransmit on NACK, max 3 retries per chunk
TLS wrapping for the TCP connection (defense in depth on top of app-level AES)
Unit tests: mock TCP connections, verify chunk integrity, simulate NACK/retry
Deliverable: Programmatically send a file between two devices over TCP with encryption and checksum validation.

Sprint 4 (Weeks 7–8): Transfer Controller & Pairing
Goals: Orchestrate the full transfer flow, implement device pairing.

Implement TransferController as the central coordinator:
State machine: DISCOVERING → READY → PAIRING → TRANSFERRING → COMPLETED / FAILED / CANCELLED
Expose transfer state as Riverpod StateNotifierProvider
Full transfer orchestration:
Receive file + recipient from UI layer
Initiate encryption handshake via EncryptionService
Start chunked transfer via TransportService
Track progress (bytes sent / total bytes) as a stream
Handle completion, failure, cancellation
Pairing verification:
First connection to new device: derive 6-digit code from shared ECDH secret
Both devices display code; user confirms match
Store trusted devices after successful pairing
Error handling flows:
Connection lost: wait 60s for device to reappear, resume from last ACK'd chunk
Permission denied: pause transfer, surface to UI
Corrupted chunk: NACK → retransmit → validate
Transfer queue: support queuing multiple files (execute sequentially for MVP)
Integration tests: end-to-end transfer between two devices
Deliverable: Full transfer pipeline working: discover → pair → encrypt → transfer → complete, with error recovery.

Sprint 5 (Weeks 9–10): UI Layer & Local Storage
Goals: Build the user-facing screens and persist app data locally.

Local Storage setup (Hive recommended — lighter than Isar, actively maintained):
Trusted device list (device ID, name, last seen, public key hash)
Transfer history (file name, size, timestamp, status, peer device)
User settings (device name, save location, auto-accept from trusted)
Screens:
Home/Discovery screen: real-time device list from DiscoveryService stream, device name + type icon + connection indicator, pull-to-refresh
Send flow: "Send" FAB → native file picker → select device from list → pairing dialog (if new) → transfer progress screen
Receive flow: incoming transfer notification → accept/decline dialog → progress screen → "saved to..." confirmation
Transfer progress screen: file name, file size, progress bar (% + bytes), transfer speed, cancel button
Settings screen: device name, default save location, trusted devices list, transfer history
Riverpod state wiring:
discoveredDevicesProvider — stream of nearby devices
activeTransferProvider — current transfer state + progress
transferHistoryProvider — list from Hive
trustedDevicesProvider — list from Hive
Dark theme with Material 3 design
Responsive layout for mobile (Android) and desktop (Windows/Linux) screen sizes
Deliverable: Fully functional UI on all three platforms — user can discover devices, select files, pair, and transfer with visible progress.

Sprint 6 (Weeks 11–12): Platform Integration & Permissions
Goals: Handle all platform-specific requirements for production-quality behavior.

Android:
Runtime permission handling: NEARBY_WIFI_DEVICES (Android 13+), ACCESS_FINE_LOCATION (for WiFi scanning pre-13), READ_MEDIA_* (Android 13+) / READ_EXTERNAL_STORAGE (older), POST_NOTIFICATIONS
Foreground service for background transfers with proper ForegroundServiceType (Android 14+: dataSync)
Scoped storage file saving (MediaStore or SAF for save location)
Handle battery optimization (request exemption or guide user)
Windows:
Auto-configure Windows Firewall: add inbound TCP rule for SwiftDrop's port range via platform channel calling PowerShell New-NetFirewallRule
Remove rule on app close / transfer complete
Handle UAC elevation prompt if needed
File save to user-selected directory (no scoped storage concerns)
Linux:
Firewall detection (ufw/iptables/nftables) and auto-rule creation via platform channel
Verify Avahi mDNS daemon is running; prompt user if not
Desktop notifications via system notification daemon
Cross-platform:
App lifecycle management: pause/resume discovery on app background/foreground
Stop discovery when idle (battery optimization)
Ensure TCP server closes after transfer (no permanent listening ports)
Test each platform end-to-end: Android ↔ Windows, Android ↔ Linux, Windows ↔ Linux
Deliverable: All three platforms handle permissions, background operation, and firewall correctly in real-world conditions.

Sprint 7 (Weeks 13–14): Testing, Performance & Polish
Goals: Harden the app, hit performance targets, polish UX.

Performance benchmarking against PRD targets:
100MB file < 10 seconds over WiFi (adjust chunk size if needed — try 256KB, 512KB, 1MB)
Handshake latency < 200ms
Memory usage stays flat during large file transfers (stream-only verification)
Stress testing:
1GB+ file transfers
Multiple sequential transfers
Discovery with 10 devices visible
Transfer during network instability (toggle WiFi)
Edge case testing:
Sender app killed mid-transfer
Receiver runs out of storage
File picker cancelled
Same device appearing via multiple network interfaces
Rapid connect/disconnect cycles
UX polish:
Empty states (no devices found, no transfer history)
Loading indicators during discovery startup
Error messages surfaced from architecture error handling flows
Haptic feedback on transfer complete (Android)
Desktop window management (minimum size, taskbar icon)
Bug fixing from all testing rounds
Chunk size optimization: benchmark 64KB vs 128KB vs 256KB vs 512KB and pick optimal default
Deliverable: A stable, performant MVP that meets all PRD non-functional requirements.

Sprint 8 (Weeks 15–16): Release Preparation
Goals: Get the app ready for distribution.

App metadata:
Android: app icon, splash screen, Play Store listing (screenshots, description)
Windows: installer via MSIX or Inno Setup, app icon
Linux: AppImage or Flatpak packaging, desktop entry file
Documentation:
README.md with build instructions, supported platforms, known limitations
Update architecture.md with decisions made (Riverpod, Hive, wire protocol, chunk size)
Version strategy: implement protocol version in mDNS TXT record + handshake message (gap in docs — prevents future incompatibility)
CI/CD setup: GitHub Actions for Flutter build + test on Android, Windows, Linux
Beta release:
Android: internal testing track on Play Store (or APK distribution)
Windows/Linux: GitHub Releases
Collect feedback, log issues for post-MVP backlog
Deliverable: Distributable MVP builds on all three platforms + CI pipeline.

Verification
Per-sprint: Each sprint has a concrete deliverable that can be tested in isolation
Integration checkpoints: Sprint 4 (end-to-end transfer works), Sprint 5 (full UI works), Sprint 6 (all platforms work)
Final validation: Sprint 7 benchmarks must meet PRD targets (100MB < 10s, handshake < 200ms, >95% success rate)
Cross-platform matrix test: Android ↔ Windows, Android ↔ Linux, Windows ↔ Linux transfers all verified in Sprint 6-7
Decisions
State management: Riverpod (reactive streams fit discovery + transfer progress patterns)
Local storage: Hive recommended over Isar (lighter, actively maintained, sufficient for key-value needs)
Platform targeting: All three simultaneously (Flutter handles cross-platform; platform-specific work isolated to Sprint 6)
Wire protocol: Must be defined in Sprint 1 before transport work begins (gap in current docs)
Protocol versioning: Added in Sprint 8 to prevent future compatibility issues (gap in current docs)
Default chunk size: 64KB initially, benchmarked and optimized in Sprint 7
mDNS fallback: UDP broadcast fallback implemented in Sprint 2 if multicast_dns package proves unreliable on any platform
