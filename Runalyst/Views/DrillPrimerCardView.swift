import SwiftData
import SwiftUI
import WorkoutKit

/// Metric cell payload for workout cards.
struct DrillCardMetric: Identifiable, Sendable {
    var id: String { title }
    let icon: String
    let title: String
    let value: String
    let color: Color
}

/// Configuration options for DrillPrimerCardView.
struct DrillCardConfig: Sendable {
    var customTitle: String?
    var customPurpose: String?
    var customTarget: String?
    var categoryLabel: String?
    var canChangeDuration: Bool
    var lockedDuration: DrillDuration?
    var customMetrics: [DrillCardMetric]?

    init(
        customTitle: String? = nil,
        customPurpose: String? = nil,
        customTarget: String? = nil,
        categoryLabel: String? = nil,
        canChangeDuration: Bool = true,
        lockedDuration: DrillDuration? = nil,
        customMetrics: [DrillCardMetric]? = nil
    ) {
        self.customTitle = customTitle
        self.customPurpose = customPurpose
        self.customTarget = customTarget
        self.categoryLabel = categoryLabel
        self.canChangeDuration = canChangeDuration
        self.lockedDuration = lockedDuration
        self.customMetrics = customMetrics
    }
}

/// Unified canonical workout card used across Drills & Runs Library and Workouts Session View.
struct DrillPrimerCardView: View {
    let drillId: PreRunDrillId
    let config: DrillCardConfig
    let baselineCadence: Int?
    var onPreview: (() -> Void)?
    var onStart: ((WorkoutPlan, DrillPrescriptionDTO) -> Void)?

    @State private var selectedDuration: DrillDuration
    @AppStorage("drillHapticFeedbackMode") private var selectedHapticModeRaw: String = HapticFeedbackMode.on.rawValue
    @AppStorage("preferredWorkoutIsIndoor") private var preferredWorkoutIsIndoor: Bool = false

    init(
        drillId: PreRunDrillId,
        config: DrillCardConfig,
        baselineCadence: Int? = nil,
        onPreview: (() -> Void)? = nil,
        onStart: ((WorkoutPlan, DrillPrescriptionDTO) -> Void)? = nil
    ) {
        self.drillId = drillId
        self.config = config
        self.baselineCadence = baselineCadence
        self.onPreview = onPreview
        self.onStart = onStart
        self._selectedDuration = State(initialValue: config.lockedDuration ?? drillId.defaultDuration)
    }

    init(
        drillId: PreRunDrillId,
        customTitle: String? = nil,
        customTarget: String? = nil,
        baselineCadence: Int? = nil,
        onStart: ((WorkoutPlan, DrillPrescriptionDTO) -> Void)? = nil
    ) {
        self.drillId = drillId
        self.config = DrillCardConfig(
            customTitle: customTitle,
            customTarget: customTarget,
            canChangeDuration: true
        )
        self.baselineCadence = baselineCadence
        self.onPreview = nil
        self.onStart = onStart
        self._selectedDuration = State(initialValue: drillId.defaultDuration)
    }

    private var selectedHapticMode: HapticFeedbackMode {
        get { HapticFeedbackMode(rawValue: selectedHapticModeRaw) ?? .on }
        nonmutating set { selectedHapticModeRaw = newValue.rawValue }
    }

    private var effectiveDuration: DrillDuration {
        if config.canChangeDuration {
            return selectedDuration
        }
        return config.lockedDuration ?? drillId.defaultDuration
    }

    var body: some View {
        let template = DrillTemplate.template(for: drillId)
        let displayTitle = config.customTitle ?? template.title
        let purpose = config.customPurpose ?? template.defaultPurpose
        let targetCadence: String? = baselineCadence.map { template.calculateTargetCadence($0) }
        let icon = drillId.iconName
        let iconColor = drillId.iconColor

        let isZone1 = drillId == .aerobicFlush || drillId == .recoveryJog
        let isZone2 = drillId == .zone2Run
        let hasCadenceTarget = !isZone1 && !isZone2

        let displayTargetText: String? = {
            if let customTarget = config.customTarget { return customTarget }
            if isZone1 { return "Zone 1 HR" }
            if isZone2 { return "Zone 2 HR" }
            if hasCadenceTarget {
                if let target = targetCadence {
                    return "\(target) SPM"
                } else {
                    return "Dynamic"
                }
            }
            return nil
        }()

        let previewDrill = PreRunDrill(
            id: drillId,
            previousCadence: baselineCadence,
            targetCadence: targetCadence,
            duration: effectiveDuration,
            hapticMode: selectedHapticMode,
            isIndoor: preferredWorkoutIsIndoor
        )
        let phases = previewDrill.generatePhases()
        let totalDuration = max(1, phases.reduce(0) { $0 + $1.durationSeconds })
        let categoryTitle = config.categoryLabel ?? (drillId.isHeartRateTargeted ? "AEROBIC RUN" : "TECHNIQUE DRILL")

        VStack(alignment: .leading, spacing: 10) {
            // Header Row: Icon badge + Category + Duration Capsule + Preview Button
            HStack(alignment: .center, spacing: 8) {
                HStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(iconColor.opacity(0.14))
                            .frame(width: 24, height: 24)
                        Image(systemName: icon)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(iconColor)
                    }

                    Text(categoryTitle)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(iconColor)

                    Text("•")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)

                    Text(effectiveDuration.title.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(iconColor)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(iconColor.opacity(0.12))
                        .clipShape(Capsule())
                }

                Spacer()

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    if let onPreview {
                        onPreview()
                    } else {
                        startDrill(title: displayTitle, purpose: purpose, targetCadence: targetCadence)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "applewatch")
                            .font(.system(size: 9, weight: .bold))
                        Text("Preview")
                            .font(.caption.bold())
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(Color(UIColor.secondarySystemFill))
                    .foregroundColor(.primary)
                    .clipShape(Capsule())
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
                .accessibilityLabel("Preview \(displayTitle) on Apple Watch")
            }

