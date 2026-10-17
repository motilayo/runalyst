import SwiftUI
import SwiftData

struct AppStoreTourView: View {
    @Query(sort: \RunRecord.date, order: .reverse) private var queryRuns: [RunRecord]
    var existingRuns: [RunRecord]
    @State private var tourStep: Int = 0
    @State private var isPulsing: Bool = false

    private var allRuns: [RunRecord] {
        queryRuns.isEmpty ? existingRuns : queryRuns
    }

    private var targetRun: RunRecord? {
        allRuns.first { $0.workingAvgCadence > 0 } ?? allRuns.first
    }

    private var baseCadence: Int? {
        if let target = targetRun, target.workingAvgCadence > 0 {
            return Int(target.workingAvgCadence)
        }
        return 165
    }

    var body: some View {
        ZStack {
            switch tourStep {
            case 0:
                DashboardView(onSync: nil)
                    .transition(.opacity)
            case 1:
                if let targetRun {
                    NavigationStack {
                        RunDetailView(runRecord: targetRun)
                    }
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                } else {
                    DashboardView(onSync: nil)
                }
            case 2:
                WorkoutsView()
                .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
            case 3:
                drillReadoutView
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
            case 4:
                NavigationStack {
                    ScrollView {
                        ProgressionChartView(allRuns: allRuns, defaultHorizon: .allTime)
                            .padding()
                    }
                    .navigationTitle("Cadence Progression")
                }
                .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
            default:
                DashboardView(onSync: nil)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(Color.blue.opacity(isPulsing ? 0.3 : 0.05))
                .frame(width: 4, height: 4)
                .padding(4)
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                        isPulsing = true
                    }
                }
        }
        .animation(.easeInOut(duration: 0.6), value: tourStep)
        .task {
            // Choreographed 24.5-second tour for App Store Preview (15-30s Apple requirement)
            try? await Task.sleep(nanoseconds: 4_500_000_000) // 4.5s on Dashboard
            withAnimation { tourStep = 1 }                    // 5.5s on Run Detail (Classification + Timeline + Biometrics)
            try? await Task.sleep(nanoseconds: 5_500_000_000)
            withAnimation { tourStep = 2 }                    // 4.0s on Pre-Run Library
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            withAnimation { tourStep = 3 }                    // 5.0s on Drill Breakdown Modal (5-Point Readout + Timeline + Watch Export)
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            withAnimation { tourStep = 4 }                    // 5.5s on Cadence Progression Chart
            try? await Task.sleep(nanoseconds: 5_500_000_000)
        }
    }

    @ViewBuilder
    private var drillReadoutView: some View {
        let template = DrillTemplate.template(for: .cadencePyramids)
        let targetCadence: String? = baseCadence.map { template.calculateTargetCadence($0) }
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
}
