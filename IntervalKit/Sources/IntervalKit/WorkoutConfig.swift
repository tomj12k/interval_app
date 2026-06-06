import Foundation

/// The five numbers the user enters on the setup screen — everything
/// `IntervalPlanBuilder` needs to compute a full workout.
public struct WorkoutConfig: Equatable, Sendable {
    public var totalDuration: TimeInterval
    public var warmupDuration: TimeInterval
    public var cooldownDuration: TimeInterval
    public var workDuration: TimeInterval
    public var restDuration: TimeInterval

    public init(
        totalDuration: TimeInterval,
        warmupDuration: TimeInterval,
        cooldownDuration: TimeInterval,
        workDuration: TimeInterval,
        restDuration: TimeInterval
    ) {
        self.totalDuration = totalDuration
        self.warmupDuration = warmupDuration
        self.cooldownDuration = cooldownDuration
        self.workDuration = workDuration
        self.restDuration = restDuration
    }
}
