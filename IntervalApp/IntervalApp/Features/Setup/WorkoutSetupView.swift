import SwiftUI
import IntervalKit

struct WorkoutSetupView: View {
    @State private var totalMinutes: Double = 45
    @State private var warmupMinutes: Double = 2
    @State private var cooldownMinutes: Double = 5
    @State private var workSeconds: Double = 30
    @State private var restSeconds: Double = 10

    @State private var planResult: Result<[WorkoutPhase], PlanBuildError>?
    @State private var presentedWorkout: PresentedWorkout?

    var body: some View {
        NavigationStack {
            Form {
                Section("Total Workout Time") {
                    MinutesStepper(label: "Total", minutes: $totalMinutes, range: 5...180, step: 1)
                }
                Section("Warm Up & Cool Down") {
                    MinutesStepper(label: "Warm Up", minutes: $warmupMinutes, range: 0...30, step: 1)
                    MinutesStepper(label: "Cool Down", minutes: $cooldownMinutes, range: 0...30, step: 1)
                }
                Section("Work & Rest") {
                    SecondsStepper(label: "Work", seconds: $workSeconds, range: 5...600, step: 5)
                    SecondsStepper(label: "Rest", seconds: $restSeconds, range: 0...300, step: 5)
                }
                Section("Your Workout") {
                    planPreview
                }
            }
            .navigationTitle("New Workout")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") { buildAndStart() }
                        .disabled(!isPlanReady)
                        .fontWeight(.semibold)
                }
            }
            .onAppear(perform: rebuildPlan)
            .onChange(of: totalMinutes) { _, _ in rebuildPlan() }
            .onChange(of: warmupMinutes) { _, _ in rebuildPlan() }
            .onChange(of: cooldownMinutes) { _, _ in rebuildPlan() }
            .onChange(of: workSeconds) { _, _ in rebuildPlan() }
            .onChange(of: restSeconds) { _, _ in rebuildPlan() }
            .fullScreenCover(item: $presentedWorkout) { workout in
                ActiveWorkoutView(phases: workout.phases)
            }
        }
    }

    private var isPlanReady: Bool {
        if case .success = planResult { return true }
        return false
    }

    @ViewBuilder
    private var planPreview: some View {
        switch planResult {
        case .success(let phases):
            let rounds = phases.first { $0.kind == .work }?.totalRounds ?? 0
            let cooldown = phases.last { $0.kind == .cooldown }?.duration
            VStack(alignment: .leading, spacing: 4) {
                Text("\(rounds) rounds of \(Int(workSeconds))s work / \(Int(restSeconds))s rest")
                    .font(.headline)
                if let cooldown, abs(cooldown - cooldownMinutes * 60) > 0.5 {
                    Text("Cool down adjusted to \(formatted(cooldown)) so the workout fills your time exactly")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        case .failure(.totalTooShortForWarmupAndCooldown):
            Text("Warm Up + Cool Down is longer than your Total time — shorten one of them.")
                .foregroundStyle(.red)
        case .failure(.noFullIntervalFits):
            Text("Work + Rest doesn't fit even once in the time left after Warm Up and Cool Down — shorten Work/Rest or lengthen Total.")
                .foregroundStyle(.red)
        case .failure(.nonPositiveDuration):
            Text("Work time must be greater than zero.")
                .foregroundStyle(.red)
        case nil:
            EmptyView()
        }
    }

    private func rebuildPlan() {
        let config = WorkoutConfig(
            totalDuration: totalMinutes * 60,
            warmupDuration: warmupMinutes * 60,
            cooldownDuration: cooldownMinutes * 60,
            workDuration: workSeconds,
            restDuration: restSeconds
        )
        planResult = IntervalPlanBuilder.build(config: config)
    }

    private func buildAndStart() {
        guard case .success(let phases) = planResult else { return }
        presentedWorkout = PresentedWorkout(phases: phases)
    }

    private func formatted(_ duration: TimeInterval) -> String {
        let total = Int(duration.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Wraps a built phase list so it can drive item-based sheet presentation.
/// Carrying the data directly in the presented item (rather than a separate
/// boolean flag plus mutable state the cover's content closure reads) guarantees
/// `ActiveWorkoutView` is always constructed with the phases that triggered
/// presentation — never a stale snapshot from before the plan was built.
private struct PresentedWorkout: Identifiable {
    let id = UUID()
    let phases: [WorkoutPhase]
}
