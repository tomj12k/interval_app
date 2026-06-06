# Interval Workout App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a SwiftUI iOS app where the user enters a total workout time, warm-up, cool-down, work duration, and rest duration, and the app automatically computes how many work/rest rounds fit — then runs the workout with audible bell chimes at every phase transition, including while the phone is locked.

**Architecture:** Two-layer split: (1) `IntervalKit`, a local Swift Package containing all pure logic — `WorkoutConfig`, the `IntervalPlanBuilder` auto-fill algorithm, the `WorkoutTimerEngine` phase state machine, and `ToneGenerator` — fully unit-testable with `swift test` and no simulator. (2) `IntervalApp`, a thin SwiftUI app target containing only views, view models, and iOS-integration code (audio playback, background session, Live Activity) that wires `IntervalKit` to the screen. A `IntervalWidgetExtension` target adds a Live Activity so the current phase and time remaining are visible on the lock screen without unlocking the phone.

**Tech Stack:** Swift 6, SwiftUI, iOS 17+, Swift Package Manager (local package), AVFoundation (AVAudioEngine for synthesized chime tones — no bundled audio assets needed), ActivityKit/WidgetKit (Live Activity), XCTest.

**Key product decisions locked in during planning:**
- When warm-up + cool-down + whole work/rest rounds don't divide the total time evenly, the app fits as many *full* rounds as possible and pads the leftover seconds onto the cool-down (so every round is full-length and the workout still ends at — or extremely close to — the requested total).
- The workout keeps running and keeps chiming when the phone is locked or the user is in another app, via a background `AVAudioSession` plus a Live Activity on the lock screen.

---

## Before You Start

This plan assumes a brand-new, empty directory at `/Users/tomfisher/interval_app` (confirmed empty during planning). All file paths below are relative to that directory unless stated otherwise.

Confirmed available tooling on this machine:
```
xcodebuild: Xcode 26.4 (Build 17E192)
swift: Apple Swift version 6.3
```
`xcodegen`/`tuist` are **not** installed, so the Xcode project itself is created via Xcode's GUI (Task 1, Step 1) — everything after that is file edits + command-line builds/tests.

---

### Task 1: Project scaffold — Xcode app project + local `IntervalKit` Swift package

**Files:**
- Create (via Xcode GUI): `IntervalApp.xcodeproj`, `IntervalApp/IntervalApp.swift`, `IntervalApp/Info.plist`
- Create (via CLI): `IntervalKit/Package.swift`, `IntervalKit/Sources/IntervalKit/IntervalKit.swift`, `IntervalKit/Tests/IntervalKitTests/IntervalKitTests.swift`

- [ ] **Step 1: Create the Xcode project (manual, in Xcode)**

Open Xcode → **File → New → Project… → iOS → App**. Use exactly these settings:
- Product Name: `IntervalApp`
- Team: your personal team (or none)
- Organization Identifier: `com.tomfisher` (or your own reverse-DNS)
- Interface: **SwiftUI**
- Language: **Swift**
- Storage: **None**
- Uncheck "Include Tests" (IntervalKit's package tests cover the logic; we'll add UI smoke-testing manually in Task 12)

Save it directly into `/Users/tomfisher/interval_app` (Xcode will create `IntervalApp.xcodeproj` and an `IntervalApp/` source folder inside it).

Then select the project in the navigator → the `IntervalApp` target → **General** tab → set **Minimum Deployments → iOS 17.0**.

- [ ] **Step 2: Scaffold the local Swift package from the command line**

```bash
cd /Users/tomfisher/interval_app
mkdir IntervalKit
cd IntervalKit
swift package init --name IntervalKit --type library
```

Expected output: `Creating library package: IntervalKit` plus a generated `Package.swift`, `Sources/IntervalKit/IntervalKit.swift`, and `Tests/IntervalKitTests/IntervalKitTests.swift`.

- [ ] **Step 3: Edit `Package.swift` to target iOS 17 and Swift 6**

Replace the entire contents of `IntervalKit/Package.swift` with:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "IntervalKit",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "IntervalKit", targets: ["IntervalKit"])
    ],
    targets: [
        .target(name: "IntervalKit"),
        .testTarget(name: "IntervalKitTests", dependencies: ["IntervalKit"])
    ]
)
```

- [ ] **Step 4: Run the generated placeholder tests to confirm the package builds**

```bash
cd /Users/tomfisher/interval_app/IntervalKit
swift test
```

Expected: `Test Suite 'All tests' passed` (the generated placeholder test passes).

- [ ] **Step 5: Add `IntervalKit` as a local package dependency of the app (manual, in Xcode)**

In Xcode: select the `IntervalApp` project → **File → Add Package Dependencies… → Add Local…** → navigate to and select the `IntervalKit` folder → **Add Package** → make sure the `IntervalApp` target is checked when prompted to choose targets.

- [ ] **Step 6: Verify the app target builds with the package linked**

```bash
cd /Users/tomfisher/interval_app
xcodebuild -project IntervalApp.xcodeproj -scheme IntervalApp \
  -destination 'generic/platform=iOS Simulator' build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
