import SwiftUI
import UIKit
import SwiftData
import WorkoutKit
import RunalystCore

struct RunAnalysisTakeawayItem: Identifiable {
    var id: String { title }
    let icon: String
    let iconColor: Color
    let title: String
    let detail: String
}

extension RunDetailView {
    var environmentInfoMessage: String {
        guard runRecord.isIndoor == true else {
            return String(localized: "Recorded outdoors with GPS. Pace, distance, and route come directly from your Apple Watch.")
        }
        switch runRecord.dataSourceRaw?.lowercased() {
        case "gymkit":
            return String(localized: "Recorded on a GymKit-connected treadmill. Speed and distance were synced directly from the machine.")
        case "footpod":
            return String(localized: "Recorded on a treadmill with a Bluetooth footpod providing distance and cadence.")
        default:
            return String(localized: "Recorded on a treadmill using your Apple Watch wrist sensors. Since the belt sets your speed, coaching focuses on heart rate and cadence rhythm.")
        }
    }

    var baselineStats: SessionSynthesisEngine.WeightedBaselineStats? {
        SessionSynthesisEngine.computeWeightedBaselineStats(from: existingRuns, priorTo: runRecord.date)
    }

    var baselinePace: Double? { baselineStats?.avgPace }
    var baselineHR: Double? { baselineStats?.avgHR }
    var baselineCadence: Double? { baselineStats?.avgCadence }
    var baselineOscillation: Double? { baselineStats?.avgOscillation }
    var baselineStrideLength: Double? { baselineStats?.avgStrideLength }
    var baselineVerticalRatio: Double? { baselineStats?.avgVerticalRatio }

