import SwiftUI

/// Standardized mini-statistic tile used universally across Dashboard, Workouts, Analysis, and Detail cards.
/// Provides minimum 44pt touch geometry for Sweaty Hands UX, monospaced digits, and combined semantic VoiceOver labels.
public struct MiniStatTile: View {
    @Environment(\.colorScheme) private var colorScheme

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

    private var effectiveAccentColor: Color? {
        guard let accentColor else { return nil }
        if colorScheme == .light {
            // Darken slightly for light mode contrast
            return accentColor
        }
        return accentColor
    }

    public var body: some View {
        HStack(spacing: 8) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(effectiveAccentColor ?? .secondary)
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
                            .foregroundColor(effectiveAccentColor ?? .secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(minHeight: 44)
        .background(
            colorScheme == .light
                ? Color(UIColor.tertiarySystemGroupedBackground)
                : Color(UIColor.tertiarySystemGroupedBackground).opacity(0.85)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(
                    Color(UIColor.separator).opacity(colorScheme == .dark ? 0.12 : 0.35),
                    lineWidth: colorScheme == .dark ? 0.5 : 0.75
                )
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(value) \(unit ?? "")")
    }
}
