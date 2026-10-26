import Foundation
import RunalystCore
import SwiftData

public typealias HistoricalSortMetric = HistoricalSortMetricCore
public typealias HistoricalSortDirection = HistoricalSortDirectionCore
public typealias HistoricalEnvironmentFilter = HistoricalEnvironmentFilterCore

public typealias WorkoutMathResult = WorkoutMathResultCore
public typealias WorkoutMathCalculator = WorkoutMathCalculatorCore

struct HistoricalQueryCriteria: Sendable, Equatable {
    typealias SortMetric = HistoricalSortMetric
    typealias Direction = HistoricalSortDirection
    typealias Environment = HistoricalEnvironmentFilter

    var core: HistoricalQueryCriteriaCore

    var metric: SortMetric {
        get { core.metric }
        set { core.metric = newValue }
    }
    var direction: Direction {
        get { core.direction }
        set { core.direction = newValue }
    }
    var environment: Environment {
        get { core.environment }
        set { core.environment = newValue }
    }
    var modality: String? {
        get { core.modality }
        set { core.modality = newValue }
    }
    var targetYear: Int? {
        get { core.targetYear }
        set { core.targetYear = newValue }
    }
    var targetMonth: Int? {
        get { core.targetMonth }
        set { core.targetMonth = newValue }
    }
    var targetDay: Int? {
        get { core.targetDay }
        set { core.targetDay = newValue }
    }
    var limit: Int {
        get { core.limit }
        set { core.limit = newValue }
    }
    var requiresPriorToCurrentRun: Bool {
        get { core.requiresPriorToCurrentRun }
        set { core.requiresPriorToCurrentRun = newValue }
    }

    init(
        metric: SortMetric = .date,
        direction: Direction = .descending,
        environment: Environment = .all,
        modality: String? = nil,
        targetYear: Int? = nil,
        targetMonth: Int? = nil,
        targetDay: Int? = nil,
        limit: Int = 1,
        requiresPriorToCurrentRun: Bool = false
    ) {
        self.core = HistoricalQueryCriteriaCore(
            metric: metric,
            direction: direction,
            environment: environment,
            modality: modality,
            targetYear: targetYear,
            targetMonth: targetMonth,
            targetDay: targetDay,
            limit: limit,
            requiresPriorToCurrentRun: requiresPriorToCurrentRun
        )
    }

    init(core: HistoricalQueryCriteriaCore) {
        self.core = core
    }

    static func parse(from query: String, relativeTo currentRun: RunRecord? = nil) -> HistoricalQueryCriteria {
        let core = HistoricalQueryCriteriaCore.parse(
            from: query,
            currentRunIsIndoor: currentRun?.isIndoor,
            referenceDate: currentRun?.date
        )
        return HistoricalQueryCriteria(core: core)
    }
}

extension RunRecord {
    var toHistoricalCandidateSample: HistoricalCandidateSampleCore {
        let pace = workingAvgPace > 0 ? workingAvgPace : rawAvgPace
        let cad = workingAvgCadence > 0 ? workingAvgCadence : rawAvgCadence
        let hr = workingAvgHeartRate > 0 ? workingAvgHeartRate : rawAvgHeartRate
        return HistoricalCandidateSampleCore(
            id: id,
            date: date,
            durationSeconds: duration,
            distanceMeters: totalDistanceMeters,
            paceSecondsPerKm: pace,
            cadenceSPM: cad,
            heartRateBPM: hr,
            isIndoor: isIndoor ?? false,
            efficiencyFactor: efficiencyFactor,
            classification: normalizedClassification,
            detectedTypeRaw: detectedTypeRaw,
            isPrimerWorkout: isPrimerWorkout
        )
    }
}

/// Deterministic matching and mathematical comparison between the active workout and a historical workout.
/// Adheres strictly to the "Thick Client, Thin AI" architectural doctrine:
/// Swift performs the data extraction, date parsing, and delta math;
/// FoundationModels performs the semantic synthesis and conversational coaching.
@MainActor
struct HistoricalRunMatcher {

    struct TelemetryData: Sendable {
        let date: Date
        let formattedDate: String
        let weekday: String
        let classification: String
        let paceSecondsPerKm: Double
        let paceFormatted: String
        let cadenceSPM: Int
        let heartRateBPM: Int
        let distanceMeters: Double
        let durationSeconds: Double
        let isIndoor: Bool
        let efficiencyFactor: Double?

