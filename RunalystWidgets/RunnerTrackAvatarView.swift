import RunalystCore
import SwiftUI

// MARK: - Stadium Track Oval Shape

/// Continuous 400-meter stadium track oval generated from pure `LiveTrackCore.trackOvalPoint`.
public struct TrackOvalShape: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let steps = 64
        for stepIndex in 0...steps {
            let progress = Double(stepIndex) / Double(steps)
            let point = LiveTrackCore.trackOvalPoint(progress: progress)
            let coordX = rect.minX + point.x * rect.width
            let coordY = rect.minY + point.y * rect.height
            if stepIndex == 0 {
                path.move(to: CGPoint(x: coordX, y: coordY))
            } else {
                path.addLine(to: CGPoint(x: coordX, y: coordY))
            }
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - Runner Track Avatar View

/// SwiftUI vector running figure + glowing halo positioned along the 3D-tilted 400m oval.
public struct RunnerTrackAvatarView: View {
    public let progress: Double
    public let statusToken: PacingAccentToken
    public let isPaused: Bool

    public init(
        progress: Double,
        statusToken: PacingAccentToken = .electricBlue,
        isPaused: Bool = false
    ) {
        self.progress = progress
        self.statusToken = statusToken
        self.isPaused = isPaused
    }

    public init(snapshot: LiveTrackSnapshot?, isPaused: Bool = false) {
        self.init(
            progress: snapshot?.lapProgress ?? 0.0,
            statusToken: snapshot?.statusToken ?? .electricBlue,
            isPaused: isPaused
        )
    }

    public var body: some View {
        GeometryReader { geometry in
            let point = LiveTrackCore.trackOvalPoint(progress: progress)
            let posX = point.x * geometry.size.width
            let posY = point.y * geometry.size.height
            let accentColor = Color(token: statusToken)

            ZStack {
                // Glowing outer halo
                Circle()
                    .fill(accentColor.opacity(isPaused ? 0.15 : 0.40))
                    .frame(width: 26, height: 26)
                    .blur(radius: 4)

                // Biometric core circle
                Circle()
                    .fill(accentColor)
                    .frame(width: 18, height: 18)
                    .shadow(color: accentColor.opacity(0.6), radius: 3)

                // Vector running figure
                Image(systemName: isPaused ? "figure.walk" : "figure.run")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
            }
            .position(x: posX, y: posY)
        }
    }
}

// MARK: - Dynamic Island Track Dot View

/// Linear 400m lap runway with glowing runner dot + ghost pacer dot for Dynamic Island Expanded presentation.
public struct DynamicIslandTrackDotView: View {
    public let lapProgress: Double
    public let ghostProgress: Double?
    public let statusToken: PacingAccentToken
    public let isPaused: Bool

    public init(
        lapProgress: Double,
        ghostProgress: Double?,
        statusToken: PacingAccentToken = .electricBlue,
        isPaused: Bool = false
    ) {
        self.lapProgress = lapProgress
        self.ghostProgress = ghostProgress
        self.statusToken = statusToken
        self.isPaused = isPaused
    }

    public init(snapshot: LiveTrackSnapshot?, isPaused: Bool = false) {
        self.init(
            lapProgress: snapshot?.lapProgress ?? 0.0,
            ghostProgress: snapshot?.ghostProgress,
            statusToken: snapshot?.statusToken ?? .electricBlue,
            isPaused: isPaused
        )
    }

    public var body: some View {
        GeometryReader { geometry in
            let totalWidth = geometry.size.width
            let horizontalInset: CGFloat = 8
            let usableWidth = max(1.0, totalWidth - (horizontalInset * 2))
            let clampedLap = min(max(lapProgress, 0.0), 1.0)
            let accentColor = Color(token: statusToken)

            ZStack(alignment: .leading) {
                // Background Track Lane Capsule (height: 6)
                Capsule()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: usableWidth, height: 6)

                // Subtle Filled Progress Bar up to lapProgress
                if clampedLap > 0 {
                    Capsule()
                        .fill(accentColor.opacity(0.35))
                        .frame(width: max(6, usableWidth * clampedLap), height: 6)
                }

                // 3 subtle vertical tick marks at 0.25, 0.50, 0.75 for 100m/200m/300m
                ForEach([0.25, 0.50, 0.75], id: \.self) { tick in
                    Rectangle()
                        .fill(Color.white.opacity(0.35))
                        .frame(width: 1.5, height: 8)
                        .offset(x: (usableWidth * tick) - 0.75)
                }

                // Muted 8pt ghost pacer Circle at ghostProgress * width when non-nil
                if let ghost = ghostProgress {
                    let clampedGhost = min(max(ghost, 0.0), 1.0)
                    Circle()
                        .fill(Color.white.opacity(0.45))
                        .frame(width: 8, height: 8)
                        .offset(x: (usableWidth * clampedGhost) - 4)
                }

                // 12pt glowing biometric runner Circle with 20pt soft halo at lapProgress * width
                ZStack {
                    Circle()
                        .fill(accentColor.opacity(isPaused ? 0.15 : 0.40))
                        .frame(width: 20, height: 20)
                        .blur(radius: 3)

                    Circle()
                        .fill(accentColor)
                        .frame(width: 12, height: 12)
                }
                .offset(x: (usableWidth * clampedLap) - 10)
            }
            .frame(width: usableWidth, height: geometry.size.height)
            .offset(x: horizontalInset)
        }
    }
}
