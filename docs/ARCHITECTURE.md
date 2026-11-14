# MYCODEX — architecture proposal (not implemented)

## Goals
A reusable Swift-facing OpenVPN SDK with a stable API and a clear separation from Apple-specific VPN extension plumbing. No private framework APIs.

## Layers

```
Consumer app (SwiftUI / UIKit / AppKit)
    |  public async Swift API and events
MYCODEX Public SDK
    |-- Configuration parser / validation (.ovpn)
    |-- Credentials and identity references (Keychain integration)
    |-- Connection state, errors, metrics and diagnostics
    |-- Tunnel lifecycle coordinator
    |        |-- NetworkExtension integration (app / provider extension)
    |        |-- Platform-specific network settings, DNS, routes and MTU
    |-- Internal C/C++ bridge (memory and concurrency boundary)
    |        `-- Audited OpenVPN 3 Core version + vetted dependencies
    `-- Tests, examples and integration fixtures
```

The Swift package's public library may need separate host-side manager and extension-side runtime products, because a VPN extension owns `NEPacketTunnelProvider` and packet flow. Explicitly design safe communication boundaries and callback ownership.

## Package foundation and candidate expansion

```
Package.swift
Sources/
  MYCODEX/                # Swift-facing public API (no UI)
  MYCODEXConfiguration/   # Limited .ovpn inspection (not full validation)
  MYCODEXAppleTunnel/     # NetworkExtension integration
  COpenVPNBridge/         # C / ObjC++ boundaries where required
Tests/
  MYCODEXTests/
  ConfigurationTests/
Examples/
  AppleVPNExample/        # Future host app + tunnel extension
Docs/
  API.md
  MIGRATION.md
```

The `Package.swift`, `Sources/MYCODEX`, `Sources/MYCODEXConfiguration` and corresponding `Tests/` are part of the local Swift-only foundation patch (not yet uploaded). AppleTunnel, COpenVPNBridge, examples and an OpenVPN engine remain **proposals only**. See `docs/API_PROPOSAL.md` and `docs/RESEARCH.md`.

## Proposed public API traits
- Typed connection configuration and credential references, not raw unvalidated dictionaries.
- Explicit connection states and observable event stream (e.g. AsyncSequence).
- Explicit start/stop/cancel semantics, idempotent cleanup, reconnect policy and timeouts.
- Separate network extension configuration from protocol engine controls.
- Error types with actionable causes, without leaking credentials or raw secrets.
- Logging/metrics hooks with opt-in safe redaction and predictable resource limits.

## Critical constraints
- `NETunnelProviderManager` works with system-managed VPN configuration; provisioning, entitlements and user consent cannot be circumvented.
- Apple platform compatibility must be proven individually; do not assume watchOS or all visionOS/tvOS variants support packet tunnels.
- OpenVPN 3 Core and original OpenVPNAdapter have license obligations; legal compliance and dependency inventory precede vendoring/reuse.
- Do not claim system-wide routing/DoH/split tunneling unless the platform's NetworkExtension APIs and integration tests substantiate it.
- Measure extension memory, CPU and battery impact on hardware; no untested performance claims.
