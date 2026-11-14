# MYCODEX

**Modern OpenVPN SDK for the Apple ecosystem — planning stage.**

MYCODEX aims to provide a maintained Swift-first OpenVPN library, integrated with Apple's NetworkExtension and packaged using Swift Package Manager, as a successor in purpose (not yet in implementation) to the archived [OpenVPNAdapter](https://github.com/ss-abramchuk/OpenVPNAdapter).

**Priority platforms:** iOS, iPadOS, macOS. **Research targets:** tvOS, visionOS; watchOS is subject to platform restrictions and is *not* promised to run a local OpenVPN tunnel.

This repository currently contains a project charter, architecture proposal and cross-chat handoff documents, **not a functional VPN engine**.

## Start here

- [AGENTS.md](AGENTS.md) — mandatory instructions for agents and cross-chat handoffs
- [memory.md](memory.md) — durable decisions and scope
- [skills.md](skills.md) — engineering rules, reviews and testing
- [PROGRESS.md](PROGRESS.md) — dated work log and next action
- [Architecture](docs/ARCHITECTURE.md) — proposed modules and boundaries
- [Roadmap](docs/ROADMAP.md) — implementation phases and acceptance criteria

## Continue in another chat

Connect the same GitHub account and ask: "Read `vladislavtemmo/MYCODEX` files `AGENTS.md`, `memory.md`, `skills.md`, `PROGRESS.md`, and `docs/ROADMAP.md` and continue the first open task. Update the log after verified work."

Files are a shared, versioned knowledge base — **not** automatic cross-chat memory. Every assistant must read and commit them explicitly.

## Legal and platform constraints

Original OpenVPNAdapter is AGPLv3-licensed and discontinued by its author; OpenVPN 3 Core/dependency licensing and Apple's VPN entitlement restrictions must be verified before distributing any implementation. No upstream source code is included in this bootstrap.
