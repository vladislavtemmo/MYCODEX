# MYCODEX — persistent project memory

**Last updated:** 2026-11-14  
**Status:** planning / documentation bootstrapping; no working VPN engine yet.

## Mission
Build a contemporary, maintainable OpenVPN SDK for Apple's ecosystem to replace reliance on the unmaintained `ss-abramchuk/OpenVPNAdapter`. This is an SDK/framework, not primarily a VPN client UI.

## Repository and reference
- Primary repository: `vladislavtemmo/MYCODEX` (GitHub, default branch `main`).
- Reference: https://github.com/ss-abramchuk/OpenVPNAdapter (archived; author explicitly discontinued support).
- Original adapter wraps OpenVPN 3 Core, uses Objective-C and NetworkExtension, and is AGPLv3-licensed. Historic behavior is useful to study but must not be copied blindly.
- Candidate protocol engine: actively maintained OpenVPN 3 Core, subject to version, build, export/compliance, dependency and licensing assessment.

## Product scope (target, NOT confirmed support)
- Tier 1: iOS, iPadOS, macOS.
- Research and validate separately: tvOS and visionOS, subject to Apple framework availability, entitlements and distribution rules.
- watchOS: investigate; do not promise a locally running packet-tunnel OpenVPN engine unless supported and verified.
- Minimum OS, Xcode/Swift versions and final licensing model are **not yet selected**.

## Design decisions agreed at project outset
1. Use Swift Package Manager as the preferred distribution mechanism.
2. Swift-first and async/await-facing public API where feasible; any lower-level bridge is internal.
3. Use Apple's NetworkExtension and authorized VPN entitlements, without private API.
4. Separate protocol engine, configuration/parser, tunnel orchestration, and public API.
5. Include tests, CI, diagnostics, structured error handling, and reproducible dependency versions.
6. Maintain a cross-chat handoff through versioned Markdown files, not ChatGPT's implicit memory.

## Capabilities to design and verify
.ovpn parsing and import, username/password and certificates, Keychain storage, UDP/TCP, DNS/routing/MTU/IPv4/IPv6, reachability/reconnect, cancellation, logs and traffic/session statistics. Include compatibility testing against OpenVPN and compatible SoftEther configurations. These are **targets**, not implemented features.

## Unresolved engineering questions
- Choose engine distribution and license compliance strategy (OpenVPN 3 Core and transitive dependencies).
- Determine minimum supported Apple OS / Swift / Xcode matrix after inspecting API/toolchain support.
- Validate tvOS/visionOS feasibility and watchOS boundaries with official APIs and device tests.
- Decide binary vs source package distribution and XCFramework build pipeline.
- Define any compatibility façade for migrating existing OpenVPNAdapter clients.

## Working protocol for every new chat
Read `AGENTS.md`, this document, `skills.md`, `PROGRESS.md`, then the docs folder before touching code. Check GitHub state. Conclude each completed task by writing tested facts into `PROGRESS.md`; move only stable decisions here. If repository write permission is absent, explicitly say so and supply ready-to-commit content.
