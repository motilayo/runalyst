import Foundation

/// Structured metric explainer providing consistent format across Working and Workout stats.
public struct MetricDetailExplainer: Sendable {
    public let title: String
    public let overview: String
    public let modeContext: String
    public let whyItMatters: String
    public let targetRange: String

    public init(
        title: String,
        overview: String,
        modeContext: String,
        whyItMatters: String,
        targetRange: String
    ) {
        self.title = title
        self.overview = overview
        self.modeContext = modeContext
        self.whyItMatters = whyItMatters
        self.targetRange = targetRange
    }

    public static func explainer(for title: String, isWorkoutStats: Bool) -> MetricDetailExplainer {
        CoachingAssetLibrary.explainer(for: title, isWorkoutStats: isWorkoutStats)
    }
}

/// Identifiable model for presentation in a metric explainer bottom sheet.
public struct MetricExplainerInfo: Identifiable, Sendable {
    public var id: String { title + (mode ?? "") }
    public let title: String
    public var mode: String?
    public let overview: String
    public var modeContext: String?
    public var whyItMatters: String?
    public var targetRange: String?
    public var userMetricDisplay: String?

    public init(title: String, definition: String, userMetricDisplay: String? = nil) {
        self.title = title
        self.mode = nil
        self.overview = definition
        self.modeContext = nil
        self.whyItMatters = nil
        self.targetRange = nil
        self.userMetricDisplay = userMetricDisplay
    }

    public init(
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

    public init(explainer: MetricDetailExplainer, mode: String? = nil, userMetricDisplay: String? = nil) {
        self.title = explainer.title
        self.mode = mode
        self.overview = explainer.overview
        self.modeContext = explainer.modeContext
        self.whyItMatters = explainer.whyItMatters
        self.targetRange = explainer.targetRange
        self.userMetricDisplay = userMetricDisplay
    }
}
