import Foundation

/// Turns a phrase grid + section labels into a timed `MoveEvent` stream that obeys every grammar
/// rule in spec §B4 — paced like a real rhythm class.
///
/// **Class-style pacing** (v2, after round-2 device feedback): real Peloton/SoulCycle-style rides
/// assign ~1–3 major moves per song, not a new move every phrase. Verses are seated/base work,
/// choruses go out of the saddle, and the chorus gets the SAME signature move every time it returns.
/// So the generator first builds a seeded per-song `SongPlan` — one primary move per section *type* —
/// then walks the song phrase by phrase emitting long same-move blocks:
///   · a section plays its planned move for its whole length
///   · long peak sections open with a build phrase (standing run) before the signature move hits
///   · CHOREOGRAPHY songs give a recurring set (push-ups, tap-backs…) alternate phrases all song
///   · bridge/breakdown may layer ONE upper-body accent block at their top (density-capped)
///   · after 2 consecutive peak phrases a recovery phrase is forced (safety canon, unchanged)
/// Cues (form/countdown) fire only on actual move *transitions*, so the ride reads as a handful of
/// deliberate blocks. Deterministic in `(trackKey, seed)`.
public struct RoutineGenerator {

    public let library: [Move]

    public init(library: [Move] = MoveLibrary.v1) {
        self.library = library
    }

    // MARK: - Public API

    public func generate(_ request: RoutineRequest) -> Routine {
        let sections = request.sections.sorted { $0.startCount < $1.startCount }
        guard let first = sections.first, let last = sections.last else {
            return Routine(trackKey: request.trackKey, seed: request.seed,
                           startCount: 0, endCount: 0, events: [])
        }

        let start = first.startCount
        let end = last.endCount
        let phraseLen = Routine.phraseLength

        // Seed folds in the track key so different tracks with the same seed still differ.
        var rng = SplitMix64(seed: request.seed ^ stableHash(request.trackKey))

        let plan = buildPlan(sections: sections, request: request, rng: &rng)

        var events: [MoveEvent] = []
        var resistanceUp = false
        var consecutivePeakPhrases = 0
        var forcedRecovery = false
        var lastUpperBodyEnd: Int? = nil
        var previousMoveName: String? = nil

        var phraseIndex = 0
        var cursor = start

        while cursor + phraseLen <= end {
            let section = sectionCovering(cursor, in: sections) ?? first
            let isLeadLegPhrase = (phraseIndex % 2 == Int(plan.leadLegParity))

            var phraseEvents: [MoveEvent] = []

            if forcedRecovery {
                // Safety step-down after 2 peak phrases. Inside a high-energy section this is ACTIVE
                // recovery (standing run — the work continues, just sub-peak), not a dead stop:
                // round-3 feedback ("Calling" test) — the chorus should stay the workout's center of
                // gravity. Recovery spin only where the section is easy anyway.
                let stepDown = stepDownMove(for: section)
                let ev = makeEvent(
                    move: stepDown, startCount: cursor, counts: phraseLen, routineStart: start,
                    isTransition: previousMoveName != stepDown.name,
                    isLeadLegPhrase: isLeadLegPhrase, confidence: request.confidence,
                    resistanceUp: &resistanceUp, lastUpperBodyEnd: &lastUpperBodyEnd
                )
                phraseEvents.append(ev)
                previousMoveName = stepDown.name
                forcedRecovery = false
                consecutivePeakPhrases = 0
            } else {
                let placement = sectionPlacement(of: cursor, in: section)
                let layout = phraseLayout(
                    section: section, placement: placement, plan: plan,
                    at: cursor, lastUpperBodyEnd: lastUpperBodyEnd,
                    previousMoveName: previousMoveName
                )

                var offset = 0
                for move in layout {
                    let sc = cursor + offset
                    let counts = tileLength(for: move)
                    // Tile the move across its slice of the phrase.
                    var remaining = layoutSlice(layout: layout, of: move, phraseLen: phraseLen)
                    remaining = min(remaining, phraseLen - offset)
                    var tiled = 0
                    while tiled < remaining {
                        let ev = makeEvent(
                            move: move, startCount: sc + tiled, counts: min(counts, remaining - tiled),
                            routineStart: start,
                            isTransition: previousMoveName != move.name && tiled == 0,
                            isLeadLegPhrase: isLeadLegPhrase && offset == 0 && tiled == 0,
                            confidence: request.confidence,
                            resistanceUp: &resistanceUp, lastUpperBodyEnd: &lastUpperBodyEnd
                        )
                        phraseEvents.append(ev)
                        previousMoveName = move.name
                        tiled += ev.counts
                    }
                    offset += remaining
                }

                // Peak / recovery bookkeeping on the phrase grid.
                let phrasePeak = phraseEvents.contains { $0.move.intensityTier == .peak }
                consecutivePeakPhrases = phrasePeak ? consecutivePeakPhrases + 1 : 0
                if consecutivePeakPhrases >= 2 {
                    forcedRecovery = true
                    consecutivePeakPhrases = 0
                }
            }

            events.append(contentsOf: phraseEvents)
            cursor += phraseLen
            phraseIndex += 1
        }

        // Tail remainder (< one phrase): fill with a single easy block if it is at least 8 counts.
        let remainder = end - cursor
        if remainder >= 8 {
            let len = (remainder / 4) * 4
            if len >= 8 {
                let move = MoveLibrary.seatedFlat
                let ev = makeEvent(
                    move: move, startCount: cursor, counts: len, routineStart: start,
                    isTransition: previousMoveName != move.name, isLeadLegPhrase: false,
                    confidence: request.confidence,
                    resistanceUp: &resistanceUp, lastUpperBodyEnd: &lastUpperBodyEnd
                )
                events.append(ev)
            }
        }

        return Routine(trackKey: request.trackKey, seed: request.seed,
                       startCount: start, endCount: end, events: events)
    }

