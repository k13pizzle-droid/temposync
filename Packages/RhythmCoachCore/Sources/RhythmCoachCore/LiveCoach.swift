import Foundation
import RoutineKit

/// Everything the live screen needs at one instant. Pure value — the SwiftUI view is a function of it.
public struct LiveFrame: Sendable, Equatable {
    public let count: Int
    public let beatPhase: Double        // 0...1, drives the pulse ring
    /// Continuous beat time (count + phase) — drives tempo-matched move animation (pedal cadence).
    public let beatTime: Double
    /// Beats elapsed since the current move BLOCK began (tiled same-move events merged) — drives
    /// progressive animations (the jump 8→4→2 cadence ladder, combo alternation).
    public let countsIntoMove: Double
    public let countInPhrase: Int       // 0...31
    public let phraseIndex: Int
    public let bpm: Double
    /// Suggested pedal cadence: downstroke locks to the beat with alternating legs, so one full
    /// crank revolution spans 2 beats → RPM ≈ BPM / 2 (spec §B1 safety canon).
    public var suggestedRPM: Int { Int((bpm / 2).rounded()) }

    public let currentMoveName: String
    public let currentFormCue: String
    public let currentPosition: Position
    public let currentIntensity: IntensityTier

    public let nextMoveName: String?
    public let countsUntilNext: Int?
    /// Non-nil when a countdown is live ("JUMPS in 8"); the number counts down with the beat.
    public let countdownText: String?

    public let resistanceUp: Bool
    public let sectionType: SectionType?
    public let confidence: MapConfidence

    public static let idle = LiveFrame(
        count: 0, beatPhase: 0, beatTime: 0, countsIntoMove: 0, countInPhrase: 0, phraseIndex: 0, bpm: 0,
        currentMoveName: "—", currentFormCue: "Waiting for the beat…",
        currentPosition: .seated, currentIntensity: .recovery,
        nextMoveName: nil, countsUntilNext: nil, countdownText: nil,
        resistanceUp: false, sectionType: nil, confidence: .prior
    )
}

/// Combines the beat grid, the routine, and the section map into a renderable `LiveFrame`.
public struct LiveCoach: Sendable {
    public let routine: Routine
    public let clock: BeatClock
    public let sections: [Section]
    public let confidence: MapConfidence

    private let player: RoutinePlayer

    public init(routine: Routine, clock: BeatClock, sections: [Section], confidence: MapConfidence) {
        self.routine = routine
        self.clock = clock
        self.sections = sections
        self.confidence = confidence
        self.player = RoutinePlayer(routine: routine)
    }

    public func frame(at time: Double) -> LiveFrame {
        let pos = clock.position(at: time)
        let state = player.state(atCount: pos.beatIndex)

        let current = state.currentEvent?.move
        let section = sectionType(covering: pos.beatIndex)

        // Countdown text: prior maps never show hard numbers (spec §B3), so gate on confidence too.
        var countdownText: String? = nil
        if confidence == .learned, let cd = state.activeCountdown, let until = state.countsUntilNext {
            let moveName = state.nextEvent?.move.name.uppercased() ?? "NEXT"
            _ = cd
            countdownText = "\(moveName) in \(until)"
        }

        let beatTime = Double(pos.beatIndex) + pos.phase
        return LiveFrame(
            count: pos.beatIndex,
            beatPhase: pos.phase,
            beatTime: beatTime,
            countsIntoMove: state.currentBlockStart.map { max(0, beatTime - Double($0)) } ?? 0,
            countInPhrase: pos.countInPhrase,
            phraseIndex: pos.phraseIndex,
            bpm: clock.bpm,
            currentMoveName: current?.name ?? "—",
            currentFormCue: current?.formCue ?? "Ride the beat",
            currentPosition: current?.position ?? .seated,
            currentIntensity: current?.intensityTier ?? .recovery,
            nextMoveName: state.nextEvent?.move.name,
            countsUntilNext: state.countsUntilNext,
            countdownText: countdownText,
            resistanceUp: state.resistanceUp,
            sectionType: section,
            confidence: confidence
        )
    }

    private func sectionType(covering count: Int) -> SectionType? {
        var result: SectionType? = nil
        for s in sections.sorted(by: { $0.startCount < $1.startCount }) where s.startCount <= count {
            if count < s.endCount { result = s.type }
            else if result == nil { result = s.type }
        }
        return result
    }
}
