import Foundation

/// Centralized repository of canonical UI explainer copy, metric definitions,
/// and coaching guidelines.
///
/// Implements the "Thick Client, Thin AI" architectural doctrine:
/// - Provides compact, token-efficient summaries (1–2 sentences) to ground LLM tool responses
///   under Apple TN3193 4,096-token limits.
/// - Supplies rich, multi-section copy (`overview`, `modeContext`, `whyItMatters`, `targetRange`)
///   for native interactive cards and bottom sheets.
/// - Guarantees 100% deterministic consistency between UI sheets and AI coaching responses.
public struct CoachingAssetLibrary: Sendable {

    // MARK: - Asset Model

    public struct Asset: Sendable, Identifiable {
        public var id: String { key }
        public let key: String
        public let title: String
        public let domain: AssetDomain
        public let compactSummary: String
        public let overview: String
        public let modeContext: String?
        public let whyItMatters: String?
        public let targetRange: String?

        public init(
            key: String,
            title: String,
            domain: AssetDomain,
            compactSummary: String,
            overview: String,
            modeContext: String? = nil,
            whyItMatters: String? = nil,
            targetRange: String? = nil
        ) {
            self.key = key
            self.title = title
            self.domain = domain
            self.compactSummary = compactSummary
            self.overview = overview
            self.modeContext = modeContext
            self.whyItMatters = whyItMatters
            self.targetRange = targetRange
        }
    }

    public enum AssetDomain: String, Sendable, CaseIterable {
        case biomechanics = "Biomechanics"
        case cardio = "Cardio & Heart Rate"
        case pacing = "Pacing & Speed"
        case physiology = "Physiology & Recovery"
        case physics = "Physics & Environment"
        case drills = "Drills & Prescriptions"
        case system = "System & Data"
    }

    // MARK: - Static Registry