    // MARK: - The per-song plan (the "1–3 major moves" heart of class pacing)

    struct SongPlan {
        /// Primary move per section type — chorus/drop entries are the song's signature moves.
        /// Always a legs move: choreography rides on top of it (see `choreo`).
        var primary: [SectionType: Move]
        /// Optional upper-body accent for bridge/breakdown tops.
        var accent: [SectionType: Move]
        /// CHOREOGRAPHY SONGS: the recurring set (push-ups, press-downs, tap-backs…) that owns
        /// alternate phrases of every section it's legal in, making it the song's main event
        /// rather than a 7-second stab. Empty on effort songs (climbs, sprints, bookends).
        var choreo: [SectionType: Move]
        /// The build move that opens long peak sections before the signature hits.
        var buildMove: Move
        /// Seeded 0/1: which phrases carry the lead-leg cue (keeps reshuffles structurally distinct).
        var leadLegParity: UInt64
    }

    /// Chance an eligible song (no strong effort role of its own) is choreography-forward.
    /// Real classes alternate: a couple of "moves" songs per class, not every song and not none.
    private static let choreoSongChance: UInt64 = 70

    /// Rhythm choreography: upper-body work, plus tap-backs — a seated move, but one a rider
    /// experiences as choreography rather than as effort.
    static func isChoreography(_ move: Move) -> Bool {
        move.upperBody || move.name == MoveLibrary.tapBacks.name
    }