        var asSummary: HistoricalRunSummary {
            let distKm = Double(String(format: "%.2f", distanceMeters / 1000.0)) ?? (distanceMeters / 1000.0)
            let durMin = max(1, Int((durationSeconds / 60.0).rounded()))
            let efFormatted = efficiencyFactor.map { String(format: "%.2f m/beat", $0) }
            return HistoricalRunSummary(
                date: formattedDate,
                formatted_date: formattedDate,
                weekday: weekday,
                classification: classification,
                environment: isIndoor ? "Indoor Treadmill" : "Outdoor",
                is_indoor: isIndoor,
                distance_km: distKm,
                duration_minutes: durMin,
                pace: paceFormatted,
                cadence_spm: cadenceSPM,
                heart_rate_bpm: heartRateBPM,
                efficiency_factor: efficiencyFactor,
                efficiency_factor_formatted: efFormatted
            )
        }
    }

    struct ComparisonTelemetry: Sendable {
        let current: TelemetryData
        let prior: TelemetryData

        // Deterministic deltas computed in Swift
        let paceDeltaSeconds: Int        // prior - current: positive = current is faster
        let cadenceDelta: Int            // current - prior: positive = current is higher
        let heartRateDelta: Int          // current - prior: positive = current is higher
        let distanceDeltaMeters: Double
        let durationDeltaSeconds: Double

