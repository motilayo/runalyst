import SwiftData
import SwiftUI

struct RunListRowView: View {
    var runRecord: RunRecord
    @AppStorage("useMetricSystem") private var useMetricSystem: Bool = Locale.current.measurementSystem == .metric

    private var prescribedDrillName: String? {
        guard !runRecord.isDeleted, runRecord.modelContext != nil else { return nil }
        return runRecord.prescribedDrillName
    }

    private var workoutTitle: String {
        if let drill = prescribedDrillName {
            return drill
        }
        return runRecord.normalizedClassification
    }

    private var workoutIcon: String {
        if let drill = prescribedDrillName {
            return PreRunDrill.iconName(for: nil, title: drill)
        }
        return RunalystIcon.forClassification(runRecord.normalizedClassification, isIndoor: runRecord.isIndoor ?? false)
    }

    private var workoutColor: Color {
        if let drill = prescribedDrillName {
            return PreRunDrill.iconColor(for: nil, title: drill)
        }
        return RunalystColor.forClassification(runRecord.normalizedClassification, isIndoor: runRecord.isIndoor ?? false)
    }

    private var formattedTimestamp: String {
        let calendar = Calendar.current
        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short
        let timeStr = timeFormatter.string(from: runRecord.date)

        if calendar.isDateInToday(runRecord.date) {
            return "Today, \(timeStr)"
        } else if calendar.isDateInYesterday(runRecord.date) {
            return "Yesterday, \(timeStr)"
        } else {
            let isCurrentYear = calendar.component(.year, from: runRecord.date) == calendar.component(.year, from: Date())
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = isCurrentYear ? "MMM d, h:mm a" : "MMM d, yyyy"
            return dateFormatter.string(from: runRecord.date)
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: workoutIcon)
                        .font(.subheadline)
                        .foregroundColor(workoutColor)
                    Text(workoutTitle)
                        .font(.headline)
                        .foregroundColor(.primary)
                }

                Spacer()

                Text(formattedTimestamp)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack {
                let distanceConverted = useMetricSystem ? (runRecord.totalDistanceMeters / 1000.0) : (runRecord.totalDistanceMeters / 1609.344)
                let distanceUnit = useMetricSystem ? "km" : "mi"
                let pace = PaceFormatter.formatPace(secondsPerKilometer: runRecord.workingAvgPace)

                HStack(spacing: 6) {
                    Text(String(format: "%.2f %@", distanceConverted, distanceUnit))
                        .font(.subheadline.bold())
                        .monospacedDigit()
                        .foregroundColor(.primary)

                    Text("•")
                        .foregroundColor(.secondary.opacity(0.6))

                    Text(pace)
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundColor(.secondary)

                    if runRecord.workingAvgHeartRate > 0 {
                        Text("•")
                            .foregroundColor(.secondary.opacity(0.6))

                        HStack(spacing: 2) {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 9))
                                .foregroundColor(Color(red: 1.0, green: 0.22, blue: 0.55))
                            Text("\(Int(runRecord.workingAvgHeartRate))")
                                .font(.subheadline)
                                .monospacedDigit()
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption2.bold())
                    .foregroundColor(Color.secondary.opacity(0.6))
            }
        }
        .liquidGlass(cornerRadius: 16, padding: 16, accentColor: workoutColor)
        .padding(.horizontal)
        .accessibilityElement(children: .combine)
    }
}