    private func buildPlan(sections: [Section], request: RoutineRequest, rng: inout SplitMix64) -> SongPlan {
        var primary: [SectionType: Move] = [:]
        var accent: [SectionType: Move] = [:]

        let presentTypes = Set(sections.map { $0.type })

        // Section types are grouped into ROLES that share one pick — this is what keeps a song at a
        // handful of moves: easy bookends share, bridge/breakdown share, chorus is the signature.
        // `maxTier` caps the role's effort: builds and bookends never spend the peak budget — the
        // peak belongs to the chorus/drop payoff (and the 2-peak-phrase safety rule stays armed for it).
        let roleGroups: [(types: [SectionType], anchor: SectionType, maxTier: IntensityTier)] = [
            ([.intro, .outro], .intro, .moderate),
            ([.verse], .verse, .high),
            ([.preChorus], .preChorus, .high),
            ([.chorus], .chorus, .peak),
            ([.drop], .drop, .peak),
            ([.bridge, .breakdown], .bridge, .high),
        ]

        for group in roleGroups {
            let present = group.types.filter { presentTypes.contains($0) }
            guard !present.isEmpty else { continue }
            let move = pickPlanMove(forAll: present, target: group.anchor, maxTier: group.maxTier,
                                    request: request, rng: &rng)
            for type in present { primary[type] = move }
        }

        // Drop shares the chorus signature when the signature is drop-legal — the recurring hook.
        if let chorusMove = primary[.chorus], presentTypes.contains(.drop),
           chorusMove.sectionAffinity.contains(.drop) {
            primary[.drop] = chorusMove
        }

        // Warm-up and cooldown songs carry NO accents — just easy riding in and out of the class.
        let easyBookendRole = request.classRole == .warmup || request.classRole == .cooldown

        if !easyBookendRole {
            // Upper-body accent for bridge/breakdown tops (push-ups / press-downs) — always present
            // when the skill level allows it. An ARMS song extends accents to every section type
            // (the density cap still spaces them out).
            let accentTypes: [SectionType] = request.classRole == .arms
                ? [.verse, .preChorus, .chorus, .bridge, .breakdown]
                : [.bridge, .breakdown]
            for type in accentTypes where presentTypes.contains(type) {
                let pool = library.filter {
                    $0.upperBody && $0.sectionAffinity.contains(type) && $0.skillTier <= request.skillLevel
                }
                if !pool.isEmpty {
                    accent[type] = pool[Int(rng.next() % UInt64(pool.count))]
                }
            }

            // Tap-backs accent at verse tops — the classic verse choreography — unless the verse
            // already rides tap-backs as its primary.
            if presentTypes.contains(.verse),
               primary[.verse]?.name != MoveLibrary.tapBacks.name,
               MoveLibrary.tapBacks.skillTier <= request.skillLevel {
                accent[.verse] = MoveLibrary.tapBacks
            }
        }

        // Is this a CHOREOGRAPHY song? Effort songs (climb/sprint) and the easy bookends keep the
        // legs as the whole story; everything else can become a "moves" song, where one set recurs
        // across the whole track. Without this, upper-body work could only ever be a single
        // half-phrase accent (~7 s a song) — nothing like a real class, where a track is often
        // *the push-up song* or *the tap-back song*.
        let choreoForward: Bool = {
            switch request.classRole {
            case .arms:                                   return true
            // Songs with a signature of their own keep it: the jumps song is about jumps, the
            // sprint song about sprints. Choreography would steal the phrases that ARE the point.
            case .warmup, .cooldown, .sprint, .climb, .jumps: return false
            // Recovery songs can carry LIGHT rhythm work (tap-backs, press-downs) — that's a real
            // active-recovery track, and it keeps every class from being choreography-free.
            case .recovery:                               return rng.next() % 100 < Self.choreoSongChance
            case .run, .none:                             return rng.next() % 100 < Self.choreoSongChance
            }
        }()

        var choreo: [SectionType: Move] = [:]
        if choreoForward && !easyBookendRole {
            // Bookends stay simple; everything else can host the set.
            let hostTypes: [SectionType] = [.verse, .preChorus, .chorus, .drop, .bridge, .breakdown]
                .filter { presentTypes.contains($0) }
            // Choreography = upper-body work plus tap-backs (a rhythm move that reads the same way
            // to a rider) — except on an ARMS track, where the whole point is the arms, so the set
            // must be real upper-body work. Ordered library filter keeps the pick deterministic.
            let armsTrack = request.classRole == .arms
            // A recovery track stays recovery: light choreography only, nothing high-tier.
            let easyOnly = request.classRole == .recovery
            let pool = library.filter { move in
                (armsTrack ? move.upperBody : Self.isChoreography(move))
                    && (!easyOnly || move.intensityTier <= .moderate)
                    && move.skillTier <= request.skillLevel
                    && hostTypes.contains(where: { move.sectionAffinity.contains($0) })
            }
            if !pool.isEmpty {
                let pick = pool[Int(rng.next() % UInt64(pool.count))]
                for type in hostTypes where pick.sectionAffinity.contains(type) {
                    choreo[type] = pick
                }
            }
        }

        return SongPlan(primary: primary, accent: accent, choreo: choreo,
                        buildMove: MoveLibrary.standingRun,
                        leadLegParity: rng.next() % 2)
    }

    /// Section → baseline effort tier (spec §B1 effort convention).
    private func baselineTier(for section: SectionType) -> IntensityTier {
        switch section {
        case .intro:     return .recovery
        case .verse:     return .moderate
        case .preChorus: return .high
        case .chorus:    return .peak
        case .drop:      return .peak
        case .bridge:    return .moderate
        case .breakdown: return .recovery
        case .outro:     return .recovery
        }
    }

