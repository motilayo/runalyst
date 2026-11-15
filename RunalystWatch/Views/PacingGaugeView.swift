import HealthKit
import RunalystCore
import SwiftUI
import WatchKit

// MARK: - Workout Watch Pages

/// Available horizontal pages in the workout companion pager.
public enum WorkoutHorizontalPage: Hashable, Sendable {
    case controls
    case main
    case nowPlaying
}

/// Available vertical metric pages inside the main workout dashboard.
public enum WorkoutMetricPage: Hashable, Sendable {
    case track
    case metrics
    case chart
}

// MARK: - Pacing Gauge View

/// Hollow workout companion gauge hosting a 3-page horizontal tab view:
/// Controls (left swipe), Main Metrics (vertical pager), Now Playing (right swipe).
public struct PacingGaugeView: View {
    @Environment(WorkoutManager.self) private var workoutManager
    @Environment(PacingViewModel.self) private var pacingViewModel
    @Environment(\.dismiss) private var dismiss

    @AppStorage("watchVoiceCuesEnabled") private var voiceCuesEnabled = true

    @State private var selectedHorizontalPage: WorkoutHorizontalPage = .main
    @State private var selectedMetricPage: WorkoutMetricPage = .track
    @State private var debriefPresentation: DebriefPresentation?
    @State private var isConfirmingEndWorkout = false

    public init() {}

    public var body: some View {
        Group {
            if let item = debriefPresentation {
                RunSummaryView(debrief: item.debrief) {
                    debriefPresentation = nil
                    pacingViewModel.completedDebrief = nil
                    workoutManager.isNavigatingToGauge = false
                    dismiss()
                }
            } else {
                TabView(selection: $selectedHorizontalPage) {
                    WatchControlsView(
                        voiceCuesEnabled: $voiceCuesEnabled,
                        onRequestEndWorkout: { isConfirmingEndWorkout = true }
                    )
                    .tag(WorkoutHorizontalPage.controls)

                    TabView(selection: $selectedMetricPage) {
                        WatchTrackView()
                            .tag(WorkoutMetricPage.track)

                        WatchMetricsView()
                            .tag(WorkoutMetricPage.metrics)

                        WatchTrajectoryChartView()
                            .tag(WorkoutMetricPage.chart)
                    }
                    .tabViewStyle(.verticalPage)
                    .tag(WorkoutHorizontalPage.main)

                    NowPlayingView()
                        .tag(WorkoutHorizontalPage.nowPlaying)
                }
                .tabViewStyle(.page(indexDisplayMode: .automatic))
                .navigationBarBackButtonHidden(true)
                .toolbar(.hidden, for: .navigationBar)
                .ignoresSafeArea(edges: [.horizontal, .bottom])
            }
        }
        .confirmationDialog("End Run?", isPresented: $isConfirmingEndWorkout, titleVisibility: .visible) {
            Button("End Run", role: .destructive) {
                Task {
                    let debrief = await workoutManager.endWorkout() ?? pacingViewModel.completedDebrief
                    if let debrief {
                        debriefPresentation = DebriefPresentation(debrief: debrief)
                    } else {
                        dismiss()
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .onChange(of: pacingViewModel.completedDebrief) { _, newDebrief in
            if let newDebrief, debriefPresentation == nil {
                debriefPresentation = DebriefPresentation(debrief: newDebrief)
            }
        }
    }
}

// MARK: - Debrief Presentation Wrapper

private struct DebriefPresentation: Identifiable {
    let id = UUID()
    let debrief: WatchRunDebrief
}