    public static let allAssets: [Asset] = [
        // --- BIOMECHANICS ---
        Asset(
            key: "cadence",
            title: "Average Cadence",
            domain: .biomechanics,
            compactSummary: "Step turnover per minute (SPM). Quicker turnover (160–180 SPM) keeps landings under your hips to reduce knee impact.",
            overview: "How many steps you take per minute (SPM).",
            modeContext: "Working Stats measures step turnover strictly while actively running, showing true rhythm.",
            whyItMatters: "Efficiency: Taking quicker, shorter steps keeps your feet landing under your hips, protecting your knees and shins.",
            targetRange: "Target Range: 160 to 180 SPM for a smooth, springy stride.\n\n• Low Cadence (< 160 SPM): Often means you are overstriding and landing with a heavy brake on your knees.\n• High Cadence (> 185 SPM): Normal during fast sprints, but don't force it on easy recovery days."
        ),
        Asset(
            key: "cadence_floor",
            title: "Height-Calibrated Cadence Floor",
            domain: .biomechanics,
            compactSummary: "Anatomical cadence threshold calculated from height. Dropping below this floor increases ground contact time and braking shock.",
            overview: "A personalized cadence floor calculated from your height. Falling below this floor increases braking shock and ground impact on your knees and hips.",
            modeContext: "Computed deterministically in Swift using your anatomical height.",
            whyItMatters: "Injury Protection: Maintaining turnover at or above your cadence floor keeps your feet landing under your center of mass, mitigating joint stress.",
            targetRange: "Target: Above your height-calibrated floor during active running."
        ),
        Asset(
            key: "vertical_oscillation",
            title: "Bounce (Vertical Oscillation)",
            domain: .biomechanics,
            compactSummary: "Upward and downward motion of your body per stride (cm). Bouncing > 10 cm wastes energy and indicates overstriding.",
            overview: "Measures the upward and downward bounce of your body with each stride, recorded in centimeters.",
            modeContext: "Working Stats measures bounce only while you are actively running, filtering out pauses and walking to show your true form.",
            whyItMatters: "Efficiency: Running is about moving forward. Reaching your foot too far in front acts like a brake, sending your energy upward into wasted bounce and stress on your joints.",
            targetRange: "Target Range: Most efficient runners bounce between 6 to 10 cm.\n\n• High Bounce (> 10 cm): Common when reaching too far ahead, increasing impact on knees.\n• Low Bounce (< 6 cm): Can cause fatigue from a flat, shuffling stride, though high bounce is much more common."
        ),
        Asset(
            key: "ground_contact_time",
            title: "Ground Contact Time",
            domain: .biomechanics,
            compactSummary: "Time your foot spends on the ground per step (ms). Under 240 ms reflects springy, elastic running economy.",
            overview: "How long your foot stays on the ground with each step, in milliseconds (ms).",
            modeContext: "Working Stats measures foot contact only while running to see how springy your stride is.",
            whyItMatters: "Efficiency: Less time on the ground means lighter, springier steps and less wasted effort.",
            targetRange: "Target Range: 200 to 250 ms for most runners; under 200 ms when running fast.\n\n• High Contact (> 260 ms): Can mean sinking into each step rather than springing forward.\n• Low Contact (< 200 ms): Quick, springy turnover with light foot strikes."
        ),
        Asset(
            key: "stride_length",
            title: "Stride Length",
            domain: .biomechanics,
            compactSummary: "Distance between consecutive footsteps. Stride should lengthen via hip drive and push-off, never by reaching forward.",
            overview: "The distance between consecutive footsteps, measured in meters or feet.",
            modeContext: "Working Stats reflects your stride length at your regular running speed.",
            whyItMatters: "Efficiency: Your stride should open up naturally from pushing behind you, not by reaching your foot too far in front.",
            targetRange: "Target Range: Usually 1.0 to 1.4 m depending on your height, pace, and cadence.\n\n• Overstriding: Reaching forward acts like a brake and strains your knees.\n• Short Stride: Often means tight hips or not pushing off fully."
        ),
        Asset(
            key: "vertical_ratio",
            title: "Bounce Ratio (Vertical Ratio)",
            domain: .biomechanics,
            compactSummary: "Percentage of upward bounce relative to forward stride distance. Lower than 8.0% reflects elite forward propulsion.",
            overview: "The percentage of upward bounce compared to how far forward you travel with each stride.",
            modeContext: "Working Stats: Calculated strictly during active running to check how forward-moving your stride is.",
            whyItMatters: "Efficiency: Lower is better. A lower percentage means more of your energy pushes you forward instead of bouncing you up and down.",
            targetRange: "Target Range: Under 8.0% is very efficient. 8.0%–9.5% is typical. Above 9.5% means you are bouncing too high or reaching your foot too far forward."
        ),
        Asset(
            key: "overstriding",
            title: "Overstriding & Braking Shock",
            domain: .biomechanics,
            compactSummary: "Landing with your foot ahead of your center of mass, acting as a brake and transmitting impact forces through joints.",
            overview: "When the foot lands ahead of a flexed knee, vertical bounce spikes and forward momentum is lost to ground braking shock.",
            modeContext: "Identified when cadence falls below floor while vertical oscillation exceeds 10 cm.",
            whyItMatters: "Joint Safety: Reaching forward creates high eccentric braking shock. Shortening your stride and raising turnover protects your knees and hips.",
            targetRange: "Target: Feet landing close under your hips with cadence above your personal floor."
        ),

        // --- CARDIO & HEART RATE ---
        Asset(
            key: "heart_rate",
            title: "Average Heart Rate",
            domain: .cardio,
            compactSummary: "Cardiovascular effort in beats per minute (BPM). Keeps easy runs truly aerobic and confirms hard workout targets.",
            overview: "How fast your heart is beating during your run, recorded in Beats Per Minute (BPM).",
            modeContext: "Working Stats: Your average heart rate while actively running, showing the true effort of your pace.",
            whyItMatters: "Efficiency: Shows how hard your heart is working so you don't accidentally push too hard on easy days.",
            targetRange: "Target Range: Zone 2 (easy and conversational) for building base stamina; Zone 4 for fast workouts.\n\n• High HR: Can be a sign of dehydration, heat, fatigue, or starting out too fast.\n• Controlled HR: Confirms you are running at a comfortable, sustainable effort."
        ),
        Asset(
            key: "cardiac_drift",
            title: "Cardiac Drift (Decoupling)",
            domain: .cardio,
            compactSummary: "Gradual rise in heart rate during constant pace, caused by core temperature rise, dehydration, or late fatigue.",
            overview: "When pace stays flat or slows while heart rate creeps upward over the second half of a workout.",
            modeContext: "Evaluated across first-half vs. second-half continuous splits.",
            whyItMatters: "Conditioning & Hydration: Drift > 8 BPM signals significant cardiovascular strain, inadequate hydration, or fatigue.",
            targetRange: "Target: Under 5 BPM drift on steady aerobic runs. Higher drift on hot days or long runs signals need for recovery."
        ),
        Asset(
            key: "efficiency_factor",
            title: "Aerobic Efficiency Factor",
            domain: .cardio,
            compactSummary: "Distance covered per heartbeat (m/beat). A rising trend proves your aerobic engine is producing more speed with less cardiac strain.",
            overview: "Measures cardiac economy by comparing meters traveled per heart beat. A rising efficiency factor indicates improving cardiovascular endurance.",
            modeContext: "Calculated strictly during steady-state aerobic segments.",
            whyItMatters: "True Fitness Metric: Demonstrates producing greater forward speed per heartbeat, proving structural mitochondrial growth.",
            targetRange: "Target: Higher is better. A steady or upward trend over 30 days confirms true aerobic progress."
        ),
        Asset(
            key: "zone_1_hr",
            title: "Zone 1 Heart Rate",
            domain: .cardio,
            compactSummary: "Very gentle active recovery effort (< 60% HR max). Gently circulates blood to clear metabolic fatigue without muscular strain.",
            overview: "A very gentle, active-recovery effort (under 60% of maximum heart rate) designed to stimulate blood flow without fatigue.",
            modeContext: "Working Stats: Measures your heart rate strictly while actively moving.",
            whyItMatters: "Active Recovery: Gently circulates blood to flush out metabolic byproducts and deliver oxygen to tired muscles, accelerating recovery.",
            targetRange: "Target: Zone 1 HR (effortless recovery).\n\n• Effort: Effortless pace; breathing is relaxed and conversational.\n• Apple Watch: Haptic cues notify you if your heart rate creeps above Zone 1 into higher training zones."
        ),
        Asset(
            key: "zone_2_hr",
            title: "Zone 2 Heart Rate",
            domain: .cardio,
            compactSummary: "Steady conversational aerobic intensity (60–70% HR max) that optimizes fat oxidation and expands mitochondrial density.",
            overview: "A steady, conversational aerobic intensity (typically 60%–70% of maximum heart rate) where your body primarily burns fat for fuel.",
            modeContext: "Working Stats: Measures your heart rate strictly while actively running.",
            whyItMatters: "Aerobic Capacity: Zone 2 expands mitochondrial density and cardiac stroke volume without muscular burnout, building a deep endurance engine.",
            targetRange: "Target: Zone 2 HR (conversational effort).\n\n• Effort: You should easily be able to talk in full sentences.\n• Apple Watch: Workout alerts will notify you via haptics if your heart rate climbs into Zone 3."
        ),
        Asset(
            key: "vo2_max",
            title: "VO2 Max",
            domain: .cardio,
            compactSummary: "Maximal rate of oxygen consumption (mL/kg/min). The gold-standard benchmark of overall aerobic power and stamina.",
            overview: "An estimate of your aerobic fitness and stamina, recorded in mL/kg/min.",
            modeContext: "Working Stats: Your aerobic fitness calculated from outdoor running workouts.",
            whyItMatters: "Endurance Capacity: A clear benchmark of your overall endurance engine and heart health.",
            targetRange: "Target Range: 38 to 48+ for active runners; 50+ for competitive runners.\n\n• Rising Trend: Your stamina and aerobic fitness are improving.\n• Declining Trend: Can signal heavy legs, fatigue, heat, or needing more rest."
        ),

        // --- PACING & SPEED ---
        Asset(
            key: "pace",
            title: "Average Pace",
            domain: .pacing,
            compactSummary: "Minutes and seconds per kilometer or mile. Working pace filters out pauses and stoplights to reveal your true running speed.",
            overview: "The time it takes to run one kilometer or mile, shown in minutes and seconds.",
            modeContext: "Working Stats: Your true running speed. Automatically filters out red lights, pauses, and walking breaks.",
            whyItMatters: "Efficiency: Running at a steady, controlled pace saves energy and keeps you from burning out early.",
            targetRange: "Target Range: Matched to the goal of today's run (easy run vs. faster workout).\n\n• Too Fast: Burns your legs out too early on easy days.\n• Controlled: Builds lasting stamina and makes running feel easier."
        ),
        Asset(
            key: "pacing_consistency",
            title: "Pace Consistency (CV)",
            domain: .pacing,
            compactSummary: "Pace variation across splits. Coefficient of variation (CV) < 0.15 indicates disciplined, energy-saving speed control.",
            overview: "Pace variation, measuring how smoothly and evenly you held your speed.",
            modeContext: "Working Stats: Calculated only during continuous running to show your pacing control.",
            whyItMatters: "Efficiency: Running with smooth, even pacing saves energy and keeps you from hitting the wall late in a run.",
            targetRange: "Target Range: CV under 0.15 indicates very steady, controlled pacing.\n\n• High Variation (> 0.20): Expected on hills or interval runs; on flat runs it means your pace was uneven.\n• Low Variation (< 0.10): Very steady and smooth pacing."
        ),

        // --- PHYSIOLOGY & RECOVERY ---
        Asset(
            key: "recovery_timeline",
            title: "Recovery Timeline & Readiness",
            domain: .physiology,
            compactSummary: "Deterministic hours required before the body can safely absorb high-intensity training, preventing injury and overtraining.",
            overview: "A biological readiness model that assesses acute fatigue, recent workout intensity, and cardiac recovery to protect you from overtraining.",
            modeContext: "Updated dynamically after every HealthKit workout sync.",
            whyItMatters: "Injury Protection: Stacking hard efforts on unrecovered muscle tissue multiplies injury risk. Recovery periods are when fitness adaptation actually occurs.",
            targetRange: "Target: 48–72 hours between hard quality sessions; easy Zone 1 or Zone 2 runs permitted during recovery windows."
        ),
        Asset(
            key: "training_load",
            title: "30-Day Training Load (ACWR)",
            domain: .physiology,
            compactSummary: "Ratio of acute 7-day workload to chronic 28-day baseline. Kept between 0.8–1.3 for safe, steady fitness progression.",
            overview: "Tracks your acute-to-chronic workload ratio (ACWR). Compares what you did this past week against your established month-long fitness base.",
            modeContext: "Calculated across your rolling 30-day HealthKit history.",
            whyItMatters: "Safe Progression: Spiking weekly volume faster than your connective tissue can adapt is the primary cause of running injuries.",
            targetRange: "Sweet Spot: 0.8 to 1.3. Values > 1.5 indicate an acute fatigue danger zone."
        ),
        Asset(
            key: "longitudinal_progression",
            title: "Longitudinal Progression",
            domain: .physiology,
            compactSummary: "Tracks multi-month physiological economy (Efficiency Factor) and speed trends across identical workout types.",
            overview: "Tracks your aerobic fitness evolution over weeks and months by plotting Efficiency Factor (Speed ÷ Heart Rate) or Average Pace for specific run classifications.",
            modeContext: "Longitudinal Trends: Isolated to identical workout types across 30 days to All Time for true apples-to-apples comparisons.",
            whyItMatters: "Long-Term Adaptation: Shows whether your aerobic engine is becoming more efficient—running faster at the same heart rate—or if fatigue is accumulating.",
            targetRange: "Target: Upward or stable trajectory across training cycles. Upward slopes prove cardiovascular expansion; downward dips signal chronic fatigue or heat strain."
        ),

        // --- PHYSICS & ENVIRONMENT ---
        Asset(
            key: "treadmill_physics",
            title: "Indoor Treadmill Physics",
            domain: .physics,
            compactSummary: "Motorized treadmill belts pull feet backward and static room air eliminates wind cooling, causing elevated heart rate.",
            overview: "Running on a motorized belt eliminates wind resistance and aerodynamic drag, but the lack of convective wind cooling causes thermal heat to accumulate rapidly.",
            modeContext: "Indoor Running: Arm swing heuristics damp erratic wrist motion.",
            whyItMatters: "Thermodynamics & Heart Rate: Heart rate typically runs 5–10 BPM higher indoors due to thermal load even though mechanical workload is slightly lower.",
            targetRange: "Use fans and hydration indoors to mitigate thermal cardiac drift."
        ),

        Asset(
            key: "distance",
            title: "Distance",
            domain: .pacing,
            compactSummary: "Total distance covered in km or miles. Working distance counts active running to track authentic volume safely.",
            overview: "Total distance covered during the workout in kilometers or miles.",
            modeContext: "Working Stats: Distance covered only while actively running.",
            whyItMatters: "Safe Volume: Tracking authentic running mileage helps build endurance safely without doing too much too soon.",
            targetRange: "Target Range: Matched to what you planned for today's run.\n\n• Too Much Volume: Bumping up mileage too quickly raises injury risk.\n• Low Volume: Great for easy recovery runs."
        ),
        Asset(
            key: "total_time",
            title: "Total Time",
            domain: .pacing,
            compactSummary: "Moving duration spent running. Pause-trimmed moving time filters out stoplights and pauses to reflect true session duration.",
            overview: "How long you were out, displayed in minutes and seconds.",
            modeContext: "Working Stats: Moving time spent running. Automatically pauses when you stop at lights.",
            whyItMatters: "Accuracy: Shows how much time you actually spent running versus standing or waiting at crosswalks.",
            targetRange: "Target Range: Matched to your planned workout duration.\n\n• Longer Runs: Build endurance and mental stamina.\n• Shorter Runs: Perfect for quick drills and recovery."
        ),
        Asset(
            key: "workout_density",
            title: "Workout Density",
            domain: .physiology,
            compactSummary: "Frequency of running sessions over a given timeframe (typically 3–5 runs/week) to build fitness safely with sufficient rest.",
            overview: "How consistently you have been running over your selected timeframe.",
            modeContext: "Working Stats: Your active running workout frequency.",
            whyItMatters: "Consistency: Getting out regularly with enough rest in between builds fitness without burning you out.",
            targetRange: "Target Range: 3 to 5 runs per week for steady progress.\n\n• High Density (5+ runs): Great for experienced runners; be sure to get plenty of sleep and recovery.\n• Low Density (≤ 2 runs): Good for maintaining fitness; harder to build new endurance."
        ),
        Asset(
            key: "target_cadence",
            title: "Target Cadence",
            domain: .biomechanics,
            compactSummary: "Calibrated turnover goal (typically 3–5 SPM above baseline) to reduce joint impact and overstriding.",
            overview: "A step rate goal based on your recent runs to help lighten your stride.",
            modeContext: "Working Stats: Calibrated to your recent running pace.",
            whyItMatters: "Joint Safety: Taking slightly quicker steps softens your landings and protects your shins and knees.",
            targetRange: "Target Range: Usually 3 to 5 SPM above your baseline, capped at 180 SPM.\n\n• Cadence Drills: Help your legs get used to lighter, quicker steps without extra effort."
        ),
        // --- SYSTEM & STATS MODES ---
        Asset(
            key: "working_stats",
            title: "Working Stats",
            domain: .system,
            compactSummary: "Pause-trimmed moving telemetry filtering out stoplights and slow walks to reflect true biomechanical and cardiovascular form.",
            overview: "Filters out stops, pauses, and walking breaks so you see your true running numbers.",
            modeContext: "Active Running: We only count the minutes and miles when you are actually running.",
            whyItMatters: "Accuracy: Red lights and shoe-tying pauses won't artificially drag down your pace, heart rate, or cadence.",
            targetRange: "Use Working Stats to see how your running form and fitness are really doing."
        ),
        Asset(
            key: "workout_stats",
            title: "Workout Stats",
            domain: .system,
            compactSummary: "Gross HealthKit session metrics from start to finish, including paused time, crosswalks, and walking recovery.",
            overview: "Shows everything recorded by your Apple Watch from start to finish, including walking and pauses.",
            modeContext: "Full Workout: Counts everything from the moment you hit Start to when you hit Finish.",
            whyItMatters: "Session Context: Useful when you want to see your total time on feet and total gross workout duration.",
            targetRange: "Use Workout Stats to review your total workout duration and raw Apple Health numbers."
        ),
        Asset(
            key: "run_classification",
            title: "Run Classification",
            domain: .system,
            compactSummary: "Categorizes workouts (e.g. Easy Run, Steady Effort, Intervals, Fartlek) using multi-signal pace and heart rate telemetry.",
            overview: "Analyzes your continuous heart rate, pace consistency, and stride mechanics to determine the type of workout your body performed.",
            modeContext: "CoreML & Biometrics: Combines on-device machine learning with physiological rules so physical cardiac strain always takes priority over model guesswork.",
            whyItMatters: "Accuracy: Ensures recovery runs, steady efforts, and high-intensity interval sessions are accurately recognized so your AI training advice stays calibrated.",
            targetRange: "Categories include Easy Run, Steady Effort, Tempo Run, Intervals, Progression Run, Long Run, and Recovery Run. You can tap the menu to override the label anytime."
        )
    ]

