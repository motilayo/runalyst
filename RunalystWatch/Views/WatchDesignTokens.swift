import SwiftUI

// MARK: - Watch Design Tokens & Color Palette

/// Canonical Apple Watch design tokens matching Runalyst's subconscious data binding.
public enum WatchColor {
    public static let pace = Color(red: 0.04, green: 0.52, blue: 1.0)
    public static let heartRate = Color(red: 1.0, green: 0.18, blue: 0.33)
    public static let cadence = Color(red: 0.20, green: 0.78, blue: 0.35)
    public static let companionAccent = Color(red: 0.69, green: 0.32, blue: 0.87)
    public static let coach = Color(red: 0.69, green: 0.32, blue: 0.87)
    public static let surgeTeal = Color(red: 0.0, green: 0.9, blue: 0.75)
    public static let recoverAmber = Color(red: 1.0, green: 0.65, blue: 0.1)
    public static let recoverOrange = Color(red: 1.0, green: 0.58, blue: 0.0)
    public static let calibratingBlue = Color(red: 0.2, green: 0.6, blue: 1.0)
}

// MARK: - Watch SF Symbols

/// Standard SF Symbols used across Apple Watch companion workout surfaces.
public enum WatchIcon {
    public static let outdoor = "road.lanes"
    public static let indoor = "figure.run.treadmill"
    public static let pace = "speedometer"
    public static let heartRate = "heart.fill"
    public static let cadence = "metronome.fill"
    public static let companion = "figure.run"
    public static let drill = "sparkles"
}

// MARK: - Watch Liquid Glass Modifier

/// Liquid Glass visual treatment tailored for small OLED watch surfaces.
public struct WatchLiquidGlassModifier: ViewModifier {
    public var accent: Color
    public var cornerRadius: CGFloat
    public var isProminent: Bool

    public init(
        accent: Color = .white,
        cornerRadius: CGFloat = 14,
        isProminent: Bool = false
    ) {
        self.accent = accent
        self.cornerRadius = cornerRadius
        self.isProminent = isProminent
    }

    public func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)

                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.white.opacity(isProminent ? 0.08 : 0.05))

                    if isProminent {
                        Circle()
                            .fill(accent.opacity(0.12))
                            .blur(radius: 20)
                            .offset(x: -24, y: -16)
                            .allowsHitTesting(false)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
            .overlay {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(isProminent ? 0.28 : 0.16),
                                    Color.white.opacity(0.06),
                                    Color.clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.75
                        )

                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                }
            }
    }
}

public extension View {
    /// Applies watchOS Liquid Glass styling with specular highlight and ambient tint.
    func watchLiquidGlass(
        accent: Color = .white,
        cornerRadius: CGFloat = 14,
        isProminent: Bool = false
    ) -> some View {
        modifier(
            WatchLiquidGlassModifier(
                accent: accent,
                cornerRadius: cornerRadius,
                isProminent: isProminent
            )
        )
    }
}

// MARK: - Companion Status Pill

/// Compact header pill displaying iPhone sync connectivity status.
public struct WatchCompanionStatusPill: View {
    public let text: String
    public let isSynced: Bool

    public init(text: String, isSynced: Bool) {
        self.text = text
        self.isSynced = isSynced
    }

    public var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "applewatch")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(isSynced ? WatchColor.cadence : .secondary)

            Text(text)
                .font(.system(size: 8.5, weight: .bold, design: .rounded))
                .tracking(0.4)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Semantic Metric Pill

/// Compact rounded cell rendering an SF Symbol, optional title, and numeric metric.
public struct WatchSemanticMetricPill: View {
    public let title: String
    public let icon: String
    public let value: String
    public let color: Color

    public init(title: String = "", icon: String, value: String, color: Color) {
        self.title = title
        self.icon = icon
        self.value = value
        self.color = color
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(color)

                if !title.isEmpty {
                    Text(title.uppercased())
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
        )
    }
}

// MARK: - Watch Bezel Track Shape

/// Continuous 9-segment clockwise track tracing the perimeter of the watch display.
/// Starts at 12 o'clock `(midX, minY)` matching `PacingDisplayState.bezelPerimeterPoint`.
public struct WatchBezelTrackShape: Shape {
    public var cornerRadius: CGFloat
    public var inset: CGFloat

    public init(cornerRadius: CGFloat = 38, inset: CGFloat = 2.5) {
        self.cornerRadius = cornerRadius
        self.inset = inset
    }

    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let minX = rect.minX + inset
        let maxX = max(minX, rect.maxX - inset)
        let minY = rect.minY + inset
        let maxY = max(minY, rect.maxY - inset)
        let r = max(0.0, min(cornerRadius, min(maxX - minX, maxY - minY) * 0.5))
        let midX = minX + (maxX - minX) * 0.5

        path.move(to: CGPoint(x: midX, y: minY))
        path.addLine(to: CGPoint(x: maxX - r, y: minY))
        path.addArc(
            center: CGPoint(x: maxX - r, y: minY + r),
            radius: r,
            startAngle: .radians(-.pi * 0.5),
            endAngle: .radians(0.0),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: maxX, y: maxY - r))
        path.addArc(
            center: CGPoint(x: maxX - r, y: maxY - r),
            radius: r,
            startAngle: .radians(0.0),
            endAngle: .radians(.pi * 0.5),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: minX + r, y: maxY))
        path.addArc(
            center: CGPoint(x: minX + r, y: maxY - r),
            radius: r,
            startAngle: .radians(.pi * 0.5),
            endAngle: .radians(.pi),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: minX, y: minY + r))
        path.addArc(
            center: CGPoint(x: minX + r, y: minY + r),
            radius: r,
            startAngle: .radians(.pi),
            endAngle: .radians(1.5 * .pi),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: midX, y: minY))

        return path
    }
}
