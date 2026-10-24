import SwiftUI

/// Standardized mini-statistic tile used universally across Dashboard, Workouts, Analysis, and Detail cards.
public struct MiniStatTile: View {
    public let title: String
    public let value: String
    public let unit: String?
    public let icon: String?
    public let accentColor: Color?

    public init(
        title: String,
        value: String,
        unit: String? = nil,
        icon: String? = nil,
        accentColor: Color? = nil
    ) {
        self.title = title
        self.value = value
        self.unit = unit
        self.icon = icon
        self.accentColor = accentColor
    }

    public var body: some View {
        HStack(spacing: 8) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(accentColor ?? .secondary)
                    .frame(width: 14)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    if let unit {
                        Text(unit)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundColor(accentColor ?? .secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(minHeight: 42)
        .background(Color(UIColor.tertiarySystemGroupedBackground).opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(UIColor.separator).opacity(0.12), lineWidth: 0.5)
        )
    }
}
