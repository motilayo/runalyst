import SwiftUI

/// Unified Liquid Glass card container modifier.
/// Implements translucent system materials, specular refraction highlights,
/// hairline optical rims, and optional ambient metric glow backdrops.
public struct LiquidGlassModifier: ViewModifier {
    public var cornerRadius: CGFloat
    public var padding: CGFloat
    public var accentColor: Color?
    public var material: Material

    public init(
        cornerRadius: CGFloat = 16,
        padding: CGFloat = 16,
        accentColor: Color? = nil,
        material: Material = .ultraThinMaterial
    ) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.accentColor = accentColor
        self.material = material
    }

    public func body(content: Content) -> some View {
        content
            .padding(padding)
            .background {
                ZStack {
                    // Optional ambient domain-colored glow orb
                    if let accentColor {
                        Circle()
                            .fill(accentColor.opacity(0.12))
                            .blur(radius: 28)
                            .offset(x: -40, y: -20)
                    }

                    // Translucent optical material base
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(material)

                    // Specular rim gradient (light reflection from top-leading to bottom-trailing)
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.38),
                                    Color.white.opacity(0.12),
                                    Color.white.opacity(0.04),
                                    Color.clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.75
                        )

                    // Subtle hairline structural base border
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color(UIColor.separator).opacity(0.14), lineWidth: 0.5)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 3)
    }
}

public extension View {
    /// Applies the unified Runalyst Liquid Glass card styling.
    func liquidGlass(
        cornerRadius: CGFloat = 16,
        padding: CGFloat = 16,
        accentColor: Color? = nil,
        material: Material = .ultraThinMaterial
    ) -> some View {
        modifier(
            LiquidGlassModifier(
                cornerRadius: cornerRadius,
                padding: padding,
                accentColor: accentColor,
                material: material
            )
        )
    }
}

/// Standalone Liquid Glass Card container view.
public struct LiquidGlassCard<Content: View>: View {
    private let cornerRadius: CGFloat
    private let padding: CGFloat
    private let accentColor: Color?
    private let material: Material
    private let content: Content

    public init(
        cornerRadius: CGFloat = 16,
        padding: CGFloat = 16,
        accentColor: Color? = nil,
        material: Material = .ultraThinMaterial,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.accentColor = accentColor
        self.material = material
        self.content = content()
    }

    public var body: some View {
        content
            .liquidGlass(
                cornerRadius: cornerRadius,
                padding: padding,
                accentColor: accentColor,
                material: material
            )
    }
}
