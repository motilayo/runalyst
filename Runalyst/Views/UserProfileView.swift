import SwiftUI
import SwiftData

struct UserProfileView: View {
    @Query(sort: \RunRecord.date, order: .reverse) private var runRecords: [RunRecord]

    @AppStorage("runnerName") private var runnerName: String = "Joshua"
    @AppStorage("runnerAge") private var runnerAge: Int = 28
    @AppStorage("useMetricSystem") private var useMetricSystem: Bool = Locale.current.measurementSystem == .metric
    @AppStorage("trainingGoal") private var trainingGoal: String = "5K Race"
    @AppStorage("userExperienceLevel") private var userExperienceLevel: String = "Auto"
    @AppStorage("userHeightCm") private var userHeightCm: Double = 175.0
    @AppStorage("cachedVO2Max") private var cachedVO2Max: Double = 40.5

    let goalOptions = [
        "5K Race",
        "10K Race",
        "Half Marathon",
        "Marathon",
        "Base Building",
        "Injury Recovery",
        "Just for Fun"
    ]

    var body: some View {
        let profile = RunnerProfile.compute(
            from: runRecords,
            trainingGoal: trainingGoal,
            experienceLevel: userExperienceLevel == "Auto" ? nil : userExperienceLevel,
            userHeightCm: userHeightCm,
            runnerName: runnerName,
            runnerAge: runnerAge,
            vo2Max: cachedVO2Max
        )

        Form {
            Section(
                header: Text("Runner Identity"),
                footer: Text(userExperienceLevel == "Auto"
                    ? "Experience level and goal benchmarks are automatically calibrated from your 30-day running volume, frequency, and personal records."
                    : "Manual override active. Select 'Auto' to let Runalyst calibrate your experience level from your running telemetry.")
            ) {
                HStack {
                    Text("Name")
                    Spacer()
                    TextField("Runner Name", text: $runnerName)
                        .multilineTextAlignment(.trailing)
                        .foregroundColor(.secondary)
                }

                Stepper(value: $runnerAge, in: 12...100) {
                    HStack {
                        Text("Age")
                        Spacer()
                        Text("\(runnerAge) yrs")
                            .foregroundColor(.secondary)
                    }
                }

                Picker("Training Goal", selection: $trainingGoal) {
                    ForEach(goalOptions, id: \.self) { option in
                        Text(option).tag(option)
                    }
                }

                Picker("Experience Level", selection: $userExperienceLevel) {
                    Text("Auto (\(profile.calculatedExperienceLevel))").tag("Auto")
                    ForEach(RunnerProfile.experienceLevelOptions, id: \.self) { option in
                        Text(option).tag(option)
                    }
                }

                HStack {
                    Text("Height")
                    Spacer()
                    Stepper(
                        value: $userHeightCm,
                        in: 130...220,
                        step: 1
                    ) {
                        if useMetricSystem {
                            Text("\(Int(userHeightCm)) cm")
                                .foregroundColor(.secondary)
                        } else {
                            let totalInches = Int((userHeightCm / 2.54).rounded())
                            let feet = totalInches / 12
                            let inches = totalInches % 12
                            Text("\(feet)'\(inches)\" (\(Int(userHeightCm)) cm)")
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            Section(
                header: Text("Current 30-Day Training Load"),
                footer: Text("Runalyst automatically tracks your empirical load, cadence floor, and goal readiness from your last 30 days of workout telemetry.")
            ) {
                HStack {
                    Text("Athletic Maturity Tier")
                    Spacer()
                    HStack(spacing: 4) {
                        if profile.isAutoCalculated {
                            Image(systemName: "sparkles")
                                .font(.caption2)
                                .foregroundColor(.purple)
                        }
                        Text(profile.experienceLevel)
                            .foregroundColor(.secondary)
                    }
                }

                HStack {
                    Text("VO2 Max")
                    Spacer()
                    Text(String(format: "%.1f mL/kg/min", cachedVO2Max))
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Cadence Floor")
                    Spacer()
                    Text("\(profile.heightAdjustedCadenceFloor) SPM")
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Weekly Volume")
                    Spacer()
                    let displayVolume = useMetricSystem
                        ? String(format: "%.1f km/wk", profile.weeklyAverageKm)
                        : String(format: "%.1f mi/wk", profile.weeklyAverageKm * 0.621371)
                    Text(displayVolume)
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Goal Target Volume")
                    Spacer()
                    Text("\(Int(profile.goalBenchmark.targetWeeklyKmMin))–\(Int(profile.goalBenchmark.targetWeeklyKmMax)) km/wk (\(profile.goalBenchmark.weeklyVolumeStatus.displayText))")
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Run Frequency")
                    Spacer()
                    Text(String(format: "%.1f runs/wk", profile.runsPerWeek))
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("User Profile")
        .task {
            if let healthHeight = try? await HealthKitManager.shared.fetchUserHeight(), healthHeight > 0 {
                if UserDefaults.standard.object(forKey: "userHeightCm") == nil || userHeightCm == 175.0 {
                    userHeightCm = healthHeight
                }
            }
            if let vo2s = try? await HealthKitManager.shared.fetchRecentGlobalVO2Maxes(limit: 1), let latestVO2 = vo2s.first, latestVO2 > 0 {
                cachedVO2Max = latestVO2
            }
        }
    }
}
