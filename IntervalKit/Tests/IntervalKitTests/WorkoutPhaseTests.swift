import XCTest
@testable import IntervalKit

final class WorkoutPhaseTests: XCTestCase {
    func test_phaseKind_displayName_isHumanReadable() {
        XCTAssertEqual(PhaseKind.warmup.displayName, "Warm Up")
        XCTAssertEqual(PhaseKind.work.displayName, "Work")
        XCTAssertEqual(PhaseKind.rest.displayName, "Rest")
        XCTAssertEqual(PhaseKind.cooldown.displayName, "Cool Down")
    }
}