        /// Strongly-typed mathematical comparison facts.
        var comparisonFacts: RunComparisonFacts {
            let envCurrent = current.isIndoor ? "Indoor Treadmill" : "Outdoor"
            let envPrior = prior.isIndoor ? "Indoor Treadmill" : "Outdoor"

            let cal = Calendar.current
            let daysDiff = cal.dateComponents([.day], from: cal.startOfDay(for: prior.date), to: cal.startOfDay(for: current.date)).day ?? 0
            let timingContrast: String
            if daysDiff > 0 {
                timingContrast = "\(daysDiff) day\(daysDiff == 1 ? "" : "s") after prior"
            } else if daysDiff < 0 {
                timingContrast = "\(abs(daysDiff)) day\(abs(daysDiff) == 1 ? "" : "s") before prior"
            } else {
                timingContrast = "Same day"
            }

            let sameClassification = current.classification.caseInsensitiveCompare(prior.classification) == .orderedSame
            let classContrast = sameClassification ? "Matched (\(current.classification))" : "Different (\(current.classification) vs \(prior.classification))"

            let currentDistKm = Double(String(format: "%.2f", current.distanceMeters / 1000.0)) ?? (current.distanceMeters / 1000.0)
            let priorDistKm = Double(String(format: "%.2f", prior.distanceMeters / 1000.0)) ?? (prior.distanceMeters / 1000.0)
            let distDiffKm = Double(String(format: "%.2f", currentDistKm - priorDistKm)) ?? (currentDistKm - priorDistKm)
            let durDiffMin = Int((current.durationSeconds - prior.durationSeconds) / 60)

            let pacePercent = prior.paceSecondsPerKm > 0 ? Int(round(Double(abs(paceDeltaSeconds)) / prior.paceSecondsPerKm * 100.0)) : 0

            let paceComp: String
            if paceDeltaSeconds > 0 {
                paceComp = "\(paceDeltaSeconds)s/km faster in current run (\(current.paceFormatted) in \(envCurrent) vs \(prior.paceFormatted) in \(envPrior))"
            } else if paceDeltaSeconds < 0 {
                paceComp = "\(abs(paceDeltaSeconds))s/km slower in current run (\(current.paceFormatted) in \(envCurrent) vs \(prior.paceFormatted) in \(envPrior))"
            } else {
                paceComp = "identical pace (\(current.paceFormatted))"
            }

            let cadComp: String
            let cadDeltaOpt: Int?
            if current.cadenceSPM > 0 && prior.cadenceSPM > 0 {
                cadDeltaOpt = cadenceDelta
                if cadenceDelta > 0 {
                    cadComp = "+\(cadenceDelta) SPM higher turnover in current run (\(current.cadenceSPM) SPM in \(envCurrent) vs \(prior.cadenceSPM) SPM in \(envPrior))"
                } else if cadenceDelta < 0 {
                    cadComp = "\(abs(cadenceDelta)) SPM lower turnover in current run (\(current.cadenceSPM) SPM in \(envCurrent) vs \(prior.cadenceSPM) SPM in \(envPrior))"
                } else {
                    cadComp = "matched turnover at \(current.cadenceSPM) SPM (\(current.cadenceSPM) SPM in \(envCurrent) vs \(prior.cadenceSPM) SPM in \(envPrior))"
                }
            } else {
                cadDeltaOpt = nil
                cadComp = "cadence unavailable for comparison (unrecorded sensor telemetry)"
            }

            let hrComp: String
            let hrDeltaOpt: Int?
            if current.heartRateBPM > 0 && prior.heartRateBPM > 0 {
                hrDeltaOpt = heartRateDelta
                if heartRateDelta > 0 {
                    hrComp = "+\(heartRateDelta) BPM higher cardiac cost in current run (\(current.heartRateBPM) BPM in \(envCurrent) vs \(prior.heartRateBPM) BPM in \(envPrior))"
                } else if heartRateDelta < 0 {
                    hrComp = "\(abs(heartRateDelta)) BPM lower cardiovascular demand in current run (\(current.heartRateBPM) BPM in \(envCurrent) vs \(prior.heartRateBPM) BPM in \(envPrior))"
                } else {
                    hrComp = "matched cardiac cost at \(current.heartRateBPM) BPM (\(current.heartRateBPM) BPM in \(envCurrent) vs \(prior.heartRateBPM) BPM in \(envPrior))"
                }
            } else {
                hrDeltaOpt = nil
                hrComp = "heart rate unavailable for comparison (unrecorded sensor telemetry)"
            }

            let distComp: String
            if distDiffKm > 0 {
                distComp = "+\(String(format: "%.2f", distDiffKm)) km longer in current run (\(String(format: "%.2f", currentDistKm)) vs \(String(format: "%.2f", priorDistKm)) km)"
            } else if distDiffKm < 0 {
                distComp = "\(String(format: "%.2f", abs(distDiffKm))) km shorter in current run (\(String(format: "%.2f", currentDistKm)) vs \(String(format: "%.2f", priorDistKm)) km)"
            } else {
                distComp = "matched distance at \(String(format: "%.2f", currentDistKm)) km"
            }

            let durComp: String
            if durDiffMin > 0 {
                durComp = "+\(durDiffMin) min longer in duration"
            } else if durDiffMin < 0 {
                durComp = "\(abs(durDiffMin)) min shorter in duration"
            } else {
                durComp = "matched duration"
            }

            var summaryParts: [String] = [
                paceDeltaSeconds >= 0 ? "\(paceDeltaSeconds)s/km faster (+\(pacePercent)%)" : "\(abs(paceDeltaSeconds))s/km slower (-\(pacePercent)%)"
            ]
            if let cd = cadDeltaOpt {
                summaryParts.append("\(cd >= 0 ? "+\(cd)" : "\(cd)") SPM turnover")
            }
            if let hd = hrDeltaOpt {
                summaryParts.append("\(hd >= 0 ? "+\(hd)" : "\(hd)") BPM cardiac cost")
            }
            let summaryStr = summaryParts.joined(separator: ", ")

            let deltas = TelemetryDeltaFacts(
                pace_delta_seconds_per_km: paceDeltaSeconds,
                pace_percentage_difference: pacePercent,
                pace_comparison: paceComp,
                cadence_delta_spm: cadDeltaOpt,
                cadence_comparison: cadComp,
                heart_rate_delta_bpm: hrDeltaOpt,
                heart_rate_comparison: hrComp,
                distance_delta_km: distDiffKm,
                distance_comparison: distComp,
                duration_delta_minutes: durDiffMin,
                duration_comparison: durComp,
                summary: summaryStr
            )

            return RunComparisonFacts(
                current_run: current.asSummary,
                prior_run: prior.asSummary,
                deltas: deltas,
                days_between: abs(daysDiff),
                timing_contrast: timingContrast,
                classification_contrast: classContrast,
                summary: summaryStr
            )
        }

        /// Structured mathematical and telemetry facts for FoundationModels tool injection.
        var structuredTelemetryFacts: String {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            if let data = try? encoder.encode(comparisonFacts),
               let json = String(data: data, encoding: .utf8) {
                return json
            }
            return "{}"
        }
    }

    struct PerformanceArcAnalysis: Sendable {
        let totalRunsInPast30Days: Int
        let bestRun: TelemetryData?
        let worstRun: TelemetryData?
        let currentRun: TelemetryData?