cd /Users/tomfisher/interval_app
git init
git add -A
git commit -m "chore: scaffold IntervalApp Xcode project and IntervalKit package"
```

---

### Task 2: `WorkoutConfig` and `WorkoutPhase` models

**Files:**
- Create: `IntervalKit/Sources/IntervalKit/WorkoutConfig.swift`
- Create: `IntervalKit/Sources/IntervalKit/WorkoutPhase.swift`
- Test: `IntervalKit/Tests/IntervalKitTests/WorkoutPhaseTests.swift`

- [ ] **Step 1: Write the failing test for `PhaseKind.displayName`**

Create `IntervalKit/Tests/IntervalKitTests/WorkoutPhaseTests.swift`:

```swift
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
```

- [ ] **Step 2: Run it to confirm it fails to compile**

```bash
cd /Users/tomfisher/interval_app/IntervalKit
swift test --filter WorkoutPhaseTests
```

Expected: FAIL — `cannot find type 'PhaseKind' in scope`.

- [ ] **Step 3: Create the models**

Create `IntervalKit/Sources/IntervalKit/WorkoutConfig.swift`:

```swift
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
```

Create `IntervalKit/Sources/IntervalKit/WorkoutPhase.swift`:

```swift
import Foundation

public enum PhaseKind: String, Equatable, Sendable {
    case warmup
    case work
    case rest
    case cooldown

    public var displayName: String {
        switch self {
        case .warmup: return "Warm Up"
        case .work: return "Work"
        case .rest: return "Rest"
        case .cooldown: return "Cool Down"
        }
    }
}

/// One segment of a built workout — e.g. "30 seconds of Work, round 3 of 12".
public struct WorkoutPhase: Equatable, Identifiable, Sendable {
    public let id: Int
    public let kind: PhaseKind
    public let duration: TimeInterval
    public let roundNumber: Int?
    public let totalRounds: Int?

    public init(
        id: Int,
        kind: PhaseKind,
        duration: TimeInterval,
        roundNumber: Int? = nil,
        totalRounds: Int? = nil
    ) {
        self.id = id
        self.kind = kind
        self.duration = duration
        self.roundNumber = roundNumber
        self.totalRounds = totalRounds
    }
}
```

- [ ] **Step 4: Run the test again to confirm it passes**

```bash
cd /Users/tomfisher/interval_app/IntervalKit
swift test --filter WorkoutPhaseTests
```

Expected: `Test Suite 'WorkoutPhaseTests' passed` — 1 test, 0 failures.

- [ ] **Step 5: Commit**

```bash
cd /Users/tomfisher/interval_app
git add IntervalKit/Sources/IntervalKit/WorkoutConfig.swift \
        IntervalKit/Sources/IntervalKit/WorkoutPhase.swift \
        IntervalKit/Tests/IntervalKitTests/WorkoutPhaseTests.swift
git commit -m "feat: add WorkoutConfig and WorkoutPhase models"
```

---

### Task 3: `IntervalPlanBuilder` — the auto-fill algorithm

This is the app's core differentiator: turn 5 numbers into a full round-by-round plan, fitting as many whole work/rest rounds as possible and padding the leftover seconds onto the cool-down.

**Files:**
- Create: `IntervalKit/Sources/IntervalKit/IntervalPlanBuilder.swift`
- Test: `IntervalKit/Tests/IntervalKitTests/IntervalPlanBuilderTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `IntervalKit/Tests/IntervalKitTests/IntervalPlanBuilderTests.swift`:

```swift
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
```

- [ ] **Step 2: Run to confirm it fails to compile**

```bash
cd /Users/tomfisher/interval_app/IntervalKit
swift test --filter IntervalPlanBuilderTests
```

Expected: FAIL — `cannot find 'IntervalPlanBuilder' in scope`.

- [ ] **Step 3: Implement the builder**

Create `IntervalKit/Sources/IntervalKit/IntervalPlanBuilder.swift`:

```swift
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
```

- [ ] **Step 4: Run the tests again to confirm they pass**