    // MARK: - Lookup & Resolution

    /// Resolves an asset definition by canonical key or common alias.
    public static func resolve(key: String) -> Asset? {
        let normalized = key.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")

        // Exact key match
        if let exact = allAssets.first(where: { $0.key == normalized }) {
            return exact
        }

        // Alias matching
        switch normalized {
        case "bounce", "vert._osc.", "vert_osc", "vertical_oscillation", "vert_oscillation":
            return asset(for: "vertical_oscillation")
        case "cadence_floor", "height_cadence_floor", "floor":
            return asset(for: "cadence_floor")
        case "avg_pace", "pace", "working_pace", "speed":
            return asset(for: "pace")
        case "avg_cadence", "cadence", "turnover", "spm":
            return asset(for: "cadence")
        case "avg_hr", "hr", "heart_rate", "heartrate":
            return asset(for: "heart_rate")
        case "drift", "cardiac_drift", "decoupling":
            return asset(for: "cardiac_drift")
        case "efficiency", "efficiency_factor", "aerobic_efficiency", "aerobic_efficiency_factor":
            return asset(for: "efficiency_factor")
        case "gct", "ground_contact", "ground_contact_time":
            return asset(for: "ground_contact_time")
        case "stride", "stride_length", "avg_stride":
            return asset(for: "stride_length")
        case "bounce_ratio", "vertical_ratio", "vert_ratio":
            return asset(for: "vertical_ratio")
        case "cv", "pace_cv", "cv_(var)", "pacing_consistency", "consistency":
            return asset(for: "pacing_consistency")
        case "overstride", "overstriding", "braking_shock":
            return asset(for: "overstriding")
        case "vo2max", "vo2_max":
            return asset(for: "vo2_max")
        case "recovery", "recovery_timeline", "readiness":
            return asset(for: "recovery_timeline")
        case "load", "acwr", "training_load", "30_day_load":
            return asset(for: "training_load")
        case "treadmill", "treadmill_physics", "indoor_physics":
            return asset(for: "treadmill_physics")
        case "working_stats", "working":
            return asset(for: "working_stats")
        case "workout_stats", "workout":
            return asset(for: "workout_stats")
        case "zone_1", "zone_1_hr", "recovery_flush", "target_zone_1_hr", "zone_1_heart_rate":
            return asset(for: "zone_1_hr")
        case "zone_2", "zone_2_hr", "aerobic_base", "target_zone_2_hr", "zone_2_heart_rate":
            return asset(for: "zone_2_hr")
        case "classification", "run_classification", "coreml", "coreml_override":
            return asset(for: "run_classification")
        case "distance":
            return asset(for: "distance")
        case "total_time", "time", "moving_time":
            return asset(for: "total_time")
        case "density", "workout_density":
            return asset(for: "workout_density")
        case "target_cadence":
            return asset(for: "target_cadence")
        case "longitudinal", "longitudinal_progression", "progression", "progression_chart":
            return asset(for: "longitudinal_progression")
        default:
            return nil
        }
    }

