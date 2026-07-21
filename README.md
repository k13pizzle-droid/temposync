# TempoSync v2 — Phase 0

Rhythm Coach + RunSync, per `tempo-sync-spec-v2.md`. This repo currently contains the two
**pure-Swift core-IP packages** from the kickoff prompt (steps 1–2), built and verified.

## What's here

```
TempoSyncV2/
  Packages/
    RoutineKit/        # §B4 routine generator — move library + grammar (zero platform imports)
    BeatKit/           # §B3 audio understanding — DSP spike + scoring harness (Accelerate only)
    RhythmCoachCore/   # app logic — coordinators, StructurePrior, resolver, SwiftData (pure Swift)
  App/                 # TempoSync iOS app (SwiftUI + iOS adapters), XcodeGen project
  Shelved/RunSync/     # RunSync (Product A) — shelved 2026-07-21, returns as a separate app
```

The three packages are ordinary SwiftPM packages; the app is an XcodeGen-generated Xcode project that
depends on all three. **RunSync is shelved** (Kevin's call after round-1 device testing — spin focus);
everything RunSync lives in `Shelved/RunSync/` with its own README for later revival.

## Toolchain note (important)

This machine has the **Swift command-line toolchain but not full Xcode**. Consequences:

- `swift build` / `swift run` work — so the packages compile and run here.
- `swift test` does **not** work — neither XCTest nor Swift Testing ships with the Command Line
  Tools. Install full Xcode to run the test suites.

To keep the core IP verifiable *today*, each package ships two ways to check it:

| Command | Needs Xcode? | What it does |
|---|---|---|
| `swift run RoutineKitCheck` | no | Runs every §B4 grammar rule + a 2,160-run fuzz sweep, prints ✅/❌ |
| `swift run BeatKitCheck`    | no | Generates the 100/128/174 BPM fixtures, round-trips WAV, scores vs the §B3 bar |
| `swift test` (in either package) | **yes** | The full XCTest suite (mirrors the Check harnesses) |

The `*Check` executables and the XCTest suites assert the same things — the Checks exist so the
grammar and DSP are provable without Xcode; the XCTest suites are your real CI/dev workflow once
Xcode is installed.

### Installing Xcode
```bash
open "macappstore://apps.apple.com/app/xcode/id497799835"   # ~17 GB, needs your Apple ID
# then:
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

## RoutineKit — the routine generator (§B4)

Pure Swift, deterministic in `(trackKey, seed)` — "same song, same class." Inputs: phrase grid +
section labels + BPM + confidence + skill + intensity dial. Output: a timed `MoveEvent` stream.

Every §B4 grammar rule is enforced by the generator and independently re-checked by `Grammar`:

- **Boundary alignment** — moves start on the 4-count grid; block length ∈ move's `allowedCounts`.
- **No 2-counts / dwell minimum** — every block ≥ 8 counts.
- **Section affinity** — moves only appear in sections they belong to (verse/chorus/drop/…).
- **Resistance-floor precedence** — every out-of-saddle / upper-body / climb move is preceded by an
  "add resistance" cue.
- **Density cap** — ≤ 1 upper-body block per 2 phrases (64 counts).
- **Mandatory recovery** — never 3 consecutive peak phrases; a recovery phrase is forced after 2.
- **Lead-leg alternation** — a switch cue ~every 2 phrases.
- **Determinism** — same `(track, seed)` → identical routine; different seed or track key → different.
- **Skill gating & intensity dial** — no move above the rider's skill; the dial biases effort tier.

Verified: all rules pass, and a **2,160-generation fuzz sweep** (120 seeds × 3 skills × 3 dials ×
2 confidences) produces **zero grammar violations**.

## BeatKit — the audio-understanding spike (§B3, open question 1)

Offline pipeline: `AudioBuffer` → spectral-flux **onset envelope** (vDSP FFT) → **autocorrelation
tempo** (with parabolic sub-lag refinement + half/double folding) → **beat-phase lock** →
**section detection** (energy-step + phrase snap). Reads/writes 16-bit PCM WAV for fixtures.

Scored against the spec's success bar on synthetic click tracks:

| Metric | Spec bar | Result |
|---|---|---|
| Tempo accuracy (within half/double) | ≥ 90% | **100%** (canonical 3 + 15-tempo sweep) |
| Beat-phase error | ≤ 50 ms | **100% pass** (14.8–41.0 ms on canonical 3) |
| Section boundary (energy jump) | — | located within 0.03–0.48 s |
| Half/double via `knownBPM` (GetSongBPM prior) | — | snaps to correct octave |

**Open-question 1 is answered: hand-rolled Accelerate DSP clears the bar — no need to compile aubio.**

### Real-song fixture set (open question 3)

The 10-track spin-playlist set is captured in `RealTrackFixtures.spinSetOne`, with reference BPM +
key + Camelot code confirmed from GetSongBPM/Tunebat (also seeds the shared `TrackTempo` cache and
RunSync's harmonic ranking). `referenceBPM` is optional by design: a `nil` entry models a track the
resolver can't find, falling back to BeatKit's on-device estimate.

To score BeatKit on real audio, drop a local copy of each track as `Fixtures/real/<slug>.wav`:
```bash
afconvert -f WAVE -d LEI16@44100 -c 1 input.m4a "Fixtures/real/<slug>.wav"   # macOS, owned files
swift run BeatKitCheck   # scores blind — reference BPM is NOT fed in, so it's a real validation
```
`swift run BeatKitCheck` prints the manifest and the exact slugs to use. (In the iOS app the same
buffers come from `AVAudioFile`/`AVAudioEngine`, so no conversion is needed there.)

## RhythmCoachCore — app logic (kickoff steps 3–6, platform-agnostic)

Third pure-Swift package: `BeatClock` + `RoutinePlayer` + `LiveCoach` (turn a count into a renderable
`LiveFrame` incl. BPM + suggested RPM), `StructurePrior` (Mode H heuristic sections), `SectionCapture`
(the learning loop: BeatKit analysis → typed phrase-aligned sections), `TrackTempoResolver` (fuzzy
title/artist → reference BPM, seeded from the fixture set — Mode H's real-tempo fix and Mode S's
half/double killer), and SwiftData `TrackTempoRecord` / `SectionMapRecord` with a higher-quality-replace
store. Platform I/O is behind protocols (`MicAudioSource` with hardware capture timestamps,
`NowPlayingSource`) so all of it is macOS-unit-tested — **14 tests**, including two integration tests
proving `StructurePrior → generator` and `capture → generator` both yield grammar-valid routines, plus
the `ModeSClockEstimator` (phase convergence + "tap the 1" reset).

**Mode S live hardening:** `ModeSClockEstimator` maps BeatKit's buffer-local beat grid onto wall-clock
time, smooths tempo (EMA), and *nudges* phase toward each detection (never snaps) so the pulse stays
smooth; session states `calibrating → locked → coasting → noisy`; a signal-quality gate coasts on the
last good lock instead of firing a wrong cue; "Tap the 1" hard-resets phase; the screen stays awake.

## TempoSync — the iOS app

`App/` is an XcodeGen project (`project.yml` is the source of truth; the `.xcodeproj` is generated and
git-ignored). SwiftUI live screen rendered via `TimelineView(.animation)` at native refresh rate:
beat-pulse ring, **animated Just-Dance-style move pictograms** (`MovePictogram` — rider pedals at the
song's tempo, jumps/tap-backs/corners have tempo-locked motion + direction arrows), BPM · RPM readout,
next-move countdown, phrase dots, resistance state, "Tap the 1" (Mode S). Adapters: `MicAudioSourceAV`
(Mode S — buffers stamped with hardware capture time via `AVAudioTime.hostTime`, the beat-accuracy
fix) and `NowPlayingSourceMP` (Mode H — 3 Hz position polling + extrapolation). Builds and runs on the
iOS 17+ simulator.

```bash
cd App
xcodegen generate
xcodebuild -project TempoSync.xcodeproj -scheme TempoSync -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
# Launch straight into the live demo (no mic needed):
#   SIMCTL_CHILD_TEMPOSYNC_DEMO=1 xcrun simctl launch <booted-device> com.pizzmusic.TempoSync
```

**Verified in the simulator:** the Demo Ride renders the live coaching screen from real generated
routine data; both simulator and device-arch (arm64) builds succeed. For running on a real iPhone
(signing + a mode-by-mode test checklist) see [`App/DEVICE_TESTING.md`](App/DEVICE_TESTING.md).

**Round-3 state (2026-07-21):** Mode H ("Ride to my music") is the primary experience. The generator
uses **class-style pacing** — a seeded per-song plan (~5 distinct moves in 15–90 s blocks, one
signature move recurring at every chorus/drop, sprints capped at 30 s) instead of per-phrase churn.
Track changes are detected and rebuild the ride. BPM resolves through the **waterfall**: SwiftData
cache → seeded fixtures → **Deezer** (no key; popularity-ranked search, `bpm` on track detail,
0 = not-analyzed = miss) → **GetSongBPM** (key in `App/Sources/Secrets.swift`, gitignored; Settings
overrides; attribution shown as their terms require). Both remote parsers are artist-STRICT: live
probing showed GetSongBPM ranks obscure covers first (Avicii "Levels" is unfindable via their search),
so an honest miss always beats a confidently wrong tempo. First hit is cached on-device forever. **Mode S (mic) UI is shelved** per device-testing feedback — the
code stays dormant in `LiveCoachViewModel` for the future calibration ride.

## Next milestone

**Calibration ride (full-song SectionMap capture)** — the one thing that fixes section *timing*
(when the chorus actually hits), which today is still a template guess: no service provides section
maps and DRM blocks direct audio analysis, so the only path is the shelved mic mode listening to one
speaker playthrough. Plan: accumulate onset/energy envelopes across the whole ride, segment at ride
end, store via `SectionMapStore` keyed by the now-playing track → Mode H flips to `learned`.

## Not yet built (Phase 1+)

MusicKit + Spotify adapters, watchOS haptics, skill tiers 3+ (spec Phase 1); shareable routines,
genre-tuned priors, community section maps (Phase 2). RunSync returns as a separate app (see
`Shelved/RunSync/README.md`).