        /// Strongly-typed mathematical performance arc facts.
        var arcFacts: PerformanceArcFacts {
            guard let current = currentRun else {
                return PerformanceArcFacts(total_runs_in_past_30_days: 0)
            }
            guard let best = bestRun else {
                return PerformanceArcFacts(
                    total_runs_in_past_30_days: totalRunsInPast30Days,
                    current_workout: current.asSummary,
                    summary: "1 workout recorded in past 30 days"
                )
            }

            let worst = worstRun ?? current

            let paceDeltaSec = Int(worst.paceSecondsPerKm.rounded() - best.paceSecondsPerKm.rounded())
            let bestVsWorstPacePercent = worst.paceSecondsPerKm > 0 ? Int(round(Double(abs(paceDeltaSec)) / worst.paceSecondsPerKm * 100.0)) : 0
            let cadDelta: Int? = (best.cadenceSPM > 0 && worst.cadenceSPM > 0) ? (best.cadenceSPM - worst.cadenceSPM) : nil
            let hrDelta: Int? = (worst.heartRateBPM > 0 && best.heartRateBPM > 0) ? (worst.heartRateBPM - best.heartRateBPM) : nil

            let bestVsWorstCadComp: String = {
                guard let cd = cadDelta else { return "Cadence unavailable for comparison (unrecorded telemetry)" }
                return "Turnover was \(abs(cd)) SPM higher in best vs toughest (\(best.cadenceSPM) SPM vs \(worst.cadenceSPM) SPM)"
            }()

            let bestVsWorstHRComp: String = {
                guard let hd = hrDelta else { return "Cardiac cost unavailable for comparison (unrecorded telemetry)" }
                return "Cardiac load was \(hd) BPM lower in best vs toughest (\(best.heartRateBPM) BPM vs \(worst.heartRateBPM) BPM)"
            }()

            var bestVsWorstSummaryParts = ["Best workout was \(abs(paceDeltaSec))s/km faster (\(bestVsWorstPacePercent)% faster pace) than toughest (\(best.paceFormatted) vs \(worst.paceFormatted))"]
            if let cd = cadDelta {
                bestVsWorstSummaryParts.append("with +\(abs(cd)) SPM higher turnover")
            }
            let bestVsWorstSummary = bestVsWorstSummaryParts.joined(separator: " ")

            let bestVsWorstDeltas = TelemetryDeltaFacts(
                pace_delta_seconds_per_km: paceDeltaSec,
                pace_percentage_difference: bestVsWorstPacePercent,
                pace_comparison: "Best workout was \(abs(paceDeltaSec))s/km faster (\(bestVsWorstPacePercent)% faster pace) than toughest (\(best.paceFormatted) vs \(worst.paceFormatted))",
                cadence_delta_spm: cadDelta,
                cadence_comparison: bestVsWorstCadComp,
                heart_rate_delta_bpm: hrDelta.map { -$0 },
                heart_rate_comparison: bestVsWorstHRComp,
                distance_delta_km: Double(String(format: "%.2f", (best.distanceMeters - worst.distanceMeters) / 1000.0)) ?? 0.0,
                distance_comparison: "Distance difference: \(String(format: "%.2f", (best.distanceMeters - worst.distanceMeters) / 1000.0)) km",
                duration_delta_minutes: Int((best.durationSeconds - worst.durationSeconds) / 60),
                duration_comparison: "Duration difference: \(Int((best.durationSeconds - worst.durationSeconds) / 60)) min",
                summary: bestVsWorstSummary
            )

            let currentVsBestDeltas: TelemetryDeltaFacts? = {
                guard current.date != best.date else { return nil }
                let currentPaceDiff = Int(current.paceSecondsPerKm.rounded() - best.paceSecondsPerKm.rounded())
                let pacePercent = current.paceSecondsPerKm > 0 ? Int(round(Double(abs(currentPaceDiff)) / current.paceSecondsPerKm * 100.0)) : 0
                let currentCadDiff: Int? = (best.cadenceSPM > 0 && current.cadenceSPM > 0) ? (best.cadenceSPM - current.cadenceSPM) : nil
                let currentHRDiff: Int? = (current.heartRateBPM > 0 && best.heartRateBPM > 0) ? (current.heartRateBPM - best.heartRateBPM) : nil

                let paceComp = currentPaceDiff > 0
                    ? "Best session was \(abs(currentPaceDiff))s/km faster (\(pacePercent)% faster pace) than current workout (\(best.paceFormatted) vs \(current.paceFormatted))"
                    : (currentPaceDiff < 0 ? "Current workout was \(abs(currentPaceDiff))s/km faster (\(pacePercent)% faster pace) than prior 30-day best (\(current.paceFormatted) vs \(best.paceFormatted))" : "Pace matched prior 30-day best at \(current.paceFormatted)")
                let cadComp: String = {
                    guard let ccd = currentCadDiff else { return "Cadence unavailable for comparison" }
                    return ccd > 0
                        ? "Turnover was \(ccd) SPM higher in best session vs current workout (\(best.cadenceSPM) SPM vs \(current.cadenceSPM) SPM)"
                        : (ccd < 0 ? "Current workout turnover was \(abs(ccd)) SPM higher than prior best (\(current.cadenceSPM) SPM vs \(best.cadenceSPM) SPM)" : "Turnover matched at \(current.cadenceSPM) SPM")
                }()
                let hrComp: String = {
                    guard let chrd = currentHRDiff else { return "Heart rate unavailable for comparison" }
                    return chrd > 0
                        ? "Cardiac cost was +\(chrd) BPM higher in current workout vs best session (\(current.heartRateBPM) BPM vs \(best.heartRateBPM) BPM)"
                        : (chrd < 0 ? "Cardiac cost was \(abs(chrd)) BPM lower in current workout vs best session (\(current.heartRateBPM) BPM vs \(best.heartRateBPM) BPM)" : "Heart rate matched at \(current.heartRateBPM) BPM")
                }()

                var curBestSummaryParts = ["30-day best was \(abs(currentPaceDiff))s/km faster (\(pacePercent)% faster pace)"]
                if let ccd = currentCadDiff {
                    curBestSummaryParts.append("with +\(abs(ccd)) SPM turnover")
                }
                let curBestSummary = curBestSummaryParts.joined(separator: " ")

                return TelemetryDeltaFacts(
                    pace_delta_seconds_per_km: currentPaceDiff,
                    pace_percentage_difference: pacePercent,
                    pace_comparison: paceComp,
                    cadence_delta_spm: currentCadDiff,
                    cadence_comparison: cadComp,
                    heart_rate_delta_bpm: currentHRDiff,
                    heart_rate_comparison: hrComp,
                    distance_delta_km: Double(String(format: "%.2f", (best.distanceMeters - current.distanceMeters) / 1000.0)) ?? 0.0,
                    distance_comparison: "Distance difference: \(String(format: "%.2f", (best.distanceMeters - current.distanceMeters) / 1000.0)) km",
                    duration_delta_minutes: Int((best.durationSeconds - current.durationSeconds) / 60),
                    duration_comparison: "Duration difference: \(Int((best.durationSeconds - current.durationSeconds) / 60)) min",
                    summary: curBestSummary
                )
            }()

            let bestCadenceSuffix = best.cadenceSPM > 0 ? ", \(best.cadenceSPM) SPM" : ""
            return PerformanceArcFacts(
                total_runs_in_past_30_days: totalRunsInPast30Days,
                best_performance_workout: best.asSummary,
                toughest_workout: worst.asSummary,
                current_workout: current.asSummary,
                current_vs_best: currentVsBestDeltas,
                best_vs_toughest: bestVsWorstDeltas,
                summary: "30-day arc: \(totalRunsInPast30Days) workouts recorded. Best on \(best.weekday) (\(best.paceFormatted)\(bestCadenceSuffix))."
            )
        }

