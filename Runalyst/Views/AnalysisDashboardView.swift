import SwiftUI
import SwiftData

/// Dedicated Analysis & Trends destination displaying deep biomechanical and longitudinal progression charts.
struct AnalysisDashboardView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query(sort: \RunRecord.date, order: .reverse) private var existingRuns: [RunRecord]
    @AppStorage("useMetricSystem") private var useMetricSystem: Bool = Locale.current.measurementSystem == .metric
    @State private var showingUserProfile = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Goal Readiness & Target Progress
                    GoalReadinessCard(allRuns: existingRuns, onEditGoal: {
                        showingUserProfile = true
                    })

                    // Longitudinal Progression Chart
                    ProgressionChartView(allRuns: existingRuns)

                    // Overstride & Vertical Oscillation Biomechanics
                    AppleWatchBiomechanicsBridgeView()
                        .padding(.horizontal)

                    // Lifetime Milestones Card
                    LifetimeMilestonesCard(allRuns: existingRuns)
                }
                .frame(maxWidth: horizontalSizeClass == .regular ? 880 : .infinity)
                .frame(maxWidth: .infinity)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
            .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Analysis")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(.regularMaterial, for: .navigationBar)
            .sheet(isPresented: $showingUserProfile) {
                UserProfileView()
            }
        }
    }
}
