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
