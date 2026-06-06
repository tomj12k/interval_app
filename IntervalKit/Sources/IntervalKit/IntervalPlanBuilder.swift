import Foundation

public enum PlanBuildError: Error, Equatable, Sendable {
    /// Work duration must be > 0; warmup/cooldown/rest must be >= 0.
    case nonPositiveDuration
    /// warmupDuration + cooldownDuration >= totalDuration, leaving nothing for intervals.
    case totalTooShortForWarmupAndCooldown
    /// One work+rest round is longer than the time left after warmup/cooldown.
    case noFullIntervalFits
}

/// Turns the 5 numbers on the setup screen into an ordered list of phases.
///
/// Strategy: fit as many *whole* work+rest rounds as possible into the time
/// remaining after warmup and cooldown, then add whatever time is left over
/// onto the cooldown — so every round stays full-length and the workout still
/// ends at (or essentially at) the user's requested total.
public enum IntervalPlanBuilder {
    public static func build(config: WorkoutConfig) -> Result<[WorkoutPhase], PlanBuildError> {
        guard config.totalDuration > 0,
              config.warmupDuration >= 0,
              config.cooldownDuration >= 0,
              config.workDuration > 0,
              config.restDuration >= 0 else {
            return .failure(.nonPositiveDuration)
        }

        let availableForIntervals = config.totalDuration - config.warmupDuration - config.cooldownDuration
        guard availableForIntervals > 0 else {
            return .failure(.totalTooShortForWarmupAndCooldown)
        }

        let cycleLength = config.workDuration + config.restDuration
        let roundCount = Int(availableForIntervals / cycleLength)
        guard roundCount > 0 else {
            return .failure(.noFullIntervalFits)
        }

        let leftover = availableForIntervals - (Double(roundCount) * cycleLength)
        let adjustedCooldown = config.cooldownDuration + leftover

        var phases: [WorkoutPhase] = []
        var nextID = 0

        if config.warmupDuration > 0 {
            phases.append(WorkoutPhase(id: nextID, kind: .warmup, duration: config.warmupDuration))
            nextID += 1
        }

        for round in 1...roundCount {
            phases.append(WorkoutPhase(id: nextID, kind: .work, duration: config.workDuration, roundNumber: round, totalRounds: roundCount))
            nextID += 1
            if config.restDuration > 0 {
                phases.append(WorkoutPhase(id: nextID, kind: .rest, duration: config.restDuration, roundNumber: round, totalRounds: roundCount))
                nextID += 1
            }
        }

        if adjustedCooldown > 0 {
            phases.append(WorkoutPhase(id: nextID, kind: .cooldown, duration: adjustedCooldown))
            nextID += 1
        }

        return .success(phases)
    }
}
