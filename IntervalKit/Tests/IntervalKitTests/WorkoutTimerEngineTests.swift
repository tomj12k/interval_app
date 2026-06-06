import XCTest
@testable import IntervalKit

@MainActor
final class WorkoutTimerEngineTests: XCTestCase {
    private let phases = [
        WorkoutPhase(id: 0, kind: .warmup, duration: 10),
        WorkoutPhase(id: 1, kind: .work, duration: 5, roundNumber: 1, totalRounds: 1),
        WorkoutPhase(id: 2, kind: .rest, duration: 3, roundNumber: 1, totalRounds: 1),
        WorkoutPhase(id: 3, kind: .cooldown, duration: 4)
    ]

    func test_start_firesPhaseStartedForFirstPhase() {
        let engine = WorkoutTimerEngine(phases: phases)
        var events: [TimerEvent] = []
        engine.onEvent = { events.append($0) }

        engine.start()

        XCTAssertEqual(events, [.phaseStarted(phases[0])])
        XCTAssertTrue(engine.isRunning)
    }

    func test_tickWithinPhase_decrementsRemainingWithoutAdvancing() {
        let engine = WorkoutTimerEngine(phases: phases)
        engine.start()

        engine.tick(by: 4)

        XCTAssertEqual(engine.currentPhaseIndex, 0)
        XCTAssertEqual(engine.remainingInPhase, 6, accuracy: 0.001)
    }

    func test_tickPastPhaseBoundary_advancesAndCarriesOverflow() {
        let engine = WorkoutTimerEngine(phases: phases)
        engine.start()
        var events: [TimerEvent] = []
        engine.onEvent = { events.append($0) }

        engine.tick(by: 11) // 10s warmup + 1s overflow into the 5s work phase

        XCTAssertEqual(engine.currentPhaseIndex, 1)
        XCTAssertEqual(engine.remainingInPhase, 4, accuracy: 0.001)
        XCTAssertEqual(events, [.phaseStarted(phases[1])])
    }

    func test_tickPastFinalPhase_finishesWorkout() {
        let engine = WorkoutTimerEngine(phases: phases)
        engine.start()
        var events: [TimerEvent] = []
        engine.onEvent = { events.append($0) }

        engine.tick(by: 100) // total duration is only 22s

        XCTAssertTrue(engine.isFinished)
        XCTAssertFalse(engine.isRunning)
        XCTAssertEqual(engine.remainingInPhase, 0)
        XCTAssertEqual(events.last, .workoutFinished)
    }

    func test_pause_stopsTickFromAdvancing() {
        let engine = WorkoutTimerEngine(phases: phases)
        engine.start()
        engine.pause()

        engine.tick(by: 5)

        XCTAssertEqual(engine.remainingInPhase, 10, accuracy: 0.001)
        XCTAssertFalse(engine.isRunning)
    }

    func test_reset_returnsToInitialState() {
        let engine = WorkoutTimerEngine(phases: phases)
        engine.start()
        engine.tick(by: 11)

        engine.reset()

        XCTAssertEqual(engine.currentPhaseIndex, 0)
        XCTAssertEqual(engine.remainingInPhase, 10, accuracy: 0.001)
        XCTAssertFalse(engine.isRunning)
        XCTAssertFalse(engine.isFinished)
    }
}
