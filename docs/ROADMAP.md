# MYCODEX — delivery roadmap

Every step must have tested evidence before marking COMPLETE. Current statuses: PLANNED except the drafted project docs, which still require GitHub publication.

## Phase 0 — bootstrap and investigation
- [ ] Publish prepared Markdown documentation in `main`, read it back through GitHub, confirm commit SHA.
- [ ] Audit upstream OpenVPNAdapter API, source layout, integration patterns and license notices; record what is intentionally replaced.
- [ ] Audit current OpenVPN 3 Core release/branch, license and dependency versions; decide source vs binary packaging.
- [ ] Verify Apple framework availability, VPN entitlement requirements and distribution rules per platform; set OS/Swift/Xcode baseline.
- [ ] Write initial public API proposal and migration strategy.

**Exit criteria:** written decisions with linked evidence and a small build/packaging spike plan.

## Phase 1 — buildable foundation
- [ ] Add Swift Package manifest, modules and build scripts.
- [ ] Create/verify the C/C++ bridge and OpenVPN Core linkage on macOS.
- [ ] Implement typed configuration model and validation with unit tests.
- [ ] Add CI matrix on supported Apple build targets with version pinning.

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
