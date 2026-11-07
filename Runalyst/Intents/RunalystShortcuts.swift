import AppIntents
import CoreSpotlight
import Foundation
import RunalystCore
import SwiftUI

// MARK: - Spotlight Semantic Index Entity

public struct RunRecordAppEntity: AppEntity, IndexedEntity {
    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Run Workout")
    public static let defaultQuery = RunRecordEntityQuery()

    public var id: String

    @Property(title: "Classification")
    public var classification: String

    @Property(title: "Distance")
    public var formattedDistance: String

    @Property(title: "Average Pace")
    public var formattedPace: String

    @Property(title: "Cadence")
    public var cadenceSPM: Int

    public var workoutDate: Date

    public init(
        id: String,
        classification: String,
        formattedDistance: String,
        formattedPace: String,
        cadenceSPM: Int,
        workoutDate: Date
    ) {
        self.id = id
        self.workoutDate = workoutDate
        self.classification = classification
        self.formattedDistance = formattedDistance
        self.formattedPace = formattedPace
        self.cadenceSPM = cadenceSPM
    }

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(classification)",
            subtitle: "\(formattedDistance) • \(formattedPace) • \(cadenceSPM) SPM"
        )
    }

    public var attributeSet: CSSearchableItemAttributeSet {
        let set = CSSearchableItemAttributeSet(contentType: .item)
        set.title = classification
        set.contentDescription = "\(formattedDistance) • \(formattedPace) • \(cadenceSPM) SPM"
        set.keywords = ["running", "workout", "cadence", "pace", classification]
        return set
    }
}

public struct RunRecordEntityQuery: EntityQuery {
    public init() {}

    public func entities(for identifiers: [String]) async throws -> [RunRecordAppEntity] {
        []
    }

    public func suggestedEntities() async throws -> [RunRecordAppEntity] {
        []
    }
}

// MARK: - App Intents

public struct CheckReadinessIntent: AppIntent {
    public static let title: LocalizedStringResource = "Check Running Readiness"
    public static let description = IntentDescription("Evaluates your daily training readiness and recovery status in Runalyst.")
    public static let openAppWhenRun: Bool = false

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog & ShowsSnippetView {
        let isFatigued = UserDefaults.standard.bool(forKey: "subjectiveFatigueOverrideToday")
        let cachedHeadline = UserDefaults.standard.string(forKey: "cachedMacroHeadline")

        let statusTitle = isFatigued ? "Recovery Priority" : "Ready to Train"
        let summaryText: String
        if isFatigued {
            summaryText = "Subjective fatigue override is active. Prioritize recovery and low-intensity movement today."
        } else if let cached = cachedHeadline, !cached.isEmpty {
            summaryText = cached
        } else {
            summaryText = "Your training balance is optimal. You are clear for your scheduled session."
        }

        return .result(
            value: statusTitle,
            dialog: IntentDialog(stringLiteral: summaryText),
            view: ReadinessSiriSnippetView(
                statusTitle: statusTitle,
                summaryText: summaryText,
                isRecoveryOverride: isFatigued
            )
        )
    }
}

public struct GetPrescribedWorkoutIntent: AppIntent {
    public static let title: LocalizedStringResource = "Get Today's Prescribed Run"
    public static let description = IntentDescription("Retrieves today's prescribed run and technique drill from Runalyst.")
    public static let openAppWhenRun: Bool = false

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog & ShowsSnippetView {
        let isFatigued = UserDefaults.standard.bool(forKey: "subjectiveFatigueOverrideToday")
        let schedule = DrillScheduleCore.schedule(
            for: "cadence_pyramids",
            durationMinutes: 10,
            readinessState: isFatigued ? "acutefatigue" : "productive"
        )

        let dialogText = "Today's prescribed session is \(schedule.displayName) (\(schedule.formattedTotalDuration)): \(schedule.preciseStructureSummary)."

        return .result(
            value: schedule.displayName,
            dialog: IntentDialog(stringLiteral: dialogText),
            view: PrescribedWorkoutSiriSnippetView(
                title: schedule.displayName,
                duration: schedule.formattedTotalDuration,
                cadenceBand: "\(schedule.targetCadenceRange.lowerBound)–\(schedule.targetCadenceRange.upperBound) SPM",
                structureSummary: schedule.preciseStructureSummary
            )
        )
    }
}

