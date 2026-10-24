import SwiftUI

/// Modal sheet explicitly exposing the mathematical formulas and ACWR calculation behind adaptive targets, rendering with unified GlassBox architecture.
struct ReadinessMathModal: View {
    @Environment(\.dismiss) private var dismiss

    let acuteLoad: Double
    let chronicWeeklyLoad: Double
    let acwr: Double?
    let targetAdjustmentNote: String

    init(
        acuteLoad: Double = 0,
        chronicWeeklyLoad: Double = 0,
        acwr: Double? = nil,
        targetAdjustmentNote: String = ""
    ) {
        if let profile = MacroProfile.load() {
            self.acuteLoad = profile.acuteLoad
            self.chronicWeeklyLoad = profile.chronicWeeklyLoad
            self.acwr = profile.acwr
            self.targetAdjustmentNote = targetAdjustmentNote.isEmpty
                ? "Adaptive Target Prescribed via Longitudinal Readiness"
                : targetAdjustmentNote
        } else {
            self.acuteLoad = acuteLoad
            self.chronicWeeklyLoad = chronicWeeklyLoad
            self.acwr = acwr
            self.targetAdjustmentNote = targetAdjustmentNote
        }
    }

    var body: some View {
        let ratioDisplay = acwr.map { String(format: "%.2f", $0) } ?? "1.00"
        GlassBoxExplainerSheet(
            title: "Training Load & Readiness",
            categoryBadge: "Banister ACWR Model",
            whatSummary: "We compare your running volume this week (Acute Load: \(Int(acuteLoad)) km) against your past month's rolling baseline (Chronic Load: \(Int(chronicWeeklyLoad)) km) to evaluate biological fatigue versus fitness.",
            whyItMatters: "Spikes in acute training volume without sufficient chronic adaptation significantly increase musculoskeletal strain and injury risk. Maintaining your ACWR within 0.8–1.3 safely drives aerobic supercompensation.",
            howItWorks: "Calculates the ratio of your 7-day exponentially weighted volume over your 28-day baseline. When ACWR > 1.3, Runalyst dynamically dials back interval intensity to protect connective tissue.",
            formula: "ACWR = 7-Day Acute Load ÷ (28-Day Chronic Load ÷ 4)",
            targetRange: "Sweet Spot: 0.80–1.30 • Danger Zone: > 1.50",
            liveMetricDisplay: "Current ACWR: \(ratioDisplay)"
        )
    }
}

// MARK: - Training Load Status Bar

/// Shared color-coded status bar displaying the athlete's ACWR ratio and status, with tap-to-inspect readiness math.
struct TrainingLoadStatusBar: View {
    let acwr: Double?
    let acuteLoad: Double
    let chronicWeeklyLoad: Double
    @State private var showingReadinessMath = false

    init(acwr: Double?, acuteLoad: Double = 0, chronicWeeklyLoad: Double = 0) {
        self.acwr = acwr
        self.acuteLoad = acuteLoad
        self.chronicWeeklyLoad = chronicWeeklyLoad
    }

    init(runRecords: [RunRecord]) {
        let profile = MacroProfile.load()
        let readiness = ReadinessEvaluator.assess(runRecords: runRecords)
        self.acwr = profile?.acwr ?? readiness.acwr
        self.acuteLoad = profile?.acuteLoad ?? readiness.acuteLoad
        self.chronicWeeklyLoad = profile?.chronicWeeklyLoad ?? readiness.chronicWeeklyLoad
    }

    var body: some View {
        let status = Self.status(for: acwr)
        Button {
            showingReadinessMath = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "gauge.with.needle")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(status.color)

                Text("Training Load:")
                    .font(.caption.weight(.medium))
                    .foregroundColor(.secondary)

                Text(status.displayText)
                    .font(.caption.bold())
                    .foregroundColor(status.color)

                Spacer()

                Image(systemName: "info.circle")
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.6))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(status.color.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(status.color.opacity(0.22), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingReadinessMath) {
            ReadinessMathModal(
                acuteLoad: acuteLoad,
                chronicWeeklyLoad: chronicWeeklyLoad,
                acwr: acwr
            )
        }
    }

    static func status(for ratio: Double?) -> (displayText: String, color: Color) {
        guard let ratio = ratio else {
            return ("Building Base", .blue)
        }
        if ratio > 1.50 { return ("Spike Risk (\(String(format: "%.2f", ratio)))", .red) }
        if ratio > 1.30 { return ("Elevated (\(String(format: "%.2f", ratio)))", .orange) }
        if ratio >= 0.80 { return ("Optimal (\(String(format: "%.2f", ratio)))", .green) }
        return ("Building Base (\(String(format: "%.2f", ratio)))", .blue)
    }
}

