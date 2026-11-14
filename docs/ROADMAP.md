# MYCODEX — delivery roadmap

Every step must have tested evidence before marking COMPLETE. Current statuses are described per task; the initial documentation is published, but the Swift-only source patch is local pending upload.

## Phase 0 — bootstrap and investigation
- [x] Publish prepared Markdown documentation in `main`, read it back through GitHub, confirm commit SHA (`5066088c43326f06d6654c1dc52dd211945bdcb2`).
- [ ] Complete detailed upstream OpenVPNAdapter API/source/license audit (initial SwiftPM and source layout review recorded in `docs/RESEARCH.md`).
- [ ] Complete OpenVPN 3 Core audit (current master snapshot and dual-license file identified; dependency inventory and packaging decision pending).
- [ ] Verify Apple framework/deployment requirements on real Xcode targets (Apple TN3134 review done; final OS/Swift/Xcode baseline still open).
- [ ] Finalize public tunnel API and migration strategy (initial draft in `docs/API_PROPOSAL.md`).

**Exit criteria:** written decisions with linked evidence and a small build/packaging spike plan.

## Phase 1 — buildable foundation
- [ ] Publish Swift Package manifest, modules and test script (created and Linux-tested in local patch; GitHub upload pending).
- [ ] Create/verify the C/C++ bridge and OpenVPN Core linkage on macOS.
- [ ] Implement typed configuration model and validation with unit tests.
- [ ] Run and pin CI matrix on supported Apple build targets (portable macOS/Linux workflow created in local patch; not executed on GitHub).

**Exit criteria:** reproducible build and passing tests on recorded destinations.

## Phase 2 — first tunnel
- [ ] Build example app + Packet Tunnel extension with proper entitlement setup.
- [ ] Implement connect, disconnect, error propagation and cancellation.
- [ ] Validate UDP and TCP with real OpenVPN endpoints and a compatible SoftEther test environment.
- [ ] Add secure credential handling and no-secret logs.

**Exit criteria:** real-device connection evidence (iOS/iPadOS, macOS), diagnostics and teardown tests.

## Phase 3 — resilience and compatibility
- [ ] Network transitions, route/DNS/MTU, IPv6 and reconnect.
- [ ] Configuration fixtures and backwards-compatibility adapter where practical.
- [ ] Fault-injection, soak, resource and regression tests.

**Exit criteria:** documented compatibility matrix and reproducible test results.

## Phase 4 — Apple ecosystem expansion
- [ ] Investigate/validate tvOS and visionOS independently.
- [ ] Record watchOS API limitation decision; offer only proven feasible interactions.
- [ ] Produce sample apps, migration guide, reference docs, license notices and versioned releases.

**Exit criteria:** release artifacts and support matrix based on measured builds/devices.