```bash
cd /Users/tomfisher/interval_app/IntervalKit
swift test --filter IntervalPlanBuilderTests
```

Expected: `Test Suite 'IntervalPlanBuilderTests' passed` — 6 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
cd /Users/tomfisher/interval_app
git add IntervalKit/Sources/IntervalKit/IntervalPlanBuilder.swift \
        IntervalKit/Tests/IntervalKitTests/IntervalPlanBuilderTests.swift
git commit -m "feat: add IntervalPlanBuilder auto-fill algorithm"
```

---

### Task 4: `WorkoutTimerEngine` — the phase state machine

A tick-driven state machine: the host calls `tick(by:)` once a second, the engine decrements the current phase's remaining time, advances phases (carrying over any overflow so the countdown stays accurate), and reports `phaseStarted`/`workoutFinished` events the UI uses to trigger chimes. Driving it by an explicit `tick(by:)` rather than an internal `Timer` makes it deterministic and fast to test — no real waiting required.

**Files:**
- Create: `IntervalKit/Sources/IntervalKit/WorkoutTimerEngine.swift`
- Test: `IntervalKit/Tests/IntervalKitTests/WorkoutTimerEngineTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `IntervalKit/Tests/IntervalKitTests/WorkoutTimerEngineTests.swift`:

```swift
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
```

- [ ] **Step 2: Run to confirm it fails to compile**

```bash
cd /Users/tomfisher/interval_app/IntervalKit
swift test --filter WorkoutTimerEngineTests
```

Expected: FAIL — `cannot find 'WorkoutTimerEngine' in scope`.

- [ ] **Step 3: Implement the engine**

Create `IntervalKit/Sources/IntervalKit/WorkoutTimerEngine.swift`:

```swift
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
```

- [ ] **Step 4: Run the tests again to confirm they pass**

```bash
cd /Users/tomfisher/interval_app/IntervalKit
swift test --filter WorkoutTimerEngineTests
```

Expected: `Test Suite 'WorkoutTimerEngineTests' passed` — 6 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
cd /Users/tomfisher/interval_app
git add IntervalKit/Sources/IntervalKit/WorkoutTimerEngine.swift \
        IntervalKit/Tests/IntervalKitTests/WorkoutTimerEngineTests.swift
git commit -m "feat: add WorkoutTimerEngine phase state machine"
```

---

### Task 5: `ToneGenerator` — synthesize chime tones in code

To avoid bundling audio assets (and the licensing/asset-pipeline overhead that comes with them), the bell sounds are synthesized at runtime as short sine-wave tones with a fade in/out envelope (so they don't click). This is pure math — `[Float]` sample arrays — and is fully testable without touching AVFoundation.

**Files:**
- Create: `IntervalKit/Sources/IntervalKit/ToneGenerator.swift`
- Test: `IntervalKit/Tests/IntervalKitTests/ToneGeneratorTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `IntervalKit/Tests/IntervalKitTests/ToneGeneratorTests.swift`:

```swift
import XCTest
@testable import IntervalKit

final class ToneGeneratorTests: XCTestCase {
    func test_sineWaveSamples_producesExpectedFrameCount() {
        let samples = ToneGenerator.sineWaveSamples(frequency: 880, duration: 0.2, sampleRate: 44_100)

        XCTAssertEqual(samples.count, 8_820)
    }

    func test_sineWaveSamples_staysWithinAmplitudeBounds() {
        let samples = ToneGenerator.sineWaveSamples(frequency: 440, duration: 0.5, amplitude: 0.6)

        XCTAssertTrue(samples.allSatisfy { abs($0) <= 0.6 + 0.0001 })
        XCTAssertTrue(samples.contains { abs($0) > 0.1 })
    }

    func test_sineWaveSamples_fadesInAndOutToAvoidClicks() throws {
        let samples = ToneGenerator.sineWaveSamples(frequency: 440, duration: 0.5, amplitude: 0.6)

        let first = try XCTUnwrap(samples.first)
        let last = try XCTUnwrap(samples.last)
        XCTAssertEqual(first, 0, accuracy: 0.001)
        XCTAssertEqual(last, 0, accuracy: 0.05)
    }

    func test_zeroDuration_producesNoSamples() {
        let samples = ToneGenerator.sineWaveSamples(frequency: 440, duration: 0)

        XCTAssertTrue(samples.isEmpty)
    }
}
```

- [ ] **Step 2: Run to confirm it fails to compile**

```bash
cd /Users/tomfisher/interval_app/IntervalKit
swift test --filter ToneGeneratorTests
```

