import SwiftData
import SwiftUI

struct RunListRowView: View {
    var runRecord: RunRecord
    @AppStorage("useMetricSystem") private var useMetricSystem: Bool = Locale.current.measurementSystem == .metric

    private var prescribedDrillName: String? {
        guard !runRecord.isDeleted, runRecord.modelContext != nil else { return nil }
        return runRecord.prescribedDrillName
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(runRecord.date, style: .date)
                    .font(.headline)
                    .foregroundColor(.primary)

                Spacer()

                if let drillName = prescribedDrillName {
                    let iconName = PreRunDrill.iconName(for: nil, title: drillName)
                    let iconColor = PreRunDrill.iconColor(for: nil, title: drillName)
                    HStack(spacing: 3) {
                        Image(systemName: iconName)
                        Text(drillName)
                    }
                    .font(.caption2.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(iconColor.opacity(0.18))
                    .foregroundColor(iconColor)
                    .clipShape(Capsule())
                } else {
                    Text(runRecord.normalizedClassification)
                        .font(.caption2.bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color(red: 0.1, green: 0.7, blue: 0.7).opacity(0.18))
                        .foregroundColor(Color(red: 0.05, green: 0.55, blue: 0.55))
                        .clipShape(Capsule())
                }
            }

            HStack {
                let distanceConverted = useMetricSystem ? (runRecord.totalDistanceMeters / 1000.0) : (runRecord.totalDistanceMeters / 1609.344)
                let distanceUnit = useMetricSystem ? "km" : "mi"
                let pace = PaceFormatter.formatPace(secondsPerKilometer: runRecord.workingAvgPace)

                Text(String(format: "%.2f %@ • %@", distanceConverted, distanceUnit, pace))
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption2.bold())
                    .foregroundColor(Color.secondary.opacity(0.6))
            }
        }
        .padding(16)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(UIColor.separator).opacity(0.15), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.03), radius: 5, x: 0, y: 2)
        .padding(.horizontal)
    }
}
