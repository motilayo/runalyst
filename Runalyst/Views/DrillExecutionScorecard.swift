import SwiftUI

enum DrillAdherenceTier {
    case exceeded
    case met
    case partiallyMet
    case notMet

    var badgeText: String {
        switch self {
        case .exceeded: return "Exceeded"
        case .met: return "Met"
        case .partiallyMet: return "Partially Met"
        case .notMet: return "Not Met"
        }
    }

    func badgeText(for drillId: PreRunDrillId) -> String {
        if drillId.isHeartRateTargeted {
            switch self {
            case .exceeded: return "Optimal"
            case .met: return "Target Met"
            case .partiallyMet: return "Partially Met"
            case .notMet: return "Not Met"
            }
        }
        return badgeText
    }

    var badgeIcon: String {
        switch self {
        case .exceeded: return "star.fill"
        case .met: return "checkmark"
        case .partiallyMet: return "minus"
        case .notMet: return "xmark"
        }
    }

    func badgeIcon(for drillId: PreRunDrillId) -> String {
        if drillId.isHeartRateTargeted {
            switch self {
            case .exceeded: return "checkmark.seal.fill"
            case .met: return "checkmark"
            case .partiallyMet: return "minus"
            case .notMet: return "xmark"
            }
        }
        return badgeIcon
    }

    var tintColor: Color {
        switch self {
        case .exceeded: return Color(red: 0.0, green: 0.75, blue: 0.65)
        case .met: return .green
        case .partiallyMet: return .orange
        case .notMet: return .red
        }
    }
}

struct DrillDisplayRep: Identifiable, Sendable {
    var id: Int { repIndex }
    let repIndex: Int
    let durationSeconds: Double?
    let isFastest: Bool
    let workPaceFormatted: String?
    let workCadence: Int
    let workHeartRate: Int
    let recoveryPaceFormatted: String?
    let recoveryCadence: Int
    let recoveryHeartRate: Int
    let recoveryHeartRateDrop: Int?
    let paceDeltaVsAverageWorkSec: Int?
    let isMet: Bool
    let observation: String?
}

struct DrillExecutionScorecard: View {
    let runRecord: RunRecord
    let drillId: PreRunDrillId
    let baselineCadence: Double?
    let baselineOscillation: Double?
    var customTitle: String?
    var customSubtitle: String?

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var isSetsExpanded: Bool = false
    @State private var expandedRepIndices: Set<Int> = []

