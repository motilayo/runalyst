import SwiftUI

/// Comprehensive modal explaining how Runalyst calculates and categorizes run classifications
struct RunClassificationExplainerSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header Card
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "sparkles")
                                .foregroundColor(.purple)
                                .font(.title3)
                            Text("CoreML & Biometrics")
                                .font(.caption.bold())
                                .foregroundColor(.purple)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.purple.opacity(0.12))
                                .clipShape(Capsule())
                            Spacer()
                        }

                        Text("How Runs Are Classified")
                            .font(.title2.bold())
                            .foregroundColor(.primary)

                        Text("Runalyst analyzes your continuous minute-by-minute running data using on-device machine learning paired with physiological cardiac rules. We identify what your body actually experienced, not just what was scheduled.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineSpacing(2)
                    }
                    .padding(14)
                    .background(Color(UIColor.secondarySystemFill))
                    .cornerRadius(12)

                    // Key Signals Analyzed
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Signals We Analyze")
                            .font(.headline)
                            .foregroundColor(.primary)

                        SignalExplainerRow(
                            icon: "heart.fill",
                            iconColor: .red,
                            title: "Cardiac Effort (Zone 4 %)",
                            description: "Strict cardiac guardrails ensure that high-intensity or elevated heart rate sessions are never classified as easy or recovery, even if your pace was slow on hills or in the heat."
                        )

                        SignalExplainerRow(
                            icon: "chart.line.uptrend.xyaxis",
                            iconColor: .orange,
                            title: "Pace Consistency (CV)",
                            description: "Measures pacing variance. Low variance (< 6%) signals steady or tempo efforts, while higher variance indicates interval surges, fartleks, or stop-and-go running."
                        )

                        SignalExplainerRow(
                            icon: "arrow.up.right",
                            iconColor: .green,
                            title: "Pacing Trend (Slope)",
                            description: "Detects whether you accelerated over time (Progression Run with negative splits) or steadily slowed down (fatigue drift)."
                        )

                        SignalExplainerRow(
                            icon: "clock.badge.checkmark",
                            iconColor: .blue,
                            title: "Duration & Volume",
                            description: "Extended steady sessions (70+ minutes) are recognized as Long Runs, while short flush sessions (< 40 minutes at low heart rate) qualify as Recovery Runs."
                        )

                        SignalExplainerRow(
                            icon: "figure.walk",
                            iconColor: .teal,
                            title: "Dead Stops vs. Rest Intervals",
                            description: "Our filter isolates active running from street crossings and traffic stops so stoplights don't skew your workout classification."
                        )
                    }

                    // Common Workout Categories
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Classification Categories")
                            .font(.headline)
                            .foregroundColor(.primary)

                        Group {
                            ClassificationCategoryRow(name: "Easy Run", tag: "Aerobic Base", color: .green, description: "Comfortable, conversational running in Zones 1–2.")
                            ClassificationCategoryRow(name: "Steady Effort", tag: "Aerobic Rhythm", color: .teal, description: "Smooth, even pace with minimal speed fluctuation.")
                            ClassificationCategoryRow(name: "Tempo Run", tag: "Lactate Threshold", color: .orange, description: "Sustained comfortably hard effort with elevated heart rate.")
                            ClassificationCategoryRow(name: "Intervals / Pyramids", tag: "Speed Repeats", color: .red, description: "High-intensity work surges alternating with recovery jogs.")
                            ClassificationCategoryRow(name: "Progression Run", tag: "Negative Splits", color: .indigo, description: "Starting relaxed and getting progressively faster each mile.")
                            ClassificationCategoryRow(name: "Long Run", tag: "Stamina", color: .blue, description: "Extended endurance run prioritizing time on feet.")
                            ClassificationCategoryRow(name: "Recovery Run", tag: "Active Recovery", color: .mint, description: "Short, low-heart-rate flush run to relieve muscle stiffness.")
                            ClassificationCategoryRow(name: "Fartlek", tag: "Speed Play", color: .purple, description: "Freeform continuous run with variable pace changes.")
                        }
                    }

                    // Manual Override Section
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "slider.horizontal.3")
                                .foregroundColor(.secondary)
                            Text("Manual Override & Learning")
                                .font(.subheadline.bold())
                                .foregroundColor(.primary)
                        }

                        Text("If a run was categorized differently than your intention (e.g. summer heat elevated your heart rate on an easy run), simply tap the Classification menu on the run card to select the correct label. Your manual corrections update the local SwiftData profile to calibrate future AI recommendations.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineSpacing(2)
                    }
                    .padding(12)
                    .background(Color(UIColor.tertiarySystemFill))
                    .cornerRadius(10)
                }
                .padding(20)
            }
            .navigationTitle("Run Classification")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

private struct SignalExplainerRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundColor(iconColor)
                .frame(width: 24, height: 24)
                .background(iconColor.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundColor(.primary)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineSpacing(2)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct ClassificationCategoryRow: View {
    let name: String
    let tag: String
    let color: Color
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(name)
                        .font(.subheadline.bold())
                        .foregroundColor(.primary)
                    Spacer()
                    Text(tag)
                        .font(.caption2.bold())
                        .foregroundColor(color)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(color.opacity(0.12))
                        .clipShape(Capsule())
                }
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
