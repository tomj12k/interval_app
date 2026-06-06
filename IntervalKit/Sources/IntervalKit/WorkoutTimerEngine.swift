import Foundation

public enum TimerEvent: Equatable, Sendable {
    case phaseStarted(WorkoutPhase)
    case workoutFinished
}

/// Drives a built phase list one tick at a time. The host (a SwiftUI view model)
/// calls `tick(by:)` from a 1-second `Timer` and reacts to `onEvent` to play chimes.
@MainActor
public final class WorkoutTimerEngine: ObservableObject {
    @Published public private(set) var currentPhaseIndex: Int
    @Published public private(set) var remainingInPhase: TimeInterval
    @Published public private(set) var isRunning: Bool
    @Published public private(set) var isFinished: Bool

    public let phases: [WorkoutPhase]
    public var onEvent: ((TimerEvent) -> Void)?

    public init(phases: [WorkoutPhase]) {
        precondition(!phases.isEmpty, "WorkoutTimerEngine requires at least one phase")
        self.phases = phases
        self.currentPhaseIndex = 0
        self.remainingInPhase = phases[0].duration
        self.isRunning = false
        self.isFinished = false
    }

    public var currentPhase: WorkoutPhase {
        phases[currentPhaseIndex]
    }

    public func start() {
        guard !isFinished else { return }
        if !isRunning {
            isRunning = true
            onEvent?(.phaseStarted(currentPhase))
        }
    }

    public func pause() {
        isRunning = false
    }

    public func reset() {
        currentPhaseIndex = 0
        remainingInPhase = phases[0].duration
        isRunning = false
        isFinished = false
    }

    public func tick(by delta: TimeInterval) {
        guard isRunning, !isFinished else { return }
        remainingInPhase -= delta
        while remainingInPhase <= 0 {
            let overflow = -remainingInPhase
            let nextIndex = currentPhaseIndex + 1
            if nextIndex < phases.count {
                currentPhaseIndex = nextIndex
                remainingInPhase = currentPhase.duration - overflow
                onEvent?(.phaseStarted(currentPhase))
            } else {
                remainingInPhase = 0
                isRunning = false
                isFinished = true
                onEvent?(.workoutFinished)
                break
            }
        }
    }
}
