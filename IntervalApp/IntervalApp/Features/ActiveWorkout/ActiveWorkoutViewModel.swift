import Combine
import Foundation
import IntervalKit

@MainActor
final class ActiveWorkoutViewModel: ObservableObject {
    @Published private(set) var phaseKind: PhaseKind = .warmup
    @Published private(set) var phaseName: String = ""
    @Published private(set) var remainingText: String = "0:00"
    @Published private(set) var roundLabel: String?
    @Published private(set) var isRunning = false
    @Published private(set) var isFinished = false

    private let engine: WorkoutTimerEngine
    private let chimePlayer: ChimePlayer
    private let activityController = WorkoutActivityController()
    private var ticker: AnyCancellable?

    init(phases: [WorkoutPhase], chimePlayer: ChimePlayer) {
        self.engine = WorkoutTimerEngine(phases: phases)
        self.chimePlayer = chimePlayer
        engine.onEvent = { [weak self] event in
            self?.handle(event)
        }
        refreshDisplay()
    }

    func start() {
        try? chimePlayer.configureSessionForBackgroundPlayback()
        engine.start()
        isRunning = true
        activityController.start(phase: engine.currentPhase, remaining: engine.remainingInPhase, roundLabel: roundLabel)
        startTicking()
    }

    func pause() {
        engine.pause()
        isRunning = false
        ticker?.cancel()
        activityController.end()
    }

    private func startTicking() {
        ticker = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.engine.tick(by: 1)
                self?.refreshDisplay()
            }
    }

    private func handle(_ event: TimerEvent) {
        switch event {
        case .phaseStarted:
            chimePlayer.play(.transition)
        case .workoutFinished:
            chimePlayer.play(.workoutComplete)
            isRunning = false
            isFinished = true
            ticker?.cancel()
            activityController.end()
        }
        refreshDisplay()
    }

    private func refreshDisplay() {
        let phase = engine.currentPhase
        phaseKind = phase.kind
        phaseName = phase.kind.displayName
        remainingText = Self.format(engine.remainingInPhase)
        if let round = phase.roundNumber, let total = phase.totalRounds {
            roundLabel = "Round \(round) of \(total)"
        } else {
            roundLabel = nil
        }
        activityController.update(phase: phase, remaining: engine.remainingInPhase, roundLabel: roundLabel)
    }

    private static func format(_ duration: TimeInterval) -> String {
        let total = max(0, Int(duration.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
