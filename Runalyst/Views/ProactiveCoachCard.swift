import SwiftUI
import WorkoutKit

struct ProactiveCoachCard: View {
    var activePrimerId: PreRunDrillId
    var baselineCadence: Int?
    var timeRange: String
    var runRecords: [RunRecord]
    var isPrimerCompletedToday: Bool
    var onTogglePrimerCompleted: () -> Void

    @AppStorage("lastWatchExportTimestamp") private var lastWatchExportTimestamp: Double = 0
    @AppStorage("lastExportedDrillId") private var lastExportedDrillId: String = ""

    @State private var activeReadoutItem: ActiveDrillReadoutItem?

    var body: some View {
        let primerId = activePrimerId
        let template = DrillTemplate.template(for: primerId)
        let baseCadence = baselineCadence
        let computedTarget = baseCadence.map { template.calculateTargetCadence($0) }

        let readiness = ReadinessEvaluator.assess(runRecords: runRecords)
        let adaptedTarget = ReadinessModifier.adaptTarget(computedTarget, baselineCadence: baseCadence, drillId: primerId, state: readiness.state)
        let primerDrill = PreRunDrill(
            id: primerId,
            previousCadence: baseCadence,
            targetCadence: adaptedTarget.targetCadence,
            readinessState: readiness.state
        )

        let dynamicDurationText: String = {
            if primerDrill.readinessAdjustedIntervalSpec != nil {
                let phases = primerDrill.generatePhases()
                let total = phases.map(\.durationSeconds).reduce(0, +)
                let mins = total / 60
                let secs = total % 60
                let formatted = secs > 0 ? "\(mins)m \(secs)s" : "\(mins) min"
                return "\(formatted) (Trimmed from \(primerDrill.duration.title))"
            }
            return "\(primerDrill.duration.title) drill"
        }()

        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: primerId.iconName)
                    .foregroundColor(primerId.iconColor)
                    .font(.headline)
                VStack(alignment: .leading, spacing: 2) {
                    Text(template.title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text(dynamicDurationText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                NavigationLink(destination: DrillsLibraryView()) {
                    HStack(spacing: 4) {
                        Text("All Drills")
                        Image(systemName: "chevron.right")
                    }
                    .font(.caption.bold())
                    .foregroundColor(.accentColor)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
            }

            Text(template.defaultPurpose)
                .font(.subheadline)
                .foregroundColor(.secondary)

            HStack(spacing: 16) {
                Label(primerDrill.defaultWorkString, systemImage: "repeat")
                    .font(.caption.bold())
                    .foregroundColor(.primary)
                Label(primerDrill.defaultRecoveryString, systemImage: "moon.zzz")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Label(template.defaultEffort, systemImage: "bolt.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            let cue = template.generateInstructionalCue(adaptedTarget.targetCadence)
            if !cue.isEmpty {
                DrillCoachingCueBox(cue: cue)
            }

            let isZone1 = primerId == .aerobicFlush || primerId == .recoveryJog
            let isZone2 = primerId == .zone2Run
            let targetExplainerTitle: String? = {
                if isZone1 { return "Zone 1 Heart Rate" }
                if isZone2 { return "Zone 2 Heart Rate" }
                return "Target Cadence"
            }()
            let targetText: String? = {
                if isZone1 {
                    return "Target: Zone 1 HR"
                }
                if isZone2 {
                    return "Target: Zone 2 HR"
                }
                if let target = adaptedTarget.targetCadence, let base = baseCadence {
                    if adaptedTarget.isCadenceRelaxed {
                        return "Target: \(target) SPM (Adapted)"
                    } else {
                        return "Target: \(target) SPM (\(timeRange) Baseline: \(base) SPM)"
                    }
                } else {
                    return "Target: Dynamic cadence"
                }
            }()

            DrillPrescriptionPanel(
                targetText: targetText,
                targetExplainerTitle: targetExplainerTitle,
                runRecords: runRecords
            )

            WorkoutPhaseTimelineView(phases: primerDrill.generatePhases())

            HStack(spacing: 12) {
                Button(action: {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    openDrillReadout(primerId: primerId, template: template, computedTarget: computedTarget, baseCadence: baseCadence)
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                        Text("Start")
                    }
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
                    .padding(.vertical, 14)
                    .background(Color(UIColor.tertiarySystemFill))
                    .foregroundColor(.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Button(action: {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onTogglePrimerCompleted()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: isPrimerCompletedToday ? "checkmark.circle.fill" : "circle")
                        Text(isPrimerCompletedToday ? "Completed ✓" : "Mark completed")
                    }
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
                    .padding(.vertical, 14)
                    .background(isPrimerCompletedToday ? Color.green.opacity(0.15) : Color.orange)
                    .foregroundColor(isPrimerCompletedToday ? .green : .white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(UIColor.separator).opacity(0.2), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
        .sheet(item: $activeReadoutItem) { item in
            DrillInterstitialReadoutView(
                readout: item.readout,
                workoutPlan: item.plan,
                prescriptionDTO: item.dto,
                onCommitToWatch: { _, dto in
                    self.lastWatchExportTimestamp = Date().timeIntervalSince1970
                    self.lastExportedDrillId = dto.preRunDrillId ?? ""
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private func openDrillReadout(primerId: PreRunDrillId, template: DrillTemplate, computedTarget: String?, baseCadence: Int?) {
        let standardDTO = DrillPrescriptionDTO(
            title: template.title,
            preRunDrillId: primerId.rawValue,
            purpose: template.defaultPurpose,
            targetCadence: computedTarget,
            previousCadence: baseCadence,
            durationMinutes: PreRunDrill(id: primerId).duration.rawValue
        )
        let readiness = ReadinessEvaluator.assess(runRecords: runRecords)
        activeReadoutItem = ActiveDrillReadoutItem.adaptive(dto: standardDTO, readiness: readiness)
    }
}
