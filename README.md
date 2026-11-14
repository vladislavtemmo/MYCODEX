# MYCODEX

**Modern OpenVPN SDK for the Apple ecosystem — Swift-only foundation stage.**

MYCODEX aims to provide a maintained Swift-first OpenVPN library, integrated with Apple's NetworkExtension and packaged using Swift Package Manager, as a successor in purpose (not yet in implementation) to the archived [OpenVPNAdapter](https://github.com/ss-abramchuk/OpenVPNAdapter).

**Priority platforms:** iOS, iPadOS, macOS. **Research targets:** tvOS, visionOS; watchOS is subject to platform restrictions and is *not* promised to run a local OpenVPN tunnel.

The first phase adds a **Swift-only package** containing typed models, redacted profile containers and limited `.ovpn` endpoint inspection. This does **not** include a functional VPN engine, NetworkExtension provider, VPN authentication or live packet transport.

## Start here

- [AGENTS.md](AGENTS.md) — mandatory instructions for agents and cross-chat handoffs
- [memory.md](memory.md) — durable decisions and scope
- [skills.md](skills.md) — engineering rules, reviews and testing
- [PROGRESS.md](PROGRESS.md) — dated work log and next action
- [Architecture](docs/ARCHITECTURE.md) — proposed modules and boundaries
- [Roadmap](docs/ROADMAP.md) — implementation phases and acceptance criteria
- [Research](docs/RESEARCH.md) — verified upstream, licensing and Apple API findings
- [API proposal](docs/API_PROPOSAL.md) — current foundation and proposed future tunnel API

## Continue in another chat

Connect the same GitHub account and ask: "Read `vladislavtemmo/MYCODEX` files `AGENTS.md`, `memory.md`, `skills.md`, `PROGRESS.md`, and `docs/ROADMAP.md` and continue the first open task. Update the log after verified work."

Files are a shared, versioned knowledge base — **not** automatic cross-chat memory. Every assistant must read and commit them explicitly.

## Legal and platform constraints

Original OpenVPNAdapter is AGPLv3-licensed and discontinued by its author; OpenVPN 3 Core/dependency licensing and Apple's VPN entitlement restrictions must be verified before distributing any implementation. No upstream source code is included in this bootstrap.

## Swift package (first local development increment)

The Swift-only foundation contains `MYCODEX` and `MYCODEXConfiguration`. With Swift 6 installed, run `swift test` on an available development host. The package currently uses provisional floors iOS 16/macOS 13; **Apple target builds and VPN functionality have not been validated**.

Do not mistake `OpenVPNProfileInspector` for a full `.ovpn` parser or a credential/security validator.

The `swift-package.yml` workflow is a **proposal committed with this patch**, not proof of a green GitHub Actions run.
