//
//  HealthKitSeeder.swift
//  Runalyst
//
//  Created by Joshua Agboola on 2026-08-22.
//  Updated for Runalyst V2: 1-Minute Chunking & Variance Profiles
//

import Foundation
import HealthKit
import SwiftData

enum MockRunProfile: String, CaseIterable {
    case easy = "Easy Run"
    case recovery = "Recovery Run"
    case steady = "Steady Effort"
    case tempo = "Tempo Run"
    case intervals = "Intervals"
    case pyramids = "Pyramids"
    case fartlek = "Fartlek"
    case progression = "Progression Run"
    case hillRepeats = "Hill Repeats"
    case longRun = "Long Run"
    case urbanTraffic = "Urban Traffic"

    var durationMinutes: Int {
        switch self {
        case .recovery: return 25
        case .longRun: return 75
        case .intervals, .hillRepeats, .pyramids: return 30
        default: return 40
        }
    }
}

@MainActor
class HealthKitSeeder {
    static let shared = HealthKitSeeder()
    static let totalProgressionRuns = 38
    let healthStore = HKHealthStore()

    static func profile(forIndex index: Int) -> MockRunProfile {
        if index == 37 {
            return .fartlek
        }
        let phase1: [MockRunProfile] = [
            .recovery, .easy, .urbanTraffic, .easy,
            .recovery, .pyramids, .urbanTraffic, .easy,
            .recovery, .recovery, .easy, .recovery
        ]
        let phase2: [MockRunProfile] = [
            .easy, .steady, .pyramids, .steady,
            .fartlek, .easy, .progression, .steady,
            .pyramids, .easy, .steady, .fartlek, .progression
        ]
        let phase3: [MockRunProfile] = [
            .steady, .tempo, .longRun, .pyramids,
            .intervals, .steady, .pyramids, .tempo,
            .hillRepeats, .progression, .intervals, .longRun, .tempo
        ]
        if index < phase1.count {
            return phase1[index]
        } else if index < phase1.count + phase2.count {
            return phase2[index - phase1.count]
        } else {
            let offset = index - (phase1.count + phase2.count)
            return phase3[min(offset, phase3.count - 1)]
        }
    }

    /// Designates realistic prescribed drills across the 38-run schedule to test all V2 drill families
    static func prescribedDrill(forIndex index: Int, profile: MockRunProfile, progress: Double) -> PreRunDrillId? {
        switch index {
        case 1:  // Early Easy Run -> Zone 2 Run
            return .zone2Run
        case 4:  // Early Recovery Run -> Recovery Jog (Controlled)
            return .recoveryJog
        case 5:  // Phase 1 Pyramids -> Cadence Pyramids (Beginner form)
            return .cadencePyramids
        case 9:  // Phase 1 Recovery Run -> Recovery Jog (High Cardiac Drift -> Not Met)
            return .recoveryJog
        case 13: // Phase 2 Steady Effort -> Rhythm Intervals
            return .rhythmIntervals
        case 17: // Phase 2 Easy Run -> Zone 2 Run (Higher turnover -> Exceeded)
            return .zone2Run
        case 20: // Phase 2 Pyramids -> Cadence Pyramids (Met)
            return .cadencePyramids
        case 26: // Phase 3 Tempo -> Tempo Surges (Met)
            return .tempoSurges
        case 28: // Phase 3 Pyramids -> Cadence Pyramids (Exceeded)
            return .cadencePyramids
        case 35: // Phase 3 Intervals -> Strides (Exceeded)
            return .strides
        default:
            return nil
        }
    }

    static func recommendedDrillId(for profile: MockRunProfile, progress: Double) -> PreRunDrillId {
        switch profile {
        case .pyramids:
            return .cadencePyramids
        case .recovery:
            return progress < 0.5 ? .recoveryJog : .aerobicFlush
        case .easy:
            return .zone2Run
        case .steady:
            return .rhythmIntervals
        case .tempo, .progression:
            return .tempoSurges
        case .intervals:
            return progress < 0.5 ? .neuromuscularPrimer : .strides
        case .fartlek:
            return .fartlekPrimer
        case .hillRepeats:
            return .hillBounds
        case .longRun:
            return .aerobicFlush
        case .urbanTraffic:
            return .neuromuscularPrimer
        }
    }

