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
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(UIColor.separator).opacity(0.15), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.03), radius: 4, x: 0, y: 2)
        .contentShape(Rectangle())
        .onTapGesture {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showingInfo = true
        }
        .sheet(isPresented: $showingInfo) {
            let metricText = "\(title): \(value) \(unit)".trimmingCharacters(in: .whitespaces)
            MetricExplainerSheet(
                title: explainer.title,
                mode: isWorkoutStats ? "Workout Stats" : "Working Stats",
                overview: explainer.overview,
                modeContext: explainer.modeContext,
                whyItMatters: explainer.whyItMatters,
                targetRange: explainer.targetRange,
                userMetricDisplay: metricText
            )
        }
    }
}