        /// Structured mathematical and telemetry facts for FoundationModels tool injection.
        var structuredTelemetryFacts: String {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            if let data = try? encoder.encode(arcFacts),
               let json = String(data: data, encoding: .utf8) {
                return json
            }
            return "{}"
        }
    }

    /// Parses potential two-run comparison targets from a single query string.
    static func parseComparisonTargets(from query: String) -> (targetA: String, targetB: String)? {
        HistoricalQueryCore.parseComparisonTargets(from: query)
    }

    /// Compares two arbitrary workouts (e.g. last outdoor run vs last indoor run) from the stored database.
    static func compareRuns(
        queryA: String,
        queryB: String,
        relativeTo currentRun: RunRecord?,
        in context: ModelContext?
    ) -> ComparisonTelemetry? {
        guard let context = context else { return nil }
        let descriptor = FetchDescriptor<RunRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        guard let allRuns = try? context.fetch(descriptor), !allRuns.isEmpty else { return nil }

        // Find runA
        guard let runA = findRun(matching: queryA, in: allRuns, relativeTo: nil) else { return nil }

        // Find runB from the remaining runs
        let remainingRuns = allRuns.filter { $0.id != runA.id }
        guard let runB = findRun(matching: queryB, in: remainingRuns, relativeTo: nil) else { return nil }

        // Order chronologically so the newer run is evaluated against the older run as baseline
        let newer: RunRecord
        let older: RunRecord
        if runA.date >= runB.date {
            newer = runA
            older = runB
        } else {
            newer = runB
            older = runA
        }

        return compare(current: newer, with: older)
    }

