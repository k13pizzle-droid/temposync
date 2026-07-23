import Foundation

/// The rhythm vocabulary (v1 + Kevin's round-7 additions). An **ordered array** on purpose: the
/// generator filters this array to build candidate lists, so selection order is deterministic.
/// (Never iterate a Set or Dictionary during generation — Swift randomizes their iteration order
/// per process, which would break the "same (track, seed) → same routine" guarantee.)
///
/// Form cues are intentionally sparse (round-7 feedback): the animated pictogram carries the "how";
/// text only appears where it names a variant the pictogram can't fully disambiguate (wide/narrow).
public enum MoveLibrary {

    /// The base ride AND the recovery move (round-8: Recovery Spin merged in — same body position,
    /// the difference is just effort, which the section context already communicates). Universal
    /// affinity: easing back is always legal, which lets the safety step-down fire in any section.
    public static let seatedFlat = Move(
        name: "Seated Flat",
        allowedCounts: [8, 16, 32],
        intensityTier: .moderate,
        position: .seated,
        sectionAffinity: Set(SectionType.allCases),
        requiresResistanceFloor: false,
        upperBody: false,
        skillTier: .one,
        formCue: ""
    )

    /// Widened to choruses 2026-07-23: Standing Climb is gated to slow tracks (< 120 BPM), so with
    /// verses-and-bridges-only affinity a climb song at 128 BPM had no climb available for its
    /// biggest sections and defaulted to Standing Run — a "climb" song that never climbed.
    public static let seatedClimb = Move(
        name: "Seated Climb",
        allowedCounts: [16, 32],
        intensityTier: .high,
        position: .seated,
        sectionAffinity: [.verse, .preChorus, .chorus, .bridge],
        requiresResistanceFloor: true,
        upperBody: false,
        skillTier: .one,
        formCue: ""
    )

    public static let standingRun = Move(
        name: "Standing Run",
        allowedCounts: [8, 16, 32],
        intensityTier: .high,
        position: .standing,
        sectionAffinity: [.verse, .preChorus, .chorus, .drop],
        requiresResistanceFloor: true,
        upperBody: false,
        skillTier: .one,
        formCue: ""
    )

    /// Low-cadence grind — the generator only offers it on slower songs (< 120 BPM ≈ < 60 RPM).
    public static let standingClimb = Move(
        name: "Standing Climb",
        allowedCounts: [16, 32],
        intensityTier: .peak,
        position: .standing,
        sectionAffinity: [.preChorus, .chorus, .bridge],
        requiresResistanceFloor: true,
        upperBody: false,
        skillTier: .two,
        formCue: ""
    )

    public static let sprintSeated = Move(
        name: "Seated Sprint",
        allowedCounts: [8, 16],
        intensityTier: .peak,
        position: .seated,
        sectionAffinity: [.chorus, .drop],
        requiresResistanceFloor: true,
        upperBody: false,
        skillTier: .two,
        cadence: .sprint,
        formCue: ""
    )

    public static let sprintStanding = Move(
        name: "Standing Sprint",
        allowedCounts: [8, 16],
        intensityTier: .peak,
        position: .standing,
        sectionAffinity: [.chorus, .drop],
        requiresResistanceFloor: true,
        upperBody: false,
        skillTier: .two,
        cadence: .sprint,
        formCue: ""
    )

    /// Half-time heavy grind (seated): the beat is cut in half, legs turn once every 4 beats against
    /// heavy resistance. The "heavy song" feel — a slow, powerful grind (~32 RPM @128 BPM).
    public static let heavyClimb = Move(
        name: "Heavy Climb",
        allowedCounts: [16, 32],
        intensityTier: .high,
        position: .seated,
        sectionAffinity: [.verse, .preChorus, .chorus, .bridge],
        requiresResistanceFloor: true,
        upperBody: false,
        skillTier: .two,
        cadence: .grind,
        formCue: "Heavy · slow"
    )

    /// Half-time heavy grind out of the saddle — the peak of a heavy song.
    public static let standingHeavyClimb = Move(
        name: "Standing Heavy Climb",
        allowedCounts: [16, 32],
        intensityTier: .peak,
        position: .standing,
        sectionAffinity: [.preChorus, .chorus, .bridge],
        requiresResistanceFloor: true,
        upperBody: false,
        skillTier: .two,
        cadence: .grind,
        formCue: "Heavy · stand"
    )

    /// Jump blocks ladder their cadence (8-count → 4-count → 2-count cycles) as the block runs —
    /// the classic early-ride blood-pumper. The pictogram drives the ladder from time-into-move.
    public static let jumps = Move(
        name: "Jumps",
        allowedCounts: [8, 16],
        intensityTier: .high,
        position: .hybrid,
        sectionAffinity: [.chorus, .drop, .bridge],
        requiresResistanceFloor: true,
        upperBody: false,
        skillTier: .two,
        formCue: ""
    )

    // Section affinities widened 2026-07-23 (Kevin's choreography feedback + instructor sources):
    // rhythm choreography is cued "using the verse AND the chorus", not parked in bridges. Upper-body
    // work deliberately still avoids `.drop` — the drop stays the legs' payoff.
    public static let tapBacks = Move(
        name: "Tap-Backs",
        allowedCounts: [8, 16],
        intensityTier: .moderate,
        position: .seated,
        sectionAffinity: [.verse, .preChorus, .chorus, .bridge, .breakdown],
        requiresResistanceFloor: false,
        upperBody: false,
        skillTier: .one,
        formCue: ""
    )

