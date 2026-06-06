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
