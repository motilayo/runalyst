import SwiftUI

/// Reusable AI disclaimer footer conforming to medical/coaching disclaimer guidelines,
/// Generative AI on-device privacy guarantee, and HealthKit attribution.
struct AIDisclaimerFooter: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
                .padding(.vertical, 4)

            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: "lock.shield.fill")
                        .font(.caption2)
                        .foregroundColor(Color(red: 0.0, green: 0.8, blue: 0.65))
                    Text("Analyzed on-device")
                        .font(.system(.caption2, design: .rounded).weight(.medium))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(UIColor.tertiarySystemFill))
                .clipShape(Capsule())

                HStack(spacing: 4) {
                    Image(systemName: "heart.text.square.fill")
                        .font(.caption2)
                        .foregroundColor(.pink)
                    Text("Apple Health")
                        .font(.system(.caption2, design: .rounded).weight(.medium))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(UIColor.tertiarySystemFill))
                .clipShape(Capsule())

                Spacer()
            }

            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.8))

                Text("AI-generated insights are for informational purposes only and do not replace professional medical or coaching advice. Always listen to your body.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding(.top, 4)
    }
}
