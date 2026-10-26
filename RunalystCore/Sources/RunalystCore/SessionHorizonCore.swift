import Foundation

/// Pure deterministic weekday templates and continuous horizon synthesis.
public enum SessionHorizonCore {

    public static func templateSpecForWeekday(
        weekday: Int,
        activeGoal: String,
        experienceLevel: String,
        useMetric: Bool
    ) -> WeekdayTemplateSpec {
        let (_, defaultMins) = SessionSynthesisCore.aerobicDurationForExperience(experienceLevel)

        if activeGoal.localizedCaseInsensitiveContains("5K") {
            switch weekday {
            case 1:
                return WeekdayTemplateSpec(kind: "run", title: useMetric ? "Aerobic Consistency Run (5 km)" : "Aerobic Consistency Run (3 mi)", intensityZone: .zone2Base, minutesLow: 25, minutesHigh: 35, primerTitle: nil, iconName: "figure.run")
            case 2:
                return WeekdayTemplateSpec(kind: "run", title: "4x800m 5K Rhythm Intervals (35m)", intensityZone: .zone5Interval, minutesLow: 30, minutesHigh: 35, primerTitle: "Rhythm Intervals", iconName: "flag.fill")
            case 3:
                return WeekdayTemplateSpec(kind: "run", title: useMetric ? "5 km Easy Aerobic Run" : "3 mi Easy Aerobic Run", intensityZone: .zone2Base, minutesLow: 25, minutesHigh: 30, primerTitle: nil, iconName: "figure.run")
            case 4:
                return WeekdayTemplateSpec(kind: "rest", title: "Rest Day", intensityZone: .rest, minutesLow: 0, minutesHigh: 0, primerTitle: nil, iconName: "bed.double.fill")
            case 5:
                return WeekdayTemplateSpec(kind: "run", title: "8x1 min Hill Surges (30m)", intensityZone: .zone5Interval, minutesLow: 25, minutesHigh: 30, primerTitle: "Cadence Pyramids", iconName: "flag.fill")
            case 6:
                return WeekdayTemplateSpec(kind: "run", title: useMetric ? "5 km Easy Aerobic Run" : "3 mi Easy Aerobic Run", intensityZone: .zone2Base, minutesLow: 25, minutesHigh: 30, primerTitle: nil, iconName: "figure.run")
            case 7:
                return WeekdayTemplateSpec(kind: "run", title: useMetric ? "Long Run 7 km" : "Long Run 4.5 mi", intensityZone: .zone2Base, minutesLow: 40, minutesHigh: 50, primerTitle: nil, iconName: "point.topleft.down.to.point.bottomright.curvepath.fill")
            default:
                return WeekdayTemplateSpec(kind: "run", title: "Easy Aerobic Run", intensityZone: .zone2Base, minutesLow: 30, minutesHigh: 35, primerTitle: nil, iconName: "figure.run")
            }
        } else if activeGoal.localizedCaseInsensitiveContains("10K") {
            switch weekday {
            case 1:
                return WeekdayTemplateSpec(kind: "run", title: useMetric ? "Aerobic Consistency Run (6 km)" : "Aerobic Consistency Run (3.5 mi)", intensityZone: .zone2Base, minutesLow: 30, minutesHigh: 40, primerTitle: nil, iconName: "figure.run")
            case 2:
                return WeekdayTemplateSpec(kind: "run", title: "5x1 km Threshold Intervals (40m)", intensityZone: .zone4Tempo, minutesLow: 35, minutesHigh: 40, primerTitle: "Rhythm Intervals", iconName: "flag.fill")
            case 3:
                return WeekdayTemplateSpec(kind: "run", title: useMetric ? "6 km Easy Aerobic Run" : "3.5 mi Easy Aerobic Run", intensityZone: .zone2Base, minutesLow: 30, minutesHigh: 35, primerTitle: nil, iconName: "figure.run")
            case 4:
                return WeekdayTemplateSpec(kind: "rest", title: "Rest Day", intensityZone: .rest, minutesLow: 0, minutesHigh: 0, primerTitle: nil, iconName: "bed.double.fill")
            case 5:
                return WeekdayTemplateSpec(kind: "run", title: "Tempo Progression (35m)", intensityZone: .zone4Tempo, minutesLow: 30, minutesHigh: 35, primerTitle: "Tempo Surges", iconName: "bolt.fill")
            case 6:
                return WeekdayTemplateSpec(kind: "run", title: useMetric ? "6 km Easy Aerobic Run" : "3.5 mi Easy Aerobic Run", intensityZone: .zone2Base, minutesLow: 30, minutesHigh: 35, primerTitle: nil, iconName: "figure.run")
            case 7:
                return WeekdayTemplateSpec(kind: "run", title: useMetric ? "Long Run 10 km" : "Long Run 6 mi", intensityZone: .zone2Base, minutesLow: 50, minutesHigh: 65, primerTitle: nil, iconName: "point.topleft.down.to.point.bottomright.curvepath.fill")
            default:
                return WeekdayTemplateSpec(kind: "run", title: "Easy Aerobic Run", intensityZone: .zone2Base, minutesLow: 30, minutesHigh: 35, primerTitle: nil, iconName: "figure.run")
            }
        } else if activeGoal.localizedCaseInsensitiveContains("Half") || activeGoal.localizedCaseInsensitiveContains("Marathon") {
            switch weekday {
            case 1:
                return WeekdayTemplateSpec(kind: "run", title: useMetric ? "Aerobic Consistency Run (8 km)" : "Aerobic Consistency Run (5 mi)", intensityZone: .zone2Base, minutesLow: 40, minutesHigh: 50, primerTitle: nil, iconName: "figure.run")
            case 2:
                return WeekdayTemplateSpec(kind: "run", title: "Zone 2 Steady (45m)", intensityZone: .zone3Steady, minutesLow: 40, minutesHigh: 45, primerTitle: "Cadence Pyramids", iconName: "figure.run")
            case 3:
                return WeekdayTemplateSpec(kind: "run", title: useMetric ? "6 km Easy Aerobic Run" : "3.5 mi Easy Aerobic Run", intensityZone: .zone2Base, minutesLow: 30, minutesHigh: 35, primerTitle: nil, iconName: "figure.run")
            case 4:
                return WeekdayTemplateSpec(kind: "rest", title: "Rest Day", intensityZone: .rest, minutesLow: 0, minutesHigh: 0, primerTitle: nil, iconName: "bed.double.fill")
            case 5:
                return WeekdayTemplateSpec(kind: "run", title: "Tempo Surges (35m)", intensityZone: .zone4Tempo, minutesLow: 30, minutesHigh: 35, primerTitle: "Tempo Surges", iconName: "bolt.fill")
            case 6:
                return WeekdayTemplateSpec(kind: "run", title: "Zone 1 Recovery Flush (40m)", intensityZone: .zone1Flush, minutesLow: 35, minutesHigh: 40, primerTitle: nil, iconName: "leaf.fill")
            case 7:
                return WeekdayTemplateSpec(kind: "run", title: useMetric ? "Long Run 14 km" : "Long Run 8.5 mi", intensityZone: .zone2Base, minutesLow: 70, minutesHigh: 90, primerTitle: nil, iconName: "point.topleft.down.to.point.bottomright.curvepath.fill")
            default:
                return WeekdayTemplateSpec(kind: "run", title: "Easy Aerobic Run", intensityZone: .zone2Base, minutesLow: 35, minutesHigh: 45, primerTitle: nil, iconName: "figure.run")
            }
        } else if activeGoal.localizedCaseInsensitiveContains("Recovery") || activeGoal.localizedCaseInsensitiveContains("Injury") {
            switch weekday {
            case 1:
                return WeekdayTemplateSpec(kind: "run", title: "Zone 1 Easy Aerobic (30m)", intensityZone: .zone1Flush, minutesLow: 25, minutesHigh: 30, primerTitle: nil, iconName: "leaf.fill")
            case 2:
                return WeekdayTemplateSpec(kind: "rest", title: "Rest & Mobility Day", intensityZone: .rest, minutesLow: 0, minutesHigh: 0, primerTitle: nil, iconName: "bed.double.fill")
            case 3:
                return WeekdayTemplateSpec(kind: "run", title: "Zone 1 Recovery Flush (25m)", intensityZone: .zone1Flush, minutesLow: 20, minutesHigh: 25, primerTitle: nil, iconName: "leaf.fill")
            case 4:
                return WeekdayTemplateSpec(kind: "rest", title: "Rest Day", intensityZone: .rest, minutesLow: 0, minutesHigh: 0, primerTitle: nil, iconName: "bed.double.fill")
            case 5:
                return WeekdayTemplateSpec(kind: "run", title: "Walk-Jog Progression (20m)", intensityZone: .zone1Flush, minutesLow: 15, minutesHigh: 20, primerTitle: nil, iconName: "leaf.fill")
            case 6:
                return WeekdayTemplateSpec(kind: "rest", title: "Rest Day", intensityZone: .rest, minutesLow: 0, minutesHigh: 0, primerTitle: nil, iconName: "bed.double.fill")
            case 7:
                return WeekdayTemplateSpec(kind: "run", title: "Zone 1 Easy Aerobic (30m)", intensityZone: .zone1Flush, minutesLow: 25, minutesHigh: 30, primerTitle: nil, iconName: "leaf.fill")
            default:
                return WeekdayTemplateSpec(kind: "run", title: "Recovery Flush (20m)", intensityZone: .zone1Flush, minutesLow: 15, minutesHigh: 20, primerTitle: nil, iconName: "leaf.fill")
            }
        } else {
            // Base Building
            switch weekday {
            case 1:
                return WeekdayTemplateSpec(kind: "run", title: "Aerobic Consistency Run (35m)", intensityZone: .zone2Base, minutesLow: 30, minutesHigh: 35, primerTitle: "Cadence Pyramids", iconName: "figure.run")
            case 2:
                return WeekdayTemplateSpec(kind: "run", title: useMetric ? "Aerobic Long Run (8 km)" : "Aerobic Long Run (5 mi)", intensityZone: .zone2Base, minutesLow: 45, minutesHigh: 55, primerTitle: "Strides", iconName: "point.topleft.down.to.point.bottomright.curvepath.fill")
            case 3:
                return WeekdayTemplateSpec(kind: "run", title: "Zone 2 Easy Aerobic Base", intensityZone: .zone2Base, minutesLow: max(25, defaultMins - 5), minutesHigh: defaultMins, primerTitle: "Cadence Pyramids", iconName: "figure.run")
            case 4:
                return WeekdayTemplateSpec(kind: "rest", title: "Rest Day", intensityZone: .rest, minutesLow: 0, minutesHigh: 0, primerTitle: nil, iconName: "bed.double.fill")
            case 5:
                return WeekdayTemplateSpec(kind: "run", title: "Zone 1 Recovery Flush (40m)", intensityZone: .zone1Flush, minutesLow: 35, minutesHigh: 40, primerTitle: nil, iconName: "leaf.fill")
            case 6:
                return WeekdayTemplateSpec(kind: "run", title: "Aerobic Consistency Run (30m)", intensityZone: .zone2Base, minutesLow: 25, minutesHigh: 30, primerTitle: "Rhythm Intervals", iconName: "figure.run")
            case 7:
                return WeekdayTemplateSpec(kind: "rest", title: "Rest Day", intensityZone: .rest, minutesLow: 0, minutesHigh: 0, primerTitle: nil, iconName: "bed.double.fill")
            default:
                return WeekdayTemplateSpec(kind: "run", title: "Zone 2 Steady (40m)", intensityZone: .zone2Base, minutesLow: 35, minutesHigh: 40, primerTitle: nil, iconName: "figure.run")
            }
        }
    }

