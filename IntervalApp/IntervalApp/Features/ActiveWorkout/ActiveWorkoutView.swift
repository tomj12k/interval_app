import SwiftUI
import UIKit
import IntervalKit

struct ActiveWorkoutView: View {
    @StateObject private var viewModel: ActiveWorkoutViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showCompletionAlert = false

    init(phases: [WorkoutPhase]) {
        _viewModel = StateObject(wrappedValue: ActiveWorkoutViewModel(phases: phases, chimePlayer: ChimePlayer()))
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            if let roundLabel = viewModel.roundLabel {
                Text(roundLabel)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            Text(viewModel.phaseName)
                .font(.system(size: 40, weight: .bold))
            Text(viewModel.remainingText)
                .font(.system(size: 96, weight: .heavy, design: .rounded))
                .monospacedDigit()
            Spacer()
            controls
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(backgroundColor.ignoresSafeArea())
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            viewModel.start()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            viewModel.pause()
        }
        .onChange(of: viewModel.isFinished) { _, finished in
            if finished { showCompletionAlert = true }
        }
        .alert("Workout Complete", isPresented: $showCompletionAlert) {
            Button("Done") { dismiss() }
        } message: {
            Text("Nice work — you finished the whole thing.")
        }
        .interactiveDismissDisabled()
    }

    private var controls: some View {
        HStack(spacing: 32) {
            Button(viewModel.isRunning ? "Pause" : "Resume") {
                viewModel.isRunning ? viewModel.pause() : viewModel.start()
            }
            .buttonStyle(.borderedProminent)

            Button("End Workout") { dismiss() }
                .buttonStyle(.bordered)
                .tint(.red)
        }
        .font(.title3)
        .padding(.bottom, 32)
    }

    private var backgroundColor: Color {
        switch viewModel.phaseKind {
        case .work: return .red.opacity(0.15)
        case .rest: return .green.opacity(0.15)
        case .warmup, .cooldown: return .blue.opacity(0.15)
        }
    }
}