    func seedCouchTo5K(context: ModelContext? = nil) async {
        let seededWorkouts = await seedAdvancedMockRuns()
        if let context = context {
            if seededWorkouts.isEmpty {
                // If Apple Health is not authorized or failed, seed directly to SwiftData
                seedDirectToSwiftData(context: context)
            } else {
                // Purge any existing SwiftData records so the ensuing HealthKit sync will populate clean, non-duplicate runs
                let descriptor = FetchDescriptor<RunRecord>()
                if let existing = try? context.fetch(descriptor) {
                    for run in existing {
                        context.delete(run)
                    }
                    try? context.save()
                }
            }
        }
    }

    @discardableResult
    func seedAdvancedMockRuns() async -> [HKWorkout] {
        var savedWorkouts: [HKWorkout] = []
        let typesToWrite: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            HKQuantityType(.distanceWalkingRunning),
            HKQuantityType(.heartRate),
            HKQuantityType(.stepCount),
            HKQuantityType(.runningSpeed),
            HKQuantityType(.vo2Max),
            HKQuantityType(.runningVerticalOscillation),
            HKQuantityType(.runningGroundContactTime),
            HKQuantityType(.runningStrideLength)
        ]

        do {
            try await healthStore.requestAuthorization(toShare: typesToWrite, read: [])
        } catch {
            print("Failed to authorize HealthKit Seeder: \(error)")
            return []
        }

        let calendar = Calendar.current
        let today = Date()

