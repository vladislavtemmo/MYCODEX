# Public API proposal — not a finished implementation

## Swift-only foundation (implemented in local patch)

```swift
import MYCODEX
import MYCODEXConfiguration

let profile = try OpenVPNProfile(ovpnText: """
client
proto udp
remote vpn.example.org 1194
""")

let endpoints = try OpenVPNProfileInspector.remoteEndpoints(in: profile)
// [OpenVPNEndpoint(hostname: "vpn.example.org", port: 1194, transport: .udp)]
```

`OpenVPNProfile` performs *only* bounded-text checks (nonblank, <= 1 MiB, no NUL). `OpenVPNProfileInspector` finds top-level `remote` and `proto` directives only, ignores inline certificate/key blocks, and does not verify DNS, cipher compatibility, server identity or the full OpenVPN grammar. There is no VPN connection capability in these two libraries yet.

## Proposed client-facing API (NOT IMPLEMENTED)

```swift
// Illustrative API direction only. Names and signatures are not final.
public protocol MYCODEXTunnelSession: Sendable {
    var events: AsyncStream<OpenVPNConnectionEvent> { get }
    func start(using profile: OpenVPNProfile, credentialReference: Data?) async throws
    func stop() async
}
```

Design boundaries to resolve before implementation:

1. Host application: `NETunnelProviderManager` configuration, user consent and start/stop commands.
2. Provider extension: `NEPacketTunnelProvider`, `NEPacketTunnelFlow`, network settings, callbacks, lifecycle, tunnel memory/CPU budget.
3. Engine: audit-pinned OpenVPN 3 Core C++ with narrow C ABI/Obj-C++ bridge, explicit packet ownership, cancellation, no C++ exception across C.
4. Credentials: Keychain persistent references and least privilege; no plaintext password in `UserDefaults`, logs, or `providerConfiguration`.
5. Events and state: no duplicate start/stop completions; reconnect/error classification; callback-to-async handoff without blocking packet threads.
6. Integration tests: a real signed extension and a real OpenVPN server; SoftEther interoperability separately verified.

## Acceptance gates for implementation

- Document each public API's ownership, thread isolation, cancellation and errors.
- Provide legitimate signed NetworkExtension examples (no entitlement bypass).
- Confirm builds for each marketed Apple platform with pinned dependencies.
- Do not describe an unbuilt provider or engine as supported.
