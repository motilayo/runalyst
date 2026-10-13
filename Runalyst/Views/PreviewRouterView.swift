import SwiftUI

struct PreviewRouterView: View {
    let previewScreen: String
    let existingRuns: [RunRecord]

    @ViewBuilder
    private var drillReadoutPreview: some View {
        let template = DrillTemplate.template(for: .cadencePyramids)
        let baseCadence = 165
        let targetCadence: String? = template.calculateTargetCadence(baseCadence)
        let drill = PreRunDrill(
            id: .cadencePyramids,
            previousCadence: baseCadence,
            targetCadence: targetCadence,
            duration: .tenMinutes,
            hapticMode: .on
        )
        let readout = DrillReadout.readout(
            for: .cadencePyramids,
            customTitle: template.title,
            targetCadence: targetCadence,
            previousCadence: baseCadence,
            customDuration: .tenMinutes
        )
        let plan = drill.buildWorkoutPlan()
        let dto = DrillPrescriptionDTO(
            title: template.title,
            preRunDrillId: PreRunDrillId.cadencePyramids.rawValue,
            purpose: template.defaultPurpose,
            targetCadence: targetCadence,
            previousCadence: baseCadence,
            durationMinutes: DrillDuration.tenMinutes.rawValue,
            hapticMode: HapticFeedbackMode.on.rawValue
        )

        DrillInterstitialReadoutView(
            readout: readout,
            workoutPlan: plan,
            prescriptionDTO: dto,
            onCommitToWatch: nil
        )
    }