Expected: FAIL — `cannot find 'ToneGenerator' in scope`.

- [ ] **Step 3: Implement the generator**

Create `IntervalKit/Sources/IntervalKit/ToneGenerator.swift`:

```swift
import Foundation

/// Synthesizes short sine-wave tones in code so the app needs zero bundled
/// audio assets. A linear fade in/out over the first/last 10% of samples
/// prevents the audible "click" a hard-edged tone would produce.
public enum ToneGenerator {
    public static func sineWaveSamples(
        frequency: Double,
        duration: TimeInterval,
        sampleRate: Double = 44_100,
        amplitude: Float = 0.6
    ) -> [Float] {
        let frameCount = Int(duration * sampleRate)
        guard frameCount > 0 else { return [] }
        return (0..<frameCount).map { frame in
            let phase = 2.0 * Double.pi * frequency * (Double(frame) / sampleRate)
            let envelope = fadeEnvelope(frame: frame, totalFrames: frameCount)
            return Float(sin(phase)) * amplitude * envelope
        }
    }

    private static func fadeEnvelope(frame: Int, totalFrames: Int) -> Float {
        let fadeFrames = max(1, totalFrames / 10)
        if frame < fadeFrames {
            return Float(frame) / Float(fadeFrames)
        }
        if frame > totalFrames - fadeFrames {
            return Float(totalFrames - frame) / Float(fadeFrames)
        }
        return 1.0
    }
}
```

- [ ] **Step 4: Run the tests again to confirm they pass**

```bash
cd /Users/tomfisher/interval_app/IntervalKit
swift test --filter ToneGeneratorTests
```

Expected: `Test Suite 'ToneGeneratorTests' passed` — 4 tests, 0 failures.

- [ ] **Step 5: Run the entire IntervalKit suite before moving into app code**

```bash
cd /Users/tomfisher/interval_app/IntervalKit
swift test
```

Expected: all suites pass (`WorkoutPhaseTests`, `IntervalPlanBuilderTests`, `WorkoutTimerEngineTests`, `ToneGeneratorTests`, plus the original placeholder).

- [ ] **Step 6: Commit**

```bash
cd /Users/tomfisher/interval_app
git add IntervalKit/Sources/IntervalKit/ToneGenerator.swift \
        IntervalKit/Tests/IntervalKitTests/ToneGeneratorTests.swift
git commit -m "feat: add ToneGenerator for synthesized chime tones"
```

---

### Task 6: Background Modes capability + Info.plist

Wire up the iOS configuration that lets audio (and therefore the running timer) continue while the screen is locked or another app is frontmost. This must be done before `ChimePlayer` is exercised on a device/simulator, otherwise chimes silently stop the moment the app backgrounds.

**Files:**
- Modify (via Xcode GUI): `IntervalApp` target → Signing & Capabilities, Info

- [ ] **Step 1: Add the Background Modes capability (manual, in Xcode)**

Select the `IntervalApp` target → **Signing & Capabilities** tab → **+ Capability** → **Background Modes** → check **Audio, AirPlay, and Picture in Picture**.

- [ ] **Step 2: Verify the entitlement landed in the generated Info.plist / project settings**

```bash
cd /Users/tomfisher/interval_app
plutil -p IntervalApp/Info.plist | grep -A2 UIBackgroundModes || \
  xcodebuild -project IntervalApp.xcodeproj -showBuildSettings -target IntervalApp | grep -i INFOPLIST
```

Expected: `UIBackgroundModes` containing `audio` (Xcode 15+ projects store this directly in `Info.plist` generated from build settings — if you don't see a standalone `Info.plist`, open the target's **Info** tab in Xcode and confirm "Background Modes — Audio, AirPlay, and Picture in Picture" is listed under **Custom iOS Target Properties**).

- [ ] **Step 3: Commit**

```bash
cd /Users/tomfisher/interval_app
git add -A
git commit -m "chore: enable background audio mode for IntervalApp"
```

---

### Task 7: `ChimePlayer` — play synthesized chimes through a background-capable audio session

**Files:**
- Create: `IntervalApp/Audio/ChimePlayer.swift`

- [ ] **Step 1: Implement the player**

Create `IntervalApp/Audio/ChimePlayer.swift`:

