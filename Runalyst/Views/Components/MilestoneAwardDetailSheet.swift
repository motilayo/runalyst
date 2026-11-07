import SwiftUI
import RunalystCore

// MARK: - Hexagon Shape

/// A clean 6-sided regular polygon shape for streak-based awards.
struct HexagonShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2.0
        guard radius > 0 else { return path }

        for index in 0..<6 {
            let angle = (CGFloat(index) * 60.0 - 30.0) * .pi / 180.0
            let point = CGPoint(
                x: center.x + radius * cos(angle),
                y: center.y + radius * sin(angle)
            )
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - Metallic Medallion View

/// Apple Fitness-inspired multi-bezel metallic medallion rendering circular,
/// split-horizon, and hexagonal award geometry.
struct MetallicMedallionView: View {
    let spec: MilestoneBadgeSpec
    let accentColor: Color
    let size: CGFloat

    private var rimThickness: CGFloat {
        max(3.0, size * 0.065)
    }

    private var innerSize: CGFloat {
        max(1.0, size - (rimThickness * 2.0))
    }

    private var outerRimGradient: LinearGradient {
        if spec.isUnlocked {
            return LinearGradient(
                colors: [
                    accentColor.opacity(0.95),
                    Color(red: 0.92, green: 0.80, blue: 0.42),
                    accentColor,
                    Color(red: 0.28, green: 0.20, blue: 0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            return LinearGradient(
                colors: [
                    Color(UIColor.systemGray4),
                    Color(UIColor.systemGray5),
                    Color(UIColor.systemGray6)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var innerDiscColor: Color {
        if spec.isUnlocked {
            return Color(red: 0.11, green: 0.10, blue: 0.08)
        } else {
            return Color(UIColor.tertiarySystemFill)
        }
    }

    var body: some View {
        ZStack {
            // Outer Rim
            Group {
                if spec.medallionShape == .hexagonStreak {
                    HexagonShape()
                        .fill(outerRimGradient)
                        .shadow(
                            color: spec.isUnlocked ? accentColor.opacity(0.35) : Color.black.opacity(0.12),
                            radius: size * 0.06,
                            x: 0,
                            y: size * 0.03
                        )
                } else {
                    Circle()
                        .fill(outerRimGradient)
                        .shadow(
                            color: spec.isUnlocked ? accentColor.opacity(0.35) : Color.black.opacity(0.12),
                            radius: size * 0.06,
                            x: 0,
                            y: size * 0.03
                        )
                }
            }
            .frame(width: size, height: size)

            // Inner Obsidian Disc
            Group {
                if spec.medallionShape == .hexagonStreak {
                    HexagonShape()
                        .fill(innerDiscColor)
                } else {
                    Circle()
                        .fill(innerDiscColor)
                }
            }
            .frame(width: innerSize, height: innerSize)
            .overlay {
                // Split-Horizon Geometry Accent
                if spec.medallionShape == .splitHorizonDistance {
                    VStack(spacing: 0) {
                        Spacer()
                        Rectangle()
                            .fill(accentColor.opacity(spec.isUnlocked ? 0.35 : 0.12))
                            .frame(height: 1.0)
                        Rectangle()
                            .fill(accentColor.opacity(spec.isUnlocked ? 0.20 : 0.06))
                            .frame(height: innerSize * 0.42)
                    }
                    .clipShape(Circle())
                }
            }

            // Center SF Symbol
            Image(systemName: spec.iconName)
                .font(.system(size: size * 0.36, weight: .semibold))
                .foregroundColor(spec.isUnlocked ? accentColor : Color.secondary.opacity(0.40))
                .offset(y: spec.medallionShape == .splitHorizonDistance ? -innerSize * 0.06 : 0.0)

            // Repeat-Count Pill Overlay for Unlocked Multi-Earned Badges
            if spec.isUnlocked && spec.timesEarnedCount > 1 && size < 120 {
                HStack(spacing: 2) {
                    Text("\(spec.timesEarnedCount)")
                        .font(.system(size: max(9.0, size * 0.15), weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
                .foregroundColor(accentColor)
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(
                    Capsule()
                        .fill(Color(red: 0.11, green: 0.10, blue: 0.08))
                        .overlay(Capsule().stroke(accentColor.opacity(0.65), lineWidth: 1))
                )
                .offset(y: size * 0.38)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Milestone Award Detail Sheet

/// Celebratory bottom sheet presenting an award's metallic medallion, earned narrative prose,
/// locked progress bar, and the qualifying workout provenance card.
struct MilestoneAwardDetailSheet: View {
    let spec: MilestoneBadgeSpec
    let accentColor: Color
    let qualifyingRun: RunRecord?
    let useMetricSystem: Bool
    var onSelectWorkout: ((RunRecord) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var selectedDetent: PresentationDetent = .large

    private var formattedQualifyingDate: String? {
        guard let date = spec.qualifyingDate ?? qualifyingRun?.date else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private var qualifyingWorkoutTitle: String {
        if let drill = qualifyingRun?.prescribedDrillName, !drill.isEmpty {
            return drill
        }
        if let type = qualifyingRun?.detectedTypeRaw, !type.isEmpty {
            return type
        }
        return spec.title
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Top Close Bar
                    HStack {
                        Spacer()
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .foregroundColor(.secondary)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    // Hero Metallic Medallion with Subtle Glow
                    ZStack {
                        Circle()
                            .fill(accentColor.opacity(spec.isUnlocked ? 0.22 : 0.05))
                            .frame(width: 210, height: 210)
                            .blur(radius: 26)

                        MetallicMedallionView(spec: spec, accentColor: accentColor, size: 176)
                    }

                    // Award Title & Narrative Prose
                    VStack(spacing: 8) {
                        Text(spec.title)
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.center)

                        Text(spec.earnedNarrativeProse(useMetric: useMetricSystem, formattedDate: formattedQualifyingDate))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)
                            .padding(.horizontal, 24)
                    }

                    // Progress Bar Card (When Locked)
                    if !spec.isUnlocked {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("PROGRESS")
                                    .font(.caption2.bold())
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(spec.earnedMetricSubtitle(useMetric: useMetricSystem))
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundColor(accentColor)
                            }
                            ProgressView(value: spec.progressFraction)
                                .tint(accentColor)
                        }
                        .padding(16)
                        .background(Color(UIColor.secondarySystemGroupedBackground))
                        .cornerRadius(16)
                        .padding(.horizontal, 20)
                    }

                    // Qualifying Workout Card (When Unlocked)
                    if spec.isUnlocked {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Workout")
                                .font(.headline)
                                .foregroundColor(.primary)

                            if let run = qualifyingRun {
                                if let onSelectWorkout {
                                    Button {
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        onSelectWorkout(run)
                                    } label: {
                                        qualifyingWorkoutCardContent(showChevron: true)
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                    NavigationLink(value: run) {
                                        qualifyingWorkoutCardContent(showChevron: true)
                                    }
                                    .buttonStyle(.plain)
                                }
                            } else {
                                qualifyingWorkoutCardContent(showChevron: false)
                            }
                        }
                        .padding(.horizontal, 20)
                    }

                    Spacer(minLength: 24)
                }
            }
            .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
            .navigationBarHidden(true)
            .navigationDestination(for: RunRecord.self) { run in
                RunDetailView(runRecord: run)
            }
        }
        .presentationDetents([.medium, .large], selection: $selectedDetent)
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private func qualifyingWorkoutCardContent(showChevron: Bool) -> some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.18))
                    .frame(width: 44, height: 44)
                Image(systemName: spec.iconName)
                    .font(.headline)
                    .foregroundColor(accentColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(qualifyingWorkoutTitle)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text(spec.earnedMetricSubtitle(useMetric: useMetricSystem))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(accentColor)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                HStack(spacing: 4) {
                    Text("\(max(1, spec.timesEarnedCount))")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Image(systemName: "hexagon.fill")
                        .font(.caption2)
                }
                .foregroundColor(accentColor)

                if let dateStr = formattedQualifyingDate {
                    Text(dateStr)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                }
            }

            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(16)
        .contentShape(Rectangle())
    }
}
