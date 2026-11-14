# MYCODEX — engineering skills and quality rules

This is a repository-local engineering playbook, not a claim that external ChatGPT plugins are automatically available to every agent.

## Competencies
- Swift 6 language/concurrency audit; Swift Package Manager, public API design and semantic versioning.
- C/C++ interoperability, native library builds, ABI boundaries, XCFramework packaging.
- OpenVPN protocol configuration and networking diagnostics, including UDP/TCP, IPv4/IPv6, DNS and routing.
- Apple NetworkExtension: NETunnelProviderManager, NEPacketTunnelProvider, NEPacketTunnelFlow, entitlements and extension lifecycle.
- Keychain and secure credential handling; memory safety and error redaction.
- XCTest/Swift Testing, protocol integration tests, simulated packet flow fixtures, CI on macOS.
- Documentation, migration guide, changelog and dependency/license inventory.

## Development rules
1. Verify relevant Apple API availability and platform support against current SDK before implementation.
2. Keep UI out of the core package. Provide a small example host app/extension later; SDK must not depend on SwiftUI.
3. Design configuration and lifecycle as explicit states (`idle`, `preparing`, `connecting`, `connected`, `reconnecting`, `disconnecting`, `failed`).
4. Never hold plaintext passwords or private keys in logs, persistent user defaults or config files. Prefer Keychain references and explicit credential ownership.
5. Do not embed or publish signing keys, provisioning files, API secrets, or real VPN profiles with credentials.
6. Test invalid .ovpn, malformed inputs, reconnect, cancellation, DNS changes, interface changes and network outages.
7. Use Swift concurrency and isolation carefully; avoid blocking extension callbacks or main actor with I/O.
8. Changes to C/C++ layers need memory ownership documentation and sanitizer/diagnostic coverage where available.
9. Avoid unsupported platform promises and fabricated performance benchmarks.
10. Preserve licensing notices and verify actual obligations before copying or vendoring external code.

## Definition of done for a feature
- Public API and behavior documented; success/error/cancellation outcomes defined.
- Automated tests added, actually executed and results recorded.
- Build matrix updated; real-device testing distinguished from simulator testing.
- `PROGRESS.md` updated with changed paths, tests and blockers.
- `memory.md` and architecture docs updated only when long-term decisions change.

## Suggested commands (only after code and package exist)
- `swift package resolve`
- `swift test` on a supported host, if the package/tests support it
- `xcodebuild -list` for an Xcode project/workspace
- Targeted `xcodebuild` builds on documented Apple destinations

These commands are **not** evidence of passing tests until their output is captured.
