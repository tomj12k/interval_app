import Foundation

public enum PhaseKind: String, Equatable, Sendable {
    case warmup
    case work
    case rest
    case cooldown

    public var displayName: String {
        switch self {
        case .warmup: return "Warm Up"
        case .work: return "Work"
        case .rest: return "Rest"
        case .cooldown: return "Cool Down"
        }
    }
}

/// One segment of a built workout — e.g. "30 seconds of Work, round 3 of 12".
public struct WorkoutPhase: Equatable, Identifiable, Sendable {
    public let id: Int
    public let kind: PhaseKind
    public let duration: TimeInterval
    public let roundNumber: Int?
    public let totalRounds: Int?

    public init(
        id: Int,
        kind: PhaseKind,
        duration: TimeInterval,
        roundNumber: Int? = nil,
        totalRounds: Int? = nil
    ) {
        self.id = id
        self.kind = kind
        self.duration = duration
        self.roundNumber = roundNumber
        self.totalRounds = totalRounds
    }
}
