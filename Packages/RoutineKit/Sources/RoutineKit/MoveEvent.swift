import Foundation

/// Kind of coaching cue attached to a move (spec §B5 cue & display engine).
public enum CueType: String, Sendable, Codable, CaseIterable, Hashable {
    case resistanceUp    // "add resistance" — precedes any resistance-floor move
    case resistanceDown  // "ease off" — on the way into recovery
    case countdown       // "SPRINT IN 8..." — learned maps only
    case leadLegSwitch   // alternate the lead leg (~every 2 phrases)
    case form            // one-line form coaching for the current move
}

/// A single timed cue. `atCount` is when it should fire, in absolute counts. For a countdown it is
/// the move's start minus `leadBeats` (fires *before* the move); for everything else it equals the
/// move's start.
public struct Cue: Sendable, Hashable, Codable {
    public let type: CueType
    public let atCount: Int
    public let text: String
    /// For countdowns: how many counts ahead of the move this fires (e.g. 8). Nil otherwise.
    public let leadBeats: Int?

    public init(type: CueType, atCount: Int, text: String, leadBeats: Int? = nil) {
        self.type = type
        self.atCount = atCount
        self.text = text
        self.leadBeats = leadBeats
    }
}

/// One move in the routine: what to do, when it starts, how long it lasts, and its cues.
public struct MoveEvent: Sendable, Hashable, Codable {
    public let startCount: Int
    public let move: Move
    public let counts: Int
    public let cues: [Cue]

    public init(startCount: Int, move: Move, counts: Int, cues: [Cue]) {
        self.startCount = startCount
        self.move = move
        self.counts = counts
        self.cues = cues
    }

    public var endCount: Int { startCount + counts }
}

/// The generated class for one track. Deterministic in `(trackKey, seed)`.
public struct Routine: Sendable, Hashable, Codable {
    public let trackKey: String
    public let seed: UInt64
    /// Absolute count where routine coverage begins (first section start).
    public let startCount: Int
    /// Absolute count where routine coverage ends.
    public let endCount: Int
    public let events: [MoveEvent]

    public init(trackKey: String, seed: UInt64, startCount: Int, endCount: Int, events: [MoveEvent]) {
        self.trackKey = trackKey
        self.seed = seed
        self.startCount = startCount
        self.endCount = endCount
        self.events = events
    }

    /// Phrase length in counts (a 32-count phrase — spec §B1).
    public static let phraseLength = 32
}
