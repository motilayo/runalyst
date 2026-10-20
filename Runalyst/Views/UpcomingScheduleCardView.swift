import SwiftUI

/// Reusable upcoming weekly training schedule card shared across WorkoutsView and AnalystChatView.
struct UpcomingScheduleCardView: View {
    let microcycle: [MicrocycleDay]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("UPCOMING SCHEDULE")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(Array(microcycle.enumerated()), id: \.element.id) { index, day in
                    HStack(spacing: 8) {
                        Image(systemName: day.iconName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(day.isRestDay ? .secondary : Color(red: 0.0, green: 0.55, blue: 1.0))
                            .frame(width: 20, alignment: .center)

                        Text(day.dayLabel)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(day.isRestDay ? .secondary : .primary)
                            .frame(width: day.dayLabel.count > 4 ? nil : 36, alignment: .leading)
                            .lineLimit(1)

                        let parsed = parseSessionSchedule(day.sessionTitle)

                        Text(parsed.name)
                            .font(.subheadline)
                            .foregroundColor(day.isRestDay ? .secondary : .primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)

                        Spacer(minLength: 6)

                        if let detail = parsed.detail {
                            Text(detail)
                                .font(.system(size: 12, weight: .semibold))
                                .monospacedDigit()
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color(UIColor.tertiarySystemGroupedBackground))
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)

                    if index < microcycle.count - 1 {
                        Divider()
                            .padding(.leading, 42)
                    }
                }
            }
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color(UIColor.separator).opacity(0.15), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
        }
        .padding(.top, 4)
    }

    private func parseSessionSchedule(_ title: String) -> (name: String, detail: String?) {
        if title.contains(" • ") {
            let parts = title.components(separatedBy: " • ")
            return (parts[0], parts.count > 1 ? parts[1] : nil)
        }
        return (title, nil)
    }
}
