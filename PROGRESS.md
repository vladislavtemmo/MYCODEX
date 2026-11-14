# MYCODEX — development progress and handoff log

## Current status
**Phase:** 0 research + Phase 1 Swift-only foundation prototype (local patch awaiting GitHub upload).  
**Runtime engine:** not implemented.  
**Automated tests:** 8 unit tests passed on Swift 6.2.1 Linux (local patch).  
**Published SDK:** none.

## 2026-11-14 — project kickoff
**Goal:** establish shared memory and working rules for multiple ChatGPT/Codex sessions; define a modern OpenVPN SDK vision.

**Completed in the prepared documentation bundle:**
- Drafted `README.md` to explain project scope and onboarding.
- Drafted `AGENTS.md` to make AI agents read and update the shared files.
- Drafted `memory.md` for permanent decisions and project state.
- Drafted `skills.md` for technical standards and acceptance criteria.
- Drafted `docs/ARCHITECTURE.md` and `docs/ROADMAP.md`.
- Confirmed upstream `ss-abramchuk/OpenVPNAdapter` is archived and its README explicitly notes discontinued support.

**Publication update:** User uploaded the initial seven docs; GitHub verified commit `5066088c43326f06d6654c1dc52dd211945bdcb2` in `main`. GitHub connector still rejects direct writes (403), including branch creation. New source patch is local only until uploaded.

**Tests:** none — documentation-only work; no native Apple build environment used.

**Next action at that point:** verify documentation; audit upstream and create a minimal Swift package.

## 2026-11-14 — source foundation and upstream research (local patch)
**Objective:** begin Swift-only foundation without prematurely vendoring OpenVPN 3 C++.

- **GitHub verification:** all original seven docs found in `main`, commit `5066088c43326f06d6654c1dc52dd211945bdcb2`.
- **Upstream audit:** original adapter SwiftPM tools version 5.1, vendored ASIO/LZ4/mbedTLS; current upstream OpenVPN 3 C++ client, dual AGPLv3/MPL 2.0, research snapshot `0c1ce172fe918b05463d71e682a0c2f2d8fe7899`; see `docs/RESEARCH.md`.
- **Apple review:** official NetworkExtension packet tunnel and TN3134 documentation reviewed; Apple builds, entitlements and devices have not been tested.
- **Local files added:** `Package.swift`, `.gitignore`, `scripts/test.sh`, `.github/workflows/swift-package.yml` (CI declaration only, not executed), 4 Swift source files (types and redacted profile), `OpenVPNProfileInspector.swift`, 2 XCTest files, `docs/RESEARCH.md`, `docs/API_PROPOSAL.md`.
- **Local files updated:** `README.md`, `AGENTS.md`, `memory.md`, `docs/ARCHITECTURE.md`, `docs/ROADMAP.md`, this file.
- **Tests:** `swift test` on Swift 6.2.1 / x86_64 Linux: **8 passed, 0 failures**. No Xcode or Apple-platform build. No OpenVPN 3 engine integration and no real VPN traffic.
- **Known limitations:** inspector extracts only top-level `remote`/`proto`; no full `.ovpn` parser; `OpenVPNProfile` checks bounded text only. No credential management, session runtime, networking or NetworkExtension package yet.
- **Blocker:** GitHub connector read works, create branch/file returns 403 `Resource not accessible by integration` even though account can upload in GitHub website. New patch has **not** been committed by assistant; GitHub CI workflow still awaits first run.
- **Next:** user uploads source patch to `main`, verify file tree, run `swift test` on macOS/Xcode, then audit/pin OpenVPN 3 engine, decide licenses/build path, start C++ bridge proof of concept.

## Template for future entries
### YYYY-MM-DD — task title
- Objective / issue:
- Branch / commit / PR:
- Files changed:
- Implementation:
- Tests executed and actual results:
- Unverified areas:
- Decisions / risks:
- Next task:

Do not erase older log entries; append new dated entries. Keep the summary at the top current.
