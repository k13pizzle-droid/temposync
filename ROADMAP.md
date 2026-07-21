# TempoSync — Product Roadmap to Consumer-Ready
*Working doc, started 2026-07-21. Owner: Kevin. Ordered by leverage, not effort.*

## ✅ Shipped in the current build (round 10)
- **Whole-app dark appearance** — killed the light/dark flip between menus and ride screens
  (`UIUserInterfaceStyle: Dark`; studio-app convention).
- **Swipe-to-remove** songs from the class plan (class-only exclusion; playlist untouched; plan re-fits).
- **Effort + skill settings** (Settings → Ride): Easy/Medium/Hard dial + skill tier 1–3, applied to
  every generated ride. Corners/Cross-Ups unlock at tier 3.

---

## NEXT — committed, in order
1. **Calibration ride** (approved): play a class playlist over the phone speaker once; the mic learns
   each song's true section timing (drops/choruses), keyed to the same track IDs Mode H uses. Every
   later headphone ride gets real chorus timing instead of template guesses. This is the single
   biggest quality unlock left. Plumbing exists (dormant Mode S, SectionMapStore, track-change
   detection); remaining work: progressive envelope accumulation, end-of-song segmentation, a
   "Calibrate" flow with per-song progress.
2. **Watch companion** (approved): transition/countdown/resistance-change haptics via
   WatchConnectivity so the rider never looks at the phone mid-sprint; move name on the wrist.
   Needs Kevin's paired Watch for the test loop. (Per-beat haptic pulses are impossible over BT
   latency — transitions only, by design.)
3. **TestFlight** (deferred until the above land): $99/yr Apple Developer Program; kills the 7-day
   re-sign dance and enables outside testers.

## Class builder — near-term improvements
- **Drag to reorder** the planned list manually (grip handles), on top of swipe-remove.
- **Per-song role override** — tap the role badge to change a song's job; planner respects pins.
- **Saved classes** — name a built class, re-ride it (same seeds = identical class, which is the
  point: learnable rides), share later.
- **Pre-ride storyboard** — the block timeline (already generated internally) as a scrollable
  preview: see every move block, duration, and section before riding.
- **Class templates** — climb-heavy day, sprint intervals, recovery spin, arms focus: presets that
  re-weight the arc.
- **Per-class effort override** (Settings default + a dial on the setup screen).
- **Smarter duration fit** — trim/extend via song selection to land within ±1 min of target.

## Ride experience — near-term
- **End-of-ride summary** — time, songs, sprint count, peak minutes, streak; feeds history.
- **Voice cues (optional)** — short spoken countdowns ("Sprint in 4") via AVSpeechSynthesizer with
  audio ducking; toggle in Settings. Visual-first stays the default.
- **Live Activity / lock-screen** — current move + countdown on the Lock Screen & Dynamic Island.
- **"Too hard / too easy" in-ride feedback** — one-tap adjust that re-biases the rest of the class.
- **Landscape handlebar layout** + optional screen-dim mode (battery/burn-in on long rides).
- **Auto-pause polish** — music stops → ride pauses cleanly (partially done via pause-freeze).
- **Pictogram v2** — richer character (filled silhouette option), form-tip sheet per move
  (tap the pictogram), optional short video demos (the spec's P1 item).

## Music & data — medium-term
- **MusicKit adapter** — full Apple Music catalog (current MPMediaQuery only sees the local
  library); catalog search, curated playlist import. Needs paid dev account + user AM subscription.
- **Spotify adapter** — the other half of the market; app-remote SDK controls playback the same way
  the transport bar does today. (Spec Phase 1.)
- **Community tempo + section maps** — CloudKit public database: one user's BPM lookup/calibration
  benefits everyone; free, serverless. (Spec Phase 2.)
- **Beat-grid offsets per track** — calibration byproduct; makes the Mode H pulse sample-accurate.
- **Genre-tuned StructurePriors** — better template guessing for hip-hop/rock when no learned map.

## Personalization & progress — medium-term
- **HealthKit workout sessions** — calories, heart rate, Activity-ring credit. Table stakes for a
  consumer fitness app; also enables HR-zone-aware coaching later (deliberately cut from v1).
- **Streaks / goals / badges** — weekly ride goals, class-completion streaks; history detail view
  with per-song breakdown.
- **Adaptive difficulty** — history-driven: rides trend harder as completion rate stays high;
  skill tier auto-suggests upgrades.

## Production-readiness checklist (the unglamorous list)
**Identity & App Store**
- [ ] App icon + branding; verify the name (trademark/App Store search) — "TempoSync" may collide.
- [ ] Launch screen, App Store screenshots, preview video of a live ride.
- [ ] Onboarding flow: what it does, permissions education (mic/media), bike-setup tips, safety
      disclaimer ("consult a physician…" — standard fitness-app legal).
- [ ] Privacy policy + terms. Our story is strong (all DSP on-device, nothing uploaded) — say it loudly.
- [ ] App Review prep: media-library usage justification, attribution links (GetSongBPM requirement).

**Quality & trust**
- [ ] Accessibility: VoiceOver labels on the live screen, Dynamic Type in menus, color-blind-safe
      role badges (add icons, not just color), Reduce Motion honored by the pictogram.
- [ ] Empty/error states: no playlists, no Apple Music subscription, song unavailable, offline
      (BPM lookups fail gracefully — already do — but say so in UI).
- [ ] Battery/thermal profiling: TimelineView at display refresh on a 120 Hz phone — consider
      capping the pulse at 60 fps.
- [ ] Localization scaffold (strings extracted) even if English-only at launch.
- [ ] Crash reporting + privacy-respecting analytics (e.g. TelemetryDeck), opt-in.

**Engineering hygiene**
- [ ] **`git init` + GitHub remote** — the project has no version control today (!). First step of
      any production path. CI after: GitHub Actions running `swift test` × 3 packages + xcodebuild.
- [ ] Release configuration, version/build automation, feature flags (roll calibration out safely).
- [ ] UI test smoke suite (launch → demo ride → class setup) on top of the 46 unit tests.
- [ ] iPad layout (`TARGETED_DEVICE_FAMILY` currently iPhone-only) — gym tablet mounts are a thing.

**Business (when ready)**
- [ ] Monetization decision: likely free ride + premium class builder/calibration ("TempoSync Pro"
      one-time or sub). Decide *after* retention proves itself with real users.
- [ ] TestFlight beta cohort → phased App Store rollout.

## Explicitly parked
- RunSync (separate app; `Shelved/RunSync/`).
- HR-zone input, BLE sensors (cut in v2 spec; HealthKit may partially revive HR display).
- Community/social features beyond shared maps (leaderboards etc.) — retention first.
