import SwiftUI

/// Standardized Coach navigation pill button for toolbar navigation across all screens.
public struct CoachPillButton: View {
    public let action: () -> Void

    public init(action: @escaping () -> Void) {
        self.action = action
    }

    public var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            action()
        }) {
            HStack(spacing: 5) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 11, weight: .bold))
                Text("Coach")
                    .font(.subheadline.weight(.bold))
            }
            .foregroundColor(.purple)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.purple.opacity(0.12))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.purple.opacity(0.18), lineWidth: 0.5)
            )
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityLabel("AI Running Coach")
        .accessibilityHint("Opens AI Biomechanical Analyst and Coach chat")
    }
}