```swift
import AVFoundation
import IntervalKit

/// Plays synthesized chime tones through an `AVAudioEngine` configured for
/// background playback, so the bell still sounds with the screen locked.
@MainActor
final class ChimePlayer {
    enum ChimeKind {
        case transition
        case workoutComplete
    }

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let sampleRate: Double = 44_100
    private var buffers: [ChimeKind: AVAudioPCMBuffer] = [:]
    private var isEngineRunning = false

    init() {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        buffers[.transition] = makeBuffer(samples: ToneGenerator.sineWaveSamples(frequency: 880, duration: 0.18, sampleRate: sampleRate))
        buffers[.workoutComplete] = makeBuffer(samples: fanfareSamples())
    }

    /// Call once before the first chime of a workout. Configures the shared
    /// session for background playback and activates it.
    func configureSessionForBackgroundPlayback() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try session.setActive(true)
    }

    func play(_ kind: ChimeKind) {
        guard let buffer = buffers[kind] else { return }
        if !isEngineRunning {
            try? engine.start()
            isEngineRunning = true
        }
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        player.play()
    }

    /// A short three-note ascending chime (C5-E5-G5) for "workout complete".
    private func fanfareSamples() -> [Float] {
        [523.25, 659.25, 783.99].flatMap {
            ToneGenerator.sineWaveSamples(frequency: $0, duration: 0.16, sampleRate: sampleRate)
        }
    }

    private func makeBuffer(samples: [Float]) -> AVAudioPCMBuffer? {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else {
            return nil
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        let channel = buffer.floatChannelData?[0]
        for (index, sample) in samples.enumerated() {
            channel?[index] = sample
        }
        return buffer
    }
}
```

- [ ] **Step 2: Add the file to the `IntervalApp` target and build**

In Xcode, make sure `ChimePlayer.swift` shows "IntervalApp" checked under Target Membership (right panel). Then:

```bash
cd /Users/tomfisher/interval_app
xcodebuild -project IntervalApp.xcodeproj -scheme IntervalApp \
  -destination 'generic/platform=iOS Simulator' build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
cd /Users/tomfisher/interval_app
git add IntervalApp/Audio/ChimePlayer.swift
git commit -m "feat: add ChimePlayer for synthesized background-capable chimes"
```

---

### Task 8: `WorkoutSetupView` — the configuration screen

The entire "0 barrier to entry" promise lives here: five plain-language fields (Total, Warm Up, Cool Down, Work, Rest), a live preview of the computed plan ("57 rounds of 30s work / 10s rest"), and a single **Start** button. No jargon, no extra screens.

**Files:**
- Create: `IntervalApp/Features/Setup/DurationStepper.swift`
- Create: `IntervalApp/Features/Setup/WorkoutSetupView.swift`

- [ ] **Step 1: Create the reusable stepper rows**

Create `IntervalApp/Features/Setup/DurationStepper.swift`:

```swift
import SwiftUI

/// A labeled stepper row showing whole minutes — used for Total / Warm Up / Cool Down.
struct MinutesStepper: View {
    let label: String
    @Binding var minutes: Double
    let range: ClosedRange<Double>
    let step: Double

    var body: some View {
        Stepper(value: $minutes, in: range, step: step) {
            HStack {
                Text(label)
                Spacer()
                Text("\(Int(minutes)) min")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// A labeled stepper row showing whole seconds — used for Work / Rest.
struct SecondsStepper: View {
    let label: String
    @Binding var seconds: Double
    let range: ClosedRange<Double>
    let step: Double

    var body: some View {
        Stepper(value: $seconds, in: range, step: step) {
            HStack {
                Text(label)
                Spacer()
                Text("\(Int(seconds)) sec")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
```

- [ ] **Step 2: Create the setup screen**

Create `IntervalApp/Features/Setup/WorkoutSetupView.swift`:

```swift
import SwiftUI
import IntervalKit

struct WorkoutSetupView: View {
    @State private var totalMinutes: Double = 45
    @State private var warmupMinutes: Double = 2
    @State private var cooldownMinutes: Double = 5
    @State private var workSeconds: Double = 30
    @State private var restSeconds: Double = 10

    @State private var planResult: Result<[WorkoutPhase], PlanBuildError>?
    @State private var currentPlan: [WorkoutPhase] = []
    @State private var isWorkoutPresented = false

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
            .fullScreenCover(isPresented: $isWorkoutPresented) {
                ActiveWorkoutView(phases: currentPlan)
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
        currentPlan = phases
        isWorkoutPresented = true
    }

    private func formatted(_ duration: TimeInterval) -> String {
        let total = Int(duration.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
```

Note: this view references `ActiveWorkoutView`, which is created in Task 9. The build will not succeed until that task is done — that's expected; do not skip ahead to "fix" it.

- [ ] **Step 3: Commit**