    var body: some View {
        let calc = DrillExecutionScorecard.calculateAdherence(
            runRecord: runRecord,
            drillId: drillId,
            baselineCadence: baselineCadence,
            baselineOscillation: baselineOscillation
        )
        let tier = calc.tier
        let tierDescription = calc.tierDescription
        let displayReps = calc.displayReps
        let isIntervalDrill = calc.isIntervalDrill
        let targetCadenceStr = calc.targetCadenceStr
        let actualCadence = calc.actualCadence
        let actualHR = calc.actualHR
        let thirtyDayCadence = calc.thirtyDayCadence
        let oscDelta = calc.oscDelta
        let isHRTarget = calc.isHRTarget
        let isDualTarget = calc.isDualTarget
        let drillObj = calc.drillObj
        let intervalSummary = calc.intervalSummary

        return VStack(spacing: 14) {
            // Header: Icon + Title/Subtitle + Capsule Badge
            HStack(spacing: 8) {
                Image(systemName: drillId.iconName)
                    .foregroundColor(drillId.iconColor)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    Text(customTitle ?? (runRecord.prescribedDrillName != nil ? drillId.title : "Workout Performance"))
                        .font(.headline.weight(.semibold))
                        .foregroundColor(.primary)

                    if let subtitle = customSubtitle {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: tier.badgeIcon(for: drillId))
                        .font(.caption2.bold())
                    Text(tier.badgeText(for: drillId))
                        .font(.caption.bold())
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(tier.tintColor.opacity(0.12))
                .foregroundColor(tier.tintColor)
                .clipShape(Capsule())
            }

            // Interval Adherence Meter (Pips + Fraction)
            if isIntervalDrill, !displayReps.isEmpty {
                let metCount = calc.metCount
                let totalCount = calc.totalCount
                let percent = totalCount > 0 ? Int(round(Double(metCount) / Double(totalCount) * 100.0)) : 0

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Interval Adherence")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(metCount) of \(totalCount) on Target (\(percent)%)")
                            .font(.caption.bold())
                            .foregroundColor(tier.tintColor)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }

                    // Pips (R1, R2, ...)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(displayReps) { rep in
                                HStack(spacing: 3) {
                                    Image(systemName: rep.isMet ? "checkmark.circle.fill" : "circle")
                                        .font(.caption2)
                                        .foregroundColor(rep.isMet ? .green : .orange)
                                    Text("R\(rep.repIndex)")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(rep.isMet ? .primary : .secondary)
                                }
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(rep.isMet ? Color.green.opacity(0.12) : Color.orange.opacity(0.12))
                                .clipShape(Capsule())
                            }
                        }
                        .padding(.horizontal, 1)
                    }
                    .mask(
                        HStack(spacing: 0) {
                            Rectangle().fill(Color.black)
                            if displayReps.count > 6 {
                                LinearGradient(
                                    colors: [Color.black, Color.clear],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                                .frame(width: 18)
                            }
                        }
                    )
                }
                .padding(10)
                .background(Color(UIColor.tertiarySystemGroupedBackground))
                .cornerRadius(10)
            }

            // Secondary Form Availability
            let hasFormDelta = abs(oscDelta) > 0.01 && runRecord.workingAvgVerticalOscillation != nil

            // Primary Target vs Actual Metric Tiles
            if isIntervalDrill, !displayReps.isEmpty {
                let avgWorkCadence: Int = {
                    if let summary = intervalSummary, summary.workCadenceAvg > 0 { return summary.workCadenceAvg }
                    let valid = displayReps.map(\.workCadence).filter { $0 > 0 }
                    return valid.isEmpty ? actualCadence : (valid.reduce(0, +) / valid.count)
                }()
                let avgRecCadence: Int = {
                    if let summary = intervalSummary, summary.recoveryCadenceAvg > 0 { return summary.recoveryCadenceAvg }
                    let valid = displayReps.map(\.recoveryCadence).filter { $0 > 0 }
                    return valid.isEmpty ? max(130, actualCadence - 20) : (valid.reduce(0, +) / valid.count)
                }()

                let workCadenceTargetMet: Bool = {
                    if let range = drillObj.effectiveTargetCadence {
                        return avgWorkCadence >= (range.lowerBound - 2) &&
                            (drillId == .strides || drillId == .tempoSurges ? avgWorkCadence <= 195 : avgWorkCadence <= range.upperBound + 8)
                    }
                    return avgWorkCadence >= thirtyDayCadence
                }()
                let workColor: Color = workCadenceTargetMet ? .green : (tier == .notMet ? .red : .orange)

                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        metricTile(
                            label: "WORK CADENCE",
                            value: "\(avgWorkCadence) SPM",
                            valueColor: workColor,
                            subtitle: "Target: \(targetCadenceStr) SPM"
                        )
                        metricTile(
                            label: "REC CADENCE",
                            value: "\(avgRecCadence) SPM",
                            valueColor: .secondary,
                            subtitle: drillId.recoveryLabel
                        )
                        if hasFormDelta {
                            metricTile(
                                label: "FORM DELTA",
                                value: String(format: "%+.1f cm", oscDelta),
                                valueColor: oscDelta <= 0 ? Color(red: 0.0, green: 0.75, blue: 0.65) : .orange,
                                subtitle: oscDelta <= 0 ? "Controlled" : "Elevated bounce"
                            )
                        }
                    }

                    if isDualTarget {
                        HStack(spacing: 10) {
                            metricTile(
                                label: "THRESHOLD GOAL",
                                value: "≥20% Zone 4",
                                valueColor: .primary
                            )
                            metricTile(
                                label: "ZONE 4 TIME",
                                value: String(format: "%.0f%%", runRecord.percentZone4 * 100),
                                valueColor: runRecord.percentZone4 >= 0.20 ? .green : (runRecord.percentZone4 >= 0.15 ? .orange : .red)
                            )
                        }
                    }
                }
            } else if isDualTarget {
                // Dual Target (Cadence + Zone 4 Threshold)
                VStack(spacing: 8) {
                    HStack(spacing: 10) {
                        metricTile(
                            label: "TARGET CADENCE",
                            value: "\(targetCadenceStr) SPM",
                            valueColor: .primary
                        )
                        metricTile(
                            label: "ACTUAL CADENCE",
                            value: "\(actualCadence) SPM",
                            valueColor: tier == .notMet ? .red : (tier == .partiallyMet ? .orange : .green)
                        )
                    }

                    HStack(spacing: 10) {
                        metricTile(
                            label: "THRESHOLD GOAL",
                            value: "≥20% Zone 4",
                            valueColor: .primary
                        )
                        metricTile(
                            label: "ZONE 4 TIME",
                            value: String(format: "%.0f%%", runRecord.percentZone4 * 100),
                            valueColor: runRecord.percentZone4 >= 0.20 ? .green : .orange
                        )
                    }
                }
            } else if isHRTarget {
                // Heart Rate Hero Metric (Target Zone, Actual HR, Turnover)
                HStack(spacing: 8) {
                    metricTile(
                        label: "TARGET ZONE",
                        value: drillId.targetHeartRateZoneName ?? "Zone 1",
                        valueColor: .primary,
                        subtitle: "Active Recovery"
                    )
                    metricTile(
                        label: "ACTUAL HEART RATE",
                        value: actualHR > 0 ? "\(actualHR) BPM" : "--",
                        valueColor: Color(red: 1.0, green: 0.22, blue: 0.55),
                        subtitle: actualHR <= 135 ? "Zero cardiac strain" : "Elevated strain"
                    )
                    metricTile(
                        label: "TURNOVER",
                        value: actualCadence > 0 ? "\(actualCadence) SPM" : "--",
                        valueColor: Color(red: 0.0, green: 0.75, blue: 0.65),
                        subtitle: "Relaxed cadence"
                    )
                }
            } else {
                // Cadence Hero Metric
                HStack(spacing: 8) {
                    metricTile(
                        label: "TARGET CADENCE",
                        value: "\(targetCadenceStr) SPM",
                        valueColor: .primary
                    )
                    metricTile(
                        label: "ACTUAL CADENCE",
                        value: "\(actualCadence) SPM",
                        valueColor: tier == .notMet ? .red : (tier == .partiallyMet ? .orange : .green)
                    )
                    if hasFormDelta {
                        metricTile(
                            label: "FORM DELTA",
                            value: String(format: "%+.1f cm", oscDelta),
                            valueColor: oscDelta <= 0 ? Color(red: 0.0, green: 0.75, blue: 0.65) : .orange,
                            subtitle: oscDelta <= 0 ? "Controlled" : "Elevated bounce"
                        )
                    }
                }
            }

            // High threshold guardrail chip (if unexpected Zone 4 spike)
            if !isDualTarget && runRecord.percentZone4 > 0.15 {
                HStack(spacing: 4) {
                    Image(systemName: "bolt.fill")
                        .font(.caption2)
                    Text(String(format: "Zone 4 Spike: %.0f%% (elevated threshold effort)", runRecord.percentZone4 * 100))
                        .font(.caption2.bold())
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.12))
                .foregroundColor(.orange)
                .clipShape(Capsule())
            }

            // Coaching Verdict Callout Banner
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: tier == .notMet ? "xmark.circle.fill" : (tier == .partiallyMet ? "info.circle.fill" : "checkmark.seal.fill"))
                    .font(.caption)
                    .foregroundColor(tier.tintColor)
                    .padding(.top, 1)
                Text(tierDescription)
                    .font(.caption)
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
            .padding(10)
            .background(tier.tintColor.opacity(0.08))
            .cornerRadius(8)

            // Expandable Rep-by-Rep Breakdown (SETS)
            if isIntervalDrill, !displayReps.isEmpty {
                Divider()

                HStack {
                    Text("SETS (\(displayReps.count))")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)

                    Spacer()

                    if displayReps.count > 3 {
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                isSetsExpanded.toggle()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(isSetsExpanded ? "Show Less" : "Show All (\(displayReps.count))")
                                    .font(.caption.bold())
                                Image(systemName: isSetsExpanded ? "chevron.up" : "chevron.down")
                                    .font(.caption2.bold())
                            }
                            .foregroundColor(drillId.iconColor)
                        }
                    }
                }

                let displayedReps = isSetsExpanded ? displayReps : Array(displayReps.prefix(3))
                VStack(spacing: 8) {
                    ForEach(displayedReps) { rep in
                        drillRepRow(rep, targetRange: drillObj.effectiveTargetCadence)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(drillId.iconColor.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.03), radius: 5, x: 0, y: 2)
        .onAppear {
            if ProcessInfo.processInfo.environment["RUNALYST_EXPAND_FIRST_REP"] == "1" {
                expandedRepIndices.insert(1)
                isSetsExpanded = true
            }
        }
    }

    // MARK: - Rep Row with Progressive Disclosure (Unified Layout)

    @ViewBuilder
    private func drillRepRow(_ rep: DrillDisplayRep, targetRange: ClosedRange<Int>?) -> some View {
        let isRepExpanded = expandedRepIndices.contains(rep.repIndex)

        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                    if isRepExpanded {
                        expandedRepIndices.remove(rep.repIndex)
                    } else {
                        expandedRepIndices.insert(rep.repIndex)
                    }
                }
            } label: {
                VStack(spacing: 6) {
                    // Line 1: Identity & Duration & Pace & Adherence Badge & Chevron
                    HStack(alignment: .center, spacing: 5) {
                        Text("Rep \(rep.repIndex)")
                            .font(.subheadline.bold())
                            .foregroundColor(.primary)
                            .lineLimit(1)

                        if let dur = rep.durationSeconds, dur > 0 {
                            let durMin = Int(dur) / 60
                            let durSec = Int(dur) % 60
                            Text(durMin > 0 ? "\(durMin)m \(durSec)s" : "\(durSec)s")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color(UIColor.tertiarySystemFill))
                                .clipShape(Capsule())
                        }

                        if rep.isFastest {
                            HStack(spacing: 2) {
                                Image(systemName: "hare.fill")
                                    .font(.system(size: 7))
                                Text("Fastest")
                                    .font(.system(size: 8.5, weight: .bold))
                            }
                            .foregroundColor(.orange)
                            .lineLimit(1)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1.5)
                            .background(Color.orange.opacity(0.12))
                            .clipShape(Capsule())
                        }

                        Spacer(minLength: 4)

                        if let pace = rep.workPaceFormatted {
                            Text(pace)
                                .font(.subheadline.bold())
                                .monospacedDigit()
                                .foregroundColor(.primary)
                                .lineLimit(1)
                                .layoutPriority(1)
                        }

                        HStack(spacing: 2.5) {
                            Image(systemName: rep.isMet ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 8, weight: .bold))
                            Text(rep.isMet ? "On Target" : "Developing")
                                .font(.system(size: 9.5, weight: .bold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                        .foregroundColor(rep.isMet ? Color(red: 0.0, green: 0.75, blue: 0.65) : .orange)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background((rep.isMet ? Color(red: 0.0, green: 0.75, blue: 0.65) : Color.orange).opacity(0.12))
                        .clipShape(Capsule())

                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary.opacity(0.6))
                            .rotationEffect(.degrees(isRepExpanded ? 90 : 0))
                    }

                    // Line 2: Biometrics & Recovery Summary
                    HStack(alignment: .center, spacing: 6) {
                        HStack(spacing: 4) {
                            Text("\(rep.workCadence) SPM")
                                .font(.caption)
                                .foregroundColor(rep.isMet ? Color(red: 0.0, green: 0.75, blue: 0.65) : .orange)
                                .lineLimit(1)

                            if rep.workHeartRate > 0 {
                                Text("·")
                                    .font(.caption.bold())
                                    .foregroundColor(.secondary.opacity(0.4))

                                Text("\(rep.workHeartRate) BPM")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        Spacer()

                        HStack(spacing: 4) {
                            if let recPace = rep.recoveryPaceFormatted {
                                Text("Rec \(recPace)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            } else if rep.recoveryCadence > 0 {
                                Text("Rec: \(rep.recoveryCadence) SPM")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }

                            if let drop = rep.recoveryHeartRateDrop {
                                recoveryHeartRateBadge(drop: drop)
                            }
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expanded Deep-Dive (Progressive Disclosure)
            if isRepExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Divider()
                        .padding(.vertical, 4)

                    // Telemetry Breakdown Badges
                    HStack(spacing: 8) {
                        if let range = targetRange {
                            let delta = rep.workCadence - range.lowerBound
                            telemetryPill(
                                label: "Target Band",
                                value: "\(range.lowerBound)–\(range.upperBound) SPM (\(delta >= 0 ? "+\(delta)" : "\(delta)"))",
                                color: rep.isMet ? Color(red: 0.0, green: 0.75, blue: 0.65) : .orange
                            )
                        } else {
                            telemetryPill(
                                label: "Cadence",
                                value: "\(rep.workCadence) SPM",
                                color: rep.isMet ? Color(red: 0.0, green: 0.75, blue: 0.65) : .orange
                            )
                        }

                        if let delta = rep.paceDeltaVsAverageWorkSec {
                            telemetryPill(
                                label: "Pacing",
                                value: paceDeltaString(delta),
                                color: abs(delta) <= 5 ? .blue : .orange
                            )
                        }

                        if let drop = rep.recoveryHeartRateDrop {
                            let hrValue: String = drop > 0 ? "↓ \(drop) BPM" : (drop == 0 ? "0 BPM" : "↑ \(abs(drop)) BPM")
                            let hrColor: Color = drop >= 10 ? Color(red: 1.0, green: 0.22, blue: 0.55) : (drop < 0 ? .orange : .secondary)
                            telemetryPill(
                                label: "HR Drop",
                                value: hrValue,
                                color: hrColor
                            )
                        }
                    }

                    // Coach's Observation
                    let observationText: String = {
                        if let obs = rep.observation, !obs.isEmpty {
                            return obs
                        }
                        return rep.isMet
                            ? "Turnover met the target cadence requirement for this interval."
                            : "Turnover fell short of the prescribed cadence band."
                    }()

                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10))
                            .foregroundColor(drillId.iconColor)
                            .padding(.top, 1)

                        Text(observationText)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(UIColor.secondarySystemGroupedBackground).opacity(0.7))
                    .cornerRadius(6)
                }
                .padding(.top, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(10)
        .background(Color(UIColor.tertiarySystemGroupedBackground))
        .cornerRadius(10)
    }

    @ViewBuilder
    private func recoveryHeartRateBadge(drop: Int?) -> some View {
        if let drop = drop {
            if drop > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 8, weight: .bold))
                    Text("\(drop) BPM")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundColor(Color(red: 0.0, green: 0.75, blue: 0.65))
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(Color(red: 0.0, green: 0.75, blue: 0.65).opacity(0.12))
                .clipShape(Capsule())
            } else if drop == 0 {
                Text("0 BPM")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1.5)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(Capsule())
            } else {
                HStack(spacing: 2) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 8, weight: .bold))
                    Text("\(abs(drop)) BPM")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundColor(.orange)
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(Color.orange.opacity(0.12))
                .clipShape(Capsule())
            }
        }
    }

    private func telemetryPill(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(6)
    }

    private func paceDeltaString(_ delta: Int) -> String {
        if delta == 0 {
            return "Even pace"
        } else if delta > 0 {
            return "+\(delta)s vs avg"
        } else {
            return "\(delta)s vs avg"
        }
    }

    @ViewBuilder
    private func metricTile(label: String, value: String, valueColor: Color, subtitle: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)
            Text(value)
                .font(.subheadline.bold())
                .foregroundColor(valueColor)
            if let sub = subtitle {
                Text(sub)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04))
        .cornerRadius(8)
    }
}

