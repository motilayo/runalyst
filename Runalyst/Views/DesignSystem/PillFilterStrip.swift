import SwiftUI

/// Standardized horizontal scrolling pill filter strip for category selection.
public struct PillFilterStrip: View {
    public let categories: [String]
    @Binding public var selectedCategory: String
    public var onSelectionChanged: ((String) -> Void)?

    public init(
        categories: [String],
        selectedCategory: Binding<String>,
        onSelectionChanged: ((String) -> Void)? = nil
    ) {
        self.categories = categories
        self._selectedCategory = selectedCategory
        self.onSelectionChanged = onSelectionChanged
    }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categories, id: \.self) { category in
                    let isSelected = selectedCategory == category
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        selectedCategory = category
                        onSelectionChanged?(category)
                    } label: {
                        Text(category)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                isSelected
                                ? Color.blue
                                : Color(UIColor.secondarySystemGroupedBackground)
                            )
                            .foregroundColor(isSelected ? .white : .primary)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(
                                        isSelected ? Color.clear : Color(UIColor.separator).opacity(0.18),
                                        lineWidth: 0.5
                                    )
                            )
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 2)
        }
    }
}