    var body: some View {
        switch previewScreen {
        case "RUN_DETAIL":
            if let run = existingRuns.first {
                NavigationStack {
                    RunDetailView(runRecord: run)
                }
            } else {
                DashboardView(onSync: nil)
            }
        case "DRILL_CARD":
            if let run = existingRuns.first, let drills = run.insight?.drillRecommendations, !drills.isEmpty {
                NavigationStack {
                    ScrollView {
                        DrillDeckView(drills: drills)
                            .padding(.top, 20)
                    }
                    .navigationTitle("Recommended Drill")
                }
                .onAppear {
                    if MacroProfile.load() == nil {
                        let profile = MacroProfile(
                            acwr: 1.02,
                            acuteLoad: 310,
                            chronicWeeklyLoad: 304,
                            baselinePace: 330,
                            baselineHR: 148,
                            baselineCadence: 168,
                            baselineEfficiencyFactor: 1.45,
                            updatedAt: Date()
                        )
                        profile.save()
                    }
                }
            } else {
                DashboardView(onSync: nil)
            }
        case "DRILLS":
            NavigationStack {
                DrillsLibraryView()
            }
        case "DRILL_READOUT":
            drillReadoutPreview
        case "BIOMECHANICS":
            NavigationStack {
                OverstrideBiomechanicsSheet()
            }
        case "SETTINGS":
            NavigationStack {
                SettingsView(onForceSync: nil)
            }
        case "PROGRESSION":
            NavigationStack {
                ScrollView {
                    ProgressionChartView(allRuns: existingRuns, defaultHorizon: .allTime)
                        .padding()
                }
                .navigationTitle("Cadence Progression")
            }
        case "ANALYST", "ANALYST_ACTIVE", "ANALYST_READ", "ANALYST_EFFORT", "ANALYST_IMPROVE", "ANALYST_MULTI", "ANALYST_ARM_DRIVE", "ANALYST_DEGRADATION", "ANALYST_WEAKNESS", "ANALYST_SPLIT_GRADE":
            if let run = existingRuns.first {
                AnalystChatView(runRecord: run)
            } else {
                DashboardView(onSync: nil)
            }
        case "READINESS":
            ReadinessMathModal(acuteLoad: 168.5, chronicWeeklyLoad: 165.2, acwr: 1.02)
        case "DETAIL":
            if let run = existingRuns.first {
                NavigationStack {
                    RunDetailView(runRecord: run)
                }
            } else {
                DashboardView(onSync: nil)
            }
        case "DRILL_EXPLAINER":
            let readiness = ReadinessEvaluator.assess(runRecords: existingRuns)
            let dto = DrillPrescriptionDTO(
                title: "Cadence Pyramids",
                preRunDrillId: PreRunDrillId.cadencePyramids.rawValue,
                purpose: "This pattern sharpens your cadence control and supports your aerobic foundation.",
                targetCadence: "160-166 SPM",
                previousCadence: 156,
                durationMinutes: 10
            )
            let item = ActiveDrillReadoutItem.adaptive(
                dto: dto,
                readiness: readiness,
                customCoachingTip: "Focus on steady, measured movement and release tension through your shoulders."
            )
            DrillInterstitialReadoutView(
                readout: item.readout,
                workoutPlan: item.plan,
                prescriptionDTO: item.dto
            )
        case "DRILL_EXPLAINER_ADAPTED":
            let assessment = ReadinessAssessment(
                state: .acuteFatigue,
                triggers: [.consecutiveHardDays],
                acuteLoad: 168.0,
                chronicWeeklyLoad: 145.0,
                acwr: 1.16,
                mileageDropFraction: nil
            )
            let dto = DrillPrescriptionDTO(
                title: "Cadence Pyramids",
                preRunDrillId: PreRunDrillId.cadencePyramids.rawValue,
                purpose: "This pattern sharpens your cadence control and supports your aerobic foundation.",
                targetCadence: "160-166 SPM",
                previousCadence: 156,
                durationMinutes: 10
            )
            let item = ActiveDrillReadoutItem.adaptive(
                dto: dto,
                readiness: assessment,
                customCoachingTip: "Focus on steady, measured movement and release tension through your shoulders."
            )
            DrillInterstitialReadoutView(
                readout: item.readout,
                workoutPlan: item.plan,
                prescriptionDTO: item.dto
            )
        case "VARIANCE_MAP":
            let sampleSegments: [PhaseSegment] = [
                PhaseSegment(startSeconds: 0, endSeconds: 300, kind: "steady", avgPace: 330, avgCadence: 160, avgHR: 138),
                PhaseSegment(startSeconds: 300, endSeconds: 600, kind: "work", avgPace: 270, avgCadence: 174, avgHR: 168),
                PhaseSegment(startSeconds: 600, endSeconds: 780, kind: "recovery", avgPace: 360, avgCadence: 154, avgHR: 142),
                PhaseSegment(startSeconds: 780, endSeconds: 1080, kind: "work", avgPace: 265, avgCadence: 176, avgHR: 172),
                PhaseSegment(startSeconds: 1080, endSeconds: 1260, kind: "recovery", avgPace: 365, avgCadence: 152, avgHR: 145),
                PhaseSegment(startSeconds: 1260, endSeconds: 1560, kind: "work", avgPace: 260, avgCadence: 178, avgHR: 175),
                PhaseSegment(startSeconds: 1560, endSeconds: 1800, kind: "steady", avgPace: 340, avgCadence: 158, avgHR: 140)
            ]
            let run = existingRuns.first
            let segments = run?.signature?.phaseSegments ?? sampleSegments
            NavigationStack {
                ScrollView {
                    RunVarianceMapView(
                        phaseSegments: segments.isEmpty ? sampleSegments : segments,
                        cadenceFloor: run?.signature?.cadenceFloor ?? 152.0,
                        averageCadence: run?.workingAvgCadence ?? 164.0,
                        workoutDuration: run?.duration ?? 1800.0
                    )
                    .padding()
                }
                .navigationTitle("Workout Rhythm")
            }
        case "AUTO_TOUR":
            AppStoreTourView(existingRuns: existingRuns)
        case "DASHBOARD":
            DashboardView(onSync: nil)
        default:
            DashboardView(onSync: nil)
        }
    }
}