            // Title & Subtitle
            VStack(alignment: .leading, spacing: 2) {
                Text(displayTitle)
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Text(purpose)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }

            // Duration Selector (Omitted when duration is locked / prescribed)
            if config.canChangeDuration {
                Picker("Duration", selection: $selectedDuration) {
                    ForEach(drillId.supportedDurations, id: \.self) { dur in
                        Text(dur.title).tag(dur)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 2)
                .onChange(of: selectedDuration) { _, _ in
                    UISelectionFeedbackGenerator().selectionChanged()
                }
            }

            // 2x2 Metric Grid (matching Main Run Standard)
            if let customMetrics = config.customMetrics, !customMetrics.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(customMetrics) { metric in
                        drillMetricCell(
                            icon: metric.icon,
                            title: metric.title,
                            value: metric.value,
                            color: metric.color
                        )
                    }
                }
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    drillMetricCell(
                        icon: "stopwatch.fill",
                        title: "Duration",
                        value: effectiveDuration.title,
                        color: .secondary
                    )
                    drillMetricCell(
                        icon: drillId.isHeartRateTargeted ? "heart.fill" : "metronome.fill",
                        title: drillId.isHeartRateTargeted ? "Target HR" : "Cadence",
                        value: displayTargetText ?? "Dynamic",
                        color: drillId.isHeartRateTargeted ? Color(red: 1.0, green: 0.18, blue: 0.55) : Color(red: 0.0, green: 0.8, blue: 0.65)
                    )
                    drillMetricCell(
                        icon: "repeat",
                        title: "Intervals",
                        value: previewDrill.shortWorkSummary,
                        color: Color(red: 1.0, green: 0.58, blue: 0.0)
                    )
                    drillMetricCell(
                        icon: "figure.walk",
                        title: "Recovery",
                        value: previewDrill.shortRecoverySummary,
                        color: Color(red: 0.20, green: 0.72, blue: 0.92)
                    )
                }
            }

            // Treadmill Hint Footnote
            if preferredWorkoutIsIndoor {
                HStack(spacing: 5) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.purple)
                    Text(
                        drillId == .hillBounds
                        ? "Treadmill: Set 4–6% incline • Launches as Indoor Run on Watch"
                        : "Treadmill: Set 0.5–1.0% incline • Focus on HR & Cadence over wrist pace"
                    )
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 1)
            }

            // Sleek 4pt Phase Mini-Bar
            VStack(alignment: .leading, spacing: 4) {
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        ForEach(phases) { phase in
                            let ratio = CGFloat(phase.durationSeconds) / CGFloat(totalDuration)
                            let w = max(4, (geo.size.width - CGFloat(phases.count - 1) * 2) * ratio)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(phase.kind.color)
                                .frame(width: w, height: 4)
                        }
                    }
                }
                .frame(height: 4)

                Text(previewDrill.structureSummary)
                    .font(.system(size: 10, weight: .medium))
                    .monospacedDigit()
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.top, 2)
        }
        .liquidGlass(cornerRadius: 16, padding: 14, accentColor: iconColor)
    }

    private func drillMetricCell(icon: String, title: String, value: String, color: Color) -> some View {
        MiniStatTile(
            title: title,
            value: value,
            unit: nil,
            icon: icon,
            accentColor: color
        )
    }

    private func startDrill(title: String, purpose: String, targetCadence: String?) {
        let drill = PreRunDrill(
            id: drillId,
            previousCadence: baselineCadence,
            targetCadence: targetCadence,
            duration: effectiveDuration,
            hapticMode: selectedHapticMode,
            isIndoor: preferredWorkoutIsIndoor
        )
        let plan = drill.buildWorkoutPlan()
        let dto = DrillPrescriptionDTO(
            title: title,
            preRunDrillId: drillId.rawValue,
            purpose: purpose,
            targetCadence: targetCadence,
            previousCadence: baselineCadence,
            durationMinutes: effectiveDuration.rawValue,
            hapticMode: selectedHapticMode.rawValue,
            isIndoor: preferredWorkoutIsIndoor
        )
        onStart?(plan, dto)
    }
}
