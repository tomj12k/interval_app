import ActivityKit
import Foundation
import IntervalKit

/// Starts, updates, and ends the Live Activity that mirrors the running
/// workout on the Lock Screen / Dynamic Island. All calls are no-ops if the
/// user has Live Activities disabled — the in-app screen and chimes still work.
@MainActor
final class WorkoutActivityController {
    private var activity: Activity<WorkoutActivityAttributes>?

    func start(phase: WorkoutPhase, remaining: TimeInterval, roundLabel: String?) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled, activity == nil else { return }
        let attributes = WorkoutActivityAttributes(workoutTitle: "Interval Workout")
        let state = makeState(phase: phase, remaining: remaining, roundLabel: roundLabel)
        activity = try? Activity.request(attributes: attributes, content: .init(state: state, staleDate: nil))
    }

    func update(phase: WorkoutPhase, remaining: TimeInterval, roundLabel: String?) {
        guard let activity else { return }
        let state = makeState(phase: phase, remaining: remaining, roundLabel: roundLabel)
        Task { await activity.update(.init(state: state, staleDate: nil)) }
    }

    func end() {
        guard let activity else { return }
        let endedActivity = activity
        Task { await endedActivity.end(nil, dismissalPolicy: .immediate) }
        self.activity = nil
    }

    private func makeState(phase: WorkoutPhase, remaining: TimeInterval, roundLabel: String?) -> WorkoutActivityAttributes.ContentState {
        WorkoutActivityAttributes.ContentState(
            phaseName: phase.kind.displayName,
            remainingSeconds: Int(remaining.rounded()),
            roundLabel: roundLabel
        )
    }
}