struct DrillAdherenceCalculation {
    let metCount: Int
    let totalCount: Int
    let targetCadence: String
    let targetCadenceStr: String
    let displayReps: [DrillDisplayRep]
    let isIntervalDrill: Bool
    let tier: DrillAdherenceTier
    let tierDescription: String
    let actualCadence: Int
    let actualHR: Int
    let thirtyDayCadence: Int
    let oscDelta: Double
    let isHRTarget: Bool
    let isDualTarget: Bool
    let drillObj: PreRunDrill
    let intervalSummary: DrillIntervalSummary?
}

extension DrillExecutionScorecard {
    /// Deterministically computes the adherence score (met count, total intervals, and target cadence)
    /// across the scorecard, ensuring perfect mathematical parity between scorecard meters, hero subtitles,
    /// and AI coaching narrative text.
    @MainActor
    static func calculateAdherence(
        runRecord: RunRecord,
        drillId: PreRunDrillId,
        baselineCadence: Double?,
        baselineOscillation: Double? = nil
    ) -> DrillAdherenceCalculation {
        let template = DrillTemplate.template(for: drillId)
        let thirtyDayCadence = Int(baselineCadence ?? (runRecord.computeHistoricalBaselineCadence() ?? (runRecord.workingAvgCadence > 0 ? runRecord.workingAvgCadence : 155)))
        let targetCadence = runRecord.effectivePrescribedTargetCadence(drillId: drillId, baselineCadence: thirtyDayCadence)
            ?? template.calculateTargetCadence(thirtyDayCadence)
        let drillObj = PreRunDrill(id: drillId, previousCadence: thirtyDayCadence, targetCadence: targetCadence)
        let actualCadence = Int(runRecord.workingAvgCadence)
        let actualHR = Int(runRecord.workingAvgHeartRate)

        let isHRTarget = drillId.isHeartRateTargeted
        let isDualTarget = (drillId == .tempoSurges)
        let targetCadenceStr = drillObj.computedCadence ?? "Steady"

        let currentOsc = runRecord.workingAvgVerticalOscillation ?? runRecord.rawAvgVerticalOscillation ?? 9.5
        let baseOsc = baselineOscillation ?? 9.5
        let oscDelta = currentOsc - baseOsc

        let intervalSummary: DrillIntervalSummary? = {
            if let parsed = DrillIntervalSummary.from(tags: runRecord.framboiseTags, drillId: drillId) {
                return parsed
            }
            if !isHRTarget && !drillId.isAerobicContinuous {
                return DrillIntervalEvaluator.evaluate(
                    buckets: [],
                    drillId: drillId,
                    baselineCadence: thirtyDayCadence,
                    workoutDuration: runRecord.duration,
                    oscDelta: oscDelta,
                    targetCadenceOverride: targetCadence
                )
            }
            return nil
        }()

        let analysisContext = WorkoutAnalysisContext(
            runRecord: runRecord,
            runSignature: runRecord.signature,
            macroProfile: nil,
            recoveryTimeline: RecoveryTimeline(
                now: Date(),
                lastHard: nil,
                hardSessionsLast72h: 0,
                requiredHours: 48,
                state: .productive
            ),
            baselineStats: baselineCadence.map { (avgPace: runRecord.workingAvgPace, avgCadence: $0, avgHR: runRecord.workingAvgHeartRate) }
        )
        let intervalEvals = analysisContext.intervalEvaluations

        let displayReps: [DrillDisplayRep] = {
            if let summary = intervalSummary, summary.totalIntervals > 1, !summary.reps.isEmpty {
                let durationCategory: DrillDuration = {
                    if runRecord.duration <= 720 { return .tenMinutes }
                    if runRecord.duration >= 1500 { return .thirtyMinutes }
                    return .fifteenMinutes
                }()
                let sched = DrillSchedule.schedule(for: drillId, duration: durationCategory)

                return summary.reps.map { rep in
                    let matchedEval = intervalEvals.first(where: { $0.repIndex == rep.repIndex })
                        ?? (rep.repIndex - 1 >= 0 && rep.repIndex - 1 < intervalEvals.count ? intervalEvals[rep.repIndex - 1] : nil)

                    let evalWorkCad = matchedEval?.workCadence ?? 0
                    let workCadence = evalWorkCad > 0
                        ? evalWorkCad
                        : (rep.workCadence > 0 ? rep.workCadence : actualCadence)
                    let workHR = rep.workHeartRate > 0 ? rep.workHeartRate : (matchedEval?.workHeartRate ?? actualHR)
                    let evalRecCad = matchedEval?.recoveryCadence ?? 0
                    let recCadence = evalRecCad > 0
                        ? evalRecCad
                        : (rep.recoveryCadence > 0 ? rep.recoveryCadence : 0)
                    let recHR = rep.recoveryHeartRate > 0 ? rep.recoveryHeartRate : (matchedEval?.recoveryHeartRate ?? 0)
                    let hrDrop: Int? = {
                        if let drop = matchedEval?.recoveryHeartRateDrop { return drop }
                        if workHR > 0 && recHR > 0 { return workHR - recHR }
                        return nil
                    }()

                    let fallbackDuration = sched.workSeconds > 0 ? sched.workSeconds : nil
                    let fallbackWorkPace: String? = {
                        if runRecord.workingAvgPace > 0 {
                            return PaceFormatter.formatPace(secondsPerKilometer: runRecord.workingAvgPace)
                        }
                        return nil
                    }()

                    let evaluatedIsMet: Bool = {
                        if let range = drillObj.effectiveTargetCadence, workCadence > 0 {
                            let upperLimit = (drillId == .strides || drillId == .tempoSurges) ? 195 : (range.upperBound + 8)
                            return rep.isMet || (workCadence >= (range.lowerBound - 2) && workCadence <= upperLimit)
                        }
                        return rep.isMet
                    }()

                    return DrillDisplayRep(
                        repIndex: rep.repIndex,
                        durationSeconds: matchedEval?.durationSeconds ?? fallbackDuration,
                        isFastest: matchedEval?.observation.starts(with: "Fastest") ?? false,
                        workPaceFormatted: matchedEval?.workPaceFormatted ?? fallbackWorkPace,
                        workCadence: workCadence,
                        workHeartRate: workHR,
                        recoveryPaceFormatted: matchedEval?.recoveryPaceFormatted,
                        recoveryCadence: recCadence,
                        recoveryHeartRate: recHR,
                        recoveryHeartRateDrop: hrDrop,
                        paceDeltaVsAverageWorkSec: matchedEval?.paceDeltaVsAverageWorkSec,
                        isMet: evaluatedIsMet,
                        observation: matchedEval?.observation
                    )
                }
            } else if intervalEvals.count > 1 && !drillId.isAerobicContinuous {
                return intervalEvals.map { eval in
                    let isMet: Bool = {
                        if let range = drillObj.effectiveTargetCadence {
                            return eval.workCadence >= (range.lowerBound - 2) && eval.workCadence <= (range.upperBound + 8)
                        }
                        return eval.workCadence >= thirtyDayCadence
                    }()
                    return DrillDisplayRep(
                        repIndex: eval.repIndex,
                        durationSeconds: eval.durationSeconds,
                        isFastest: eval.observation.starts(with: "Fastest"),
                        workPaceFormatted: eval.workPaceFormatted,
                        workCadence: eval.workCadence,
                        workHeartRate: eval.workHeartRate,
                        recoveryPaceFormatted: eval.recoveryPaceFormatted,
                        recoveryCadence: eval.recoveryCadence ?? 0,
                        recoveryHeartRate: eval.recoveryHeartRate ?? 0,
                        recoveryHeartRateDrop: eval.recoveryHeartRateDrop,
                        paceDeltaVsAverageWorkSec: eval.paceDeltaVsAverageWorkSec,
                        isMet: isMet,
                        observation: eval.observation
                    )
                }
            }
            return []
        }()

        let isIntervalDrill = (intervalSummary?.totalIntervals ?? 0) > 1 || displayReps.count > 1

        let effectiveMetCount: Int
        let effectiveTotalCount: Int
        if let summary = intervalSummary, summary.totalIntervals > 1 {
            effectiveMetCount = displayReps.isEmpty
                ? summary.intervalsMet
                : max(summary.intervalsMet, displayReps.filter(\.isMet).count)
            effectiveTotalCount = displayReps.isEmpty ? summary.totalIntervals : displayReps.count
        } else if isIntervalDrill, !displayReps.isEmpty {
            effectiveMetCount = displayReps.filter(\.isMet).count
            effectiveTotalCount = displayReps.count
        } else {
            effectiveMetCount = intervalSummary?.intervalsMet ?? 0
            effectiveTotalCount = intervalSummary?.totalIntervals ?? 0
        }

        let tier: DrillAdherenceTier
        let tierDescription: String

        if let summary = intervalSummary, summary.totalIntervals > 1 {
            if isDualTarget {
                let intervalsOk = effectiveMetCount >= (effectiveTotalCount + 1) / 2
                let zone4Ok = runRecord.percentZone4 >= 0.20
                if effectiveMetCount == effectiveTotalCount && runRecord.percentZone4 >= 0.35 {
                    tier = .exceeded
                    tierDescription = "Nailed all \(effectiveTotalCount) surges with high threshold capacity (≥35% Zone 4)."
                } else if (summary.tier == .met || summary.tier == .exceeded) || (intervalsOk && zone4Ok) {
                    tier = .met
                    tierDescription = "Landed target surges with sustained threshold effort."
                } else if intervalsOk || runRecord.percentZone4 >= 0.15 {
                    tier = .partiallyMet
                    tierDescription = intervalsOk ? "Hit turnover surges, but overall time in threshold was limited." : "Reached threshold intensity, but surge turnover discipline was developing."
                } else {
                    tier = .notMet
                    tierDescription = summary.verdict
                }
            } else if effectiveMetCount > summary.intervalsMet {
                if effectiveMetCount == effectiveTotalCount && effectiveTotalCount > 0 {
                    tier = .met
                    tierDescription = "Flawless turnover discipline: hit all \(effectiveTotalCount) work intervals on target."
                } else if effectiveMetCount >= (effectiveTotalCount + 1) / 2 {
                    tier = .partiallyMet
                    tierDescription = "Strong turnover adherence: hit \(effectiveMetCount) of \(effectiveTotalCount) target intervals."
                } else {
                    tier = .notMet
                    tierDescription = "Developing turnover: hit \(effectiveMetCount) of \(effectiveTotalCount) intervals in target band."
                }
            } else {
                tier = summary.tier
                tierDescription = summary.verdict
            }
        } else if isIntervalDrill, !displayReps.isEmpty {
            let metCount = displayReps.filter(\.isMet).count
            let total = displayReps.count
            if metCount == total {
                tier = .met
                tierDescription = "Flawless turnover discipline: hit all \(total) work intervals on target."
            } else if metCount >= (total + 1) / 2 {
                tier = .partiallyMet
                tierDescription = "Strong turnover adherence: hit \(metCount) of \(total) target intervals."
            } else {
                tier = .notMet
                tierDescription = "Developing turnover: hit \(metCount) of \(total) intervals in target band."
            }
        } else if isDualTarget {
            let cadenceExact: Bool = {
                if let range = drillObj.effectiveTargetCadence {
                    return range.contains(actualCadence)
                }
                return true
            }()
            let cadenceClose: Bool = {
                if let range = drillObj.effectiveTargetCadence {
                    return actualCadence >= range.lowerBound - 2 && actualCadence <= range.upperBound + 2
                }
                return true
            }()
            let zone4Percent = runRecord.percentZone4

            if cadenceExact && zone4Percent >= 0.35 {
                tier = .exceeded
                tierDescription = "Held target turnover with high threshold capacity (≥35% Zone 4)."
            } else if (cadenceExact || cadenceClose) && zone4Percent >= 0.20 {
                tier = .met
                tierDescription = "Landed in target cadence band with sustained threshold effort."
            } else if cadenceExact || zone4Percent >= 0.15 {
                tier = .partiallyMet
                tierDescription = cadenceExact ? "Hit turnover target, but effort remained sub-threshold." : "Reached threshold intensity, but cadence was off target."
            } else {
                tier = .notMet
                tierDescription = "Missed both target cadence and threshold intensity goals."
            }

        } else if isHRTarget {
            if let zone = drillId.targetHeartRateZone {
                if zone == 2 {
                    if actualHR > 0 {
                        if runRecord.percentZone4 <= 0.04 && actualCadence >= 155 {
                            tier = .exceeded
                            tierDescription = "Preserved Zone 2 ceiling with crisp turnover (≥155 SPM)."
                        } else if runRecord.percentZone4 <= 0.08 {
                            tier = .met
                            tierDescription = "Successfully maintained steady Zone 2 aerobic intensity."
                        } else if runRecord.percentZone4 <= 0.20 {
                            tier = .partiallyMet
                            tierDescription = "Moderate intensity drift; spent partial duration above Zone 2."
                        } else {
                            tier = .notMet
                            tierDescription = "Cardiac drift exceeded aerobic threshold into Zones 3 and 4."
                        }
                    } else {
                        tier = .met
                        tierDescription = "Completed steady aerobic effort."
                    }
                } else { // zone 1
                    if actualHR > 0 {
                        if runRecord.percentZone4 == 0 && actualHR <= 125 {
                            tier = .exceeded
                            tierDescription = "Flawless active recovery with zero cardiac strain."
                        } else if runRecord.percentZone4 <= 0.03 && actualHR <= 135 {
                            tier = .met
                            tierDescription = "Controlled intensity within the Zone 1 recovery envelope."
                        } else if runRecord.percentZone4 <= 0.10 {
                            tier = .partiallyMet
                            tierDescription = "Effort drifted slightly higher than target recovery ceiling."
                        } else {
                            tier = .notMet
                            tierDescription = "Intensity was too elevated for an active recovery run."
                        }
                    } else {
                        tier = .met
                        tierDescription = "Completed gentle recovery effort."
                    }
                }
            } else {
                tier = .met
                tierDescription = "Completed aerobic session."
            }
        } else if let range = drillObj.effectiveTargetCadence {
            let zeroSpike = runRecord.percentZone4 <= 0.05
            let formImproved = oscDelta <= 0
            if range.contains(actualCadence) && zeroSpike && formImproved {
                tier = .exceeded
                tierDescription = "Target turnover held with effortless aerobic stability and form control."
            } else if range.contains(actualCadence) {
                tier = .met
                tierDescription = "Cadence landed precisely within the target \(targetCadenceStr) SPM band."
            } else if actualCadence >= range.lowerBound - 2 && actualCadence <= range.upperBound + 2 {
                tier = .partiallyMet
                tierDescription = "Turnover was close to target (within 2 SPM of target band)."
            } else {
                tier = .notMet
                tierDescription = "Turnover missed the target cadence band by more than 2 SPM."
            }
        } else {
            tier = .met
            tierDescription = "Completed steady effort drill."
        }

        return DrillAdherenceCalculation(
            metCount: effectiveMetCount,
            totalCount: effectiveTotalCount,
            targetCadence: targetCadence,
            targetCadenceStr: targetCadenceStr,
            displayReps: displayReps,
            isIntervalDrill: isIntervalDrill,
            tier: tier,
            tierDescription: tierDescription,
            actualCadence: actualCadence,
            actualHR: actualHR,
            thirtyDayCadence: thirtyDayCadence,
            oscDelta: oscDelta,
            isHRTarget: isHRTarget,
            isDualTarget: isDualTarget,
            drillObj: drillObj,
            intervalSummary: intervalSummary
        )
    }

    @MainActor
    static func evaluateDrillAdherence(
        runRecord: RunRecord,
        drillId: PreRunDrillId,
        baselineCadence: Double?
    ) -> (metCount: Int, totalCount: Int, targetCadence: String) {
        let calc = calculateAdherence(
            runRecord: runRecord,
            drillId: drillId,
            baselineCadence: baselineCadence,
            baselineOscillation: nil
        )
        return (metCount: calc.metCount, totalCount: calc.totalCount, targetCadence: calc.targetCadence)
    }
}
