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
                .padding(.top, 16)
                .padding(.bottom, 20)
            }
            .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Analysis")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingAnalystChat = true
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "bubble.left.and.bubble.right.fill")
                                .font(.system(size: 12, weight: .bold))
                            Text("Coach")
                                .font(.subheadline.weight(.bold))
                        }
                        .foregroundColor(.purple)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.purple.opacity(0.12))
                        .clipShape(Capsule())
                    }
                    .frame(minHeight: 44)
                    .accessibilityLabel("AI Running Coach")
                    .accessibilityHint("Opens AI Biomechanical Analyst and Coach chat")
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(.regularMaterial, for: .navigationBar)
            .sheet(isPresented: $showingAnalystChat) {
                AnalystChatView(mode: .macroCoach)
            }
            .sheet(isPresented: $showingUserProfile) {
                UserProfileView()
            }
        }
    }
}
