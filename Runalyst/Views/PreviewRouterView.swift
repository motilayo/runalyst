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
        case "RUN_DETAIL_DRILL_INTERVALS":
            RunDetailPreviewContainer(targetType: "DrillIntervals")
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
        case "GLASS_BOX":
            GlassBoxExplainerSheet(
                title: "30-Day Aerobic Profile",
                categoryBadge: "Longitudinal Adaptation",
                whatSummary: "Your rolling 30-day baseline captures aerobic base stabilization and metabolic efficiency.",
                whyItMatters: "Consistent volume at conversational heart rates establishes capillary density and neuromuscular economy while protecting joint health from impact spikes.",
                howItWorks: "Runalyst calculates rolling 30-day time-locked medians across pause-trimmed Working Pace, heart rate, and cadence to determine your physiological trajectory.",
                formula: "Efficiency Factor = Speed (m/s) ÷ (Heart Rate - Resting HR)",
                targetRange: "Cadence Floor: ≥ 156–160 SPM • Stable or Rising Efficiency Factor",
                liveMetricDisplay: "166 SPM • 5:42/km"
            )
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
        case "ANALYST_MACRO":
            AnalystChatView(mode: .macroCoach)
        case "WORKOUTS":
            WorkoutsView()
        case "REST_DAY":
            let restSession = PrescribedDailySession(
                targetGoal: "General Fitness",
                sessionTitle: "Rest & Structural Recovery Day",
                durationBand: "No Run Prescribed",
                paceBand: "No Pacing Target",
                hrCap: "HR: Rest / < 125 BPM",
                cadenceFloor: 0,
                groundedRationale: "You've banked 89 min in the last 48 hours (70% of your 126 min/week average). A rest day allows deep recovery, glycogen replenishment, and joint remodeling to prevent cumulative overload.",
                readinessStateText: "Scheduled Structural Recovery",
                readinessTriggerLead: "48-Hour Volume Compression (70% of weekly baseline)",
                primerDrillId: .recoveryJog,
                primerDrillTitle: "Optional Recovery Jog",
                primerTargetCadence: "Zone 1 HR",
                primerWorkDescription: "15 min active recovery jog • Keep HR in Zone 1",
                primerPhasesDuration: "15 min (Optional)",
                isTrimmed: true,
                microcycle: [],
                mainSessionTemplateId: .recoveryJog,
                mainRunDurationMinutes: 15,
                completedPrimerRun: nil,
                isRestDay: true,
                dayLabel: "Today",
                isToday: true,
                readinessState: .acuteFatigue
            )
            NavigationStack {
                ScrollView {
                    PrescribedSessionCardView(
                        session: restSession,
                        isToday: true,
                        preferredWorkoutIsIndoor: .constant(true)
                    )
                    .padding()
                }
                .navigationTitle("Workouts")
            }
        case "WORKOUTS_COMPLETED_TODAY":
            WorkoutsCompletedTodayPreview(existingRuns: existingRuns)
        case "READINESS":
            GlassBoxExplainerSheet(
                title: "Training Load & Readiness",
                categoryBadge: "Acute Readiness",
                whatSummary: "We compare your running effort this week against your past month to evaluate whether your body is primed to adapt or needs recovery.",
                whyItMatters: "Spiking weekly mileage or intensity too quickly elevates musculoskeletal injury risk. Maintaining your ACWR within the sweet spot (0.8–1.3) safely builds durable aerobic fitness.",
                howItWorks: "Banister impulse-response model calculates 7-day acute volume divided by rolling 28-day chronic volume with time-decay weighting.",
                formula: "ACWR = Acute Load (7 Days) ÷ Chronic Load (28 Days)",
                targetRange: "Optimal Zone: 0.8–1.3 • Overreaching Warning: > 1.5",
                liveMetricDisplay: "ACWR: 1.02 (Optimal)"
            )
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
            GlassBoxExplainerSheet(
                title: "Efficiency Factor Progression",
                categoryBadge: "Steady Effort • 30 Days",
                whatSummary: "Efficiency Factor (Speed ÷ Heart Rate) tracks physiological economy over time. By comparing how fast you run against the cardiovascular effort required, Runalyst shows whether your aerobic engine is becoming more efficient.",
                whyItMatters: "As aerobic endurance improves through base training, you run faster at the same heart rate, or maintain the same speed at a lower heart rate. A declining trend signals accumulated fatigue, dehydration, or heat stress.",
                howItWorks: "Isolated to Steady Effort runs across 30 Days to eliminate pacing noise and ensure authentic physiological comparisons.",
                formula: "Efficiency Factor = Speed (m/min) ÷ Heart Rate (BPM)",
                targetRange: "Target: Upward or stable trajectory across training cycles.",
                liveMetricDisplay: "1.48 EF"
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
            if targetType == "DrillIntervals" {
                let hasWorkReps = run.signature?.phaseSegments.contains(where: { $0.kind == "work" && $0.avgPace > 0 }) ?? false
                return run.evaluationModality == .intervals && hasWorkReps
            }
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
                    .onAppear {
                        if targetType == "DrillIntervals" && run.prescribedDrillName == nil {
                            WorkoutBridge.linkDrill(to: run, drillId: .rhythmIntervals, baselineCadence: 160)
                        }
                    }
            }
        } else {
            ProgressView("Loading run...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(UIColor.systemGroupedBackground))
        }
    }
}

private struct WorkoutsCompletedTodayPreview: View {
    let existingRuns: [RunRecord]

    var body: some View {
        let primerSnap = RunRecordSnapshot(
            id: UUID(),
            date: Date().addingTimeInterval(-3600),
            workoutType: "Indoor Cadence Pyramids",
            durationFormatted: "15:03",
            distanceFormatted: "1.46 km",
            letterGrade: "A",
            isIndoor: true,
            isPrimerDrill: true
        )
        let mainSnap = RunRecordSnapshot(
            id: UUID(),
            date: Date(),
            workoutType: "Indoor Easy Run",
            durationFormatted: "40:01",
            distanceFormatted: "4.48 km",
            letterGrade: "A",
            isIndoor: true,
            isPrimerDrill: false,
            additionalCompletedRuns: [primerSnap]
        )
        let dummyState = SessionSynthesisEngine.evaluateDailyState(
            runRecords: existingRuns,
            activeGoal: "Base Building",
            experienceLevel: "Intermediate",
            useMetric: true,
            userHeightCm: 175.0,
            now: Date()
        )
        let dummyTomorrow: PrescribedDailySession = {
            switch dummyState {
            case .preRun(let s): return s
            case .completedToday(_, let s): return s
            }
        }()

        WorkoutsView(overrideDailyState: .completedToday(completedRun: mainSnap, tomorrowSession: dummyTomorrow))
    }
}
