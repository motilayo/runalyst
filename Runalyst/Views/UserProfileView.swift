import SwiftUI
import SwiftData

struct UserProfileView: View {
    @Query(sort: \RunRecord.date, order: .reverse) private var runRecords: [RunRecord]

    @AppStorage("useMetricSystem") private var useMetricSystem: Bool = Locale.current.measurementSystem == .metric
    @AppStorage("trainingGoal") private var trainingGoal: String = "Base Building"
    @AppStorage("userExperienceLevel") private var userExperienceLevel: String = "Auto"
    @AppStorage("userHeightCm") private var userHeightCm: Double = 175.0

    let goalOptions = [
        "Base Building",
        "Injury Recovery",
        "5K Race",
        "10K Race",
        "Half Marathon",
        "Marathon",
        "Just for Fun"
    ]

    var body: some View {
        let profile = RunnerProfile.compute(
            from: runRecords,
            trainingGoal: trainingGoal,
            experienceLevel: userExperienceLevel == "Auto" ? nil : userExperienceLevel,
            userHeightCm: userHeightCm
        )

        Form {
            Section(
                header: Text("Runner Identity"),
                footer: Text(userExperienceLevel == "Auto"
                    ? "Experience level is automatically calibrated from your 30-day running volume, frequency, and personal records."
                    : "Manual override active. Select 'Auto' to let Runalyst calibrate your experience level from your running telemetry.")
            ) {
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
                footer: Text("Runalyst automatically tracks your empirical load and consistency from your last 30 days of workout telemetry.")
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
                    Text("Weekly Volume")
                    Spacer()
                    let displayVolume = useMetricSystem
                        ? String(format: "%.1f km/wk", profile.weeklyAverageKm)
                        : String(format: "%.1f mi/wk", profile.weeklyAverageKm * 0.621371)
                    Text(displayVolume)
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
    }
}