    /// Pick the ONE move a role group will use all song: it must be affinity-legal for EVERY section
    /// type in the group, skill-gated, tier-capped for its role, and weighted by closeness to the
    /// dial-adjusted target tier.
    private func pickPlanMove(forAll types: [SectionType], target anchorType: SectionType,
                              maxTier: IntensityTier, request: RoutineRequest,
                              rng: inout SplitMix64) -> Move {
        // Role ceiling: warm-up/cooldown songs never go hard; recovery songs never go peak.
        let roleCap: IntensityTier = {
            switch request.classRole {
            // Recovery songs sit at moderate: capped at .high they picked up seated climbs and
            // stopped being recovery at all.
            case .warmup, .cooldown, .recovery: return .moderate
            default:                            return .peak
            }
        }()
        let cappedMax = IntensityTier(rawValue: min(maxTier.rawValue, roleCap.rawValue)) ?? maxTier

        let baseline = baselineTier(for: anchorType).rawValue
        // 5-step dial: 0→-2, 0.25→-1, 0.5→0, 0.75→+1, 1.0→+2 tiers around the section baseline.
        let shift = Int(((request.intensity.value - 0.5) * 4.0).rounded())
        let target = min(max(baseline + shift, 0), cappedMax.rawValue)

        // The primary is always a LEGS move: upper-body work rides on top of it as the song's
        // choreography set (see SongPlan.choreo), so the pedals never stop being the ride.
        // Warm-ups and cooldowns additionally skip rhythm choreography entirely — those songs are
        // for finding the beat and coming back down, not for a tap-back feature.
        // Standing Climb is a low-cadence grind: only offered on slower songs (< 120 BPM ≈ < 60 RPM).
        let bookend = request.classRole == .warmup || request.classRole == .cooldown
        let candidates = library.filter { move in
            move.skillTier <= request.skillLevel && !move.upperBody &&
            !(bookend && Self.isChoreography(move)) &&
            move.intensityTier <= cappedMax &&
            !(move.name == MoveLibrary.standingClimb.name && request.bpm >= 120) &&
            types.allSatisfy { move.sectionAffinity.contains($0) }
        }
        // Fallback must stay affinity-safe for ANY section → recovery spin (universal affinity).
        let pool = candidates.isEmpty ? [MoveLibrary.seatedFlat] : candidates

        let weighted: [(Move, Double)] = pool.map { move in
            let distance = abs(move.intensityTier.rawValue - target)
            var weight = 1.0 / (1.0 + Double(distance))
            weight *= roleBoost(move, role: request.classRole)
            return (move, weight)
        }
        return rng.weightedPick(weighted) ?? MoveLibrary.seatedFlat
    }

    /// Role steering: which moves a song's class role pulls toward (heavy boosts make the role's
    /// signature nearly certain while keeping seeds meaningful for everything else).
    private func roleBoost(_ move: Move, role: SongRole?) -> Double {
        guard let role else { return 1 }
        let isSprint = move.name.contains("Sprint"), isClimb = move.name.contains("Climb")
        switch role {
        case .jumps:  return move.name == MoveLibrary.jumps.name ? 25 : 1
        // Sprint and climb damp each OTHER: without this, a sprint song's long verses could fill
        // with seated climbs and the track read as a climb song with sprints bolted on.
        case .sprint: return isSprint ? 8 : (isClimb ? 0.3 : 1)
        case .climb:  return isClimb ? 8 : (isSprint ? 0.3 : 1)
        case .run:    return move.name == MoveLibrary.standingRun.name ? 5 : 1
        default:      return 1
        }
    }

    // MARK: - Phrase layout within a section

    private struct Placement { let phraseInSection: Int; let phrasesInSection: Int }

    private func sectionPlacement(of count: Int, in section: Section) -> Placement {
        let phraseLen = Routine.phraseLength
        let index = max(0, (count - section.startCount) / phraseLen)
        let total = max(1, section.counts / phraseLen)
        return Placement(phraseInSection: index, phrasesInSection: total)
    }

    /// Which move(s) fill this phrase. Nearly always a single move (the section's plan); the two
    /// exceptions are the build phrase opening a long peak section, and an accent block at the top
    /// of bridge/breakdown.
    private func phraseLayout(section: Section, placement: Placement, plan: SongPlan,
                              at count: Int, lastUpperBodyEnd: Int?,
                              previousMoveName: String?) -> [Move] {
        let primary = plan.primary[section.type] ?? MoveLibrary.seatedFlat

        /// Enough leg work since the last upper-body set to start another (spec §B4 rule 5).
        func restedEnough(_ move: Move) -> Bool {
            guard move.upperBody else { return true }
            return lastUpperBodyEnd.map { count - $0 >= Grammar.minUpperBodyGap } ?? true
        }

        // Long peak section → open with the build move before the signature hits… unless the rider
        // is already IN the build (a pre-chorus just ran it) — then the payoff lands on the drop.
        if primary.intensityTier == .peak, placement.phrasesInSection >= 3, placement.phraseInSection == 0,
           previousMoveName != plan.buildMove.name {
            return [plan.buildMove]
        }

        // CHOREOGRAPHY SONG: the set owns alternate phrases, so the rider gets "a phrase of
        // push-ups, a phrase back on the beat, repeat" — the way it's actually cued, and what
        // keeps a continuous upper-body run inside the safety cap while still making the set the
        // song's main event.
        if let choreoMove = plan.choreo[section.type],
           placement.phraseInSection % 2 == 0,
           choreoMove.name != primary.name,
           restedEnough(choreoMove) {
            return [choreoMove]
        }

        // Section top → accent block (tap-backs on verses, push-ups/press-downs on bridge/breakdown).
        // The density cap only constrains upper-body accents.
        if placement.phraseInSection == 0, let accentMove = plan.accent[section.type] {
            if restedEnough(accentMove) && accentMove.name != primary.name {
                return [accentMove, primary]     // half-phrase each
            }
        }

        return [primary]
    }

