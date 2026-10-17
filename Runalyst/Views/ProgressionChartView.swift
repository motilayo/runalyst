import SwiftUI
import Charts
import SwiftData

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

    private var latestMetricDisplay: String? {
        let matchingRuns = horizonRuns.filter { run in
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

    private var horizonRuns: [RunRecord] {
        let baseRuns: [RunRecord]
        if let days = selectedHorizon.days,
           let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) {
            baseRuns = allRuns.filter { $0.date >= cutoff }
        } else {
            baseRuns = allRuns
        }

        if selectedMetric == .efficiencyFactor {
            return baseRuns.filter { run in
                guard run.workingAvgHeartRate > 0, run.workingAvgPace > 0 else { return false }
                guard let ef = run.efficiencyFactor, ef > 0 else { return false }
                return true
            }
        } else {
            return baseRuns.filter { $0.workingAvgPace > 0 }
        }
    }

    /// Sorted unique run classifications by frequency in the selected horizon
    private var availableRunTypesSorted: [String] {
        var counts: [String: Int] = [:]
        for run in horizonRuns {
            let type = run.normalizedClassification
            counts[type, default: 0] += 1
        }
        return counts.sorted { $0.value > $1.value }.map(\.key)
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

    /// Generates segmented, daily-aggregated chart points for strictly the single active run type
    private var activeSegments: [ChartSegment] {
        guard let type = selectedRunType else { return [] }

        let runsOfType = horizonRuns
            .filter { $0.normalizedClassification == type }
            .sorted { $0.date < $1.date }

        guard !runsOfType.isEmpty else { return [] }

        // Group by calendar day to eliminate same-day vertical spikes
        var dailyRuns: [Date: [RunRecord]] = [:]
        for run in runsOfType {
            let day = Calendar.current.startOfDay(for: run.date)
            dailyRuns[day, default: []].append(run)
        }

        var dailyPoints: [ChartRunPoint] = []
        for (day, dayRuns) in dailyRuns {
            let totalDuration = dayRuns.map(\.duration).reduce(0, +)
            let value: Double
            let pace: Double
            let ef: Double?

            if totalDuration > 0 {
                pace = dayRuns.map { $0.workingAvgPace * $0.duration }.reduce(0, +) / totalDuration
                if selectedMetric == .efficiencyFactor {
                    let validEfs = dayRuns.compactMap { r -> (Double, Double)? in
                        guard let val = r.efficiencyFactor else { return nil }
                        return (val, r.duration)
                    }
                    let efDuration = validEfs.map(\.1).reduce(0, +)
                    value = efDuration > 0 ? (validEfs.map { $0.0 * $0.1 }.reduce(0, +) / efDuration) : 0
                    ef = value
                } else {
                    value = pace
                    let validEfs = dayRuns.compactMap(\.efficiencyFactor)
                    ef = validEfs.isEmpty ? nil : (validEfs.reduce(0, +) / Double(validEfs.count))
                }
            } else {
                pace = dayRuns.map(\.workingAvgPace).reduce(0, +) / Double(dayRuns.count)
                if selectedMetric == .efficiencyFactor {
                    let validEfs = dayRuns.compactMap(\.efficiencyFactor)
                    value = validEfs.isEmpty ? 0 : (validEfs.reduce(0, +) / Double(validEfs.count))
                    ef = value
                } else {
                    value = pace
                    let validEfs = dayRuns.compactMap(\.efficiencyFactor)
                    ef = validEfs.isEmpty ? nil : (validEfs.reduce(0, +) / Double(validEfs.count))
                }
            }

            guard value > 0 else { continue }
            let latestDateOnDay = dayRuns.map(\.date).max() ?? day

            dailyPoints.append(ChartRunPoint(
                id: "\(type)-\(day.timeIntervalSince1970)",
                date: latestDateOnDay,
                runType: type,
                value: value,
                pace: pace,
                efficiencyFactor: ef
            ))
        }

        dailyPoints.sort { $0.date < $1.date }

        // Segment across time gaps (> 45 days) to avoid sagging spline artifacts across inactive months
        var allSegments: [ChartSegment] = []
        var currentPoints: [ChartRunPoint] = []
        var segmentIdx = 0

        for point in dailyPoints {
            if let lastPoint = currentPoints.last {
                let daysApart = Calendar.current.dateComponents([.day], from: lastPoint.date, to: point.date).day ?? 0
                if daysApart > 45 {
                    if !currentPoints.isEmpty {
                        allSegments.append(ChartSegment(
                            id: "\(type)-seg-\(segmentIdx)",
                            runType: type,
                            points: currentPoints
                        ))
                        segmentIdx += 1
                        currentPoints = []
                    }
                }
            }
            currentPoints.append(point)
        }

        if !currentPoints.isEmpty {
            allSegments.append(ChartSegment(
                id: "\(type)-seg-\(segmentIdx)",
                runType: type,
                points: currentPoints
            ))
        }

        return allSegments
    }

    /// Dynamically scales the Y-axis to frame the single active run type with comfortable breathing room
    private var yDomain: ClosedRange<Double> {
        let allPoints = activeSegments.flatMap(\.points)
        if selectedMetric == .efficiencyFactor {
            let values = allPoints.map(\.value)
            guard let minVal = values.min(), let maxVal = values.max() else {
                return 0.70...1.20
            }
            let spread = maxVal - minVal
            if spread < 0.04 {
                let center = (minVal + maxVal) / 2.0
                return max(0.40, center - 0.12)...(center + 0.12)
            }
            let padding = max(0.04, spread * 0.18)
            return max(0.40, minVal - padding)...(maxVal + padding)
        } else {
            let values = allPoints.map(\.value)
            guard let minVal = values.min(), let maxVal = values.max() else {
                return 300.0...600.0
            }
            let spread = maxVal - minVal
            if spread < 10.0 {
                let center = (minVal + maxVal) / 2.0
                return max(180.0, center - 25.0)...(center + 25.0)
            }
            let padding = max(10.0, spread * 0.18)
            return max(180.0, minVal - padding)...(maxVal + padding)
        }
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
            // Header: Title & Metric Segmented Control
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .foregroundColor(.orange)
                            .font(.headline)
                        Text("Longitudinal Progression")
                            .font(.headline)
                            .foregroundColor(.primary)
                    }
                    Spacer()

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
                    .accessibilityLabel("Longitudinal Progression Explanation")
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

                // Time Horizon Picker
                Picker("Time Horizon", selection: $selectedHorizon) {
                    ForEach(availableHorizons) { horizon in
                        Text(horizon.rawValue).tag(horizon)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: selectedHorizon) {
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
                    AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                            .font(.caption2)
                    }
                }
                .chartXSelection(value: $selectedDate)
                .frame(height: 240)
                .animation(.easeInOut(duration: 0.3), value: selectedMetric)
                .animation(.easeInOut(duration: 0.3), value: selectedRunType)
            }

            // Descriptive Subtitle / Metric Context (Interactive Explainer Trigger)
            Button(action: {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showingInfo = true
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if selectedMetric == .efficiencyFactor {
                        Text("Efficiency Factor (Speed ÷ Heart Rate) tracks physiological economy for \(selectedRunType ?? "this workout type").")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.leading)
                    } else {
                        Text("Pace progression over time reveals pure speed adaptation for \(selectedRunType ?? "this workout type").")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.5))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Learn more about this metric")
        }
        .padding(16)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(18)
        .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
        .padding(.horizontal)
        .onAppear {
            syncDefaultSelectedRunType()
        }
        .sheet(isPresented: $showingInfo) {
            let contextType = selectedRunType ?? "Steady Effort"
            MetricExplainerSheet(
                title: selectedMetric == .efficiencyFactor ? "Efficiency Factor Progression" : "Pace Progression",
                mode: "\(contextType) • \(selectedHorizon.rawValue)",
                overview: selectedMetric == .efficiencyFactor
                    ? "Efficiency Factor (Speed ÷ Heart Rate) tracks physiological economy over time. By comparing how fast you run against the cardiovascular effort required, Runalyst shows whether your aerobic engine is becoming more efficient."
                    : "Pace progression tracks your speed development over time across identical workout classifications, showing true aerobic speed development independent of race-day surges.",
                modeContext: selectedMetric == .efficiencyFactor
                    ? "Isolated to \(contextType) runs across \(selectedHorizon.rawValue) to eliminate pacing noise and ensure authentic physiological comparisons."
                    : "Filtered strictly to \(contextType) runs across \(selectedHorizon.rawValue) using pause-trimmed Working Pace.",
                whyItMatters: selectedMetric == .efficiencyFactor
                    ? "Aerobic Economy: As aerobic endurance improves through base training, you run faster at the same heart rate, or maintain the same speed at a lower heart rate. A declining trend signals accumulated fatigue, dehydration, or heat stress."
                    : "Speed Development: Consistent, unforced speed gains at comfortable heart rates reflect genuine muscular and metabolic adaptation.",
                targetRange: selectedMetric == .efficiencyFactor
                    ? "Target: Upward or stable trajectory across training cycles.\n\n• Rising: You are getting fitter and faster with less cardiovascular effort.\n• Dropping: You may be tired, overtraining, or battling heat/dehydration."
                    : "Target: Steady, gradual progression over 6–12 week mesocycles without spiking cardiovascular strain.",
                userMetricDisplay: latestMetricDisplay
            )
        }
    }
}
