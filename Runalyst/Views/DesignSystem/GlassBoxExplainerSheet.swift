import SwiftUI

/// Universal Glass-Box Explainer modal sheet.
/// Unpacks technical sports science into structured, human-readable sections:
/// 1. What It Is (Runner English)
/// 2. Why It Matters (Physiological Impact)
/// 3. How Runalyst Calculates It (Transparent Swift Math & Targets)
public struct GlassBoxExplainerSheet: View {
    public let title: String
    public let categoryBadge: String
    public let whatSummary: String
    public let whyItMatters: String
    public let howItWorks: String
    public var formula: String?
    public var targetRange: String?
    public var liveMetricDisplay: String?

    @Environment(\.dismiss) private var dismiss

    public init(
        title: String,
        categoryBadge: String,
        whatSummary: String,
        whyItMatters: String,
        howItWorks: String,
        formula: String? = nil,
        targetRange: String? = nil,
        liveMetricDisplay: String? = nil
    ) {
        self.title = title
        self.categoryBadge = categoryBadge
        self.whatSummary = whatSummary
        self.whyItMatters = whyItMatters
        self.howItWorks = howItWorks
        self.formula = formula
        self.targetRange = targetRange
        self.liveMetricDisplay = liveMetricDisplay
    }

    public init(info: MetricExplainerInfo) {
        self.title = info.title
        self.categoryBadge = info.mode ?? "Metric"
        self.whatSummary = info.overview
        self.whyItMatters = info.whyItMatters ?? "Maintaining safe biomechanical targets preserves energy, prevents soft-tissue fatigue, and supports joint longevity."
        self.howItWorks = info.modeContext ?? "Calculated locally from your Apple Watch high-frequency sensor telemetry, pause-trimmed to eliminate sensor noise."
        self.formula = nil
        self.targetRange = info.targetRange
        self.liveMetricDisplay = info.userMetricDisplay
    }

    public init(explainer: MetricDetailExplainer, mode: String? = nil, userMetricDisplay: String? = nil) {
        self.title = explainer.title
        self.categoryBadge = mode ?? "Metric"
        self.whatSummary = explainer.overview
        self.whyItMatters = explainer.whyItMatters
        self.howItWorks = explainer.modeContext
        self.formula = nil
        self.targetRange = explainer.targetRange
        self.liveMetricDisplay = userMetricDisplay
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header Status Bar
                    HStack(spacing: 8) {
                        Text(categoryBadge.uppercased())
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.purple)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.purple.opacity(0.12))
                            .clipShape(Capsule())

                        if let live = liveMetricDisplay, !live.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "waveform.path.ecg")
                                    .font(.caption2.bold())
                                Text(live)
                                    .font(.caption.bold())
                                    .monospacedDigit()
                            }
                            .foregroundColor(.blue)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.12))
                            .clipShape(Capsule())
                        }

                        Spacer()
                    }

                    // Section 1: What It Is
                    sectionBox(
                        title: "What It Is",
                        icon: "sparkles",
                        iconColor: .purple,
                        content: whatSummary
                    )

                    // Section 2: Why It Matters
                    sectionBox(
                        title: "Why It Matters",
                        icon: "bolt.heart.fill",
                        iconColor: Color(red: 1.0, green: 0.18, blue: 0.55),
                        content: whyItMatters
                    )

                    // Section 3: How Runalyst Calculates It
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "function")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.blue)
                            Text("HOW RUNALYST CALCULATES IT")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(.secondary)
                        }

                        Text(howItWorks)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                            .lineSpacing(3)

                        if let formula, !formula.isEmpty {
                            HStack {
                                Text(formula)
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.blue)
                                    .padding(10)
                                Spacer()
                            }
                            .background(Color(UIColor.tertiarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .padding(.top, 4)
                        }

                        if let targetRange, !targetRange.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("TARGET RANGE")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.secondary)
                                Text(targetRange)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineSpacing(2)
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.green.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Color.green.opacity(0.2), lineWidth: 0.5)
                            )
                            .padding(.top, 4)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color(UIColor.separator).opacity(0.12), lineWidth: 0.5)
                    )
                }
                .padding(20)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        dismiss()
                    }
                    .font(.subheadline.bold())
                    .frame(minHeight: 44)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func sectionBox(title: String, icon: String, iconColor: Color, content: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(iconColor)
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary)
            }

            Text(content)
                .font(.subheadline)
                .foregroundColor(.primary)
                .lineSpacing(3)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(UIColor.separator).opacity(0.12), lineWidth: 0.5)
        )
    }
}