    public static let pressDowns = Move(
        name: "Press-Downs",
        allowedCounts: [8, 16],
        intensityTier: .moderate,
        position: .seated,
        sectionAffinity: [.verse, .preChorus, .chorus, .bridge, .breakdown],
        requiresResistanceFloor: false,
        upperBody: true,
        skillTier: .one,
        formCue: ""
    )

    public static let handlebarPushups = Move(
        name: "Handlebar Push-Ups",
        allowedCounts: [8, 16],
        intensityTier: .high,
        position: .hybrid,
        sectionAffinity: [.verse, .chorus, .bridge, .breakdown],
        requiresResistanceFloor: true,
        upperBody: true,
        skillTier: .two,
        formCue: "Narrow grip"
    )

    public static let widePushups = Move(
        name: "Wide Push-Ups",
        allowedCounts: [8, 16],
        intensityTier: .high,
        position: .hybrid,
        sectionAffinity: [.verse, .chorus, .bridge, .breakdown],
        requiresResistanceFloor: true,
        upperBody: true,
        skillTier: .two,
        formCue: "Wide grip"
    )

    /// Alternating narrow/wide push-up sets, switching every 4 counts.
    public static let pushUpCombo = Move(
        name: "Push-Up Combo",
        allowedCounts: [8, 16],
        intensityTier: .high,
        position: .hybrid,
        sectionAffinity: [.verse, .chorus, .bridge, .breakdown],
        requiresResistanceFloor: true,
        upperBody: true,
        skillTier: .two,
        formCue: "Narrow · wide"
    )

    /// 4 counts of push-ups into 4 counts of tap-backs, repeating.
    public static let pushUpTapBackCombo = Move(
        name: "Push-Up + Tap-Back Combo",
        allowedCounts: [8, 16],
        intensityTier: .high,
        position: .hybrid,
        sectionAffinity: [.verse, .chorus, .bridge, .breakdown],
        requiresResistanceFloor: true,
        upperBody: true,
        skillTier: .two,
        formCue: ""
    )

    /// Upper-body figure-eight sweep over the bars, riding the beat.
    public static let figure8s = Move(
        name: "Figure 8s",
        allowedCounts: [8, 16],
        intensityTier: .moderate,
        position: .seated,
        sectionAffinity: [.verse, .preChorus, .bridge, .breakdown],
        requiresResistanceFloor: false,
        upperBody: true,
        skillTier: .two,
        formCue: ""
    )

    /// Hover: hips pushed back and lifted an inch off the saddle, held over the pedal stroke — an
    /// isometric core/glute burn. A control move, not upper body.
    public static let hovers = Move(
        name: "Hovers",
        allowedCounts: [16, 32],
        intensityTier: .high,
        position: .hybrid,
        sectionAffinity: [.verse, .preChorus, .bridge],
        requiresResistanceFloor: true,
        upperBody: false,
        skillTier: .two,
        formCue: "Hips back, hover"
    )

    /// Seated crunch: drop the elbows toward the bars and contract through the abs on the beat.
    /// Upper-body / core choreography.
    public static let crunches = Move(
        name: "Crunches",
        allowedCounts: [8, 16],
        intensityTier: .moderate,
        position: .seated,
        sectionAffinity: [.verse, .chorus, .bridge, .breakdown],
        requiresResistanceFloor: false,
        upperBody: true,
        skillTier: .two,
        formCue: ""
    )

    /// The 64-count combo: a repeating signature sequence (tap-backs → push-ups → hovers →
    /// crunches), one 16-count set each, cycling every 64 counts. The advanced "combo song"
    /// centerpiece — high cognitive load, so skill 3 only. Not tagged upper-body: the sequence
    /// self-balances leg and arm work, so it isn't subject to the continuous-upper-body cap.
    public static let combo64 = Move(
        name: "64-Count Combo",
        allowedCounts: [32],
        intensityTier: .high,
        position: .hybrid,
        sectionAffinity: [.chorus, .drop, .bridge],
        requiresResistanceFloor: true,
        upperBody: false,
        skillTier: .three,
        formCue: ""
    )

    public static let cornersCrossUps = Move(
        name: "Corners / Cross-Ups",
        allowedCounts: [16, 32],
        intensityTier: .high,
        position: .standing,
        sectionAffinity: [.verse, .chorus],
        requiresResistanceFloor: true,
        upperBody: false,
        skillTier: .three,
        formCue: ""
    )

    /// The full vocabulary, ordered.
    public static let v1: [Move] = [
        seatedFlat,
        seatedClimb,
        standingRun,
        standingClimb,
        heavyClimb,
        standingHeavyClimb,
        sprintSeated,
        sprintStanding,
        jumps,
        tapBacks,
        hovers,
        pressDowns,
        crunches,
        handlebarPushups,
        widePushups,
        pushUpCombo,
        pushUpTapBackCombo,
        figure8s,
        combo64,
        cornersCrossUps,
    ]
}
