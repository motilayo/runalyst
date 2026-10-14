import SwiftUI

struct SyncProgressBannerView: View {
    let isSyncing: Bool
    let syncProgress: (current: Int, total: Int)?
    let syncStatusMessage: String?

    var body: some View {
        if isSyncing {
            if let progress = syncProgress, progress.total > 5 {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: "figure.run")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.accentColor)
                            .symbolEffect(.bounce.up, options: .repeating)

                        Text(syncStatusMessage ?? "Calibrating History")
                            .font(.caption.bold())
                            .foregroundColor(.primary)

                        Spacer(minLength: 4)

                        Text("\(progress.current)/\(progress.total)")
                            .font(.caption.bold())
                            .monospacedDigit()
                            .foregroundColor(.secondary)
                    }

                    ProgressView(value: Double(progress.current), total: Double(max(1, progress.total)))
                        .tint(.accentColor)

                    Text("Keep Runalyst open to complete baseline calibration")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                AnimatedLoadingView(
                    text: syncStatusMessage ?? "Syncing Health Data & AI...",
                    isHorizontal: true,
                    imageSize: 16,
                    textFont: .caption,
                    spacing: 8
                )
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.regularMaterial)
                .clipShape(Capsule())
                .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
                .padding(.bottom, 20)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
}