    private static func asset(for key: String) -> Asset? {
        allAssets.first { $0.key == key }
    }

    /// Provides a fallback asset if a raw query string does not match standard keys.
    public static func defaultAsset(for rawKey: String) -> Asset {
        let title = rawKey.replacingOccurrences(of: "_", with: " ").capitalized
        return Asset(
            key: rawKey.lowercased(),
            title: title,
            domain: .biomechanics,
            compactSummary: "A running telemetry metric tracked by Apple Health and analyzed deterministically by Runalyst.",
            overview: "A running metric tracked by Apple Health and analyzed by Runalyst.",
            modeContext: "Working Stats filters out pauses to reflect numbers while actively running.",
            whyItMatters: "Tracking your numbers over time helps spot fatigue and protect against injury.",
            targetRange: "Compare against your personalized 30-day baseline to see your progress."
        )
    }

    // MARK: - Dynamic Facade Grounding Helpers

    /// Extracts compact 1-2 sentence definitions for the metrics present or anomalous in a workout.
    /// Strictly limits the map to 4–6 relevant keys to respect the 4,096-token limit.
    public static func compactExplainers(forMetrics metrics: [String]) -> [String: String] {
        var result: [String: String] = [:]
        for metric in metrics {
            if let asset = resolve(key: metric) {
                result[asset.key] = asset.compactSummary
            }
        }
        return result
    }

