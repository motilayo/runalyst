import Foundation

// MARK: - Milestone Badge Formatting Extensions

extension MilestoneBadgeSpec {

    public func earnedMetricSubtitle(useMetric: Bool) -> String {
        switch identifier {
        case .firstRun:
            if isUnlocked {
                if let meters = qualifyingDistanceMeters, meters > 0 {
                    let distance = useMetric ? (meters / 1000.0) : (meters / 1609.344)
                    let unit = useMetric ? "km" : "mi"
                    return String(format: "%.1f %@", distance, unit)
                }
                return "1st Run"
            }
            return "0 / 1 Run"

        case .fiveK:
            if isUnlocked {
                let dist = qualifyingDistanceMeters ?? 5000.0
                let val = useMetric ? (dist / 1000.0) : (dist / 1609.344)
                let unit = useMetric ? "km" : "mi"
                return String(format: "%.1f %@", val, unit)
            } else {
                let current = qualifyingDistanceMeters ?? 0.0
                if useMetric {
                    return String(format: "%.1f / 5 km", current / 1000.0)
                } else {
                    return String(format: "%.1f / 3.1 mi", current / 1609.344)
                }
            }

        case .tenK:
            if isUnlocked {
                let dist = qualifyingDistanceMeters ?? 10_000.0
                let val = useMetric ? (dist / 1000.0) : (dist / 1609.344)
                let unit = useMetric ? "km" : "mi"
                return String(format: "%.1f %@", val, unit)
            } else {
                let current = qualifyingDistanceMeters ?? 0.0
                if useMetric {
                    return String(format: "%.1f / 10 km", current / 1000.0)
                } else {
                    return String(format: "%.1f / 6.2 mi", current / 1609.344)
                }
            }

        case .halfMarathon:
            if isUnlocked {
                let dist = qualifyingDistanceMeters ?? 21_097.5
                let val = useMetric ? (dist / 1000.0) : (dist / 1609.344)
                let unit = useMetric ? "km" : "mi"
                return String(format: "%.1f %@", val, unit)
            } else {
                let current = qualifyingDistanceMeters ?? 0.0
                if useMetric {
                    return String(format: "%.1f / 21.1 km", current / 1000.0)
                } else {
                    return String(format: "%.1f / 13.1 mi", current / 1609.344)
                }
            }

        case .centuryVolume:
            let meters = qualifyingDistanceMeters ?? 0.0
            if isUnlocked {
                let val = useMetric ? (meters / 1000.0) : (meters / 1609.344)
                let unit = useMetric ? "km" : "mi"
                return String(format: "%.1f %@", val, unit)
            } else {
                if useMetric {
                    return String(format: "%.1f / 100 km", meters / 1000.0)
                } else {
                    return String(format: "%.1f / 62.1 mi", meters / 1609.344)
                }
            }

        case .fiveHundredK:
            let meters = qualifyingDistanceMeters ?? 0.0
            if isUnlocked {
                let val = useMetric ? (meters / 1000.0) : (meters / 1609.344)
                let unit = useMetric ? "km" : "mi"
                return String(format: "%.1f %@", val, unit)
            } else {
                if useMetric {
                    return String(format: "%.1f / 500 km", meters / 1000.0)
                } else {
                    return String(format: "%.1f / 310.7 mi", meters / 1609.344)
                }
            }

        case .rhythmMaster:
            if isUnlocked {
                let cad = Int(round(qualifyingCadenceSPM ?? 170.0))
                return "\(cad) SPM"
            } else {
                let cad = Int(round(qualifyingCadenceSPM ?? 0.0))
                return "\(cad) / 170 SPM"
            }

        case .aerobicEngine:
            if isUnlocked {
                let ef = qualifyingEfficiencyFactor ?? 1.35
                return String(format: "%.2f EF", ef)
            } else {
                let ef = qualifyingEfficiencyFactor ?? 0.0
                return String(format: "%.2f / 1.35 EF", ef)
            }

        case .consistency:
            if isUnlocked {
                let runs = max(1, timesEarnedCount) * 10
                return "\(runs)+ Runs"
            } else {
                let runs = Int(round(progressFraction * 10.0))
                return "\(runs) / 10 Runs"
            }
        }
    }

