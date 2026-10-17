import SwiftUI

struct MilestoneBadge: Identifiable {
    let id: String
    let title: String
    let iconName: String
    let description: String
    let isUnlocked: Bool
    let accentColor: Color
}

struct LifetimeMilestonesCard: View {
    var allRuns: [RunRecord]
    @AppStorage("useMetricSystem") private var useMetricSystem: Bool = Locale.current.measurementSystem == .metric
    @State private var selectedBadge: MilestoneBadge?

    private var totalDistanceMeters: Double {
        allRuns.map(\.totalDistanceMeters).reduce(0, +)
    }

    private var totalDurationSeconds: TimeInterval {
        allRuns.map(\.duration).reduce(0, +)
    }

    private var formattedTotalDistance: String {
        let distance = useMetricSystem ? (totalDistanceMeters / 1000.0) : (totalDistanceMeters / 1609.344)
        let unit = useMetricSystem ? "km" : "mi"
        return String(format: "%.1f %@", distance, unit)
    }

    private var formattedTotalTime: String {
        let hours = Int(totalDurationSeconds) / 3600
        let minutes = (Int(totalDurationSeconds) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    private var longestRunFormatted: String {
        guard let maxMeters = allRuns.map(\.totalDistanceMeters).max(), maxMeters > 0 else { return "—" }
        let distance = useMetricSystem ? (maxMeters / 1000.0) : (maxMeters / 1609.344)
        let unit = useMetricSystem ? "km" : "mi"
        return String(format: "%.1f %@", distance, unit)
    }

    private var fastestPaceFormatted: String {
        let validPaces = allRuns.filter { $0.workingAvgPace > 0 && $0.totalDistanceMeters >= 1000.0 }.map(\.workingAvgPace)
        guard let minPace = validPaces.min() else { return "—" }
        return PaceFormatter.formatPace(secondsPerKilometer: minPace)
    }

    private var highestCadenceFormatted: String {
        guard let maxCadence = allRuns.map(\.workingAvgCadence).filter({ $0 > 0 }).max() else { return "—" }
        return "\(Int(maxCadence)) SPM"
    }

    private var peakEfficiencyFactorFormatted: String {
        let efs = allRuns.compactMap(\.efficiencyFactor)
        guard let maxEF = efs.max() else { return "—" }
        return String(format: "%.2f", maxEF)
    }

    private var milestoneBadges: [MilestoneBadge] {
        let totalKm = totalDistanceMeters / 1000.0
        let maxRunKm = (allRuns.map(\.totalDistanceMeters).max() ?? 0) / 1000.0
        let maxCadence = allRuns.map(\.workingAvgCadence).max() ?? 0
        let maxEF = allRuns.compactMap(\.efficiencyFactor).max() ?? 0
        let runCount = allRuns.count

        return [
            MilestoneBadge(
                id: "first_run",
                title: "First Steps",
                iconName: "figure.run.circle.fill",
                description: "Recorded your first run in Runalyst.",
                isUnlocked: runCount >= 1,
                accentColor: .blue
            ),
            MilestoneBadge(
                id: "five_k",
                title: "5K Milestone",
                iconName: "flame.fill",
                description: "Logged a single run of at least 5 km.",
                isUnlocked: maxRunKm >= 5.0,
                accentColor: .orange
            ),
            MilestoneBadge(
                id: "ten_k",
                title: "10K Club",
                iconName: "trophy.fill",
                description: "Logged a single run of at least 10 km.",
                isUnlocked: maxRunKm >= 10.0,
                accentColor: .yellow
            ),
            MilestoneBadge(
                id: "half_marathon",
                title: "Half Marathon",
                iconName: "medal.fill",
                description: "Completed a 21.1 km endurance effort.",
                isUnlocked: maxRunKm >= 21.1,
                accentColor: .purple
            ),
            MilestoneBadge(
                id: "century_volume",
                title: "100K Century",
                iconName: "sparkles",
                description: "Accumulated 100 km of total lifetime running volume.",
                isUnlocked: totalKm >= 100.0,
                accentColor: .cyan
            ),
            MilestoneBadge(
                id: "five_hundred_k",
                title: "500K Titan",
                iconName: "crown.fill",
                description: "Accumulated 500 km of total lifetime running volume.",
                isUnlocked: totalKm >= 500.0,
                accentColor: .indigo
            ),
            MilestoneBadge(
                id: "rhythm_master",
                title: "Rhythm Master",
                iconName: "metronome.fill",
                description: "Maintained optimal turnover of 170+ SPM.",
                isUnlocked: maxCadence >= 170.0,
                accentColor: .teal
            ),
            MilestoneBadge(
                id: "aerobic_engine",
                title: "Aerobic Engine",
                iconName: "bolt.heart.fill",
                description: "Achieved an Efficiency Factor exceeding 1.35 m/beat.",
                isUnlocked: maxEF >= 1.35,
                accentColor: .pink
            ),
            MilestoneBadge(
                id: "consistency",
                title: "Consistent Runner",
                iconName: "calendar.badge.checkmark",
                description: "Logged 10 or more structured running workouts.",
                isUnlocked: runCount >= 10,
                accentColor: .green
            )
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: "trophy.fill")
                    .foregroundColor(.yellow)
                    .font(.headline)
                Text("Lifetime Volume & Milestones")
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
                Text("\(allRuns.count) Total Runs")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
            }

            // Hero Volume Stats Grid
            HStack(spacing: 12) {
                // Total Distance
                VStack(alignment: .leading, spacing: 4) {
                    Text("TOTAL DISTANCE")
                        .font(.caption2.bold())
                        .foregroundColor(.secondary)
                    Text(formattedTotalDistance)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color(UIColor.tertiarySystemFill))
                .cornerRadius(12)

                // Total Time
                VStack(alignment: .leading, spacing: 4) {
                    Text("TIME ON FEET")
                        .font(.caption2.bold())
                        .foregroundColor(.secondary)
                    Text(formattedTotalTime)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color(UIColor.tertiarySystemFill))
                .cornerRadius(12)
            }

            // Personal Records Grid
            VStack(alignment: .leading, spacing: 8) {
                Text("PERSONAL RECORDS")
                    .font(.caption2.bold())
                    .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    // Longest Run
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Image(systemName: "road.lanes")
                                .font(.caption2)
                                .foregroundColor(.indigo)
                            Text("Longest")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        Text(longestRunFormatted)
                            .font(.subheadline.bold())
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.80)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Fastest Pace
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Image(systemName: "speedometer")
                                .font(.caption2)
                                .foregroundColor(.teal)
                            Text("Fastest")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        Text(fastestPaceFormatted)
                            .font(.subheadline.bold())
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.80)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Best Cadence
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Image(systemName: "figure.run")
                                .font(.caption2)
                                .foregroundColor(.blue)
                            Text("Cadence")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        Text(highestCadenceFormatted)
                            .font(.subheadline.bold())
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.80)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Peak EF
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Image(systemName: "bolt.heart")
                                .font(.caption2)
                                .foregroundColor(.pink)
                            Text("Peak EF")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        Text(peakEfficiencyFactorFormatted)
                            .font(.subheadline.bold())
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.80)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(12)
                .background(Color(UIColor.tertiarySystemFill))
                .cornerRadius(12)
            }

            // Milestone Badges Carousel / Grid
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("MILESTONE BADGES")
                        .font(.caption2.bold())
                        .foregroundColor(.secondary)
                    Spacer()
                    let unlockedCount = milestoneBadges.filter(\.isUnlocked).count
                    Text("\(unlockedCount) of \(milestoneBadges.count) Unlocked")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(milestoneBadges) { badge in
                            Button(action: {
                                selectedBadge = badge
                            }) {
                                VStack(spacing: 6) {
                                    ZStack {
                                        Circle()
                                            .fill(badge.isUnlocked ? badge.accentColor.opacity(0.18) : Color.gray.opacity(0.12))
                                            .frame(width: 52, height: 52)
                                        Image(systemName: badge.iconName)
                                            .font(.title3)
                                            .foregroundColor(badge.isUnlocked ? badge.accentColor : Color.secondary.opacity(0.4))
                                    }

                                    Text(badge.title)
                                        .font(.caption2.bold())
                                        .foregroundColor(badge.isUnlocked ? .primary : .secondary)
                                        .lineLimit(1)
                                }
                                .frame(width: 78)
                                .padding(.vertical, 8)
                                .background(badge.isUnlocked ? Color(UIColor.secondarySystemGroupedBackground) : Color.clear)
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(badge.isUnlocked ? badge.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(16)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(18)
        .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
        .padding(.horizontal)
        .alert(item: $selectedBadge) { badge in
            Alert(
                title: Text(badge.title),
                message: Text(badge.description + (badge.isUnlocked ? "\n\nStatus: Unlocked ✓" : "\n\nStatus: Locked")),
                dismissButton: .default(Text("OK"))
            )
        }
    }
}
