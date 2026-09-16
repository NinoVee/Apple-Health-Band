import SwiftUI

/// A single Apple-Activity-style progress ring. `progress` is 0...1 for
/// the base ring; values above 1.0 (up to 1.5) draw a dimmer overlap lap
/// to show over-achievement, the same way Apple's rings "lap" past 100%.
struct RingProgressView: View {
    let progress: Double
    let gradient: [Color]
    let lineWidth: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke((gradient.first ?? .gray).opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(progress, 1.0))
                .stroke(
                    AngularGradient(colors: gradient, center: .center),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.6), value: progress)
            if progress > 1.0 {
                Circle()
                    .trim(from: 0, to: min(progress - 1.0, 1.0))
                    .stroke(
                        AngularGradient(colors: gradient, center: .center),
                        style: StrokeStyle(lineWidth: lineWidth * 0.4, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .padding(lineWidth * 0.35)
                    .opacity(0.6)
                    .animation(.easeOut(duration: 0.6), value: progress)
            }
        }
    }
}
