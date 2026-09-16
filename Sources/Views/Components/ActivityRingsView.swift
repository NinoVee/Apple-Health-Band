import SwiftUI

/// The Move / Exercise / Stand triple ring, laid out and colored to match
/// Apple's Activity app.
struct ActivityRingsView: View {
    let moveProgress: Double
    let exerciseProgress: Double
    let standProgress: Double
    var diameter: CGFloat = 220

    var body: some View {
        ZStack {
            RingProgressView(progress: moveProgress, gradient: RingColors.move, lineWidth: diameter * 0.09)
            RingProgressView(progress: exerciseProgress, gradient: RingColors.exercise, lineWidth: diameter * 0.09)
                .padding(diameter * 0.11)
            RingProgressView(progress: standProgress, gradient: RingColors.stand, lineWidth: diameter * 0.09)
                .padding(diameter * 0.22)
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Activity rings")
        .accessibilityValue(
            "Move \(Int(moveProgress * 100)) percent, Exercise \(Int(exerciseProgress * 100)) percent, Stand \(Int(standProgress * 100)) percent"
        )
    }
}