// MARK: - Drill Coaching Cue Box

/// Stylized warm coaching cue callout for drill cards.
struct DrillCoachingCueBox: View {
    let cue: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lightbulb.fill")
                .foregroundColor(.orange)
                .font(.caption)
                .padding(.top, 1)
            Text(cue)
                .font(.caption)
                .foregroundColor(.primary.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.orange.opacity(0.18), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Drill Prescription Panel

/// Unified container integrating target prescriptions (cadence/heart rate) and training load balance into a single sleek panel.
struct DrillPrescriptionPanel: View {
    let targetText: String?
    let targetExplainerTitle: String?
    let acwr: Double?
    let acuteLoad: Double
    let chronicWeeklyLoad: Double

    @State private var showingTargetExplainer = false
    @State private var showingReadinessMath = false

    init(
        targetText: String? = nil,
        targetExplainerTitle: String? = nil,
        acwr: Double?,
        acuteLoad: Double = 0,
        chronicWeeklyLoad: Double = 0
    ) {
        self.targetText = targetText
        self.targetExplainerTitle = targetExplainerTitle
        self.acwr = acwr
        self.acuteLoad = acuteLoad
        self.chronicWeeklyLoad = chronicWeeklyLoad
    }

    init(
        targetText: String? = nil,
        targetExplainerTitle: String? = nil,
        runRecords: [RunRecord]
    ) {
        let profile = MacroProfile.load()
        let readiness = ReadinessEvaluator.assess(runRecords: runRecords)
        self.targetText = targetText
        self.targetExplainerTitle = targetExplainerTitle
        self.acwr = profile?.acwr ?? readiness.acwr
        self.acuteLoad = profile?.acuteLoad ?? readiness.acuteLoad
        self.chronicWeeklyLoad = profile?.chronicWeeklyLoad ?? readiness.chronicWeeklyLoad
    }

    var body: some View {
        let status = TrainingLoadStatusBar.status(for: acwr)

        VStack(spacing: 8) {
            if let target = targetText, !target.isEmpty {
                Button {
                    if targetExplainerTitle != nil {
                        showingTargetExplainer = true
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "target")
                            .foregroundColor(.orange)
                            .font(.caption.weight(.bold))

                        Text(target)
                            .font(.caption.weight(.medium))
                            .foregroundColor(.primary.opacity(0.85))

                        Spacer()

                        if targetExplainerTitle != nil {
                            Image(systemName: "info.circle")
                                .font(.caption2)
                                .foregroundColor(.secondary.opacity(0.7))
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(targetExplainerTitle == nil)

                Divider()
                    .background(Color(UIColor.separator).opacity(0.4))
            }

            Button {
                showingReadinessMath = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "gauge.with.needle")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(status.color)

                    Text("Training Load:")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.secondary)

                    Text(status.displayText)
                        .font(.caption.bold())
                        .foregroundColor(status.color)

                    Spacer()

                    Image(systemName: "info.circle")
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.7))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(UIColor.tertiarySystemFill).opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(UIColor.separator).opacity(0.25), lineWidth: 1)
        )
        .sheet(isPresented: $showingTargetExplainer) {
            if let title = targetExplainerTitle {
                let explainer = MetricDetailExplainer.explainer(for: title, isWorkoutStats: false)
                MetricExplainerSheet(explainer: explainer, mode: "Working Stats")
            }
        }
        .sheet(isPresented: $showingReadinessMath) {
            ReadinessMathModal(
                acuteLoad: acuteLoad,
                chronicWeeklyLoad: chronicWeeklyLoad,
                acwr: acwr
            )
        }
    }
}

#Preview {
    ReadinessMathModal(
        acuteLoad: 35.0,
        chronicWeeklyLoad: 32.0,
        acwr: 1.09,
        targetAdjustmentNote: "Balanced acute-to-chronic training load."
    )
}