    var formattedRunDate: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEEE, MMM d, yyyy"
        return formatter.string(from: runRecord.date)
    }

    var formattedRunTimeRange: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "h:mm a"
        let startStr = formatter.string(from: runRecord.date)
        if runRecord.duration > 0 {
            let endDate = runRecord.date.addingTimeInterval(runRecord.duration)
            let endStr = formatter.string(from: endDate)
            return "\(startStr) – \(endStr)"
        }
        return startStr
    }

    var classificationOptions: [String] {
        [
            "Steady Effort", "Easy Run", "Tempo Run", "Intervals", "Pyramids",
            "Progression Run", "Recovery Run", "Hill Repeats",
            "Long Run", "Fartlek", "Urban Traffic", "Mixed Effort (Review)"
        ]
    }

    var prescribedDrillName: String? {
        guard !runRecord.isDeleted, runRecord.modelContext != nil else { return nil }
        return runRecord.prescribedDrillName
    }

    var drillPillText: String {
        if let name = prescribedDrillName {
            return "Drill: \(name)"
        }
        return "Prescribed Drill"
    }

    var effectiveScorecardDrillId: PreRunDrillId? {
        guard let drillName = prescribedDrillName else { return nil }
        return PreRunDrillId.allCases.first(where: { $0.title == drillName || $0.rawValue == drillName })
    }

    var hasIntervalWorkReps: Bool {
        runRecord.signature?.phaseSegments.contains(where: { $0.kind == "work" && $0.avgPace > 0 }) ?? false
    }

    func normalizeDrillClassification() {
        guard !runRecord.isDeleted, runRecord.modelContext != nil else { return }
        // Clean up any invalid drill tags on runs that are not genuine drills
        cleanUpInvalidDrillTagsIfNeeded()

        // Only normalize if detectedTypeRaw is an ACTUAL drill title (e.g. "Rhythm Intervals"), never a standard classification like "Intervals"
        guard let canonicalDrill = PreRunDrillId.canonicalDrillTitle(for: runRecord.detectedTypeRaw),
              let parentClass = PreRunDrillId.correspondingClassification(for: runRecord.detectedTypeRaw) else {
            return
        }

        if !runRecord.framboiseTags.contains("prescribedDrill") {
            runRecord.framboiseTags.append("prescribedDrill")
        }
        let drillTag = "drill:\(canonicalDrill)"
        if !runRecord.framboiseTags.contains(drillTag) {
            runRecord.framboiseTags.append(drillTag)
        }
        if runRecord.detectedTypeRaw != parentClass {
            runRecord.detectedTypeRaw = parentClass
            try? modelContext.save()
        }
    }

    func cleanUpInvalidDrillTagsIfNeeded() {
        guard !runRecord.isDeleted, runRecord.modelContext != nil else { return }
        let allIds = Set(PreRunDrillId.allCases.map(\.rawValue))
        let allTitles = Set(PreRunDrillId.allCases.map(\.title))
        let hasAnyDrillTag = runRecord.framboiseTags.contains {
            $0 == "prescribedDrill" || $0.hasPrefix("drill:") || allIds.contains($0) || allTitles.contains($0)
        }
        // A run is only a prescribed drill if it has a confirmed authentic drill name
        if hasAnyDrillTag && prescribedDrillName == nil {
            runRecord.framboiseTags.removeAll { tag in
                tag == "prescribedDrill" ||
                tag.hasPrefix("drill:") ||
                tag.hasPrefix("drillIntervals:") ||
                tag.hasPrefix("drillWorkCadence:") ||
                tag.hasPrefix("drillRecCadence:") ||
                tag.hasPrefix("drillReps:") ||
                tag.hasPrefix("drillRepDetails:") ||
                allIds.contains(tag) ||
                allTitles.contains(tag)
            }
            if let sigClass = runRecord.signature?.classification.trimmingCharacters(in: .whitespacesAndNewlines),
               !sigClass.isEmpty,
               runRecord.detectedTypeRaw != sigClass {
                runRecord.detectedTypeRaw = sigClass
            }
            try? modelContext.save()
        }
    }

    var resolvedSessionDrillId: PreRunDrillId? {
        if let drillId = effectiveScorecardDrillId { return drillId }
        let isRec = runRecord.detectedTypeRaw == "Recovery Run" || (runRecord.percentZone4 <= 0.02 && runRecord.workingAvgHeartRate > 0 && runRecord.workingAvgHeartRate <= 135 && runRecord.duration >= 600)
        let isEasyOrSteady = runRecord.detectedTypeRaw == "Easy Run" || runRecord.detectedTypeRaw == "Steady Effort" || runRecord.detectedTypeRaw == "Zone 2" || runRecord.detectedTypeRaw == "Long Run"
        if isRec { return .aerobicFlush }
        if isEasyOrSteady { return .zone2Run }
        return nil
    }

    var takeawaySummary: RunTakeawaySummary {
        let isIndoor = runRecord.isIndoor ?? false
        let heightFlr = Int(runRecord.signature?.cadenceFloor ?? Double(SessionSynthesisCore.heightAdjustedCadenceFloor(heightCm: UserDefaults.standard.double(forKey: "userHeight") > 0 ? UserDefaults.standard.double(forKey: "userHeight") : 175.0)))

        let drillAdherenceContext: RunTakeawaySummary.DrillAdherenceContext? = {
            guard let drill = resolvedSessionDrillId else { return nil }
            let adherence = DrillExecutionScorecard.calculateAdherence(
                runRecord: runRecord,
                drillId: drill,
                baselineCadence: baselineCadence,
                baselineOscillation: baselineOscillation
            )
            let tierStr: String = {
                switch adherence.tier {
                case .exceeded: return "exceeded"
                case .met: return "met"
                case .partiallyMet: return "partiallyMet"
                case .notMet: return "notMet"
                }
            }()
            let firstDigits = adherence.targetCadence.components(separatedBy: CharacterSet.decimalDigits.inverted).first(where: { !$0.isEmpty })
            let targetCadInt = firstDigits.flatMap(Int.init) ?? Int(round(runRecord.workingAvgCadence))
            return RunTakeawaySummary.DrillAdherenceContext(
                drillIdentifier: drill.rawValue,
                drillDisplayName: drill.title,
                targetCadence: targetCadInt,
                targetHeartRateZone: drill.targetHeartRateZone ?? 2,
                isHeartRateTargeted: drill.isHeartRateTargeted,
                metCount: adherence.metCount,
                totalCount: adherence.totalCount,
                actualHR: Double(adherence.actualHR),
                actualCadence: adherence.actualCadence,
                effectiveCadenceFloor: adherence.effectiveCadenceFloor,
                tier: tierStr,
                tierBadgeText: adherence.tier.badgeText(for: drill)
            )
        }()

        let intervalContext: RunTakeawaySummary.IntervalSummaryContext? = {
            guard runRecord.evaluationModality == .intervals && hasIntervalWorkReps else { return nil }
            let workSegments = runRecord.signature?.phaseSegments.filter { $0.kind == "work" && $0.avgPace > 0 } ?? []
            guard !workSegments.isEmpty else { return nil }
            let meanWorkPace = workSegments.reduce(0.0) { $0 + $1.avgPace } / Double(workSegments.count)
            let avgWorkCad = Int(workSegments.reduce(0.0) { $0 + $1.avgCadence } / Double(workSegments.count))
            return RunTakeawaySummary.IntervalSummaryContext(
                meanWorkPaceSecondsPerKm: meanWorkPace,
                avgWorkCadence: avgWorkCad
            )
        }()

        let context = WorkoutAnalysisContext(
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
            baselineStats: baselineStats.map { (avgPace: $0.avgPace, avgCadence: $0.avgCadence, avgHR: $0.avgHR) }
        )
        let hasDrift = context.hasCardiacDrift
        let driftMag = context.cardiacDriftMagnitudeBPM

        return RunTakeawaySummary.evaluate(
            detectedTypeRaw: runRecord.detectedTypeRaw,
            workingAvgCadence: runRecord.workingAvgCadence,
            workingAvgHeartRate: runRecord.workingAvgHeartRate,
            percentZone4: runRecord.percentZone4,
            heightAdjustedCadenceFloor: heightFlr,
            isIndoor: isIndoor,
            hasCardiacDrift: hasDrift,
            cardiacDriftMagnitudeBPM: driftMag,
            prescribedDrillName: prescribedDrillName,
            drillAdherence: drillAdherenceContext,
            intervalSummary: intervalContext,
            cachedInsightHeadline: runRecord.insight?.headline
        )
    }

    var deterministicRunAnalysisTakeaways: [RunAnalysisTakeawayItem] {
        let summary = takeawaySummary
        let resolvedDrill = resolvedSessionDrillId
        return summary.items.map { item in
            let color: Color = {
                if item.id == "execution-verdict", let drill = resolvedDrill {
                    let adherence = DrillExecutionScorecard.calculateAdherence(
                        runRecord: runRecord,
                        drillId: drill,
                        baselineCadence: baselineCadence,
                        baselineOscillation: baselineOscillation
                    )
                    return adherence.tier.tintColor
                } else if item.id == "interval-execution" {
                    return Color.purple
                } else if item.id == "cardio-control" {
                    return item.isWarning ? Color.orange : Color(red: 1.0, green: 0.18, blue: 0.55)
                } else {
                    return item.isWarning ? Color.orange : Color.green
                }
            }()
            return RunAnalysisTakeawayItem(
                icon: item.iconName,
                iconColor: color,
                title: item.title,
                detail: item.detail
            )
        }
    }

    var deterministicRunAnalysisSummary: String? {
        let details = deterministicRunAnalysisTakeaways.map(\.detail)
        guard !details.isEmpty else { return nil }
        return details.joined(separator: " ")
    }

    @ViewBuilder
    var environmentPill: some View {
        let isIndoor = runRecord.isIndoor ?? false
        Button {
            showingEnvironmentInfo = true
        } label: {
            HStack(spacing: 5) {
                Image(systemName: isIndoor ? RunalystIcon.indoor : RunalystIcon.outdoor)
                    .font(.caption2.bold())
                Text(isIndoor ? "Indoor" : "Outdoor")
                    .font(.caption.bold())
            }
            .foregroundColor(isIndoor ? RunalystColor.indoor : RunalystColor.outdoor)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background((isIndoor ? RunalystColor.indoor : RunalystColor.outdoor).opacity(0.12))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke((isIndoor ? RunalystColor.indoor : RunalystColor.outdoor).opacity(0.3), lineWidth: 1)
            )
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Workout Environment: \(isIndoor ? "Indoor" : "Outdoor")")
        .accessibilityHint("Double tap to change workout environment")
        .alert(isIndoor ? "Indoor Session" : "Outdoor Session", isPresented: $showingEnvironmentInfo) {
            Button(isIndoor ? "Switch to Outdoor" : "Switch to Indoor (Treadmill)") {
                let newIndoor = !isIndoor
                runRecord.isIndoor = newIndoor
                runRecord.framboiseTags.removeAll { $0 == "userSetIndoor" || $0 == "userSetOutdoor" }
                runRecord.framboiseTags.append(newIndoor ? "userSetIndoor" : "userSetOutdoor")
                UserDefaults.standard.set(newIndoor, forKey: "preferredWorkoutIsIndoor")
                try? modelContext.save()
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text(environmentInfoMessage)
        }
    }

    @ViewBuilder
    var classificationPill: some View {
        Menu {
            ForEach(classificationOptions, id: \.self) { option in
                Button {
                    let old = runRecord.detectedTypeRaw
                    runRecord.detectedTypeRaw = option
                    updateClassification(to: option, from: old)
                } label: {
                    if option == runRecord.detectedTypeRaw {
                        Label(option, systemImage: "checkmark")
                    } else {
                        Text(option)
                    }
                }
            }

            Divider()

            Button {
                showingClassificationExplainer = true
            } label: {
                Label("About Classifications...", systemImage: "info.circle")
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "figure.run")
                    .font(.caption2.bold())
                Text(runRecord.detectedTypeRaw.isEmpty ? runRecord.normalizedClassification : runRecord.detectedTypeRaw)
                    .font(.caption.bold())
                Image(systemName: "chevron.down")
                    .font(.caption2.bold())
                    .opacity(0.7)
            }
            .foregroundColor(runRecord.detectedTypeRaw == "Mixed Effort (Review)" ? .orange : Color(red: 0.05, green: 0.45, blue: 0.5))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                (runRecord.detectedTypeRaw == "Mixed Effort (Review)" ? Color.orange : Color(red: 0.05, green: 0.45, blue: 0.5))
                    .opacity(0.12)
            )
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(
                        (runRecord.detectedTypeRaw == "Mixed Effort (Review)" ? Color.orange : Color(red: 0.05, green: 0.45, blue: 0.5))
                            .opacity(0.3),
                        lineWidth: 1
                    )
            )
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Workout Classification: \(runRecord.detectedTypeRaw.isEmpty ? runRecord.normalizedClassification : runRecord.detectedTypeRaw)")
        .accessibilityHint("Double tap to reclassify workout")
    }

    @ViewBuilder
    var drillControl: some View {
        DrillLinkControlView(
            runRecord: runRecord,
            prescribedDrillName: prescribedDrillName,
            baselineCadence: baselineCadence
        )
    }

    var hasBiomechanicsData: Bool {
        (runRecord.workingAvgVerticalOscillation ?? runRecord.rawAvgVerticalOscillation) != nil ||
        (runRecord.workingAvgStrideLength ?? runRecord.rawAvgStrideLength) != nil ||
        runRecord.verticalRatio != nil ||
        runRecord.efficiencyFactor != nil
    }

    func updateClassification(to newType: String, from oldType: String? = nil) {
        let previous = oldType ?? runRecord.detectedTypeRaw
        guard newType != previous else { return }
        let correction = TrainingCorrection(
            runRecordID: runRecord.id,
            originalLabel: previous,
            correctedLabel: newType,
            featureVector: [runRecord.workingAvgPace, runRecord.paceCV, runRecord.paceSlope, runRecord.percentZone4, runRecord.duration / 60.0]
        )
        modelContext.insert(correction)
        runRecord.detectedTypeRaw = newType
        runRecord.classificationProvenance = .userConfirmed
        runRecord.classificationConfidence = 1.0
        if !runRecord.framboiseTags.contains("userConfirmedClassification") {
            runRecord.framboiseTags.append("userConfirmedClassification")
        }
        try? modelContext.save()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}