    public struct WorkoutFeatureSet: Sendable {
        public let isIndoor: Bool
        public let hasCardiacDrift: Bool
        public let hasEfficiencyFactor: Bool
        public let hasVerticalOscillation: Bool
        public let hasGroundContactTime: Bool
        public let hasStrideLength: Bool
        public let isIntervals: Bool

        public init(
            isIndoor: Bool = false,
            hasCardiacDrift: Bool = false,
            hasEfficiencyFactor: Bool = false,
            hasVerticalOscillation: Bool = false,
            hasGroundContactTime: Bool = false,
            hasStrideLength: Bool = false,
            isIntervals: Bool = false
        ) {
            self.isIndoor = isIndoor
            self.hasCardiacDrift = hasCardiacDrift
            self.hasEfficiencyFactor = hasEfficiencyFactor
            self.hasVerticalOscillation = hasVerticalOscillation
            self.hasGroundContactTime = hasGroundContactTime
            self.hasStrideLength = hasStrideLength
            self.isIntervals = isIntervals
        }
    }

    /// Dynamically selects the most relevant 4–6 metric explainers for a workout analysis context.
    public static func selectExplainers(features: WorkoutFeatureSet) -> [String: String] {
        var keys: [String] = ["working_stats", "cadence_floor"]

        if features.isIndoor {
            keys.append("treadmill_physics")
        }
        if features.hasCardiacDrift {
            keys.append("cardiac_drift")
        }
        if features.hasEfficiencyFactor {
            keys.append("efficiency_factor")
        }
        if features.hasVerticalOscillation {
            keys.append("vertical_oscillation")
        }
        if features.hasGroundContactTime && keys.count < 6 {
            keys.append("ground_contact_time")
        }
        if features.hasStrideLength && keys.count < 6 {
            keys.append("stride_length")
        }
        if features.isIntervals && keys.count < 6 {
            keys.append("pacing_consistency")
        }
        if keys.count < 4 {
            keys.append("cadence")
        }
        if keys.count < 5 {
            keys.append("pace")
        }

        return compactExplainers(forMetrics: keys)
    }

