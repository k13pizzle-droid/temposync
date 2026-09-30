# TempoSyncV2 — Working Notes

Beat-synced spin coaching for iOS (Rhythm Coach). Tempo data by GetSongBPM.

- **Source of truth:** `README.md` (including its Toolchain note — read it before building) and `ROADMAP.md`; design spec referenced as `tempo-sync-spec-v2.md`.
- **Layout:** `Packages/RoutineKit` (routine generator — move library + grammar, zero platform imports), `Packages/BeatKit` (audio understanding — DSP + scoring, Accelerate only), `Packages/RhythmCoachCore` (app logic — coordinators, StructurePrior, resolver, SwiftData, pure Swift). `App/` is the SwiftUI iOS app, XcodeGen-generated, depending on all three packages.
- **Keep the purity boundaries:** the three packages are pure Swift by design — no UIKit/SwiftUI imports inside them.
- **RunSync is shelved** (2026-07-21, Kevin's call after round-1 device testing — spin focus won). Everything RunSync lives in `Shelved/RunSync/` with its own README. Don't revive or fold it back in without asking.
- Use the iOS Simulator tools to run and verify UI changes; `Pizz Music Apps/TempoSync-Pitch.pptx` is the pitch deck if positioning context is needed.

## Cloud sessions (Claude Code on the web, usually from Kevin's phone)

The cloud container is Ubuntu, not a Mac. No Xcode, no Simulator, no signing, and no Swift unless the environment's setup script installs it (see `.claude/cloud-setup.sh`). What works well from the phone: reading code, planning a change, editing Swift with care, updating `ROADMAP.md` and `App/DEVICE_TESTING.md`, drafting release notes, writing up a bug Kevin hit on the bike.

- Never say a build or test passed unless you ran it. If `swift` is on the PATH, `swift run RoutineKitCheck` inside `Packages/RoutineKit` is the only check that can pass on Linux. BeatKit needs Accelerate and RhythmCoachCore needs SwiftData, both Apple-only. Everything else is verified on the Mac.
- Commit to a branch named for the change and say so. Kevin pulls it down at his desk and runs it there.
- Keep replies short on the phone: answer first, no wide tables, one question at a time.
- This repo is public. Nothing personal, no client material, no API keys. `App/Sources/Secrets.swift` stays untracked.
- Anything that isn't about this app belongs in Kevin's private `go-bag` repo, not here.