    public static func synthesizeHorizon(
        startDate: Date,
        daysCount: Int = 5,
        runs: [SynthesisRunSample],
        context: AthleteSynthesisContext,
        isTomorrowRecovery: Bool = false,
        isTomorrowRest: Bool = false,
        hasRecentLongRun: Bool = false
    ) -> [SynthesizedHorizonDay] {
        var days: [SynthesizedHorizonDay] = []
        let cal = context.calendar
        let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

        let weightedBase = SessionSynthesisCore.computeWeightedBaseline(from: runs, priorTo: startDate)
        let matrix = TrainingZoneCore.calculateZones(anchorPaceSecPerKm: weightedBase.pace, activeGoal: context.activeGoal)
        let floorSPM = SessionSynthesisCore.heightAdjustedCadenceFloor(heightCm: context.userHeightCm)

        for offset in 0..<daysCount {
            guard let targetDate = cal.date(byAdding: .day, value: offset, to: startDate) else { continue }
            let canonicalDate = cal.startOfDay(for: targetDate)
            let weekday = cal.component(.weekday, from: canonicalDate)
            let dayName = dayNames[max(0, min(6, weekday - 1))]

            let isFirstDay = (offset == 0)
            let isTomorrow = cal.isDate(canonicalDate, inSameDayAs: cal.date(byAdding: .day, value: 1, to: context.now) ?? context.now)
            let label = isTomorrow ? "Tomorrow" : dayName

            var template = templateSpecForWeekday(
                weekday: weekday,
                activeGoal: context.activeGoal,
                experienceLevel: context.experienceLevel,
                useMetric: context.useMetric
            )

            if isFirstDay && isTomorrowRecovery {
                template = WeekdayTemplateSpec(
                    kind: "run",
                    title: "Zone 1 Recovery Flush (40m)",
                    intensityZone: .zone1Flush,
                    minutesLow: 35,
                    minutesHigh: 40,
                    primerTitle: nil,
                    iconName: "leaf.fill"
                )
            } else if isFirstDay && isTomorrowRest {
                template = WeekdayTemplateSpec(
                    kind: "rest",
                    title: "Rest Day",
                    intensityZone: .rest,
                    minutesLow: 0,
                    minutesHigh: 0,
                    primerTitle: nil,
                    iconName: "bed.double.fill"
                )
            } else if offset == 4 && !hasRecentLongRun && !days.contains(where: { $0.sessionTitle.lowercased().contains("long") }) {
                if context.activeGoal.localizedCaseInsensitiveContains("5K") {
                    template = WeekdayTemplateSpec(
                        kind: "run",
                        title: context.useMetric ? "Long Run 7 km" : "Long Run 4.5 mi",
                        intensityZone: .zone2Base,
                        minutesLow: 40,
                        minutesHigh: 50,
                        primerTitle: nil,
                        iconName: "point.topleft.down.to.point.bottomright.curvepath.fill"
                    )
                } else if context.activeGoal.localizedCaseInsensitiveContains("10K") {
                    template = WeekdayTemplateSpec(
                        kind: "run",
                        title: context.useMetric ? "Long Run 10 km" : "Long Run 6 mi",
                        intensityZone: .zone2Base,
                        minutesLow: 50,
                        minutesHigh: 65,
                        primerTitle: nil,
                        iconName: "point.topleft.down.to.point.bottomright.curvepath.fill"
                    )
                } else if context.activeGoal.localizedCaseInsensitiveContains("Half") || context.activeGoal.localizedCaseInsensitiveContains("Marathon") {
                    template = WeekdayTemplateSpec(
                        kind: "run",
                        title: context.useMetric ? "Long Run 14 km" : "Long Run 8.5 mi",
                        intensityZone: .zone2Base,
                        minutesLow: 70,
                        minutesHigh: 90,
                        primerTitle: nil,
                        iconName: "point.topleft.down.to.point.bottomright.curvepath.fill"
                    )
                }
            }

            let isRest = template.kind == "rest" || template.intensityZone == .rest
            let intent: DailySessionIntent = isRest ? .fullRest : (template.intensityZone == .zone1Flush ? .recoveryFlush : .train)
            let paceBand = SessionSynthesisCore.resolvePaceBand(for: template.intensityZone, matrix: matrix, useMetric: context.useMetric)
            let hrCap: String = {
                if isRest { return "HR: Rest / < 125 BPM" }
                switch template.intensityZone {
                case .zone1Flush: return "HR: < 135 BPM"
                case .zone2Base, .zone3Steady: return "HR: < 150 BPM"
                case .zone4Tempo: return "HR: < 162-165 BPM"
                case .zone5Interval: return "HR: < 168 BPM"
                case .rest: return "HR: Rest / < 125 BPM"
                }
            }()
            let dayCadFloor: Int? = {
                if isRest { return nil }
                if template.intensityZone == .zone1Flush { return max(140, floorSPM - 6) }
                if template.intensityZone == .zone4Tempo { return max(155, floorSPM) }
                if template.intensityZone == .zone5Interval { return max(160, floorSPM) }
                return floorSPM
            }()

            let spec = PlannedSessionSpec(
                kind: isRest ? "rest" : "run",
                intent: intent,
                title: template.title,
                minutesLow: template.minutesLow,
                minutesHigh: template.minutesHigh,
                paceBand: paceBand,
                hrCap: hrCap,
                cadenceFloor: dayCadFloor,
                primerTitle: template.primerTitle,
                adjustmentTriggers: [],
                provisional: true
            )

            let formatter = DateFormatter()
            formatter.calendar = cal
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            let isoId = formatter.string(from: canonicalDate)

            days.append(SynthesizedHorizonDay(
                id: isoId,
                date: canonicalDate,
                dayLabel: label,
                sessionTitle: template.title,
                iconName: template.iconName,
                isRestDay: isRest,
                spec: spec
            ))
        }

        return days
    }
}
