import SwiftUI
import Charts
import SwiftData
import RunalystCore

enum ProgressionMetric: String, CaseIterable, Identifiable {
    case efficiencyFactor = "Efficiency Factor"
    case pace = "Average Pace"

    var id: String { rawValue }

    var shortTitle: String {
        switch self {
        case .efficiencyFactor: return "Eff. Factor (Speed ÷ HR)"
        case .pace: return "Average Pace"
        }
    }

    var coreMetric: ProgressionMetricCore {
        switch self {
        case .efficiencyFactor: return .efficiencyFactor
        case .pace: return .pace
        }
    }
}

enum ChartTimeHorizon: String, CaseIterable, Identifiable {
    case thirtyDays = "30 Days"
    case sixMonths = "6 Months"
    case oneYear = "1 Year"
    case allTime = "All Time"

    var id: String { rawValue }

    var days: Int? {
        switch self {
        case .thirtyDays: return 30
        case .sixMonths: return 180
        case .oneYear: return 365
        case .allTime: return nil
        }
    }
}

struct ChartRunPoint: Identifiable {
    let id: String
    let date: Date
    let runType: String
    let value: Double
    let pace: Double
    let efficiencyFactor: Double?
}

struct ChartSegment: Identifiable {
    let id: String
    let runType: String
    let points: [ChartRunPoint]
}

struct ProgressionChartView: View {
    var allRuns: [RunRecord]

    @AppStorage("useMetricSystem") private var useMetricSystem: Bool = Locale.current.measurementSystem == .metric
    @State private var selectedMetric: ProgressionMetric = .efficiencyFactor
    @State private var selectedHorizon: ChartTimeHorizon
    @State private var selectedRunType: String?
    @State private var selectedDate: Date?
    @State private var showingInfo = false

    private var chartInputs: [ChartRunInputCore] {
        allRuns.filter { !$0.isDeleted }.map { $0.toChartRunInputCore() }
    }

