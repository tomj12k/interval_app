import XCTest
@testable import IntervalKit

final class IntervalPlanBuilderTests: XCTestCase {
    func test_evenlyDivisibleWorkout_buildsExpectedRoundsWithNoLeftover() {
        // 45 min total, 2 min warmup, 5 min cooldown, 30s work / 10s rest
        // -> 2280s available for intervals / 40s per round = exactly 57 rounds, 0 leftover
        let config = WorkoutConfig(totalDuration: 2700, warmupDuration: 120, cooldownDuration: 300, workDuration: 30, restDuration: 10)

        let result = IntervalPlanBuilder.build(config: config)

        guard case .success(let phases) = result else {
            return XCTFail("expected a successful plan, got \(result)")
        }
        XCTAssertEqual(phases.first, WorkoutPhase(id: 0, kind: .warmup, duration: 120))
        XCTAssertEqual(phases.last, WorkoutPhase(id: phases.count - 1, kind: .cooldown, duration: 300))
        let workPhases = phases.filter { $0.kind == .work }
        let restPhases = phases.filter { $0.kind == .rest }
        XCTAssertEqual(workPhases.count, 57)
        XCTAssertEqual(restPhases.count, 57)
        XCTAssertEqual(workPhases.first?.roundNumber, 1)
        XCTAssertEqual(workPhases.last?.roundNumber, 57)
        XCTAssertEqual(workPhases.last?.totalRounds, 57)
        XCTAssertEqual(phases.count, 1 + 57 * 2 + 1)
    }

    func test_unevenWorkout_padsLeftoverSecondsOntoCooldown() {
        // 30 min total, 1 min warmup, 2 min cooldown, 45s work / 20s rest
        // -> 1620s available / 65s per round = 24 rounds using 1560s, 60s leftover
        // -> cooldown grows from 120s to 180s
        let config = WorkoutConfig(totalDuration: 1800, warmupDuration: 60, cooldownDuration: 120, workDuration: 45, restDuration: 20)

        let result = IntervalPlanBuilder.build(config: config)

        guard case .success(let phases) = result else {
            return XCTFail("expected a successful plan, got \(result)")
        }
        XCTAssertEqual(phases.filter { $0.kind == .work }.count, 24)
        XCTAssertEqual(phases.last?.kind, .cooldown)
        XCTAssertEqual(phases.last?.duration ?? -1, 180, accuracy: 0.001)
    }

    func test_zeroRestAndNoWarmupOrCooldown_omitsThosePhases() {
        let config = WorkoutConfig(totalDuration: 600, warmupDuration: 0, cooldownDuration: 0, workDuration: 30, restDuration: 0)

        let result = IntervalPlanBuilder.build(config: config)

        guard case .success(let phases) = result else {
            return XCTFail("expected a successful plan, got \(result)")
        }
        XCTAssertEqual(phases.count, 20)
        XCTAssertTrue(phases.allSatisfy { $0.kind == .work })
    }

    func test_warmupAndCooldownLongerThanTotal_returnsError() {
        let config = WorkoutConfig(totalDuration: 300, warmupDuration: 200, cooldownDuration: 200, workDuration: 30, restDuration: 10)

        let result = IntervalPlanBuilder.build(config: config)

        guard case .failure(let error) = result else {
            return XCTFail("expected a failure, got \(result)")
        }
        XCTAssertEqual(error, .totalTooShortForWarmupAndCooldown)
    }

    func test_workPlusRestDoesNotFitEvenOnce_returnsError() {
        let config = WorkoutConfig(totalDuration: 300, warmupDuration: 0, cooldownDuration: 0, workDuration: 600, restDuration: 600)

        let result = IntervalPlanBuilder.build(config: config)

        guard case .failure(let error) = result else {
            return XCTFail("expected a failure, got \(result)")
        }
        XCTAssertEqual(error, .noFullIntervalFits)
    }

    func test_zeroWorkDuration_returnsError() {
        let config = WorkoutConfig(totalDuration: 600, warmupDuration: 0, cooldownDuration: 0, workDuration: 0, restDuration: 10)

        let result = IntervalPlanBuilder.build(config: config)

        guard case .failure(let error) = result else {
            return XCTFail("expected a failure, got \(result)")
        }
        XCTAssertEqual(error, .nonPositiveDuration)
    }
}