public struct ReportSubjectiveDistressIntent: AppIntent {
    public static let title: LocalizedStringResource = "Report Subjective Fatigue"
    public static let description = IntentDescription("Activates the biological safety override in Runalyst when you feel exhausted or unwell.")
    public static let openAppWhenRun: Bool = false

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        UserDefaults.standard.set(true, forKey: "subjectiveFatigueOverrideToday")
        let dialogText = "Safety override active. Today's prescription has been switched to rest and recovery."
        return .result(
            value: "Recovery Day Activated",
            dialog: IntentDialog(stringLiteral: dialogText)
        )
    }
}

// MARK: - App Shortcuts Provider

public struct RunalystAppShortcuts: AppShortcutsProvider {
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CheckReadinessIntent(),
            phrases: [
                "Check my running readiness with \(.applicationName)",
                "How is my recovery in \(.applicationName)?",
                "Am I ready to run with \(.applicationName)?"
            ],
            shortTitle: "Running Readiness",
            systemImageName: "heart.text.square.fill"
        )
        AppShortcut(
            intent: GetPrescribedWorkoutIntent(),
            phrases: [
                "Get today's prescribed run in \(.applicationName)",
                "What is my workout in \(.applicationName)?",
                "Today's run prescription in \(.applicationName)"
            ],
            shortTitle: "Prescribed Run",
            systemImageName: "figure.run"
        )
        AppShortcut(
            intent: ReportSubjectiveDistressIntent(),
            phrases: [
                "Report fatigue to \(.applicationName)",
                "I'm feeling exhausted in \(.applicationName)",
                "Activate recovery day in \(.applicationName)"
            ],
            shortTitle: "Report Fatigue",
            systemImageName: "bed.double.fill"
        )
    }
}

// MARK: - Siri Snippet Views

public struct ReadinessSiriSnippetView: View {
    public let statusTitle: String
    public let summaryText: String
    public let isRecoveryOverride: Bool

    public init(statusTitle: String, summaryText: String, isRecoveryOverride: Bool) {
        self.statusTitle = statusTitle
        self.summaryText = summaryText
        self.isRecoveryOverride = isRecoveryOverride
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: isRecoveryOverride ? "bed.double.fill" : "bolt.heart.fill")
                    .foregroundColor(isRecoveryOverride ? .orange : Color(red: 0.0, green: 0.8, blue: 0.65))
                    .font(.headline)
                Text(statusTitle)
                    .font(.system(.headline, design: .rounded))
                    .foregroundColor(.primary)
                Spacer()
            }
            Text(summaryText)
                .font(.system(.subheadline, design: .rounded))
                .foregroundColor(.secondary)
                .lineLimit(3)
        }
        .padding(12)
    }
}

public struct PrescribedWorkoutSiriSnippetView: View {
    public let title: String
    public let duration: String
    public let cadenceBand: String
    public let structureSummary: String

    public init(title: String, duration: String, cadenceBand: String, structureSummary: String) {
        self.title = title
        self.duration = duration
        self.cadenceBand = cadenceBand
        self.structureSummary = structureSummary
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(.headline, design: .rounded))
                    .foregroundColor(.primary)
                Spacer()
                Text(duration)
                    .font(.system(.subheadline, design: .rounded).monospacedDigit())
                    .foregroundColor(.secondary)
            }
            HStack(spacing: 6) {
                Image(systemName: "metronome.fill")
                    .foregroundColor(.green)
                    .font(.caption)
                Text(cadenceBand)
                    .font(.system(.caption, design: .rounded).monospacedDigit())
                    .foregroundColor(.green)
            }
            Text(structureSummary)
                .font(.system(.caption, design: .rounded))
                .foregroundColor(.secondary)
                .lineLimit(2)
        }
        .padding(12)
    }
}
