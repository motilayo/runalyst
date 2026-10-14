import Foundation

/// Structured metric explainer providing consistent format across Working and Workout stats.
struct MetricDetailExplainer {
    let title: String
    let overview: String
    let modeContext: String
    let whyItMatters: String
    let targetRange: String

    static func explainer(for title: String, isWorkoutStats: Bool) -> MetricDetailExplainer {
        switch title.lowercased() {
        case "bounce", "vert. osc.", "vertical oscillation":
            return MetricDetailExplainer(
                title: "Bounce (Vertical Oscillation)",
                overview: "Measures the upward and downward bounce of your body with each stride, recorded in centimeters.",
                modeContext: isWorkoutStats
                    ? "Workout Stats: Averages bounce across your whole session from start to finish, including walking pauses."
                    : "Working Stats: Measures bounce only while you are actively running, filtering out pauses and walking to show your true form.",
                whyItMatters: "Efficiency: Running is about moving forward. Reaching your foot too far in front acts like a brake, sending your energy upward into wasted bounce and stress on your joints.",
                targetRange: "Target Range: Most efficient runners bounce between 6 to 10 cm.\n\n• High Bounce (> 10 cm): Common when reaching too far ahead, increasing impact on knees.\n• Low Bounce (< 6 cm): Can cause fatigue from a flat, shuffling stride, though high bounce is much more common."
            )
        case "avg pace", "pace":
            return MetricDetailExplainer(
                title: "Average Pace",
                overview: "The time it takes to run one kilometer or mile, shown in minutes and seconds.",
                modeContext: isWorkoutStats
                    ? "Workout Stats: Overall pace dividing total clock time by total distance, counting all pauses and slow walks."
                    : "Working Stats: Your true running speed. Automatically filters out red lights, pauses, and walking breaks.",
                whyItMatters: "Efficiency: Running at a steady, controlled pace saves energy and keeps you from burning out early.",
                targetRange: "Target Range: Matched to the goal of today's run (easy run vs. faster workout).\n\n• Too Fast: Burns your legs out too early on easy days.\n• Controlled: Builds lasting stamina and makes running feel easier."
            )
        case "avg cadence", "cadence", "average cadence":
            return MetricDetailExplainer(
                title: "Average Cadence",
                overview: "How many steps you take per minute (SPM).",
                modeContext: isWorkoutStats
                    ? "Workout Stats: Blends in slow walking steps (~100–120 SPM) and pauses, bringing down your overall average."
                    : "Working Stats: Your step turnover while actually running, showing your true rhythm.",
                whyItMatters: "Efficiency: Taking quicker, shorter steps keeps your feet landing under your hips, protecting your knees and shins.",
                targetRange: "Target Range: 160 to 180 SPM for a smooth, springy stride.\n\n• Low Cadence (< 160 SPM): Often means you are overstriding and landing with a heavy brake on your knees.\n• High Cadence (> 185 SPM): Normal during fast sprints, but don't force it on easy recovery days."
            )
        case "avg hr", "heart rate", "hr":
            return MetricDetailExplainer(
                title: "Average Heart Rate",
                overview: "How fast your heart is beating during your run, recorded in Beats Per Minute (BPM).",
                modeContext: isWorkoutStats
                    ? "Workout Stats: Your average heart rate across the whole workout, including warm-up, rest breaks, and cool-down."
                    : "Working Stats: Your average heart rate while actively running, showing the true effort of your pace.",
                whyItMatters: "Efficiency: Shows how hard your heart is working so you don't accidentally push too hard on easy days.",
                targetRange: "Target Range: Zone 2 (easy and conversational) for building base stamina; Zone 4 for fast workouts.\n\n• High HR: Can be a sign of dehydration, heat, fatigue, or starting out too fast.\n• Controlled HR: Confirms you are running at a comfortable, sustainable effort."
            )
        case "zone 1 hr", "target zone 1 hr", "zone 1 heart rate":
            return MetricDetailExplainer(
                title: "Zone 1 Heart Rate",
                overview: "A very gentle, active-recovery effort (under 60% of maximum heart rate) designed to stimulate blood flow without fatigue.",
                modeContext: isWorkoutStats
                    ? "Workout Stats: Averages heart rate across your entire session, including pauses and walking."
                    : "Working Stats: Measures your heart rate strictly while actively moving.",
                whyItMatters: "Active Recovery: Gently circulates blood to flush out metabolic byproducts and deliver oxygen and nutrients to tired muscles, accelerating recovery.",
                targetRange: "Target: Zone 1 HR (effortless recovery).\n\n• Effort: Effortless pace; breathing is relaxed and conversational.\n• Apple Watch: Haptic cues notify you if your heart rate creeps above Zone 1 into higher training zones."
            )
        case "zone 2 hr", "target zone 2 hr", "zone 2 heart rate":
            return MetricDetailExplainer(
                title: "Zone 2 Heart Rate",
                overview: "A steady, conversational aerobic intensity (typically 60%–70% of maximum heart rate) where your body primarily burns fat for fuel.",
                modeContext: isWorkoutStats
                    ? "Workout Stats: Averages heart rate across your entire session, including pauses and walking."
                    : "Working Stats: Measures your heart rate strictly while actively running.",
                whyItMatters: "Aerobic Capacity: Zone 2 expands mitochondrial density and cardiac stroke volume without muscular burnout, building a deep endurance engine.",
                targetRange: "Target: Zone 2 HR (conversational effort).\n\n• Effort: You should easily be able to talk in full sentences.\n• Apple Watch: Workout alerts will notify you via haptics if your heart rate climbs into Zone 3."
            )
        case "distance":
            return MetricDetailExplainer(
                title: "Distance",
                overview: "Total distance covered during the workout in kilometers or miles.",
                modeContext: isWorkoutStats
                    ? "Workout Stats: Total distance recorded by your Apple Watch from start to finish, including walking intervals."
                    : "Working Stats: Distance covered only while actively running.",
                whyItMatters: "Efficiency: Tracking your true running mileage helps you build volume safely without doing too much too soon.",
                targetRange: "Target Range: Matched to what you planned for today's run.\n\n• Too Much Volume: Bumping up mileage too quickly raises injury risk.\n• Low Volume: Great for easy recovery runs."
            )
        case "total time", "time", "moving time":
            return MetricDetailExplainer(
                title: "Total Time",
                overview: "How long you were out, displayed in minutes and seconds.",
                modeContext: isWorkoutStats
                    ? "Workout Stats: Total clock time from start to finish, including shoe-tying, stoplights, and pauses."
                    : "Working Stats: Moving time spent running. Automatically pauses when you stop at lights.",
                whyItMatters: "Efficiency: Shows how much time you actually spent running versus standing or waiting at crosswalks.",
                targetRange: "Target Range: Matched to your planned workout duration.\n\n• Longer Runs: Build endurance and mental stamina.\n• Shorter Runs: Perfect for quick drills and recovery."
            )
        case "ground contact time", "gct":
            return MetricDetailExplainer(
                title: "Ground Contact Time",
                overview: "How long your foot stays on the ground with each step, in milliseconds (ms).",
                modeContext: isWorkoutStats
                    ? "Workout Stats: Includes walking, where your feet naturally stay on the ground much longer (~300+ ms)."
                    : "Working Stats: Measures foot contact only while running to see how springy your stride is.",
                whyItMatters: "Efficiency: Less time on the ground means lighter, springier steps and less wasted effort.",
                targetRange: "Target Range: 200 to 250 ms for most runners; under 200 ms when running fast.\n\n• High Contact (> 260 ms): Can mean sinking into each step rather than springing forward.\n• Low Contact (< 200 ms): Quick, springy turnover with light foot strikes."
            )
        case "avg stride", "stride length":
            return MetricDetailExplainer(
                title: "Stride Length",
                overview: "The distance between consecutive footsteps, measured in meters or feet.",
                modeContext: isWorkoutStats
                    ? "Workout Stats: Blends in shorter recovery walking steps, making your average look shorter."
                    : "Working Stats: Your stride length at your regular running speed.",
                whyItMatters: "Efficiency: Your stride should open up naturally from pushing behind you, not by reaching your foot too far in front.",
                targetRange: "Target Range: Usually 1.0 to 1.4 m depending on your height, pace, and cadence.\n\n• Overstriding: Reaching forward acts like a brake and strains your knees.\n• Short Stride: Often means tight hips or not pushing off fully."
            )
        case "bounce ratio", "vert. ratio", "vertical ratio":
            return MetricDetailExplainer(
                title: "Bounce Ratio",
                overview: "The percentage of upward bounce compared to how far forward you travel with each stride.",
                modeContext: isWorkoutStats
                    ? "Workout Stats: Includes walking breaks, which can elevate your bounce ratio."
                    : "Working Stats: Calculated strictly during active running to check how forward-moving your stride is.",
                whyItMatters: "Efficiency: Lower is better. A lower percentage means more of your energy pushes you forward instead of bouncing you up and down.",
                targetRange: "Target Range: Under 8.0% is very efficient. 8.0%–9.5% is typical. Above 9.5% means you are bouncing too high or reaching your foot too far forward."
            )
        case "pace cv", "cv (var)":
            return MetricDetailExplainer(
                title: "Pace Consistency (CV)",
                overview: "Pace variation, measuring how smoothly and evenly you held your speed.",
                modeContext: isWorkoutStats
                    ? "Workout Stats: Displays higher variation because stoplights and walking breaks are factored in."
                    : "Working Stats: Calculated only during continuous running to show your pacing control.",
                whyItMatters: "Efficiency: Running with smooth, even pacing saves energy and keeps you from hitting the wall late in a run.",
                targetRange: "Target Range: CV under 0.15 indicates very steady, controlled pacing.\n\n• High Variation (> 0.20): Expected on hills or interval runs; on flat runs it means your pace was uneven.\n• Low Variation (< 0.10): Very steady and smooth pacing."
            )
        case "vo2 max":
            return MetricDetailExplainer(
                title: "VO2 Max",
                overview: "An estimate of your aerobic fitness and stamina, recorded in mL/kg/min.",
                modeContext: isWorkoutStats
                    ? "Workout Stats: Fitness score estimated by Apple Health across your recent outdoor walks and runs."
                    : "Working Stats: Your aerobic fitness calculated from outdoor running workouts.",
                whyItMatters: "Efficiency: A clear benchmark of your overall endurance engine and heart health.",
                targetRange: "Target Range: 38 to 48+ for active runners; 50+ for competitive runners.\n\n• Rising Trend: Your stamina and aerobic fitness are improving.\n• Declining Trend: Can signal heavy legs, fatigue, heat, or needing more rest."
            )
        case "workout density":
            return MetricDetailExplainer(
                title: "Workout Density",
                overview: "How consistently you have been running over your selected timeframe.",
                modeContext: isWorkoutStats
                    ? "Workout Stats: Total workouts recorded in Apple Health."
                    : "Working Stats: Your active running workout frequency.",
                whyItMatters: "Efficiency: Getting out regularly with enough rest in between builds fitness without burning you out.",
                targetRange: "Target Range: 3 to 5 runs per week for steady progress.\n\n• High Density (5+ runs): Great for experienced runners; be sure to get plenty of sleep and recovery.\n• Low Density (≤ 2 runs): Good for maintaining fitness; harder to build new endurance."
            )
        case "target cadence":
            return MetricDetailExplainer(
                title: "Target Cadence",
                overview: "A step rate goal based on your recent runs to help lighten your stride.",
                modeContext: isWorkoutStats
                    ? "Workout Stats: Target derived from your overall workout session history."
                    : "Working Stats: Calibrated to your recent running pace.",
                whyItMatters: "Efficiency: Taking slightly quicker steps softens your landings and protects your shins and knees.",
                targetRange: "Target Range: Usually 3 to 5 SPM above your baseline, capped at 180 SPM.\n\n• Cadence Drills: Help your legs get used to lighter, quicker steps without extra effort."
            )
        case "working stats":
            return MetricDetailExplainer(
                title: "Working Stats",
                overview: "Filters out stops, pauses, and walking breaks so you see your true running numbers.",
                modeContext: "Active Running: We only count the minutes and miles when you are actually running.",
                whyItMatters: "Efficiency: Red lights and walking breaks won't artificially drag down your pace, heart rate, or cadence.",
                targetRange: "Use Working Stats to see how your running form and fitness are really doing."
            )
        case "workout stats":
            return MetricDetailExplainer(
                title: "Workout Stats",
                overview: "Shows everything recorded by your Apple Watch from start to finish, including walking and pauses.",
                modeContext: "Full Workout: Counts everything from the moment you hit Start to when you hit Finish.",
                whyItMatters: "Efficiency: Useful when you want to see your total time on feet and total overall activity.",
                targetRange: "Use Workout Stats to review your total workout duration and raw Apple Health numbers."
            )
        case "classification", "run classification", "coreml", "coreml override":
            return MetricDetailExplainer(
                title: "Run Classification",
                overview: "Analyzes your continuous heart rate, pace consistency, and stride mechanics to determine the type of workout your body performed.",
                modeContext: "CoreML & Biometrics: Combines on-device machine learning with physiological rules so physical cardiac strain always takes priority over model guesswork.",
                whyItMatters: "Accuracy: Ensures recovery runs, steady efforts, and high-intensity interval sessions are accurately recognized so your AI training advice stays calibrated.",
                targetRange: "Categories include Easy Run, Steady Effort, Tempo Run, Intervals, Progression Run, Long Run, and Recovery Run. You can tap the menu to override the label anytime."
            )
        default:
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
    }
}

/// Identifiable model for presentation in a metric explainer bottom sheet.
struct MetricExplainerInfo: Identifiable {
    var id: String { title + (mode ?? "") }
    let title: String
    var mode: String?
    let overview: String
    var modeContext: String?
    var whyItMatters: String?
    var targetRange: String?

    init(title: String, definition: String) {
        self.title = title
        self.mode = nil
        self.overview = definition
        self.modeContext = nil
        self.whyItMatters = nil
        self.targetRange = nil
    }

    init(
        title: String,
        mode: String? = nil,
        overview: String,
        modeContext: String? = nil,
        whyItMatters: String? = nil,
        targetRange: String? = nil
    ) {
        self.title = title
        self.mode = mode
        self.overview = overview
        self.modeContext = modeContext
        self.whyItMatters = whyItMatters
        self.targetRange = targetRange
    }

    init(explainer: MetricDetailExplainer, mode: String? = nil) {
        self.title = explainer.title
        self.mode = mode
        self.overview = explainer.overview
        self.modeContext = explainer.modeContext
        self.whyItMatters = explainer.whyItMatters
        self.targetRange = explainer.targetRange
    }
}
