# Instructions for AI agents — MYCODEX

This file is the mandatory entry point for ChatGPT, Codex, and other assistants working in this repository.

## Session start
1. Read `memory.md`, `skills.md`, `PROGRESS.md`, `docs/ARCHITECTURE.md`, and `docs/ROADMAP.md` in this order; read `docs/RESEARCH.md` and `docs/API_PROPOSAL.md` when working on implementation.
2. Inspect the actual repository tree and current branch before making claims about implemented functionality.
3. Respect confirmed decisions in `memory.md`; treat roadmap entries as proposals, not completed work.
4. Identify one task and acceptance criteria before editing production code.

## Session end — mandatory persistent handoff
1. Update `PROGRESS.md`: date, goal, files touched, changes made, tests (with actual results), blockers, next task.
2. Update `memory.md` only for durable decisions or newly verified facts, not ephemeral chat commentary.
3. Update `docs/ARCHITECTURE.md` when components/interfaces or supported-platform decisions change.
4. Never report a file as committed unless GitHub confirms the write; if write access fails, provide a patch or files and record the blocker.
5. No secrets, tokens, passwords, private keys, signing certificates, account identifiers, or user data in these documents.

## Technical principles
- Swift-first public API; keep OpenVPN engine behind a narrow C/C++ bridge.
- Apple NetworkExtension controls tunnels and permissions; do not use private Apple APIs or claim to bypass entitlements.
- Platform-specific availability must be verified with Apple SDK and physical/virtual-device tests.
- Preserve .ovpn interoperability where practical and validate against real servers.
- Review dependency licensing, especially AGPL/MPL obligations, before integrating upstream code.
- Never mark tests/builds passed without actually running them; distinguish unit, build, simulator, and device tests.