    /// Finds a historical run in the model context matching the user's natural language query.
    static func findRun(
        matching query: String,
        relativeTo currentRun: RunRecord? = nil,
        in context: ModelContext?
    ) -> RunRecord? {
        guard let context = context else { return nil }
        let descriptor = FetchDescriptor<RunRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        guard let allRuns = try? context.fetch(descriptor) else { return nil }

        let pool = currentRun.map { cr in allRuns.filter { $0.id != cr.id } } ?? allRuns
        guard !pool.isEmpty else { return nil }

        return findRun(matching: query, in: pool, relativeTo: currentRun)
    }

    typealias HistoricalQueryCriteria = Runalyst.HistoricalQueryCriteria

    /// Finds a matching run within an explicit pool of runs using deterministic composable query criteria.
    static func findRun(
        matching criteria: HistoricalQueryCriteria,
        in pool: [RunRecord],
        relativeTo currentRun: RunRecord? = nil
    ) -> RunRecord? {
        guard !pool.isEmpty else { return nil }
        let candidateSamples = pool.map(\.toHistoricalCandidateSample)
        let sortedSamples = HistoricalQueryCore.filterAndSort(
            candidates: candidateSamples,
            criteria: criteria.core,
            referenceDate: currentRun?.date
        )
        guard let firstMatch = sortedSamples.first else { return nil }
        return pool.first { $0.id == firstMatch.id }
    }

    /// Finds a matching run within an explicit pool of runs.
    static func findRun(
        matching query: String,
        in pool: [RunRecord],
        relativeTo currentRun: RunRecord? = nil
    ) -> RunRecord? {
        let criteria = HistoricalQueryCriteria.parse(from: query, relativeTo: currentRun)
        return findRun(matching: criteria, in: pool, relativeTo: currentRun)
    }

    /// Extracts standardized telemetry data from a RunRecord.
    static func extractTelemetry(from run: RunRecord) -> TelemetryData {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "MMMM d, yyyy"

        let weekdayFormatter = DateFormatter()
        weekdayFormatter.locale = Locale(identifier: "en_US_POSIX")
        weekdayFormatter.dateFormat = "EEEE"

        let currentFormattedDate = dateFormatter.string(from: run.date)
        let currentWeekday = weekdayFormatter.string(from: run.date)

        let currentType: String = {
            if run.isPrimerWorkout {
                return run.prescribedDrillName.map { "\($0) (Primer)" } ?? "\(run.normalizedClassification) (Primer)"
            }
            return run.detectedTypeRaw.isEmpty ? run.normalizedClassification : run.detectedTypeRaw
        }()
        let currentPace = run.workingAvgPace > 0 ? run.workingAvgPace : run.rawAvgPace
        let currentCad = Int(round(run.workingAvgCadence > 0 ? run.workingAvgCadence : run.rawAvgCadence))
        let currentHR = Int(round(run.workingAvgHeartRate > 0 ? run.workingAvgHeartRate : run.rawAvgHeartRate))
        let currentPaceStr = PaceFormatter.formatPace(secondsPerKilometer: currentPace)

        return TelemetryData(
            date: run.date,
            formattedDate: currentFormattedDate,
            weekday: currentWeekday,
            classification: currentType,
            paceSecondsPerKm: currentPace,
            paceFormatted: currentPaceStr,
            cadenceSPM: currentCad,
            heartRateBPM: currentHR,
            distanceMeters: run.totalDistanceMeters,
            durationSeconds: run.duration,
            isIndoor: run.isIndoor ?? false,
            efficiencyFactor: run.efficiencyFactor
        )
    }