    public func earnedNarrativeProse(useMetric: Bool, formattedDate: String?) -> String {
        let dateClause: String
        if let formattedDate = formattedDate, !formattedDate.isEmpty {
            dateClause = " on \(formattedDate)"
        } else {
            dateClause = ""
        }

        if isUnlocked {
            switch identifier {
            case .firstRun:
                if let meters = qualifyingDistanceMeters, meters > 0 {
                    let distance = useMetric ? (meters / 1000.0) : (meters / 1609.344)
                    let unit = useMetric ? "km" : "mi"
                    let distStr = String(format: "%.2f %@", distance, unit)
                    return "You earned this award by recording your first run in Runalyst. First run: \(distStr)\(dateClause)."
                }
                return "You earned this award by recording your first run in Runalyst\(dateClause)."

            case .fiveK:
                let dist = useMetric ? ((qualifyingDistanceMeters ?? 5000.0) / 1000.0) : ((qualifyingDistanceMeters ?? 5000.0) / 1609.344)
                let unit = useMetric ? "km" : "mi"
                let distStr = String(format: "%.2f %@", dist, unit)
                return "You earned this award by logging a single run of at least 5 km. Best qualifying run: \(distStr)\(dateClause)."

            case .tenK:
                let dist = useMetric ? ((qualifyingDistanceMeters ?? 10_000.0) / 1000.0) : ((qualifyingDistanceMeters ?? 10_000.0) / 1609.344)
                let unit = useMetric ? "km" : "mi"
                let distStr = String(format: "%.2f %@", dist, unit)
                return "You earned this award by logging a single run of at least 10 km. Best qualifying run: \(distStr)\(dateClause)."

            case .halfMarathon:
                let dist = useMetric ? ((qualifyingDistanceMeters ?? 21_097.5) / 1000.0) : ((qualifyingDistanceMeters ?? 21_097.5) / 1609.344)
                let unit = useMetric ? "km" : "mi"
                let distStr = String(format: "%.2f %@", dist, unit)
                return "You earned this award by completing a 21.1 km endurance effort. Best qualifying run: \(distStr)\(dateClause)."

            case .centuryVolume:
                let dist = useMetric ? ((qualifyingDistanceMeters ?? 100_000.0) / 1000.0) : ((qualifyingDistanceMeters ?? 100_000.0) / 1609.344)
                let unit = useMetric ? "km" : "mi"
                let distStr = String(format: "%.1f %@", dist, unit)
                let targetStr = useMetric ? "100 km" : "62.1 mi"
                return "You earned this award by accumulating \(targetStr) of total lifetime running volume. Total volume: \(distStr)\(dateClause)."

            case .fiveHundredK:
                let dist = useMetric ? ((qualifyingDistanceMeters ?? 500_000.0) / 1000.0) : ((qualifyingDistanceMeters ?? 500_000.0) / 1609.344)
                let unit = useMetric ? "km" : "mi"
                let distStr = String(format: "%.1f %@", dist, unit)
                let targetStr = useMetric ? "500 km" : "310.7 mi"
                return "You earned this award by accumulating \(targetStr) of total lifetime running volume. Total volume: \(distStr)\(dateClause)."

            case .rhythmMaster:
                let cad = Int(round(qualifyingCadenceSPM ?? 170.0))
                return "You earned this award by maintaining optimal turnover of 170+ SPM. Peak cadence: \(cad) SPM\(dateClause)."

            case .aerobicEngine:
                let efStr = String(format: "%.2f EF", qualifyingEfficiencyFactor ?? 1.35)
                return "You earned this award by achieving an Efficiency Factor exceeding 1.35 m/beat. Peak efficiency: \(efStr)\(dateClause)."

            case .consistency:
                let count = max(1, timesEarnedCount) * 10
                return "You earned this award by logging \(count) or more structured running workouts\(dateClause)."
            }
        } else {
            let pct = Int(round(progressFraction * 100))
            switch identifier {
            case .firstRun:
                return "Record your first run in Runalyst to unlock this award. Current progress: 0%."
            case .fiveK:
                let targetStr = useMetric ? "5 km" : "3.1 mi"
                return "Complete a single run of at least \(targetStr) to unlock this award. Current progress: \(pct)%."
            case .tenK:
                let targetStr = useMetric ? "10 km" : "6.2 mi"
                return "Complete a single run of at least \(targetStr) to unlock this award. Current progress: \(pct)%."
            case .halfMarathon:
                let targetStr = useMetric ? "21.1 km" : "13.1 mi"
                return "Complete a single run of at least \(targetStr) to unlock this award. Current progress: \(pct)%."
            case .centuryVolume:
                let targetStr = useMetric ? "100 km" : "62.1 mi"
                return "Accumulate \(targetStr) of total lifetime running volume to unlock this award. Current progress: \(pct)%."
            case .fiveHundredK:
                let targetStr = useMetric ? "500 km" : "310.7 mi"
                return "Accumulate \(targetStr) of total lifetime running volume to unlock this award. Current progress: \(pct)%."
            case .rhythmMaster:
                return "Maintain optimal turnover of 170+ SPM on a run to unlock this award. Current progress: \(pct)%."
            case .aerobicEngine:
                return "Achieve an Efficiency Factor exceeding 1.35 m/beat on a run to unlock this award. Current progress: \(pct)%."
            case .consistency:
                return "Log 10 structured running workouts to unlock this award. Current progress: \(pct)%."
            }
        }
    }
}