    /// Selects canonical guidance notes to ground readiness tool responses.
    public static func readinessGuidance(for verdict: String, isDistress: Bool) -> [String: String] {
        var notes: [String: String] = [:]
        if let recoveryAsset = resolve(key: "recovery_timeline") {
            notes["recovery_policy"] = recoveryAsset.compactSummary
        }
        if isDistress || verdict.contains("REST") {
            notes["medical_boundary"] = "Prioritize biological rest over training targets. Advise consulting a physical therapist or sports physician if symptoms persist."
        } else {
            if let z2 = resolve(key: "zone_2_hr") {
                notes["aerobic_zone_guidelines"] = z2.compactSummary
            }
            if let load = resolve(key: "training_load") {
                notes["load_progression"] = load.compactSummary
            }
        }
        return notes
    }

    /// Backwards compatibility bridge for `MetricDetailExplainer`.
    public static func explainer(for title: String, isWorkoutStats: Bool) -> MetricDetailExplainer {
        if let asset = resolve(key: title) {
            let modeContext = isWorkoutStats
                ? "Workout Stats: Averages across your entire session, including pauses and walking."
                : (asset.modeContext ?? "Working Stats: Measures strictly while actively running.")
            return MetricDetailExplainer(
                title: asset.title,
                overview: asset.overview,
                modeContext: modeContext,
                whyItMatters: asset.whyItMatters ?? "Efficiency: Keeping track of your numbers over time helps you spot fatigue and avoid injury.",
                targetRange: asset.targetRange ?? "Compare against your personalized 30-day baseline to see your progress."
            )
        }
        return MetricDetailExplainer(
            title: title,
            overview: "A running metric tracked by Apple Health and analyzed by Runalyst.",
            modeContext: isWorkoutStats
                ? "Workout Stats: Unadjusted session data directly from Apple Health."
                : "Working Stats: Filtered to show your numbers while actually running.",
            whyItMatters: "Efficiency: Keeping track of your numbers over time helps you spot fatigue and avoid injury.",
            targetRange: "Compare against your personalized 30-day baseline to see your progress."
        )
    }

    /// Converts an asset to `MetricExplainerInfo` for presentation in `MetricExplainerSheet`.
    public static func explainerInfo(for key: String, mode: String? = nil, userMetricDisplay: String? = nil) -> MetricExplainerInfo? {
        guard let asset = resolve(key: key) else { return nil }
        return MetricExplainerInfo(
            title: asset.title,
            mode: mode ?? "Working Stats",
            overview: asset.overview,
            modeContext: asset.modeContext,
            whyItMatters: asset.whyItMatters,
            targetRange: asset.targetRange,
            userMetricDisplay: userMetricDisplay
        )
    }
}