        // Seed 38 runs spanning 3 months (~90 days) showing beginner-to-intermediate progression
        let totalRuns = Self.totalProgressionRuns
        for index in 0..<totalRuns {
            let profile = Self.profile(forIndex: index)
            let progress = Double(index) / Double(max(1, totalRuns - 1))
            let daysAgo = 90.0 - (Double(index) * (89.0 / Double(max(1, totalRuns - 1))))
            guard let workoutStartTime = calendar.date(byAdding: .day, value: -Int(daysAgo), to: today) else { continue }

            let isIndoorWorkout = (index == 37 || index == 36)
            let configuration = HKWorkoutConfiguration()
            configuration.activityType = .running
            configuration.locationType = isIndoorWorkout ? .indoor : .outdoor

            let totalMinutes = profile.durationMinutes
            let workoutEndTime = workoutStartTime.addingTimeInterval(TimeInterval(totalMinutes * 60))

            do {
                let builder = HKWorkoutBuilder(healthStore: healthStore, configuration: configuration, device: nil)
                try await builder.beginCollection(at: workoutStartTime)

                var allSamples: [HKSample] = []

                for chunkIndex in 0..<(totalMinutes * 4) {
                    let chunkStart = workoutStartTime.addingTimeInterval(TimeInterval(chunkIndex * 15))
                    let chunkEnd = chunkStart.addingTimeInterval(15)

                    let metrics = Self.generate15SecondMetrics(for: profile, workoutIndex: index, chunkIndex: chunkIndex, progress: progress)

                    let distanceQuantity = HKQuantity(unit: .meter(), doubleValue: metrics.distanceMeters)
                    let speedQuantity = HKQuantity(
                        unit: HKUnit.meter().unitDivided(by: .second()),
                        doubleValue: metrics.distanceMeters / 15.0
                    )
                    let hrQuantity = HKQuantity(unit: HKUnit.count().unitDivided(by: .minute()), doubleValue: metrics.heartRate)
                    let oscQuantity = HKQuantity(unit: .meterUnit(with: .centi), doubleValue: metrics.oscillation)
                    let gctQuantity = HKQuantity(unit: .secondUnit(with: .milli), doubleValue: metrics.gct)
                    let strideQuantity = HKQuantity(unit: .meter(), doubleValue: metrics.stride)

                    let distanceSample = HKCumulativeQuantitySample(
                        type: HKQuantityType(.distanceWalkingRunning),
                        quantity: distanceQuantity,
                        start: chunkStart,
                        end: chunkEnd
                    )
                    let speedSample = HKQuantitySample(
                        type: HKQuantityType(.runningSpeed),
                        quantity: speedQuantity,
                        start: chunkStart,
                        end: chunkEnd
                    )
                    let hrSample = HKQuantitySample(
                        type: HKQuantityType(.heartRate),
                        quantity: hrQuantity,
                        start: chunkStart,
                        end: chunkEnd
                    )
                    let cadenceSample = HKQuantitySample(
                        type: HKQuantityType(.stepCount),
                        quantity: HKQuantity(unit: .count(), doubleValue: metrics.cadence / 4.0),
                        start: chunkStart,
                        end: chunkEnd
                    )
                    let oscSample = HKQuantitySample(
                        type: HKQuantityType(.runningVerticalOscillation),
                        quantity: oscQuantity,
                        start: chunkStart,
                        end: chunkEnd
                    )
                    let gctSample = HKQuantitySample(
                        type: HKQuantityType(.runningGroundContactTime),
                        quantity: gctQuantity,
                        start: chunkStart,
                        end: chunkEnd
                    )
                    let strideSample = HKQuantitySample(
                        type: HKQuantityType(.runningStrideLength),
                        quantity: strideQuantity,
                        start: chunkStart,
                        end: chunkEnd
                    )

                    allSamples.append(contentsOf: [distanceSample, speedSample, hrSample, cadenceSample, oscSample, gctSample, strideSample])
                }

                // Add a VO2 Max sample that gradually improves from 38.5 to 44.0 mL/(kg·min)
                let vo2Value = 38.5 + (progress * 5.5) + Double.random(in: -0.3...0.3)
                let vo2Quantity = HKQuantity(
                    unit: HKUnit(from: "ml/kg*min"),
                    doubleValue: vo2Value
                )
                let vo2Sample = HKQuantitySample(
                    type: HKQuantityType(.vo2Max),
                    quantity: vo2Quantity,
                    start: workoutEndTime.addingTimeInterval(-60),
                    end: workoutEndTime
                )
                allSamples.append(vo2Sample)
                var metadata: [String: Any] = [
                    HKMetadataKeyIndoorWorkout: NSNumber(value: isIndoorWorkout)
                ]
                if index == 36 {
                    metadata[HKMetadataKeyFitnessMachineDuration] = NSNumber(value: profile.durationMinutes * 60)
                }
                try await builder.addMetadata(metadata)
                try await builder.addSamples(allSamples)
                try await builder.endCollection(at: workoutEndTime)
                let workout = try await builder.finishWorkout()
                if let workout = workout {
                    savedWorkouts.append(workout)
                }
            } catch {
                print("Seeder error adding mock workout for day -\(Int(daysAgo)): \(error)")
            }
        }

