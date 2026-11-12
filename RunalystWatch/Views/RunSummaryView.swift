import RunalystCore
import SwiftUI

// MARK: - Run Summary View

/// Hollow post-run review sheet rendering coach takeaways on Apple Watch.
///
/// Binds strictly to `WatchRunDebrief`. Zero inline math or string synthesis.
public struct RunSummaryView: View {
    public let debrief: WatchRunDebrief
    public let onDone: () -> Void

    public init(debrief: WatchRunDebrief, onDone: @escaping () -> Void) {
        self.debrief = debrief
        self.onDone = onDone
    }

    private let tealAccent = Color(red: 0.0, green: 0.9, blue: 0.75)
    private let electricBlue = Color(red: 0.0, green: 0.8, blue: 1.0)
    private let vibrantGreen = Color(red: 0.18, green: 0.85, blue: 0.35)

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 10) {
                    // Header
                    VStack(spacing: 2) {
                        Text("Coach's Takeaway")
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(.white)
                        Text("POST-RUN DEBRIEF")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)

                    // Compact metrics pill strip
                    HStack(spacing: 4) {
                        metricPill(label: "TIME", value: debrief.elapsedFormatted, color: .white)
                        metricPill(label: "DIST", value: debrief.distanceFormatted, color: electricBlue)
                        metricPill(label: "AVG PACE", value: debrief.averagePaceFormatted, color: electricBlue)
                    }
                    .padding(.horizontal, 2)

                    // 3 crisp dark glass takeaway cards
                    // 1. Adaptations
                    takeawayCard(
                        title: "ADAPTATIONS",
                        icon: "arrow.up.right",
                        iconColor: tealAccent,
                        bullet: debrief.adaptationsBullet
                    )

                    // 2. Efficiency Score
                    takeawayCard(
                        title: "EFFICIENCY SCORE",
                        icon: "waveform.path.ecg",
                        iconColor: electricBlue,
                        bullet: debrief.efficiencyScoreBullet
                    )

                    // 3. Form Insight
                    takeawayCard(
                        title: "FORM INSIGHT",
                        icon: "figure.run",
                        iconColor: vibrantGreen,
                        bullet: debrief.formInsightBullet
                    )

                    // Done CTA button (minimum 44pt hit target)
                    Button {
                        onDone()
                    } label: {
                        Text("Done")
                            .font(.system(.headline, design: .rounded))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(Color.green)
                            .foregroundStyle(.black)
                            .clipShape(RoundedRectangle(cornerRadius: 22))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
                .padding(.horizontal, 8)
            }
        }
        .navigationBarBackButtonHidden(true)
    }

    private func metricPill(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 1) {
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.caption2, design: .rounded))
                .fontWeight(.semibold)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 4)
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func takeawayCard(title: String, icon: String, iconColor: Color, bullet: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundStyle(iconColor)
                Text(title)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Text(bullet)
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.white.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