```bash
cd /Users/tomfisher/interval_app
git add IntervalApp/Features/Setup/
git commit -m "feat: add workout setup screen with live plan preview"
```

---

### Task 9: `ActiveWorkoutViewModel` + `ActiveWorkoutView` — the running workout screen

The screen people actually look at mid-set: huge countdown digits, the current phase name, which round they're on, and Pause/End controls. The view model wires `WorkoutTimerEngine` (logic) to `ChimePlayer` (sound) and refreshes its published display strings every tick.

**Files:**
- Create: `IntervalApp/Features/ActiveWorkout/ActiveWorkoutViewModel.swift`
- Create: `IntervalApp/Features/ActiveWorkout/ActiveWorkoutView.swift`

- [ ] **Step 1: Create the view model**

Create `IntervalApp/Features/ActiveWorkout/ActiveWorkoutViewModel.swift`:

```swift
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
        startTicking()
    }

    func pause() {
        engine.pause()
        isRunning = false
        ticker?.cancel()
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
    }

    private static func format(_ duration: TimeInterval) -> String {
        let total = max(0, Int(duration.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
```

- [ ] **Step 2: Create the view**

Create `IntervalApp/Features/ActiveWorkout/ActiveWorkoutView.swift`:

```swift
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
```

- [ ] **Step 3: Build the app and run it in the simulator**

```bash
cd /Users/tomfisher/interval_app
xcodebuild -project IntervalApp.xcodeproj -scheme IntervalApp \
  -destination 'platform=iOS Simulator,name=iPhone 16' build
```

