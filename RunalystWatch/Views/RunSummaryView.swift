import RunalystCore
import SwiftUI

// MARK: - Run Summary View

/// Hollow post-run review sheet rendering coach takeaways on Apple Watch.
/// Binds strictly to `WatchRunDebrief`. Zero inline math or string synthesis.
public struct RunSummaryView: View {
    public let debrief: WatchRunDebrief
    public let onDone: () -> Void

    public init(debrief: WatchRunDebrief, onDone: @escaping () -> Void) {
        self.debrief = debrief
        self.onDone = onDone
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 8) {
                    summaryHeroCard

                    takeawaysCard

                    doneButton
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 12)
            }
        }
        .navigationBarBackButtonHidden(true)
    }

    // MARK: - Subviews

    private var summaryHeroCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(WatchColor.cadence.opacity(0.15))
                        .frame(width: 20, height: 20)
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(WatchColor.cadence)
                }

                Text(debrief.companionSyncBadgeText)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(WatchColor.cadence)

                Spacer()

                HStack(spacing: 3) {
                    Image(systemName: "clock")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                    Text(debrief.elapsedFormatted)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(debrief.primaryDistanceValue)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)

                Text(debrief.distanceUnitLabel)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 0) {
                summaryStatColumn(
                    icon: WatchIcon.pace,
                    label: "PACE",
                    value: debrief.averagePaceFormatted,
                    iconColor: WatchColor.pace
                )
                Divider().frame(height: 18).opacity(0.25)
                summaryStatColumn(
                    icon: WatchIcon.heartRate,
                    label: "HR",
                    value: debrief.averageHeartRateFormatted,
                    iconColor: WatchColor.heartRate
                )
                Divider().frame(height: 18).opacity(0.25)
                summaryStatColumn(
                    icon: WatchIcon.cadence,
                    label: "CADENCE",
                    value: debrief.averageCadenceFormatted,
                    iconColor: WatchColor.cadence
                )
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 4)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
            )
            .padding(.top, 2)
        }
        .padding(10)
        .watchLiquidGlass(accent: WatchColor.cadence, cornerRadius: 14, isProminent: true)
    }

    private func summaryStatColumn(icon: String, label: String, value: String, iconColor: Color) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(iconColor)
                Text(label)
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity)
    }

    private var takeawaysCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            takeawayRow(
                title: "PACING",
                icon: "waveform.path.ecg",
                iconColor: WatchColor.pace,
                bullet: debrief.adaptationsBullet
            )
            Divider().opacity(0.25)
            takeawayRow(
                title: "AEROBIC",
                icon: "heart.fill",
                iconColor: WatchColor.heartRate,
                bullet: debrief.efficiencyScoreBullet
            )
            Divider().opacity(0.25)
            takeawayRow(
                title: "CADENCE",
                icon: WatchIcon.cadence,
                iconColor: WatchColor.cadence,
                bullet: debrief.formInsightBullet
            )
        }
        .padding(8)
        .watchLiquidGlass(cornerRadius: 12)
    }

    private func takeawayRow(title: String, icon: String, iconColor: Color, bullet: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(iconColor)
                Text(title)
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Text(bullet)
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var doneButton: some View {
        Button {
            onDone()
        } label: {
            Text("Done")
                .font(.system(.headline, design: .rounded))
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity, minHeight: 44)
                .foregroundStyle(.black)
                .background(WatchColor.cadence)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.top, 2)
    }
}
