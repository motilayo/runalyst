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

struct DrillExecutionScorecard: View {
    let runRecord: RunRecord
    let drillId: PreRunDrillId
    let baselineCadence: Double?
    let baselineOscillation: Double?
    var customTitle: String?
    @State private var isSetsExpanded: Bool = false

    var body: some View {
        let template = DrillTemplate.template(for: drillId)
        let thirtyDayCadence = Int(baselineCadence ?? (runRecord.computeHistoricalBaselineCadence() ?? (runRecord.workingAvgCadence > 0 ? runRecord.workingAvgCadence : 155)))
        let targetCadence = template.calculateTargetCadence(thirtyDayCadence)
        let drillObj = PreRunDrill(id: drillId, previousCadence: thirtyDayCadence, targetCadence: targetCadence)
        let actualCadence = Int(runRecord.workingAvgCadence)
        let actualHR = Int(runRecord.workingAvgHeartRate)

        let isHRTarget = drillId.isHeartRateTargeted
        let isDualTarget = (drillId == .tempoSurges)
        let targetCadenceStr = drillObj.computedCadence ?? "Steady"

        let currentOsc = runRecord.workingAvgVerticalOscillation ?? runRecord.rawAvgVerticalOscillation ?? 9.5
        let baseOsc = baselineOscillation ?? 9.5
        let oscDelta = currentOsc - baseOsc

        // Attempt to parse stored interval-by-interval results from framboiseTags
        let intervalSummary: DrillIntervalSummary? = {
            if let parsed = DrillIntervalSummary.from(tags: runRecord.framboiseTags, drillId: drillId) {
                return parsed
            }
            if !isHRTarget && !drillId.isAerobicContinuous {
                // Synthesize baseline interval evaluation if not yet tagged
                return DrillIntervalEvaluator.evaluate(
                    buckets: [],
                    drillId: drillId,
                    baselineCadence: thirtyDayCadence,
                    workoutDuration: runRecord.duration,
                    oscDelta: oscDelta
                )
            }
            return nil
        }()

        let isIntervalDrill = (intervalSummary?.totalIntervals ?? 0) > 1

        let tier: DrillAdherenceTier
        let tierDescription: String

        if let summary = intervalSummary, isIntervalDrill {
            if isDualTarget {
                let intervalsOk = summary.intervalsMet >= (summary.totalIntervals + 1) / 2
                let zone4Ok = runRecord.percentZone4 >= 0.20
                if summary.intervalsMet == summary.totalIntervals && runRecord.percentZone4 >= 0.35 {
                    tier = .exceeded
                    tierDescription = "Nailed all \(summary.totalIntervals) surges with high threshold capacity (≥35% Zone 4)."
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
            } else {
                tier = summary.tier
                tierDescription = summary.verdict
            }
        } else if isDualTarget {
            // Tempo Surges: Cadence + Zone 4 Threshold
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

        return VStack(spacing: 14) {
            // Header: Icon + Title + Capsule Badge (Single line)
            HStack(spacing: 8) {
                Image(systemName: drillId.iconName)
                    .foregroundColor(drillId.iconColor)
                    .font(.title3)
                Text(customTitle ?? (runRecord.prescribedDrillName != nil ? "Drill Performance" : "Workout Performance"))
                    .font(.headline.weight(.semibold))
                    .foregroundColor(.primary)
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
            if let summary = intervalSummary, isIntervalDrill {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Interval Adherence")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(summary.intervalsMet) of \(summary.totalIntervals) on Target (\(summary.adherencePercentage)%)")
                            .font(.caption.bold())
                            .foregroundColor(summary.tier.tintColor)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }

                    // Pips (R1, R2, ...)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(summary.reps, id: \.repIndex) { rep in
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
                            if summary.reps.count > 6 {
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
            if let summary = intervalSummary, isIntervalDrill {
                let workCadenceVal = summary.workCadenceAvg > 0 ? summary.workCadenceAvg : actualCadence
                let workCadenceTargetMet: Bool = {
                    if let range = drillObj.effectiveTargetCadence {
                        return workCadenceVal >= (range.lowerBound - 2) &&
                            (drillId == .strides || drillId == .tempoSurges ? workCadenceVal <= 195 : workCadenceVal <= range.upperBound + 8)
                    }
                    return workCadenceVal >= thirtyDayCadence
                }()
                let workColor: Color = workCadenceTargetMet ? .green : (summary.tier == .notMet ? .red : .orange)

                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        metricTile(
                            label: "WORK CADENCE",
                            value: "\(workCadenceVal) SPM",
                            valueColor: workColor,
                            subtitle: "Target: \(targetCadenceStr) SPM"
                        )
                        metricTile(
                            label: "REC CADENCE",
                            value: "\(summary.recoveryCadenceAvg > 0 ? summary.recoveryCadenceAvg : max(130, actualCadence - 20)) SPM",
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
            if let summary = intervalSummary, isIntervalDrill, !summary.reps.isEmpty {
                Divider()

                HStack {
                    Text("SETS (\(summary.totalIntervals))")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)

                    Spacer()

                    if summary.totalIntervals > 2 {
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                isSetsExpanded.toggle()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(isSetsExpanded ? "Show Less" : "Show All (\(summary.totalIntervals))")
                                    .font(.caption.bold())
                                Image(systemName: isSetsExpanded ? "chevron.up" : "chevron.down")
                                    .font(.caption2.bold())
                            }
                            .foregroundColor(drillId.iconColor)
                        }
                    }
                }

                let displayedReps = isSetsExpanded ? summary.reps : Array(summary.reps.prefix(2))
                VStack(spacing: 6) {
                    ForEach(displayedReps, id: \.repIndex) { rep in
                        HStack(spacing: 8) {
                            Text("R\(rep.repIndex)")
                                .font(.caption.bold())
                                .foregroundColor(.primary)
                                .frame(width: 26, alignment: .leading)

                            Image(systemName: rep.isMet ? "checkmark.circle.fill" : "circle")
                                .font(.caption2)
                                .foregroundColor(rep.isMet ? .green : .orange)

                            Text("\(rep.workCadence) SPM")
                                .font(.caption.bold())
                                .monospacedDigit()
                                .foregroundColor(rep.isMet ? Color(red: 0.0, green: 0.75, blue: 0.65) : .orange)

                            if rep.recoveryCadence > 0 {
                                Text("Rec: \(rep.recoveryCadence) SPM")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Text(rep.isMet ? "On Target" : "Developing")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(rep.isMet ? .green : .orange)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(rep.isMet ? Color.green.opacity(0.12) : Color.orange.opacity(0.12))
                                .clipShape(Capsule())
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(Color(UIColor.tertiarySystemGroupedBackground))
                        .cornerRadius(8)
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
