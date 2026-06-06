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
