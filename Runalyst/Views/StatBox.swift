import SwiftUI

enum MetricPolarity {
    case higherIsBetter
    case lowerIsBetter
}

struct StatBox: View {
    var title: String
    var value: String
    var unit: String
    var currentValue: Double?
    var baselineValue: Double?
    var polarity: MetricPolarity?
    var isWorkoutStats: Bool = false

    @State private var showingInfo = false

    var body: some View {
        let explainer = MetricDetailExplainer.explainer(for: title, isWorkoutStats: isWorkoutStats)

        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
                .textCase(.uppercase)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text(unit)
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let current = currentValue, let baseline = baselineValue, let polarity = polarity {
                    let diff = current - baseline
                    if abs(diff) > 0.01 {
                        let isPositiveTrend = diff > 0
                        let isGood = (polarity == .higherIsBetter) ? isPositiveTrend : !isPositiveTrend
                        Image(systemName: isPositiveTrend ? "arrow.up.right" : "arrow.down.right")
                            .font(.subheadline)
                            .bold()
                            .foregroundColor(isGood ? .green : .red)
                            .padding(.leading, 2)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(cornerRadius: 16, padding: 14)
        .contentShape(Rectangle())
        .onTapGesture {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showingInfo = true
        }
        .sheet(isPresented: $showingInfo) {
            let metricText = "\(title): \(value) \(unit)".trimmingCharacters(in: .whitespaces)
            GlassBoxExplainerSheet(
                explainer: explainer,
                mode: isWorkoutStats ? "Workout Stats" : "Working Stats",
                userMetricDisplay: metricText
            )
        }
    }
}
