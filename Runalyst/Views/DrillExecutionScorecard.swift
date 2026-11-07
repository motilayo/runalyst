import SwiftUI
import RunalystCore

struct DrillExecutionScorecard: View {
    let runRecord: RunRecord
    let drillId: PreRunDrillId
    let baselineCadence: Double?
    let baselineOscillation: Double?
    var customTitle: String?
    var customSubtitle: String?

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State var isSetsExpanded: Bool = false
    @State var expandedRepIndices: Set<Int> = []

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
        let effectiveCadenceFloor = calc.effectiveCadenceFloor
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
                        let thresholdTier = AerobicStrainEvaluation.evaluateThresholdGoalTier(percentZone4: runRecord.percentZone4)
                        HStack(spacing: 10) {
                            metricTile(
                                label: "THRESHOLD GOAL",
                                value: "≥20% Zone 4",
                                valueColor: .primary
                            )
                            metricTile(
                                label: "ZONE 4 TIME",
                                value: String(format: "%.0f%%", runRecord.percentZone4 * 100),
                                valueColor: thresholdTier == "met" ? .green : (thresholdTier == "partial" ? .orange : .red)
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

                    let thresholdTier = AerobicStrainEvaluation.evaluateThresholdGoalTier(percentZone4: runRecord.percentZone4)
                    HStack(spacing: 10) {
                        metricTile(
                            label: "THRESHOLD GOAL",
                            value: "≥20% Zone 4",
                            valueColor: .primary
                        )
                        metricTile(
                            label: "ZONE 4 TIME",
                            value: String(format: "%.0f%%", runRecord.percentZone4 * 100),
                            valueColor: thresholdTier == "met" ? .green : .orange
                        )
                    }
                }
            } else if isHRTarget {
                // Heart Rate Target Adherence (Target Zone, Ceiling Control, Cadence Floor)
                let targetSubtitle: String = {
                    if drillId.targetHeartRateZone == 2 {
                        return "Aerobic Base"
                    } else {
                        return "Active Recovery"
                    }
                }()
                let hrCeiling = drillId.targetHeartRateZone == 2 ? 144 : 135
                let strain = AerobicStrainEvaluation.evaluate(
                    workingAvgHeartRate: Double(actualHR),
                    percentZone4: runRecord.percentZone4,
                    zone2Ceiling: Double(hrCeiling),
                    isRecoveryPrescription: drillId.targetHeartRateZone != 2
                )
                let isZone4Spike = strain.isZone4Overreach
                let hrSubtitle: String = {
                    if drillId.targetHeartRateZone == 2 {
                        if isZone4Spike {
                            return "Zone 4 threshold strain"
                        } else {
                            return actualHR <= 144 ? "Ceiling ≤ 144 held" : "Elevated strain (Zone 3)"
                        }
                    } else {
                        if isZone4Spike {
                            return "Zone 4 threshold strain"
                        } else {
                            return actualHR <= 135 ? "Ceiling ≤ 135 held" : "Elevated strain"
                        }
                    }
                }()
                let ceilingValue = !strain.isCeilingExceeded ? "Preserved" : "Exceeded"
                let ceilingColor: Color = ceilingValue == "Preserved" ? Color(red: 0.0, green: 0.75, blue: 0.65) : (isZone4Spike ? .red : .orange)

                HStack(spacing: 8) {
                    metricTile(
                        label: "TARGET ZONE",
                        value: drillId.targetHeartRateZoneName ?? "Zone 1",
                        valueColor: .primary,
                        subtitle: targetSubtitle
                    )
                    metricTile(
                        label: "AEROBIC CEILING",
                        value: ceilingValue,
                        valueColor: ceilingColor,
                        subtitle: hrSubtitle
                    )
                    metricTile(
                        label: "MECHANICAL FLOOR",
                        value: actualCadence > 0 ? "\(actualCadence) SPM" : "--",
                        valueColor: actualCadence >= effectiveCadenceFloor ? Color(red: 0.0, green: 0.75, blue: 0.65) : .orange,
                        subtitle: actualCadence >= effectiveCadenceFloor ? "Cushioned stride" : "Turnover dip"
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
            let highStrain = AerobicStrainEvaluation.evaluate(
                workingAvgHeartRate: Double(actualHR),
                percentZone4: runRecord.percentZone4,
                zone2Ceiling: Double(drillId.targetHeartRateZone == 2 ? 144 : 135),
                isRecoveryPrescription: drillId.targetHeartRateZone != 2
            )
            if !isDualTarget && highStrain.isZone4Overreach {
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
        .liquidGlass(cornerRadius: 16, padding: 16, accentColor: drillId.iconColor)
        .onAppear {
            if ProcessInfo.processInfo.environment["RUNALYST_EXPAND_FIRST_REP"] == "1" {
                expandedRepIndices.insert(1)
                isSetsExpanded = true
            }
        }
    }

    @ViewBuilder
    func metricTile(label: String, value: String, valueColor: Color, subtitle: String? = nil) -> some View {
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
