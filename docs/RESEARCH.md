# Engineering research — source-grounded snapshot

**Checked:** 2026-11-14. Research is not a substitute for building or testing Apple targets.

## 1. Historical adapter

- Repository: https://github.com/ss-abramchuk/OpenVPNAdapter (archived; README says support discontinued).
- Swift Package: https://github.com/ss-abramchuk/OpenVPNAdapter/blob/master/Package.swift — `swift-tools-version: 5.1`, original platform floors iOS 9.0 and macOS 10.11, Objective-C/OpenVPN3 wrapper, vendored ASIO, LZ4 and mbedTLS build targets.
- Existing OpenVPNAdapter public API is Obj-C oriented (adapter + delegate, configuration, packet flow, reachability). Treat as compatibility reference only; never blindly copy AGPL source.
- We deliberately replace direct delegate-facing API with a Swift-first model and separate provider lifecycle, while preserving .ovpn compatibility where possible.

## 2. OpenVPN 3 Core

- Repository: https://github.com/OpenVPN/openvpn3 — C++ *client* library; does not implement OpenVPN server functionality.
- API entry point referenced in upstream README: `client/ovpncli.hpp`.
- Upstream master was observed at `0c1ce172fe918b05463d71e682a0c2f2d8fe7899` (commit timestamp 2026-11-04). This is a **research snapshot, not the selected pinned runtime version**.
- The repository was active when checked on 2026-11-14. GitHub Releases page currently shows no published releases; choose an audited commit/tag rather than relying on an unspecified moving `master`.
- License file: https://github.com/OpenVPN/openvpn3/blob/master/LICENSE.md — dual AGPLv3 or MPL 2.0. Review exact source/dependency notices and distribution obligations, particularly for static linking and App Store shipment, before vendoring C++.
- Upstream CMake instructions exist for macOS. Building a portable XCFramework for iOS/macOS/tvOS/visionOS is **not yet demonstrated**.

## 3. Apple NetworkExtension

- `NEPacketTunnelProvider` owns `packetFlow`, network settings, routing, DNS and MTU in the provider extension, not in a reusable SwiftUI view. Entitlement `com.apple.developer.networking.networkextension` is required: https://developer.apple.com/documentation/networkextension/nepackettunnelprovider
- Deployment overview (Apple TN3134): https://developer.apple.com/documentation/technotes/tn3134-network-extension-provider-deployment
  - iOS: packet tunnel provider app extension supported.
  - tvOS: packet tunnel provider extension since tvOS 17; restrictions apply to per-app mode.
  - visionOS: packet tunnel provider extension listed starting from visionOS 1.0; per-app restrictions depend on version.
  - macOS: requires its own provider deployment and signing decision.
  - watchOS: no corresponding packet tunnel provider row in this guidance; do not promise on-watch tunneling.
- API presence alone does not prove provisioning, entitlement availability for an account, deployment packaging or actual network functionality. Validate Apple platforms using Xcode and devices.

## 4. Current implementation strategy

- No vendored upstream C++ code in Phase 1 Swift-only foundation.
- Two package libraries: `MYCODEX` (value types, profile container, connection state vocabulary) and `MYCODEXConfiguration` (limited, read-only .ovpn endpoint inspection).
- Swift-tools version 6.0; provisional package floors iOS 16 / macOS 13 for the Swift-only core. These are **not** final tunnel deployment minima and do not imply that tvOS/visionOS/watchOS are supported by the SDK today.
- Separate future host-side tunnel manager from provider-side engine; do not use private API.
- Before engine integration: choose audited OpenVPN 3 SHA, cryptographic dependency strategy, license, C ABI or Obj-C++ wrapper, error/ownership model and build target matrix.

## 5. Risks and limitations

- Minimal .ovpn inspection is not full parsing and cannot validate arbitrary OpenVPN configuration; the OpenVPN engine must validate profiles before connection.
- Profiles can contain private keys. Treat them as sensitive; never log them, and store credentials in Keychain.
- Tests in Linux only validate portable Swift code, **not** NetworkExtension or the real VPN protocol.
- The ChatGPT GitHub integration can read `MYCODEX` but rejects write requests with HTTP 403 `Resource not accessible by integration`. Changes require an authorized write mechanism.