    /// How many counts of the phrase a layout entry occupies: the whole phrase for a solo move,
    /// half for each of an accent pair.
    private func layoutSlice(layout: [Move], of move: Move, phraseLen: Int) -> Int {
        layout.count == 1 ? phraseLen : phraseLen / layout.count
    }

    /// Largest block size the move supports that tiles a phrase slice cleanly.
    private func tileLength(for move: Move) -> Int {
        for candidate in [32, 16, 8] where move.allowedCounts.contains(candidate) {
            return candidate
        }
        return move.allowedCounts.max() ?? 8
    }

    // MARK: - Event construction (cues fire on transitions only)

    private func makeEvent(
        move: Move,
        startCount: Int,
        counts: Int,
        routineStart: Int,
        isTransition: Bool,
        isLeadLegPhrase: Bool,
        confidence: MapConfidence,
        resistanceUp: inout Bool,
        lastUpperBodyEnd: inout Int?
    ) -> MoveEvent {
        var cues: [Cue] = []

        // Resistance floor: transition low→high before any resistance-requiring move; ease back off
        // when the ride settles into easy seated work. The down-cue used to key on `.recovery`-tier
        // moves, but no library move has carried that tier since Recovery Spin merged into Seated
        // Flat — so riders were told to add resistance and never to take it off. Easy here means:
        // no resistance required and at or below the moderate tier (base saddle work).
        if move.needsResistance {
            if !resistanceUp {
                cues.append(Cue(type: .resistanceUp, atCount: startCount, text: "Add resistance"))
                resistanceUp = true
            }
        } else if move.intensityTier <= .moderate && resistanceUp {
            cues.append(Cue(type: .resistanceDown, atCount: startCount, text: "Ease the resistance"))
            resistanceUp = false
        }

        // Lead-leg alternation (physical, so emitted regardless of confidence or continuation).
        if isLeadLegPhrase {
            cues.append(Cue(type: .leadLegSwitch, atCount: startCount, text: "Switch your lead leg"))
        }

        if isTransition {
            // Anticipatory countdown — learned maps only, attacking moves only, and only when the
            // full 8-count lead fits inside the routine (a countdown before count 0 pointed at a
            // moment that never renders).
            if confidence == .learned, move.intensityTier >= .high, startCount - 8 >= routineStart {
                cues.append(Cue(type: .countdown, atCount: startCount - 8,
                                text: "\(move.name.uppercased()) in 8", leadBeats: 8))
            }
            cues.append(Cue(type: .form, atCount: startCount, text: move.formCue))
        }

        if move.upperBody {
            lastUpperBodyEnd = startCount + counts    // where the LEGS get the ride back
        }

        return MoveEvent(startCount: startCount, move: move, counts: counts, cues: cues)
    }

    // MARK: - Helpers

    /// Sub-peak move for the mandatory step-down after 2 peak phrases: keep working (standing run)
    /// wherever it's section-legal, spin easy only in sections that are easy anyway.
    private func stepDownMove(for section: Section) -> Move {
        MoveLibrary.standingRun.sectionAffinity.contains(section.type)
            ? MoveLibrary.standingRun
            : MoveLibrary.seatedFlat
    }

    private func sectionCovering(_ count: Int, in sorted: [Section]) -> Section? {
        var result: Section? = nil
        for section in sorted where section.startCount <= count && count < section.endCount {
            result = section
        }
        // If between sections, fall back to the last one starting at or before `count`.
        if result == nil {
            for section in sorted where section.startCount <= count { result = section }
        }
        return result
    }
}