    /// Evaluates 30-day performance rankings, identifying the athlete's peak and toughest workouts.
    static func analyzePerformanceArc(
        relativeTo currentRun: RunRecord? = nil,
        in context: ModelContext?
    ) -> PerformanceArcAnalysis {
        guard let context = context else {
            if let current = currentRun {
                let currentTelemetry = extractTelemetry(from: current)
                return PerformanceArcAnalysis(
                    totalRunsInPast30Days: 1,
                    bestRun: currentTelemetry,
                    worstRun: nil,
                    currentRun: currentTelemetry
                )
            }
            return PerformanceArcAnalysis(
                totalRunsInPast30Days: 0,
                bestRun: nil,
                worstRun: nil,
                currentRun: nil
            )
        }

        let descriptor = FetchDescriptor<RunRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        guard let allRuns = try? context.fetch(descriptor), !allRuns.isEmpty else {
            if let current = currentRun {
                let currentTelemetry = extractTelemetry(from: current)
                return PerformanceArcAnalysis(
                    totalRunsInPast30Days: 1,
                    bestRun: currentTelemetry,
                    worstRun: nil,
                    currentRun: currentTelemetry
                )
            }
            return PerformanceArcAnalysis(
                totalRunsInPast30Days: 0,
                bestRun: nil,
                worstRun: nil,
                currentRun: nil
            )
        }

        guard let referenceRun = currentRun ?? allRuns.first else {
            return PerformanceArcAnalysis(
                totalRunsInPast30Days: 0,
                bestRun: nil,
                worstRun: nil,
                currentRun: nil
            )
        }
        let currentTelemetry = extractTelemetry(from: referenceRun)

        let calendar = Calendar.current
        let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: referenceRun.date) ?? referenceRun.date.addingTimeInterval(-30 * 86400)
        let futureLimit = referenceRun.date.addingTimeInterval(3600)

        var past30DaysRuns = allRuns.filter { $0.date >= thirtyDaysAgo && $0.date <= futureLimit }
        if !past30DaysRuns.contains(where: { $0.id == referenceRun.id }) {
            past30DaysRuns.append(referenceRun)
        }

        guard past30DaysRuns.count >= 2 else {
            return PerformanceArcAnalysis(
                totalRunsInPast30Days: past30DaysRuns.count,
                bestRun: currentTelemetry,
                worstRun: nil,
                currentRun: currentTelemetry
            )
        }

        let enduranceRuns = past30DaysRuns.filter { !$0.isPrimerWorkout && $0.totalDistanceMeters >= 1000 && $0.duration >= 600 }
        let candidateRuns: [RunRecord]
        if enduranceRuns.count >= 2 {
            candidateRuns = enduranceRuns
        } else {
            let nonPrimers = past30DaysRuns.filter { !$0.isPrimerWorkout }
            candidateRuns = nonPrimers.count >= 2 ? nonPrimers : past30DaysRuns
        }

        let candidateSamples = candidateRuns.map(\.toHistoricalCandidateSample)
        let sortedSamples = HistoricalQueryCore.filterAndSort(
            candidates: candidateSamples,
            criteria: HistoricalQueryCriteriaCore(metric: .efficiencyFactor, direction: .descending)
        )

        guard let bestId = sortedSamples.first?.id,
              let bestRecord = candidateRuns.first(where: { $0.id == bestId }) else {
            return PerformanceArcAnalysis(
                totalRunsInPast30Days: past30DaysRuns.count,
                bestRun: currentTelemetry,
                worstRun: nil,
                currentRun: currentTelemetry
            )
        }
        let worstRecord = sortedSamples.count > 1 ? candidateRuns.first(where: { $0.id == sortedSamples.last?.id }) : nil

        let bestTelemetry = extractTelemetry(from: bestRecord)
        let worstTelemetry = worstRecord.map { extractTelemetry(from: $0) }