    private var latestMetricDisplay: String? {
        let matchingRuns = allRuns.filter { run in
            guard !run.isDeleted else { return false }
            if let days = selectedHorizon.days, let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()), run.date < cutoff {
                return false
            }
            if let selType = selectedRunType {
                return run.normalizedClassification == selType
            }
            return true
        }
        guard let latestRun = matchingRuns.sorted(by: { $0.date > $1.date }).first else {
            return nil
        }
        if selectedMetric == .efficiencyFactor, let ef = latestRun.efficiencyFactor, ef > 0 {
            return String(format: "%.2f EF", ef)
        } else if selectedMetric == .pace, latestRun.workingAvgPace > 0 {
            return PaceFormatter.formatPace(secondsPerKilometer: latestRun.workingAvgPace)
        }
        return nil
    }

    private let defaultHorizon: ChartTimeHorizon

    init(allRuns: [RunRecord], defaultHorizon: ChartTimeHorizon = .thirtyDays) {
        self.allRuns = allRuns
        self.defaultHorizon = defaultHorizon
        self._selectedHorizon = State(initialValue: defaultHorizon)
    }

    private var availableHorizons: [ChartTimeHorizon] {
        if defaultHorizon == .allTime {
            return [.sixMonths, .oneYear, .allTime]
        }
        return ChartTimeHorizon.allCases
    }

    /// Sorted unique run classifications by frequency in the selected horizon (evaluated via Core SSOT)
    private var availableRunTypesSorted: [String] {
        ProgressionChartCore.availableRunTypesSorted(
            runs: chartInputs,
            metric: selectedMetric.coreMetric,
            horizonDays: selectedHorizon.days,
            now: Date()
        )
    }

    /// Color mapping for canonical run classifications
    private func colorForRunType(_ type: String) -> Color {
        switch type {
        case "Easy Run": return Color.teal
        case "Steady Effort": return Color(red: 0.15, green: 0.55, blue: 0.95)
        case "Tempo Run": return Color.orange
        case "Intervals": return Color.purple
        case "Long Run": return Color.indigo
        case "Progression Run": return Color.green
        case "Recovery Run": return Color(red: 0.2, green: 0.8, blue: 0.6)
        case "Hill Repeats": return Color.red
        case "Fartlek": return Color.pink
        default: return Color.yellow
        }
    }

    private var coreSegments: [ChartSegmentCore] {
        guard let type = selectedRunType else { return [] }
        return ProgressionChartCore.evaluateSegments(
            runs: chartInputs,
            selectedType: type,
            metric: selectedMetric.coreMetric,
            horizonDays: selectedHorizon.days,
            now: Date()
        )
    }

    /// Generates segmented, daily-aggregated chart points for strictly the single active run type
    private var activeSegments: [ChartSegment] {
        coreSegments.map { segment in
            ChartSegment(
                id: segment.id,
                runType: segment.runType,
                points: segment.points.map { pt in
                    ChartRunPoint(
                        id: pt.id,
                        date: pt.date,
                        runType: pt.runType,
                        value: pt.value,
                        pace: pt.pace,
                        efficiencyFactor: pt.efficiencyFactor
                    )
                }
            )
        }
    }

    /// Dynamically scales the Y-axis via pure Core SSOT math
    private var yDomain: ClosedRange<Double> {
        let domain = ProgressionChartCore.calculateYDomain(
            segments: coreSegments,
            metric: selectedMetric.coreMetric
        )
        return domain.lower...domain.upper
    }

    /// Closest run to selected scrubber date
    private var highlightedPoint: ChartRunPoint? {
        guard let selDate = selectedDate else { return nil }
        let allPoints = activeSegments.flatMap(\.points)
        return allPoints.min(by: { abs($0.date.timeIntervalSince(selDate)) < abs($1.date.timeIntervalSince(selDate)) })
    }

    private func syncDefaultSelectedRunType() {
        let types = availableRunTypesSorted
        guard !types.isEmpty else {
            selectedRunType = nil
            return
        }

        if let current = selectedRunType, types.contains(current) {
            return
        }
        selectedRunType = types.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header: Title, Time Horizon Dropdown Menu, and Info Button
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .foregroundColor(.orange)
                            .font(.headline)
                        Text("Performance Trends")
                            .font(.headline)
                            .foregroundColor(.primary)
                    }
                    Spacer()

                    HStack(spacing: 6) {
                        // Time Horizon Menu (Apple Health Style dropdown eliminating stacked controls)
                        Menu {
                            Picker("Time Horizon", selection: $selectedHorizon) {
                                ForEach(availableHorizons) { horizon in
                                    Text(horizon.rawValue).tag(horizon)
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(selectedHorizon.rawValue)
                                    .font(.system(size: 12, weight: .semibold))
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 9, weight: .bold))
                            }
                            .foregroundColor(.primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color(UIColor.tertiarySystemFill))
                            .clipShape(Capsule())
                        }
                        .onChange(of: selectedHorizon) {
                            syncDefaultSelectedRunType()
                        }

                        Button(action: {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            showingInfo = true
                        }) {
                            Image(systemName: "info.circle")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Performance Trends Explanation")
                    }
                }

                // Full-width metric selector
                Picker("Metric", selection: $selectedMetric) {
                    Text("Efficiency Factor").tag(ProgressionMetric.efficiencyFactor)
                    Text("Average Pace").tag(ProgressionMetric.pace)
                }
                .pickerStyle(.segmented)
                .onChange(of: selectedMetric) {
                    syncDefaultSelectedRunType()
                }
            }

            // Single-Select Run Type Chips (Only 1 graphed at a time)
            if !availableRunTypesSorted.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(availableRunTypesSorted, id: \.self) { type in
                            let isSelected = selectedRunType == type
                            let typeColor = colorForRunType(type)

                            Button(action: {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    selectedRunType = type
                                }
                            }) {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(isSelected ? .white : typeColor)
                                        .frame(width: 8, height: 8)
                                    Text(type)
                                        .font(.caption.bold())
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(isSelected ? typeColor : Color(UIColor.tertiarySystemFill))
                                .foregroundColor(isSelected ? .white : .primary)
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(isSelected ? Color.white.opacity(0.3) : typeColor.opacity(0.3), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            // Highlighted Scrubber Tooltip
            if let point = highlightedPoint {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(colorForRunType(point.runType))
                                .frame(width: 8, height: 8)
                            Text(point.runType)
                                .font(.caption.bold())
                                .foregroundColor(.primary)
                        }
                        Text(point.date, style: .date)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        if selectedMetric == .efficiencyFactor {
                            Text(String(format: "%.2f m/beat", point.value))
                                .font(.subheadline.bold())
                                .foregroundColor(colorForRunType(point.runType))
                            Text("Pace: \(PaceFormatter.formatPace(secondsPerKilometer: point.pace))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        } else {
                            Text(PaceFormatter.formatPace(secondsPerKilometer: point.value))
                                .font(.subheadline.bold())
                                .foregroundColor(colorForRunType(point.runType))
                            if let ef = point.efficiencyFactor {
                                Text(String(format: "EF: %.2f m/beat", ef))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .padding(10)
                .background(Color(UIColor.tertiarySystemFill))
                .cornerRadius(10)
                .transition(.opacity)
            }

            // Apple Chart
            if activeSegments.isEmpty || activeSegments.allSatisfy({ $0.points.isEmpty }) {
                VStack(spacing: 8) {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.largeTitle)
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("No runs with \(selectedMetric == .efficiencyFactor ? "heart rate" : "valid pace") recorded for the selected workout type.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                Chart {
                    ForEach(activeSegments) { segment in
                        let color = colorForRunType(segment.runType)

                        // Smooth gradient area fill under the line
                        if segment.points.count >= 2 {
                            ForEach(segment.points) { point in
                                AreaMark(
                                    x: .value("Date", point.date),
                                    yStart: .value("Baseline", yDomain.lowerBound),
                                    yEnd: .value(selectedMetric.rawValue, point.value)
                                )
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [color.opacity(0.18), color.opacity(0.01)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .interpolationMethod(.monotone)
                            }

                            // Smooth trajectory line
                            ForEach(segment.points) { point in
                                LineMark(
                                    x: .value("Date", point.date),
                                    y: .value(selectedMetric.rawValue, point.value)
                                )
                                .foregroundStyle(color)
                                .lineStyle(StrokeStyle(lineWidth: 3.0, lineCap: .round, lineJoin: .round))
                                .interpolationMethod(.monotone)
                            }
                        }

                        // Workout PointMarks directly on the line
                        ForEach(segment.points) { point in
                            PointMark(
                                x: .value("Date", point.date),
                                y: .value(selectedMetric.rawValue, point.value)
                            )
                            .foregroundStyle(color)
                            .symbolSize(42)
                        }
                    }

                    // Scrubber line
                    if let sel = highlightedPoint {
                        RuleMark(x: .value("Selected", sel.date))
                            .foregroundStyle(Color.secondary.opacity(0.5))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                    }
                }
                .chartYScale(domain: yDomain)
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                        AxisValueLabel(anchor: .trailing) {
                            if selectedMetric == .efficiencyFactor {
                                if let val = value.as(Double.self) {
                                    Text(String(format: "%.2f", val))
                                        .font(.caption2)
                                }
                            } else {
                                if let paceSecs = value.as(Double.self) {
                                    let minutes = Int(paceSecs) / 60
                                    let seconds = Int(paceSecs) % 60
                                    Text(String(format: "%d:%02d", minutes, seconds))
                                        .font(.caption2)
                                }
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel(anchor: .top) {
                            if let date = value.as(Date.self) {
                                if selectedHorizon == .thirtyDays {
                                    Text(date.formatted(.dateTime.month(.abbreviated).day()))
                                        .font(.system(size: 10, weight: .semibold))
                                        .monospacedDigit()
                                } else {
                                    Text(date.formatted(.dateTime.month(.abbreviated)))
                                        .font(.system(size: 10, weight: .semibold))
                                }
                            }
                        }
                    }
                }
                .chartXSelection(value: $selectedDate)
                .frame(height: 240)
                .animation(.easeInOut(duration: 0.3), value: selectedMetric)
                .animation(.easeInOut(duration: 0.3), value: selectedRunType)
            }
        }
        .liquidGlass(
            cornerRadius: 16,
            padding: 16,
            accentColor: selectedMetric == .efficiencyFactor ? Color.purple : Color.blue
        )
        .padding(.horizontal)
        .onAppear {
            syncDefaultSelectedRunType()
        }
        .sheet(isPresented: $showingInfo) {
            let contextType = selectedRunType ?? "Steady Effort"
            if selectedMetric == .efficiencyFactor {
                GlassBoxExplainerSheet(
                    title: "Efficiency Factor Progression",
                    categoryBadge: "\(contextType) • \(selectedHorizon.rawValue)",
                    whatSummary: "Efficiency Factor tracks your aerobic work-to-effort ratio. It measures how much speed you produce for each heartbeat.",
                    whyItMatters: "Aerobic Economy & Stroke Volume: As endurance develops, your left ventricle pumps more oxygenated blood per beat (stroke volume). A rising line means you are running faster at lower heart rates.",
                    howItWorks: "Calculated strictly across pause-trimmed Working Pace and continuous heart rate data.",
                    formula: "Efficiency Factor = Speed (m/s) ÷ (Avg HR - Resting HR)",
                    targetRange: "Target: Upward or stable trajectory across 4–12 week mesocycles.",
                    liveMetricDisplay: latestMetricDisplay
                )
            } else {
                GlassBoxExplainerSheet(
                    title: "Pace Progression",
                    categoryBadge: "\(contextType) • \(selectedHorizon.rawValue)",
                    whatSummary: "Pace progression tracks aerobic velocity development across identical workout classifications over time.",
                    whyItMatters: "Aerobic Speed: Consistent speed gains at comfortable heart rates reflect muscular economy and metabolic efficiency.",
                    howItWorks: "Filtered strictly to \(contextType) runs across \(selectedHorizon.rawValue) using pause-trimmed Working Pace.",
                    formula: "Working Pace = Pause-Trimmed Time ÷ Distance",
                    targetRange: "Target: Steady, gradual progression without spiking cardiovascular strain.",
                    liveMetricDisplay: latestMetricDisplay
                )
            }
        }
    }
}
