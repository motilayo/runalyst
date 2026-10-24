import SwiftUI

/// Standard bottom sheet modal explaining a running metric or data setting, rendering with unified GlassBox architecture.
struct MetricExplainerSheet: View {
    let title: String
    var mode: String?
    var overview: String
    var modeContext: String?
    var whyItMatters: String?
    var targetRange: String?
    var userMetricDisplay: String?

    init(title: String, definition: String, userMetricDisplay: String? = nil) {
        self.title = title
        self.mode = nil
        self.overview = definition
        self.modeContext = nil
        self.whyItMatters = nil
        self.targetRange = nil
        self.userMetricDisplay = userMetricDisplay
    }

    init(
        title: String,
        mode: String? = nil,
        overview: String,
        modeContext: String? = nil,
        whyItMatters: String? = nil,
        targetRange: String? = nil,
        userMetricDisplay: String? = nil
    ) {
        self.title = title
        self.mode = mode
        self.overview = overview
        self.modeContext = modeContext
        self.whyItMatters = whyItMatters
        self.targetRange = targetRange
        self.userMetricDisplay = userMetricDisplay
    }

    init(info: MetricExplainerInfo) {
        self.title = info.title
        self.mode = info.mode
        self.overview = info.overview
        self.modeContext = info.modeContext
        self.whyItMatters = info.whyItMatters
        self.targetRange = info.targetRange
        self.userMetricDisplay = info.userMetricDisplay
    }

    init(explainer: MetricDetailExplainer, mode: String? = nil, userMetricDisplay: String? = nil) {
        self.title = explainer.title
        self.mode = mode
        self.overview = explainer.overview
        self.modeContext = nil
        self.whyItMatters = explainer.whyItMatters
        self.targetRange = explainer.targetRange
        self.userMetricDisplay = userMetricDisplay
    }

    var body: some View {
        GlassBoxExplainerSheet(
            title: title,
            categoryBadge: mode ?? "Biometrics",
            whatSummary: overview,
            whyItMatters: whyItMatters ?? (modeContext ?? "Consistent metric tracking helps optimize mechanical efficiency and reduce injury risk."),
            howItWorks: modeContext ?? "Pause-trimmed telemetry calculated locally across working segments.",
            formula: nil,
            targetRange: targetRange,
            liveMetricDisplay: userMetricDisplay
        )
    }
}

#Preview {
    MetricExplainerSheet(
        title: "Vertical Oscillation",
        mode: "Form Dynamics",
        overview: "The vertical bounce of your center of mass during each running stride.",
        whyItMatters: "Excessive bounce (> 10 cm) directs energy vertically rather than horizontally.",
        targetRange: "6.0–9.0 cm",
        userMetricDisplay: "8.2 cm"
    )
}
