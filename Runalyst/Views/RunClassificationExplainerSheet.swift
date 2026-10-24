import SwiftUI

/// Comprehensive modal explaining how Runalyst calculates and categorizes run classifications, rendering with unified GlassBox architecture.
struct RunClassificationExplainerSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        GlassBoxExplainerSheet(
            title: "Workout Classification",
            categoryBadge: "CoreML & Biometrics",
            whatSummary: "Runalyst analyzes your continuous minute-by-minute running data using on-device machine learning paired with physiological cardiac rules to identify what your body actually experienced.",
            whyItMatters: "Strict cardiac guardrails ensure that high-intensity or elevated heart rate sessions are never classified as easy or recovery, even if your pace was slow on hills or in the heat.",
            howItWorks: "Evaluates multi-signal telemetry across pace coefficient of variation (CV), pace slope regression, duration, and Zone 4 heart rate percentage with sub-20s pause trimming.",
            formula: "Pace CV = σ ÷ μ • Pace Slope = Linear Regression over Time",
            targetRange: "Easy: Zone 1–2 • Steady: CV < 6% • Tempo: Zone 3–4 • Intervals: Work Surges"
        )
    }
}

#Preview {
    RunClassificationExplainerSheet()
}
