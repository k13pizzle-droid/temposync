# TempoSync — on-device testing (round 3)

Round-2 feedback: routines churned way too fast (real classes = 1–3 major moves/song) · track title
didn't update on song change · wire GetSongBPM · shelve the mic mode, focus on headphones · pictogram
should match RPM. All addressed. **"Ride to my music" (Mode H) is now the primary experience.**

## What changed in this build

1. **Class-style pacing (the big one).** The generator now works like a real instructor: it picks a
   small per-song plan — a base move for verses, ONE signature move that returns at every chorus/drop,
   an accent for the bridge — and rides each section as a long block. A typical song is now ~5
   distinct moves in deliberate 15–90 s blocks (was: a new move every 4–8 seconds). Sprints still cap
   at ~30 s with recovery after (safety rule).
2. **"Next:" is honest** — it names the next *different* move ("Next: Tap-Backs in 48"), not the next
   internal block of the same thing.
3. **Track changes are detected** — skip a song or let it end and the app rebuilds for the new track
   (title, BPM, routine) within a second.
4. **GetSongBPM wired.** Settings → paste your API key (free at getsongbpm.com/api). With a key, ANY
   song's real BPM resolves automatically — looked up once per song, then cached on-device forever.
   Without a key you still get the 10 seeded fixture tracks + honest "BPM est." elsewhere.
5. **Mic mode (Mode S) shelved from the UI** per your call — the code stays dormant for the future
   "calibration ride". No mic prompt anymore.
6. **Pictogram cadence**: the rider's legs turn exactly one crank revolution per 2 beats — i.e. the
   ~RPM number shown in the header. (During sprints the legs intentionally double to one rev/beat.)

## Setup: get your GetSongBPM key (2 min, yours to do)
1. Go to **getsongbpm.com/api** → sign up (free) → copy the API key.
2. In the app: **Settings → Tempo data → paste the key.**
(Their terms require the "Tempo data by GetSongBPM" attribution link — it's in Settings.)

## What to test

### Ride to my music (Mode H — the main flow)
Play any song in the Music app, then open **Ride to my music**.
- [ ] Status shows track title + real BPM (fixture tracks work with no key; others need the key).
- [ ] **Pacing feels like a class now?** Long blocks, one signature move recurring at choruses,
      sprints ~30 s max. This is the thing to judge.
- [ ] Skip to the next track mid-ride → title/BPM/routine update within ~1 s.
- [ ] Pause / scrub the song → pulse follows.
- [ ] Pedal figure's leg speed matches the ~RPM number.
- [ ] Play an obscure song with a key set → BPM resolves after a beat (status updates from
      "BPM est." to the real number).

### Known honest limitation (unchanged)
Section *timing* (when the chorus actually hits) is still a template guess scaled to song length —
no service provides section maps, and DRM blocks analyzing the audio. The fix is the shelved
calibration ride (play the song out loud once, the app learns its real structure); revisit when
you want it.

## What to send back
Pacing verdict (does it ride like a class?), any track where the BPM came back wrong, and whether
track-skip pickup feels fast enough.

---

## Setup
```bash
cd App && ./generate.sh && open TempoSync.xcodeproj
```
`generate.sh` regenerates the project and keeps your signing team: it lives in
`App/Signing.xcconfig` (gitignored, created on first run). Set it once —

```
DEVELOPMENT_TEAM = XXXXXXXXXX      # Xcode → Settings → Accounts → Team ID
```

— and you never have to touch Signing & Capabilities again, on any target, after any
regeneration. Then ⌘R. (Free Apple ID builds expire weekly — just re-run ⌘R.)

### Running on the iPhone + Watch
- **Scheme must be `TempoSync`**, destination your iPhone. Selecting `TempoSyncWidgets`
  runs the widget-extension debug flow instead and fails with a `SendProcessControlEvent`
  / "Failed to show Widget" error.
- **Unlock the phone before ⌘R.** A locked device refuses the launch request
  ("Unable to launch because the device was not, or could not be, unlocked").
- The watch app installs automatically with the phone app (it's embedded). Keep the Watch
  unlocked and near the phone; first install can take a couple of minutes.
- To debug the watch app itself, switch the scheme to `TempoSyncWatch` and pick the Watch
  as the destination.
- Terminal builds: **never pass `-sdk iphonesimulator`** with the embedded watch target —
  use `-destination` only, or the watch app tries to build against the iOS SDK.