(Swap `iPhone 16` for any simulator from `xcrun simctl list devices available` if that one isn't installed.)

Expected: `** BUILD SUCCEEDED **`. Then run it from Xcode (▶) on a simulator and manually walk through:
1. Leave the defaults (45 min total / 2 min warm up / 5 min cool down / 30s work / 10s rest) — the preview should read "57 rounds of 30s work / 10s rest".
2. Tap **Start** — you should land on a blue "Warm Up" screen counting down from 2:00, hear a chime, then it should switch to a red "Work — Round 1 of 57" screen.
3. Tap **Pause**, confirm the countdown stops; tap **Resume**, confirm it continues from where it left off.
4. Tap **End Workout**, confirm you're returned to the setup screen.

- [ ] **Step 4: Commit**

```bash
cd /Users/tomfisher/interval_app
git add IntervalApp/Features/ActiveWorkout/
git commit -m "feat: add active workout screen wired to timer engine and chimes"
```

---

### Task 10: Wire up the app entry point

**Files:**
- Modify: `IntervalApp/IntervalApp.swift` (the `@main` file Xcode generated in Task 1)

- [ ] **Step 1: Replace the generated entry point's body**

Open `IntervalApp/IntervalApp.swift` (Xcode names the `@main` struct after the product, so it should already look close to this) and replace its `body` so the app launches straight into setup — no splash, no onboarding, nothing between opening the app and being able to start a workout:

```swift
import SwiftUI

@main
struct IntervalApp: App {
    var body: some Scene {
        WindowGroup {
            WorkoutSetupView()
        }
    }
}
```

- [ ] **Step 2: Build and launch end to end**

```bash
cd /Users/tomfisher/interval_app
xcodebuild -project IntervalApp.xcodeproj -scheme IntervalApp \
  -destination 'platform=iOS Simulator,name=iPhone 16' build
```

Expected: `** BUILD SUCCEEDED **`. Run from Xcode — the app should open directly to the setup form.

- [ ] **Step 3: Commit**

```bash
cd /Users/tomfisher/interval_app
git add IntervalApp/IntervalApp.swift
git commit -m "feat: launch app directly into workout setup"
```

---

### Task 11: Live Activity — show the running workout on the Lock Screen

This is what lets someone glance at their *locked* phone mid-set and instantly see "Work — 0:14 — Round 8 of 57" without unlocking. It requires its own Xcode target (a Widget Extension), a small `ActivityAttributes` type shared between the app and that extension, and an `ActivityConfiguration` describing the lock-screen / Dynamic Island UI.

**Files:**
- Create (via Xcode GUI): `IntervalWidgetExtension` target
- Create: `IntervalApp/Shared/WorkoutActivityAttributes.swift` (shared with the widget extension)
- Create: `IntervalWidgetExtension/IntervalWidgetBundle.swift`
- Create: `IntervalWidgetExtension/WorkoutLiveActivity.swift`
- Create: `IntervalApp/Audio/WorkoutActivityController.swift`
- Modify: `IntervalApp/Features/ActiveWorkout/ActiveWorkoutViewModel.swift`

- [ ] **Step 1: Add the Widget Extension target (manual, in Xcode)**

**File → New → Target… → Widget Extension**:
- Product Name: `IntervalWidgetExtension`
- Uncheck "Include Configuration Intent"
- When prompted "Activate scheme?", choose **Activate**

Xcode generates a folder with a `WidgetBundle` and a sample `Widget` — you'll replace both.

- [ ] **Step 2: Enable Live Activities support (manual, in Xcode)**

Select the `IntervalApp` target → **Info** tab → add a row to **Custom iOS Target Properties**:
- Key: `NSSupportsLiveActivities`
- Type: Boolean
- Value: `YES`

- [ ] **Step 3: Create the shared attributes type**

Create `IntervalApp/Shared/WorkoutActivityAttributes.swift`. In Xcode's File Inspector, check **both** `IntervalApp` and `IntervalWidgetExtension` under Target Membership — both binaries need this type:

```swift
import ActivityKit
import Foundation

/// The data a Live Activity needs to render the lock-screen / Dynamic Island UI.
/// `ContentState` is what gets pushed on every update (every tick of the workout).
struct WorkoutActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var phaseName: String
        var remainingSeconds: Int
        var roundLabel: String?
    }

    var workoutTitle: String
}
```

- [ ] **Step 4: Replace the generated widget files**

Delete the sample widget Xcode generated inside `IntervalWidgetExtension/` and create `IntervalWidgetExtension/WorkoutLiveActivity.swift`:

```swift
import ActivityKit
import SwiftUI
import WidgetKit

struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 6) {
                Text(context.state.phaseName)
                    .font(.headline)
                Text(timeString(context.state.remainingSeconds))
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .monospacedDigit()
                if let roundLabel = context.state.roundLabel {
                    Text(roundLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .activityBackgroundTint(.black.opacity(0.8))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    VStack {
                        Text(context.state.phaseName)
                            .font(.headline)
                        Text(timeString(context.state.remainingSeconds))
                            .font(.title2)
                            .monospacedDigit()
                    }
                }
            } compactLeading: {
                Text(context.state.phaseName.prefix(4))
            } compactTrailing: {
                Text(timeString(context.state.remainingSeconds))
                    .monospacedDigit()
            } minimal: {
                Text(timeString(context.state.remainingSeconds))
                    .monospacedDigit()
            }
        }
    }

    private func timeString(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
```

Create `IntervalWidgetExtension/IntervalWidgetBundle.swift`:

```swift
import SwiftUI
import WidgetKit

@main
struct IntervalWidgetBundle: WidgetBundle {
    var body: some Widget {
        WorkoutLiveActivity()
    }
}
```

- [ ] **Step 5: Create the activity controller on the app side**

Create `IntervalApp/Audio/WorkoutActivityController.swift`:

```swift
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
```

- [ ] **Step 6: Wire the controller into the view model**

Modify `IntervalApp/Features/ActiveWorkout/ActiveWorkoutViewModel.swift`:

Add the controller as a stored property, alongside `chimePlayer`:

```swift
    private let engine: WorkoutTimerEngine
    private let chimePlayer: ChimePlayer
    private let activityController = WorkoutActivityController()
    private var ticker: AnyCancellable?
```

In `start()`, start the activity right after the engine starts:

```swift
    func start() {
        try? chimePlayer.configureSessionForBackgroundPlayback()
        engine.start()
        isRunning = true
        activityController.start(phase: engine.currentPhase, remaining: engine.remainingInPhase, roundLabel: roundLabel)
        startTicking()
    }
```

In `refreshDisplay()`, push an update after recomputing the display strings (append at the end of the method, after `roundLabel` is set):

```swift
        activityController.update(phase: phase, remaining: engine.remainingInPhase, roundLabel: roundLabel)
```

In `handle(_:)`, end the activity when the workout finishes — add it to the `.workoutFinished` case body, alongside the existing lines:

```swift
        case .workoutFinished:
            chimePlayer.play(.workoutComplete)
            isRunning = false
            isFinished = true
            ticker?.cancel()
            activityController.end()
```

Finally, in `pause()`, end the activity too (a paused workout shouldn't keep showing a moving countdown on the lock screen):

```swift
    func pause() {
        engine.pause()
        isRunning = false
        ticker?.cancel()
        activityController.end()
    }
```

- [ ] **Step 7: Build for the simulator and verify on device**

```bash
cd /Users/tomfisher/interval_app
xcodebuild -project IntervalApp.xcodeproj -scheme IntervalApp \
  -destination 'platform=iOS Simulator,name=iPhone 16' build
```

Expected: `** BUILD SUCCEEDED **`.

Live Activities render fully only on a physical device (the simulator's Lock Screen doesn't reliably surface them). On a real iPhone running iOS 17+: start a workout, lock the phone, and confirm the Lock Screen shows the current phase name and a live countdown that updates each second; long-press the Dynamic Island (iPhone 14 Pro or later) to confirm the expanded view also updates.

- [ ] **Step 8: Commit**

```bash
cd /Users/tomfisher/interval_app
git add IntervalApp/Shared/ IntervalApp/Audio/WorkoutActivityController.swift \
        IntervalApp/Features/ActiveWorkout/ActiveWorkoutViewModel.swift \
        IntervalWidgetExtension/ IntervalApp.xcodeproj
git commit -m "feat: add Live Activity showing workout progress on Lock Screen"
```

---

### Task 12: End-to-end manual verification

No more code changes — this is the final pass to confirm the whole thing works the way someone mid-workout actually needs it to. Run every check on a **physical iPhone** (Live Activities and true backgrounded-audio behavior don't fully reproduce in the simulator).

**Files:** none (manual verification only)

- [ ] **Step 1: Golden path — exactly the example from the spec**

Set Total = 45 min, Warm Up = 2 min, Cool Down = 5 min, Work = 30s, Rest = 10s.
Confirm the preview reads **"57 rounds of 30s work / 10s rest"** and that starting the workout plays a chime on every single phase change (Warm Up → Round 1 Work → Round 1 Rest → … → Cool Down → Complete fanfare).

- [ ] **Step 2: Uneven duration — confirm the cooldown padding is visible and correct**

Set Total = 30 min, Warm Up = 1 min, Cool Down = 2 min, Work = 45s, Rest = 20s.
Confirm the preview shows **24 rounds** and a note that cool down was adjusted to **3:00** (120s + 60s leftover).

- [ ] **Step 3: Locked-screen behavior — the most important check**

Start any workout, then lock the phone (or switch to another app) during a Work phase. Wait through at least 3 phase transitions without touching the phone. Confirm:
- You hear a chime at every transition, even though the screen is off / another app is open.
- Unlocking the phone shows the Lock Screen Live Activity with the correct current phase, an accurate countdown, and the right round number.
- Returning to the app shows it perfectly in sync with what the Live Activity displayed (no drift, no skipped phases).

- [ ] **Step 4: Validation messages — confirm they're plain-language, not technical**

Try each of these and confirm the in-form message is immediately understandable with zero domain knowledge:
- Warm Up = 30 min, Cool Down = 30 min, Total = 45 min → "Warm Up + Cool Down is longer than your Total time…"
- Work = 9 min, Rest = 9 min, Total = 10 min, Warm Up = 0, Cool Down = 0 → "Work + Rest doesn't fit even once…"

- [ ] **Step 5: Pause / Resume / End — confirm no surprises**

Start a workout, pause mid-Rest, wait 30 seconds, resume — confirm the countdown picks up exactly where it left off (not from the start of the phase). Tap **End Workout** mid-set and confirm you land back on the setup screen with your last-entered values still showing (SwiftUI `@State` survives the `fullScreenCover` dismissal automatically — if it doesn't, that's a regression to investigate, not expected behavior to design around).

- [ ] **Step 6: Final commit**

```bash
cd /Users/tomfisher/interval_app
git add -A
git status
```

If `git status` shows anything beyond what's already committed (it shouldn't — this task is verification-only), review it before committing. Otherwise, the app is done.

---

## Self-Review Notes

- **Spec coverage:** total/warmup/cooldown/work/rest inputs → Task 8; auto-fill math → Task 3; bell chime on every transition → Tasks 5, 7, 9; "0 barrier to entry" simple naming and single-screen flow → Task 8 (plain labels: Total / Warm Up / Cool Down / Work / Rest, one Start button, inline plain-language errors); works with the phone locked → Tasks 6, 7, 11.
- **Type consistency check:** `WorkoutPhase`, `PhaseKind`, `WorkoutConfig`, `PlanBuildError`, `TimerEvent`, `WorkoutTimerEngine`, `ChimePlayer.ChimeKind`, `ActiveWorkoutViewModel`, `WorkoutActivityAttributes.ContentState` are each defined exactly once and referenced with the same names/signatures everywhere they're used across Tasks 2–11.
- **No placeholders:** every step that touches code includes the complete file contents or an exact, located edit — nothing is left as "add appropriate handling" or "similar to above".
