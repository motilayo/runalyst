import SwiftUI

/// Standard bottom sheet modal explaining a running metric or data setting.
struct MetricExplainerSheet: View {
    let title: String
    var mode: String?
    var overview: String
    var modeContext: String?
    var whyItMatters: String?
    var targetRange: String?
    @Environment(\.dismiss) private var dismiss
    @State private var showingBiomechanicsModal = false

    private var isBiomechanicsMetric: Bool {
        let lower = title.lowercased()
        return lower.contains("osc") || lower.contains("vertical") || lower.contains("stride") || lower.contains("bounce")
    }

    init(title: String, definition: String) {
        self.title = title
        self.mode = nil
        self.overview = definition
        self.modeContext = nil
        self.whyItMatters = nil
        self.targetRange = nil
    }

    init(
        title: String,
        mode: String? = nil,
        overview: String,
        modeContext: String? = nil,
        whyItMatters: String? = nil,
        targetRange: String? = nil
    ) {
        self.title = title
        self.mode = mode
        self.overview = overview
        self.modeContext = modeContext
        self.whyItMatters = whyItMatters
        self.targetRange = targetRange
    }

    init(info: MetricExplainerInfo) {
        self.title = info.title
        self.mode = info.mode
        self.overview = info.overview
        self.modeContext = info.modeContext
        self.whyItMatters = info.whyItMatters
        self.targetRange = info.targetRange
    }

    init(explainer: MetricDetailExplainer, mode: String? = nil) {
        self.title = explainer.title
        self.mode = mode
        self.overview = explainer.overview
        self.modeContext = explainer.modeContext
        self.whyItMatters = explainer.whyItMatters
        self.targetRange = explainer.targetRange
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.title3.bold())
                            .foregroundColor(.primary)
                        if let mode = mode, !mode.isEmpty {
                            let isWorkout = mode.localizedCaseInsensitiveContains("workout")
                            Text(mode)
                                .font(.caption.bold())
                                .foregroundColor(isWorkout ? .orange : .teal)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background((isWorkout ? Color.orange : Color.teal).opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.secondary.opacity(0.6))
                    }
                }

                // Overview
                Text(overview)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .lineSpacing(2)

                // Mode Context
                if let context = modeContext, !context.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(mode == "Working Stats" ? "Working Stats Context" : (mode == "Workout Stats" ? "Workout Stats Context" : "Context"))
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)
                        Text(context)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(UIColor.tertiarySystemFill))
                    .cornerRadius(10)
                }

                // Running Form & Biomechanics Guide (Progressive Disclosure)
                if isBiomechanicsMetric {
                    Button(action: { showingBiomechanicsModal = true }) {
                        HStack(spacing: 12) {
                            Image(systemName: "figure.run")
                                .font(.subheadline.bold())
                                .foregroundColor(.accentColor)
                                .frame(width: 32, height: 32)
                                .background(Color.accentColor.opacity(0.12))
                                .clipShape(Circle())

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Running Form & Overstriding Guide")
                                    .font(.subheadline.bold())
                                    .foregroundColor(.primary)
                                Text("See how foot landing affects bounce, cadence, and efficiency.")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption2.bold())
                                .foregroundColor(.secondary)
                        }
                        .padding(12)
                        .background(Color(UIColor.secondarySystemFill))
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                    .sheet(isPresented: $showingBiomechanicsModal) {
                        OverstrideBiomechanicsSheet()
                    }
                }

                // Why It Matters
                if let why = whyItMatters, !why.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Why It Matters")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)
                        Text(why)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineSpacing(2)
                    }
                }

                // Target Range
                if let target = targetRange, !target.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Target Range")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)
                        Text(target)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineSpacing(2)
                    }
                }
            }
            .padding(20)
        }
        .presentationDetents(isBiomechanicsMetric ? [.fraction(0.58), .medium, .large] : [.fraction(0.52), .medium, .large])
        .presentationDragIndicator(.visible)
    }
}