        return PerformanceArcAnalysis(
            totalRunsInPast30Days: past30DaysRuns.count,
            bestRun: bestTelemetry,
            worstRun: worstTelemetry,
            currentRun: currentTelemetry
        )
    }

    /// Computes deterministic telemetry deltas between the current run and a prior run.
    static func compare(current: RunRecord, with prior: RunRecord) -> ComparisonTelemetry {
        let currentTelemetry = extractTelemetry(from: current)
        let priorTelemetry = extractTelemetry(from: prior)

        let deltas = HistoricalQueryCore.computeDeltas(
            current: current.toHistoricalCandidateSample,
            prior: prior.toHistoricalCandidateSample
        )

        return ComparisonTelemetry(
            current: currentTelemetry,
            prior: priorTelemetry,
            paceDeltaSeconds: deltas.paceDeltaSec,
            cadenceDelta: deltas.cadDelta,
            heartRateDelta: deltas.hrDelta,
            distanceDeltaMeters: deltas.distDelta,
            durationDeltaSeconds: deltas.durDelta
        )
    }

    /// Formats a strongly-typed catalog of the athlete's recorded workouts for tool listing queries.
    static func listRecentRuns(
        relativeTo currentRun: RunRecord? = nil,
        in context: ModelContext?,
        limit: Int = 10
    ) -> String {
        guard let context = context else {
            return "{\"status\":\"no_context\",\"message\":\"No stored records available.\"}"
        }
        let descriptor = FetchDescriptor<RunRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        guard let allRuns = try? context.fetch(descriptor), !allRuns.isEmpty else {
            return "{\"status\":\"empty_database\",\"message\":\"No workouts found in stored records.\"}"
        }
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "EEEE, MMMM d, yyyy"

        let totalCount = allRuns.count
        let newestDateStr = allRuns.first.map { dateFormatter.string(from: $0.date) } ?? "N/A"
        let oldestDateStr = allRuns.last.map { dateFormatter.string(from: $0.date) } ?? "N/A"

        let summaries: [HistoricalRunSummary] = allRuns.prefix(limit).map { run in
            extractTelemetry(from: run).asSummary
        }

        let olderCount = max(0, totalCount - limit)
        let olderNote: String? = olderCount > 0
            ? "\(olderCount) older workouts recorded in athlete database down to first logged run on \(oldestDateStr)"
            : nil

        let headerStr = "ATHLETE WORKOUT DATABASE (\(totalCount) total workouts recorded, spanning from \(oldestDateStr) to \(newestDateStr))"

        let catalog = HistoricalRunCatalog(
            total_workouts_count: totalCount,
            newest_workout_date: newestDateStr,
            oldest_workout_date: oldestDateStr,
            workouts: summaries,
            older_workouts_count: olderCount,
            header: headerStr,
            older_workouts_note: olderNote
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        if let data = try? encoder.encode(catalog),
           let json = String(data: data, encoding: .utf8) {
            return json
        }
        return "{}"
    }

    /// Formats a standalone telemetry card for a historical workout without requiring comparison math.
    static func formatSingleRun(
        _ run: RunRecord,
        totalWorkoutsCount: Int? = nil,
        rankInHistory: Int? = nil
    ) -> String {
        let telemetry = extractTelemetry(from: run)
        let total = totalWorkoutsCount ?? 1
        let rankNote: String
        if let rank = rankInHistory {
            if rank == 1 {
                rankNote = "Oldest recorded workout (#1 of \(total) total workouts)"
            } else if rank == total {
                rankNote = "Most recent workout (#\(total) of \(total) total workouts)"
            } else {
                rankNote = "Workout #\(rank) of \(total) total workouts in chronological order"
            }
        } else {
            rankNote = ""
        }

        let lookup = HistoricalRunLookup(
            status: "success",
            workout: telemetry.asSummary,
            rank_in_history: rankInHistory,
            total_workouts_count: totalWorkoutsCount,
            rank_note: rankNote.isEmpty ? nil : rankNote
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        if let data = try? encoder.encode(lookup),
           let json = String(data: data, encoding: .utf8) {
            return json
        }
        return "{}"
    }

    /// Looks up a specific historical run by query criteria and returns its deterministic telemetry.
    static func lookupRun(
        matching query: String,
        relativeTo currentRun: RunRecord?,
        in context: ModelContext?
    ) -> String {
        guard let context = context else {
            return "{\"status\":\"no_context\",\"message\":\"No workouts found in stored records.\"}"
        }
        let descriptor = FetchDescriptor<RunRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        guard let allRuns = try? context.fetch(descriptor), !allRuns.isEmpty else {
            return "{\"status\":\"empty_database\",\"message\":\"No workouts found in stored records.\"}"
        }
        guard let match = findRun(matching: query, in: allRuns, relativeTo: currentRun) else {
            return "{\"status\":\"no_matching_run\",\"query\":\"\(query)\"}"
        }
        let ascending = allRuns.sorted(by: { $0.date < $1.date })
        let rank = ascending.firstIndex(where: { $0.id == match.id }).map { $0 + 1 }
        return formatSingleRun(match, totalWorkoutsCount: allRuns.count, rankInHistory: rank)
    }
}
