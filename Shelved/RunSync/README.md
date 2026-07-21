# RunSync — shelved 2026-07-21

Kevin's call: focus entirely on the spin product (Rhythm Coach); RunSync will return later as a
**separate app**. Everything RunSync-specific was moved here so the main app carries zero running
code, permissions, or UI.

## What's in this folder

| File | What it is | Where it lived |
|---|---|---|
| `RunSyncEngine.swift` | The cadence-matching engine: EMA smoothing, ±6 BPM/20s dead band, half/double-time equivalence, no-repeat window, ≤1 switch per 90s. Pure Swift, fully unit-tested when it was removed. | `Packages/RhythmCoachCore/Sources/RhythmCoachCore/` |
| `RunSyncView.swift` | Minimal SwiftUI screen: now-playing card, live pedometer toggle, cadence simulator slider. | `App/Sources/RunSync/` |
| `CadenceSourceCM.swift` | `CMPedometer` adapter (steps/min). Conformed to the `CadenceSource` protocol. | `App/Sources/Adapters/` |
| `RunSyncEngineTests.swift` | The 3 unit tests that covered the engine (first-track pick + half/double match, dead-band suppression, sustained-change switch). | extracted from `RhythmCoachCoreTests` |

Also removed from the main app when this was shelved:
- `CadenceSource` protocol from `RhythmCoachCore/Sources.swift`
- The RunSync section from `RootView`
- `NSMotionUsageDescription` from `App/project.yml` (no motion permission prompt anymore)

## State when shelved
All engine tests were green. The pedometer path compiled for device but was never validated on
hardware (simulator has no step data). Everything here was working code, not a broken draft.

## To revive as its own app
1. New XcodeGen project (copy `App/project.yml`, drop mic/media permissions, keep
   `NSMotionUsageDescription`, add HealthKit if going the Watch route).
2. Depend on `RoutineKit`-style shared packages? No — RunSync only needs `BeatKit`'s BPM data via
   the shared `TrackTempo` cache and the resolver. The engine itself is self-contained.
3. Re-add a `CadenceSource` protocol (it was 6 lines — see git history or `CadenceSourceCM.swift`'s
   conformance) or just use the concrete `CMPedometer` adapter directly.
4. Drop these three Swift files in, re-add the tests, wire `RunSyncView` as the root.
5. Spec reference: §A (RunSync) in `tempo-sync-spec-v2.md` — the Watch (`HKWorkoutSession`) source
   and the harmonic/energy ranking from v1 §7.4 were never built and remain the open items.
