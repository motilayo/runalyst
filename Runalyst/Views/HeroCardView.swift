import SwiftData
import SwiftUI

struct HeroCardView: View {
    var runRecord: RunRecord
    var isSyncing: Bool
    var allRuns: [RunRecord]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @AppStorage("useMetricSystem") private var useMetricSystem: Bool = Locale.current.measurementSystem == .metric

    private var formattedDuration: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: runRecord.duration) ?? ""
    }

    private var baselineStats: SessionSynthesisEngine.WeightedBaselineStats? {
        SessionSynthesisEngine.computeWeightedBaselineStats(from: allRuns, priorTo: runRecord.date)
    }

    private var baselinePace: Double? {
        baselineStats?.avgPace
    }

    private var baselineHR: Double? {
        baselineStats?.avgHR
    }

    private var baselineCadence: Double? {
        baselineStats?.avgCadence
    }

    private var hasBiometrics: Bool {
        runRecord.workingAvgCadence > 0 || runRecord.workingAvgHeartRate > 0
    }

    private var prescribedDrillName: String? {
        guard !runRecord.isDeleted, runRecord.modelContext != nil else { return nil }
        return runRecord.prescribedDrillName
    }

    private func cleanUpInvalidDrillTagsIfNeeded() {
        guard !runRecord.isDeleted, runRecord.modelContext != nil else { return }
        var needsSave = false
        if let userLinked = runRecord.framboiseTags.first(where: { $0.hasPrefix("userLinkedDrill:") }) {
            let drillTitle = String(userLinked.dropFirst("userLinkedDrill:".count))
            let valid = PreRunDrillId.allCases.contains { $0.title == drillTitle || $0.rawValue == drillTitle }
            if !valid {
                runRecord.framboiseTags.removeAll { $0 == userLinked }
                needsSave = true
            }
        }
        if let userUnlinked = runRecord.framboiseTags.first(where: { $0.hasPrefix("userUnlinkedDrill:") }) {
            let drillTitle = String(userUnlinked.dropFirst("userUnlinkedDrill:".count))
            let valid = PreRunDrillId.allCases.contains { $0.title == drillTitle || $0.rawValue == drillTitle }
            if !valid {
                runRecord.framboiseTags.removeAll { $0 == userUnlinked }
                needsSave = true
            }
        }
        if needsSave {
            try? modelContext.save()
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header Row: Status tag, Date, and Indoor Pill
            HStack(alignment: .center) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 8, height: 8)
                    Text("LATEST RUN")
                        .font(.caption2.bold())
                        .foregroundColor(.secondary)
                        .tracking(0.5)
                }

                if runRecord.isIndoor == true {
                    HStack(spacing: 3) {
                        Image(systemName: "figure.run.treadmill")
                        Text("Treadmill")
                    }
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.12))
                    .foregroundColor(.secondary)
                    .clipShape(Capsule())
                }

                Spacer()

                Text(runRecord.date, style: .date)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            // Big Hero Numbers: Distance & Time
            HStack(alignment: .firstTextBaseline) {
                let distanceConverted = useMetricSystem ? (runRecord.totalDistanceMeters / 1000.0) : (runRecord.totalDistanceMeters / 1609.344)
                let distanceUnit = useMetricSystem ? "km" : "mi"

                Text(String(format: "%.2f", distanceConverted))
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                Text(distanceUnit)
                    .font(.title3.bold())
                    .foregroundColor(.secondary)
                    .padding(.trailing, 16)

                Text(formattedDuration)
                    .font(.title2.bold())
                    .foregroundColor(.secondary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.subheadline.bold())
                    .foregroundColor(Color.secondary.opacity(0.6))
            }

            Divider()

            // Metrics Grid: Pace, HR, Cadence with Delta Arrows
            HStack(spacing: 0) {
                let pace = PaceFormatter.formatPace(secondsPerKilometer: runRecord.workingAvgPace)
                MetricView(
                    title: "Working Pace",
                    value: pace,
                    currentValue: runRecord.workingAvgPace > 0 ? runRecord.workingAvgPace : nil,
                    baselineValue: baselinePace,
                    polarity: .lowerIsBetter
                )
                .frame(maxWidth: .infinity, alignment: .leading)

                let hrValue = runRecord.workingAvgHeartRate > 0 ? "\(Int(round(runRecord.workingAvgHeartRate))) BPM" : "--"
                MetricView(
                    title: "Avg HR",
                    value: hrValue,
                    currentValue: runRecord.workingAvgHeartRate > 0 ? runRecord.workingAvgHeartRate : nil,
                    baselineValue: baselineHR,
                    polarity: .lowerIsBetter
                )
                .frame(maxWidth: .infinity, alignment: .leading)

                let cadValue = runRecord.workingAvgCadence > 0 ? "\(Int(round(runRecord.workingAvgCadence))) SPM" : "--"
                MetricView(
                    title: "Avg Cadence",
                    value: cadValue,
                    currentValue: runRecord.workingAvgCadence > 0 ? runRecord.workingAvgCadence : nil,
                    baselineValue: baselineCadence,
                    polarity: .higherIsBetter
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Secondary Metrics: Vertical Oscillation & Stride Length (Outdoors / with Pod)
            let currentOsc = runRecord.workingAvgVerticalOscillation ?? runRecord.rawAvgVerticalOscillation
            let currentStride = runRecord.workingAvgStrideLength ?? runRecord.rawAvgStrideLength

            if currentOsc != nil || currentStride != nil {
                HStack(spacing: 12) {
                    if let osc = currentOsc, osc > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.and.down")
                                .font(.caption2)
                            Text(String(format: "Bounce: %.1f cm", osc))
                                .font(.caption2.bold())
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.1))
                        .foregroundColor(.secondary)
                        .clipShape(Capsule())
                    }

                    if let stride = currentStride, stride > 0 {
                        let strideConverted = useMetricSystem ? stride : (stride * 3.28084)
                        let strideUnit = useMetricSystem ? "m" : "ft"
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.left.and.right")
                                .font(.caption2)
                            Text(String(format: "Stride: %.2f %@", strideConverted, strideUnit))
                                .font(.caption2.bold())
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.1))
                        .foregroundColor(.secondary)
                        .clipShape(Capsule())
                    }

                    Spacer()
                }
            }

            // Classification Pill or Drill Focus Pill
            HStack(spacing: 6) {
                if let drillName = prescribedDrillName {
                    let iconName = PreRunDrill.iconName(for: nil, title: drillName)
                    let iconColor = PreRunDrill.iconColor(for: nil, title: drillName)
                    HStack(spacing: 4) {
                        Image(systemName: iconName)
                        Text(drillName)
                    }
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(iconColor.opacity(0.15))
                    .foregroundColor(iconColor)
                    .clipShape(Capsule())
                } else {
                    let classification = runRecord.detectedTypeRaw.isEmpty ? runRecord.normalizedClassification : runRecord.detectedTypeRaw
                    let isReview = classification == "Mixed Effort (Review)"
                    Text(classification)
                        .font(.caption.bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background((isReview ? Color.orange : Color(red: 0.05, green: 0.45, blue: 0.5)).opacity(0.12))
                        .foregroundColor(isReview ? .orange : Color(red: 0.05, green: 0.45, blue: 0.5))
                        .clipShape(Capsule())
                }

                Spacer()
            }

            // AI Insight Headline
            if let headline = runRecord.insight?.headline, !headline.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "sparkles")
                        .foregroundColor(.orange)
                        .font(.subheadline)
                        .padding(.top, 1)

                    Text(headline)
                        .font(.subheadline.bold())
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 2)
            }

            // AI Disclaimer Footer
            aiDisclaimerFooter
        }
        .padding(18)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color(UIColor.separator).opacity(0.15), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 3)
        .padding(.horizontal)
        .onAppear {
            cleanUpInvalidDrillTagsIfNeeded()
        }
    }

    @ViewBuilder
    private var aiDisclaimerFooter: some View {
        AIDisclaimerFooter()
    }
}

struct MetricView: View {
    let title: String
    let value: String
    var currentValue: Double?
    var baselineValue: Double?
    var polarity: MetricPolarity?

    @State private var showingInfo = false

    var body: some View {
        let explainer = MetricDetailExplainer.explainer(for: title, isWorkoutStats: false)

        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Image(systemName: "info.circle")
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.7))
            }

            HStack(spacing: 4) {
                Text(value)
                    .font(.headline)
                    .foregroundColor(.primary)

                if let current = currentValue, let baseline = baselineValue, let polarity = polarity {
                    let diff = current - baseline
                    if abs(diff) > 0.01 {
                        let isPositiveTrend = diff > 0
                        let isGood = (polarity == .higherIsBetter) ? isPositiveTrend : !isPositiveTrend

                        Image(systemName: isPositiveTrend ? "arrow.up.right" : "arrow.down.right")
                            .font(.caption2)
                            .bold()
                            .foregroundColor(isGood ? .green : .red)
                    }
                }
            }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .onTapGesture {
            showingInfo = true
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
        .accessibilityHint("Double tap to learn more about this metric")
        .sheet(isPresented: $showingInfo) {
            GlassBoxExplainerSheet(explainer: explainer, mode: "Working Stats")
        }
    }
}
