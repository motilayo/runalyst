import Foundation
import Observation
import RunalystCore

// MARK: - Pacing View Model

/// Main-actor observable view model binding `AdaptivePacingCore` snapshots to hollow watchOS views.
@MainActor
@Observable
public final class PacingViewModel {
    public var displayState: PacingDisplayState
    public var latestEvents: [PacingEvent] = []
    public var isPaused: Bool = false
    public var completedDebrief: WatchRunDebrief?

    public init(targetPaceSecondsPerKm: Int? = nil, adjustmentsEnabled: Bool = true) {
        self.displayState = .initial(
            targetPaceSecondsPerKm: targetPaceSecondsPerKm,
            adjustmentsEnabled: adjustmentsEnabled
        )
        self.completedDebrief = nil
    }

    public func setCompletedDebrief(_ debrief: WatchRunDebrief?) {
        self.completedDebrief = debrief
    }

    /// Receives new core output, updates presentation state, and triggers multimodal feedback.
    public func update(events: [PacingEvent], display: PacingDisplayState) {
        self.latestEvents = events
        self.displayState = display
        FeedbackDispatcher.shared.dispatch(events: events)
    }

    /// Resets state for a new session.
    public func reset(targetPaceSecondsPerKm: Int? = nil, adjustmentsEnabled: Bool = true) {
        self.displayState = .initial(
            targetPaceSecondsPerKm: targetPaceSecondsPerKm,
            adjustmentsEnabled: adjustmentsEnabled
        )
        self.latestEvents = []
        self.isPaused = false
        self.completedDebrief = nil
    }
}
