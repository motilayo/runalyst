import SwiftUI
import SwiftData

/// Dedicated Analysis & Trends destination displaying deep biomechanical and longitudinal progression charts.
struct AnalysisDashboardView: View {
    @Query(sort: \RunRecord.date, order: .reverse) private var existingRuns: [RunRecord]
    @AppStorage("useMetricSystem") private var useMetricSystem: Bool = Locale.current.measurementSystem == .metric
    @State private var showingUserProfile = false
    @State private var showingAnalystChat = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Longitudinal Progression Chart
                    ProgressionChartView(allRuns: existingRuns)

                    // Overstride & Vertical Oscillation Biomechanics
                    AppleWatchBiomechanicsBridgeView()
                        .padding(.horizontal)

                    // Lifetime Milestones Card
                    LifetimeMilestonesCard(allRuns: existingRuns)
                }
                .padding(.top, 16)
                .padding(.bottom, 100)
            }
            .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Analysis")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !existingRuns.isEmpty {
                        Button {
                            showingAnalystChat = true
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        } label: {
                            Image(systemName: "bubble.left.and.bubble.right.fill")
                                .foregroundColor(.purple)
                        }
                        .accessibilityLabel("AI Coach")
                    }
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(.regularMaterial, for: .navigationBar)
            .sheet(isPresented: $showingAnalystChat) {
                if let latestRun = existingRuns.first {
                    AnalystChatView(runRecord: latestRun)
                }
            }
            .sheet(isPresented: $showingUserProfile) {
                UserProfileView()
            }
        }
    }
}
