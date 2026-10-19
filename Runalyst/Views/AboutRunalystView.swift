import SwiftUI

struct AboutRunalystView: View {
    var isEmbedded: Bool = false

    var body: some View {
        if isEmbedded {
            aboutContent
        } else {
            ScrollView {
                aboutContent
                    .padding()
            }
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: 90)
            }
            .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("About Runalyst")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var aboutContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            // MARK: - Hero
            VStack(spacing: 8) {
                if let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
                   let primaryIcon = icons["CFBundlePrimaryIcon"] as? [String: Any],
                   let iconFiles = primaryIcon["CFBundleIconFiles"] as? [String],
                   let lastIcon = iconFiles.last,
                   let uiImage = UIImage(named: lastIcon) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                } else {
                    Image(systemName: "figure.run.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.linearGradient(colors: [.teal, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                }
                Text("Runalyst")
                    .font(.largeTitle.bold())
                Text("Your biomechanical running coach")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8)

            // MARK: - Philosophy
            VStack(alignment: .leading, spacing: 8) {
                Text("Philosophy")
                    .font(.headline)
                Text("Runalyst is built on a simple belief: every runner — from a first-time jogger to a seasoned competitor — deserves a coach that prioritizes long-term health over short-term speed. We focus on biomechanical efficiency, aerobic adaptation, and injury prevention so you can run better, not just faster.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineSpacing(3)
            }
            .padding(16)
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .cornerRadius(16)

            // MARK: - How It Works
            VStack(alignment: .leading, spacing: 16) {
                Text("How It Works")
                    .font(.headline)

                AboutFeatureRow(
                    icon: "waveform.path.ecg",
                    color: .red,
                    title: "Framboise Engine",
                    description: "Analyzes workouts minute-by-minute, trims dead stops and pauses, and isolates your true working pace, cadence, and cardiovascular telemetry."
                )
                AboutFeatureRow(
                    icon: "brain.head.profile",
                    color: .purple,
                    title: "On-Device AI Coaching",
                    description: "Apple Foundation Models coach your running form privately on your phone. Your workout data never leaves your device."
                )
                AboutFeatureRow(
                    icon: "chart.xyaxis.line",
                    color: .teal,
                    title: "Rolling Baselines",
                    description: "Every workout and drill is evaluated against your personalized 30-day rolling baseline — never against arbitrary, one-size-fits-all averages."
                )
                AboutFeatureRow(
                    icon: "figure.run",
                    color: .orange,
                    title: "Pre-Run Primers",
                    description: "Targeted neuromuscular drills (Cadence Pyramids, Rhythm Intervals, Strides) designed to optimize turnover and ground contact mechanics before your workout."
                )
                AboutFeatureRow(
                    icon: "cpu",
                    color: .indigo,
                    title: "Smart Workout Classification",
                    description: "An on-device machine learning model classifies each workout's aerobic load (Recovery, Steady Effort, Tempo, Intervals) and refines classification accuracy from your feedback over time."
                )
            }

            // MARK: - Privacy
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "lock.shield.fill")
                        .foregroundColor(.green)
                        .font(.title3)
                    Text("Privacy First")
                        .font(.headline)
                }
                Text("All AI coaching, calculations, and analysis happen entirely on your device. Runalyst reads from Apple Health but never sends your data to external servers. Your running data stays with you.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineSpacing(3)
            }
            .padding(16)
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .cornerRadius(16)

            // MARK: - Footer
            VStack(spacing: 12) {
                Divider()

                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.shield.fill")
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.8))
                    Text("AI-generated insights are for informational and training purposes only and do not replace professional medical or coaching advice. Always listen to your body.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                }

                Text("Made with ❤️ for runners everywhere")
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.6))
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

struct AboutFeatureRow: View {
    let icon: String
    let color: Color
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
                .frame(width: 28, alignment: .center)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundColor(.primary)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineSpacing(2)
            }
        }
    }
}
