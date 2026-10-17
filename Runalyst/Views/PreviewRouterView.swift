import SwiftUI
import SwiftData

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

    @Query(sort: \RunRecord.date, order: .reverse) private var queriedRuns: [RunRecord]

    private var effectiveRuns: [RunRecord] {
        queriedRuns.isEmpty ? existingRuns : queriedRuns
    }

    var body: some View {
        switch previewScreen {
        case "RUN_DETAIL":
            RunDetailPreviewContainer(targetType: nil)
        case "RUN_DETAIL_INTERVALS":
            RunDetailPreviewContainer(targetType: "Intervals")
        case "RUN_DETAIL_FARTLEK":
            RunDetailPreviewContainer(targetType: "Fartlek")
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
        case "PROFILE":
            NavigationStack {
                UserProfileView()
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
        case "WORKOUTS":
            WorkoutsView()
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
        case "ANALYSIS":
            AnalysisDashboardView()
        case "PROGRESSION_EXPLAINER":
            MetricExplainerSheet(
                title: "Efficiency Factor Progression",
                mode: "Steady Effort • 30 Days",
                overview: "Efficiency Factor (Speed ÷ Heart Rate) tracks physiological economy over time. By comparing how fast you run against the cardiovascular effort required, Runalyst shows whether your aerobic engine is becoming more efficient.",
                modeContext: "Isolated to Steady Effort runs across 30 Days to eliminate pacing noise and ensure authentic physiological comparisons.",
                whyItMatters: "Aerobic Economy: As aerobic endurance improves through base training, you run faster at the same heart rate, or maintain the same speed at a lower heart rate. A declining trend signals accumulated fatigue, dehydration, or heat stress.",
                targetRange: "Target: Upward or stable trajectory across training cycles.\n\n• Rising: You are getting fitter and faster with less cardiovascular effort.\n• Dropping: You may be tired, overtraining, or battling heat/dehydration.",
                userMetricDisplay: "1.48 EF"
            )
        case "MILESTONES":
            NavigationStack {
                ScrollView {
                    LifetimeMilestonesCard(allRuns: existingRuns)
                        .padding(.top, 16)
                }
                .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
                .navigationTitle("Milestones")
                .navigationBarTitleDisplayMode(.inline)
            }
        default:
            DashboardView(onSync: nil)
        }
    }
}

private struct RunDetailPreviewContainer: View {
    let targetType: String?
    @Query(sort: \RunRecord.date, order: .reverse) private var runs: [RunRecord]

    var body: some View {
        let matchingRun = runs.first(where: { run in
            if targetType == "Intervals" || targetType == "Fartlek" {
                let isRecovery = run.detectedTypeRaw == "Recovery Run" || (run.percentZone4 <= 0.02 && run.workingAvgHeartRate > 0 && run.workingAvgHeartRate <= 135 && run.duration >= 600)
                let hasWorkReps = run.signature?.phaseSegments.contains(where: { $0.kind == "work" && $0.avgPace > 0 }) ?? false
                let hasPrescribedDrill = run.framboiseTags.contains("prescribedDrill")
                return run.evaluationModality == .intervals && hasWorkReps && !isRecovery && !hasPrescribedDrill
            }
            if let target = targetType {
                return run.detectedTypeRaw == target
            }
            return true
        }) ?? runs.first

        if let run = matchingRun {
            NavigationStack {
                RunDetailView(runRecord: run)
            }
        } else {
            ProgressView("Loading run...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(UIColor.systemGroupedBackground))
        }
    }
}