        print("Seeded \(savedWorkouts.count) advanced mock workouts across 3-month progression.")
        return savedWorkouts
    }

    /// Fallback seeding mechanism that writes directly to SwiftData when HealthKit is unavailable or denied
    func seedDirectToSwiftData(context: ModelContext) {
        let descriptor = FetchDescriptor<RunRecord>()
        if let existing = try? context.fetch(descriptor) {
            for run in existing {
                context.delete(run)
            }
            try? context.save()
        }

        let calendar = Calendar.current
        let today = Date()
        let totalRuns = Self.totalProgressionRuns

        for index in 0..<totalRuns {
            let profile = Self.profile(forIndex: index)
            let progress = Double(index) / Double(max(1, totalRuns - 1))
            let daysAgo: Double = {
                if index == totalRuns - 1 { return 2.0 } // Thursday Oct 15
                if index == totalRuns - 2 { return 4.0 } // Tuesday Oct 13
                if index == totalRuns - 3 { return 6.0 } // Sunday Oct 11
                return 90.0 - (Double(index) * (82.0 / Double(max(1, totalRuns - 4))))
            }()
            guard let date = calendar.date(byAdding: .day, value: -Int(daysAgo), to: today) else { continue }

            let rawDurationSec: TimeInterval = (index == 37) ? 2475.0 : TimeInterval(profile.durationMinutes * 60)

            // Calculate active working duration vs pause duration
            let pauseSec: TimeInterval = (index == 37) ? 0.0 : {
                switch profile {
                case .urbanTraffic: return 120.0
                case .intervals: return 60.0
                case .easy, .recovery, .steady, .pyramids: return 30.0
                default: return 0.0
                }
            }()
            let workingSec = max(rawDurationSec - pauseSec, 60.0)

            // Speed progression: 6:30/km (390s) early on down to 5:00/km (300s) for tempo
            let basePace = 390.0 - (progress * 60.0)
            let profilePaceOffset: Double = {
                switch profile {
                case .tempo: return -35.0
                case .intervals: return -30.0
                case .pyramids: return -15.0
                case .recovery: return 35.0
                case .easy: return 15.0
                case .longRun: return 20.0
                case .hillRepeats: return 10.0
                case .fartlek: return -25.0
                default: return 0.0
                }
            }()
            let workingPaceSec = (index == 37) ? 342.0 : max(275.0, basePace + profilePaceOffset + Double.random(in: -3...3))
            let distanceMeters = (index == 37) ? 5800.0 : ((workingSec / workingPaceSec) * 1000.0)
            let distanceKm = distanceMeters / 1000.0

            // Exact mathematical averages:
            let workingAvgPace = distanceKm > 0 ? (workingSec / distanceKm) : workingPaceSec
            let rawAvgPace = distanceKm > 0 ? (rawDurationSec / distanceKm) : workingPaceSec

            // Cadence begins at ~148 SPM (beginner floor) and climbs toward ~168 SPM
            let baseCadence = 148.0 + (progress * 20.0)
            let profileCadenceOffset: Double = {
                switch profile {
                case .intervals: return 2.0
                case .pyramids: return 1.0
                case .tempo: return 4.0
                case .recovery: return -4.0
                case .easy: return -2.0
                case .urbanTraffic: return -5.0
                case .hillRepeats: return -2.0
                default: return 0.0
                }
            }()
            let workingCadence: Double = {
                if index == 37 {
                    return 180.0
                }
                if index == 26 {
                    return 174.0
                }
                return min(186.0, max(142.0, baseCadence + profileCadenceOffset + Double.random(in: -1.5...1.5)))
            }()
            // Raw cadence is total steps over the entire elapsed duration
            let rawCadence = (workingCadence * (workingSec / 60.0)) / (rawDurationSec / 60.0)

            // Vertical oscillation: starts higher at ~10.4 cm (bounding) and drops to ~8.0 cm (efficient)
            let baseOsc = 10.4 - (progress * 2.4)
            let profileOscOffset: Double = {
                switch profile {
                case .pyramids: return -0.4
                case .recovery: return 0.3
                case .urbanTraffic: return 0.4
                default: return 0.0
                }
            }()
            let vertOsc: Double = {
                if index == 37 {
                    return 7.4
                }
                return max(7.2, baseOsc + profileOscOffset + Double.random(in: -0.2...0.2))
            }()
            // Vertical oscillation is only recorded when actively running, so working and raw are identical
            let rawOsc = vertOsc

            // Heart rate: Aerobic efficiency improves over time
            let baseHR = 154.0 - (progress * 12.0)
            let profileHROffset: Double = {
                switch profile {
                case .recovery: return -20.0
                case .easy: return -10.0
                case .steady: return 0.0
                case .tempo: return 15.0
                case .intervals: return 5.0
                case .hillRepeats: return 10.0
                case .fartlek: return 5.0
                case .progression: return 5.0
                case .pyramids: return 5.0
                case .longRun: return 5.0
                case .urbanTraffic: return -5.0
                }
            }()
            let workingHR: Double = {
                if index == 9 {
                    return 166.0 // Elevated HR on recovery run -> Not Met
                }
                return max(115.0, min(192.0, baseHR + profileHROffset + Double.random(in: -2...2)))
            }()
            // Raw HR includes pauses where heart rate drops (assuming rest HR around 110 for recovery)
            let rawHR = ((workingHR * workingSec) + (110.0 * pauseSec)) / rawDurationSec

            let paceCV: Double = {
                switch profile {
                case .intervals: return 0.18
                case .fartlek, .pyramids: return 0.12
                case .urbanTraffic: return 0.22
                case .hillRepeats: return 0.15
                default: return 0.04
                }
            }()
            let paceSlope = profile == .progression ? -0.45 : (profile == .longRun ? 0.35 : 0.0)
            let percentZone4: Double = {
                if index == 9 {
                    return 0.22 // High drift on recovery jog -> Not Met adherence
                }
                if index == 1 {
                    return 0.05 // Zone 2 Run -> Met
                }
                if index == 17 {
                    return 0.02 // Zone 2 Run -> Exceeded
                }
                if index == 4 {
                    return 0.00 // Recovery Jog -> Met
                }
                if index == 26 {
                    return 0.25 // Tempo Surges -> Met
                }
                if index == 37 {
                    return 0.45 // Tempo Surges -> Exceeded
                }
                switch profile {
                case .tempo: return 0.65
                case .intervals: return 0.45
                case .pyramids: return 0.35
                case .hillRepeats: return 0.40
                case .fartlek: return 0.30
                default: return 0.08
                }
            }()

            // Aligned Drill Recommendation
            let prescribed = Self.prescribedDrill(forIndex: index, profile: profile, progress: progress)
            let drillId = (index == 37) ? .cadencePyramids : (prescribed ?? Self.recommendedDrillId(for: profile, progress: progress))
            let template = DrillTemplate.template(for: drillId)
            let targetCadenceString = template.calculateTargetCadence(Int(baseCadence))

            let drill = DrillRecommendation(
                drillTitle: template.title,
                preRunDrillId: template.id.rawValue,
                drillPurpose: template.defaultPurpose,
                drillWork: template.defaultWork,
                drillCues: template.generateInstructionalCue(targetCadenceString),
                drillEffort: template.defaultEffort,
                drillRecovery: template.defaultRecovery,
                targetCadence: "\(targetCadenceString) SPM",
                previousCadence: Int(baseCadence),
                isCompleted: prescribed != nil
            )

            // Dynamic Coaching Insight tailored to the runner's 3-month progression (Zero Numbers rule)
            let headline: String
            let observation: String
            if index == 37 {
                headline = "Dynamic Cadence Turnover"
                observation = "Your turnover held a crisp 163 SPM rhythm through all 5 fartlek surges while maintaining compact foot strikes beneath your hips. Cardiac drift was observed (+10 BPM) across later sets on the indoor track."
            } else if progress < 0.33 {
                headline = "Cadence Rhythm Foundation"
                observation = "Early baseline indicates room to quicken your turnover and soften your foot strike. Focus on light, agile strides beneath your hips to protect knees and build consistency."
            } else if progress < 0.67 {
                headline = "Steady Aerobic Base"
                observation = "Your rhythm is stabilizing nicely across varying terrain and effort levels. Cardiac drift remains contained, reflecting steady improvements in your aerobic efficiency."
            } else {
                headline = "Efficient Biomechanics"
                observation = "Your turnover is well-stabilized with minimal vertical bounce. Form remains resilient through varying paces and sustains fluid forward momentum."
            }

            let insight = CoachingInsight(
                headline: headline,
                longitudinalObservation: observation,
                drillRecommendation: drill,
                drillRecommendations: [drill]
            )

            let isIndoor: Bool = (index == 37 || index == 36)
            let dataSource: String = (index == 36) ? "gymkit" : "wrist"
            let needsInclineReview: Bool = false
            let classificationConfidence: Double = (index == 37) ? 0.96 : ((index == 36) ? 0.94 : 0.95)
            let effectiveType: String = (index == 37) ? "Fartlek" : (prescribed?.correspondingClassification ?? profile.rawValue)

            let seededSignatureData: Data? = {
                let segments: [PhaseSegment]
                let floor: Double
                if index == 37 {
                    segments = [
                        PhaseSegment(startSeconds: 0, endSeconds: 300, kind: "steady", avgPace: 360, avgCadence: 156, avgHR: 136),
                        PhaseSegment(startSeconds: 300, endSeconds: 540, kind: "work", avgPace: 339, avgCadence: 164, avgHR: 162),
                        PhaseSegment(startSeconds: 540, endSeconds: 720, kind: "recovery", avgPace: 385, avgCadence: 152, avgHR: 138),
                        PhaseSegment(startSeconds: 720, endSeconds: 960, kind: "work", avgPace: 344, avgCadence: 162, avgHR: 166),
                        PhaseSegment(startSeconds: 960, endSeconds: 1140, kind: "recovery", avgPace: 390, avgCadence: 150, avgHR: 140),
                        PhaseSegment(startSeconds: 1140, endSeconds: 1380, kind: "work", avgPace: 341, avgCadence: 163, avgHR: 169),
                        PhaseSegment(startSeconds: 1380, endSeconds: 1560, kind: "recovery", avgPace: 395, avgCadence: 150, avgHR: 143),
                        PhaseSegment(startSeconds: 1560, endSeconds: 1800, kind: "work", avgPace: 343, avgCadence: 164, avgHR: 173),
                        PhaseSegment(startSeconds: 1800, endSeconds: 1980, kind: "recovery", avgPace: 400, avgCadence: 148, avgHR: 147),
                        PhaseSegment(startSeconds: 1980, endSeconds: 2220, kind: "work", avgPace: 342, avgCadence: 163, avgHR: 176),
                        PhaseSegment(startSeconds: 2220, endSeconds: 2475, kind: "steady", avgPace: 370, avgCadence: 154, avgHR: 148)
                    ]
                    floor = 152
                } else if index == 36 {
                    segments = [
                        PhaseSegment(startSeconds: 0, endSeconds: 300, kind: "steady", avgPace: 320, avgCadence: 162, avgHR: 140),
                        PhaseSegment(startSeconds: 300, endSeconds: 900, kind: "work", avgPace: 280, avgCadence: 172, avgHR: 165),
                        PhaseSegment(startSeconds: 900, endSeconds: 1200, kind: "recovery", avgPace: 350, avgCadence: 155, avgHR: 142),
                        PhaseSegment(startSeconds: 1200, endSeconds: 1800, kind: "work", avgPace: 275, avgCadence: 174, avgHR: 168)
                    ]
                    floor = 155
                } else {
                    segments = [
                        PhaseSegment(startSeconds: 0, endSeconds: 300, kind: "steady", avgPace: rawAvgPace, avgCadence: workingCadence, avgHR: workingHR),
                        PhaseSegment(startSeconds: 300, endSeconds: rawDurationSec, kind: "steady", avgPace: rawAvgPace, avgCadence: workingCadence, avgHR: workingHR)
                    ]
                    floor = max(140, workingCadence - 6)
                }
                let sig = RunSignature(
                    classification: effectiveType,
                    confidence: classificationConfidence,
                    probabilities: [effectiveType: classificationConfidence],
                    anomalies: index == 37 ? ["Cardiovascular drift on flat belt"] : [],
                    cadenceFloor: floor,
                    phaseSegments: segments,
                    dataSource: dataSource,
                    isIndoor: isIndoor,
                    needsInclineReview: needsInclineReview
                )
                return try? JSONEncoder().encode(sig)
            }()

            let seededStride = (distanceMeters > 0 && workingCadence > 0 && workingSec > 0)
                ? (distanceMeters / ((workingCadence / 60.0) * workingSec))
                : 1.15

            let record = RunRecord(
                hkWorkoutID: UUID(),
                date: date,
                totalDistanceMeters: distanceMeters,
                duration: rawDurationSec,
                rawAvgPace: rawAvgPace,
                rawAvgHeartRate: rawHR,
                rawAvgCadence: rawCadence,
                workingAvgPace: workingAvgPace,
                workingAvgCadence: workingCadence,
                workingAvgHeartRate: workingHR,
                workingAvgVerticalOscillation: isIndoor ? nil : vertOsc,
                rawAvgVerticalOscillation: isIndoor ? nil : rawOsc,
                rawAvgStrideLength: isIndoor ? nil : seededStride,
                workingAvgStrideLength: isIndoor ? nil : seededStride,
                workingDistanceMeters: distanceMeters,
                workingDurationSeconds: workingSec,
                isIndoor: isIndoor,
                paceCV: paceCV,
                paceSlope: paceSlope,
                percentZone4: percentZone4,
                detectedTypeRaw: effectiveType,
                framboiseTags: {
                    var tags = [effectiveType]
                    if isIndoor { tags.append("indoor") }
                    if index == 37 {
                        tags.append("cardiacDrift")
                        tags.append("fatigueDrift")
                    }
                    if let drill = prescribed {
                        tags.append("prescribedDrill")
                        tags.append(drill.rawValue)
                        tags.append("drill:\(drill.rawValue)")
                        tags.append("drill:\(drill.title)")
                    }
                    return tags
                }(),
                insight: insight,
                dataSourceRaw: dataSource,
                classificationConfidence: classificationConfidence,
                needsInclineReview: needsInclineReview,
                runSignatureData: seededSignatureData
            )

            context.insert(record)
        }

        try? context.save()
        print("✅ Successfully seeded \(totalRuns) SwiftData RunRecords directly with 3-month progression and aligned drill IDs!")
    }

    static func generate15SecondMetrics(
        for profile: MockRunProfile,
        workoutIndex: Int,
        chunkIndex: Int,
        progress: Double
    ) -> (distanceMeters: Double, heartRate: Double, cadence: Double, oscillation: Double, gct: Double, stride: Double) {
        var distance: Double = 0
        var hr: Double = 0
        var cadence: Double = 0

        // Speed scale factor: beginner runs slower (~0.85x), advanced runs faster (~1.12x)
        let speedFactor = 0.85 + (progress * 0.27)
        // Cadence progression offset: -10 SPM early on to +8 SPM later
        let cadenceShift = -10.0 + (progress * 18.0)
        // HR efficiency shift: runs at easy paces cost less cardiac effort as fitness improves
        let hrShift = 6.0 - (progress * 12.0)

        let minuteIndex = chunkIndex / 4

        switch profile {
        case .easy:
            if minuteIndex == 15 {
                distance = 0
                hr = Double.random(in: 125...132)
                cadence = 0
            } else {
                distance = (Double.random(in: 155...165) * speedFactor) / 4.0
                hr = Double.random(in: 135...142) + hrShift
                cadence = Double.random(in: 158...162) + cadenceShift
            }

        case .recovery:
            if workoutIndex == 9 {
                // Flawed recovery workout for testing Not Met adherence (runner pushed into tempo effort)
                distance = (Double.random(in: 175...185) * speedFactor) / 4.0
                hr = Double.random(in: 165...175)
                cadence = Double.random(in: 164...168)
            } else if minuteIndex == 12 {
                distance = 0
                hr = Double.random(in: 118...124)
                cadence = 0
            } else {
                distance = (Double.random(in: 145...155) * speedFactor) / 4.0
                hr = Double.random(in: 122...130) + hrShift
                cadence = Double.random(in: 154...158) + cadenceShift
            }

        case .steady:
            if minuteIndex == 18 {
                distance = 0
                hr = Double.random(in: 135...140)
                cadence = 0
            } else {
                distance = (Double.random(in: 162...172) * speedFactor) / 4.0
                hr = Double.random(in: 148...152) + hrShift
                cadence = Double.random(in: 164...166) + cadenceShift
            }

        case .tempo:
            distance = (Double.random(in: 175...185) * speedFactor) / 4.0
            hr = Double.random(in: 172...179)
            cadence = Double.random(in: 170...174) + (cadenceShift * 0.5)

        case .intervals:
            let isWorkInterval = (minuteIndex % 5) < 3
            let isRestStop = minuteIndex == 14 || minuteIndex == 24
            if isWorkInterval {
                distance = (Double.random(in: 185...195) * speedFactor) / 4.0
                hr = Double.random(in: 178...186)
                cadence = Double.random(in: 174...178) + (cadenceShift * 0.5)
            } else if isRestStop {
                distance = 0
                hr = Double.random(in: 125...135)
                cadence = 0
            } else {
                distance = (Double.random(in: 120...135) * speedFactor) / 4.0
                hr = Double.random(in: 135...145) + hrShift
                cadence = Double.random(in: 150...156) + cadenceShift
            }

        case .fartlek:
            let isFast = (minuteIndex % 4) == 0
            if isFast {
                distance = (Double.random(in: 185...195) * speedFactor) / 4.0
                hr = Double.random(in: 175...183)
                cadence = Double.random(in: 174...178) + (cadenceShift * 0.5)
            } else {
                distance = (Double.random(in: 140...150) * speedFactor) / 4.0
                hr = Double.random(in: 135...145) + hrShift
                cadence = Double.random(in: 155...160) + cadenceShift
            }

        case .progression:
            let minuteProgress = Double(minuteIndex) / 45.0
            distance = ((140.0 + (minuteProgress * 40.0) + Double.random(in: -4...4)) * speedFactor) / 4.0
            hr = 135.0 + (minuteProgress * 40.0) + Double.random(in: -3...3)
            cadence = 155.0 + (minuteProgress * 15.0) + cadenceShift + Double.random(in: -2...2)

        case .longRun:
            let minuteProgress = Double(minuteIndex) / 90.0
            distance = ((155.0 - (minuteProgress * 15.0) + Double.random(in: -5...5)) * speedFactor) / 4.0
            hr = 145.0 + (minuteProgress * 20.0) + Double.random(in: -3...3)
            cadence = 165.0 - (minuteProgress * 5.0) + cadenceShift + Double.random(in: -2...2)

        case .pyramids:
            let cycle = minuteIndex % 8
            let isPause = minuteIndex == 15
            if isPause {
                distance = 0
                hr = Double.random(in: 130...138)
                cadence = 0
            } else {
                let effort = cycle < 4 ? Double(cycle) : Double(7 - cycle)
                distance = ((148.0 + (effort * 10.0)) * speedFactor) / 4.0
                hr = 145.0 + (effort * 8.0)
                cadence = 160.0 + (effort * 3.0) + (cadenceShift * 0.5)
            }

        case .hillRepeats:
            let isUphill = (minuteIndex % 3) == 0
            let isPauseAtBottom = minuteIndex == 14 || minuteIndex == 26
            if isUphill {
                distance = (Double.random(in: 130...140) * speedFactor) / 4.0
                hr = Double.random(in: 175...185)
                cadence = Double.random(in: 156...162) + (cadenceShift * 0.5)
            } else if isPauseAtBottom {
                distance = 0
                hr = Double.random(in: 130...140)
                cadence = 0
            } else {
                distance = (Double.random(in: 120...135) * speedFactor) / 4.0
                hr = Double.random(in: 138...148) + hrShift
                cadence = Double.random(in: 150...155) + cadenceShift
            }

        case .urbanTraffic:
            let isDeadStop = (minuteIndex == 12 || minuteIndex == 25)
            if isDeadStop {
                distance = 0
                hr = Double.random(in: 130...140)
                cadence = 0
            } else {
                distance = (Double.random(in: 155...165) * speedFactor) / 4.0
                hr = Double.random(in: 145...155) + hrShift
                cadence = Double.random(in: 160...165) + cadenceShift
            }
        }

        // Biomechanical relationships:
        // Lower turnover & beginner stage = higher vertical oscillation and longer ground contact time
        let baseOsc = 10.4 - (progress * 2.4)
        let baseGCT = 275.0 - (progress * 42.0)

        let osc = cadence > 0 ? max(6.8, baseOsc + Double.random(in: -0.3...0.3)) : 0.0
        let gct = cadence > 0 ? max(210.0, baseGCT + Double.random(in: -6...6)) : 0.0

        // Exact physical derivation from Velocity Equation: Stride (m) = Distance (m) / StepCount
        let stepsInChunk = (cadence / 60.0) * 15.0
        let stride = (stepsInChunk > 0 && distance > 0) ? min(1.8, max(0.6, distance / stepsInChunk)) : 0.0

        return (distanceMeters: distance, heartRate: max(100.0, hr), cadence: max(0, cadence), oscillation: osc, gct: gct, stride: stride)
    }
}
