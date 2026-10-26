import SwiftUI

// Liquid Glass on macOS 26, with material fallbacks for macOS 12–15. The
// compiler check keeps the project building with Xcode versions older than 26.

extension View {
    /// A rounded glass panel behind the view.
    func glassCard(cornerRadius: CGFloat = 18, tint: Color? = nil) -> some View {
        modifier(GlassCard(shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous), tint: tint))
    }

    /// A circular glass badge behind the view.
    func glassCircle(tint: Color? = nil) -> some View {
        modifier(GlassCard(shape: Circle(), tint: tint))
    }

    func glassButton(prominent: Bool = false) -> some View {
        modifier(GlassButton(prominent: prominent))
    }
}

private struct GlassCard<S: InsettableShape>: ViewModifier {
    let shape: S
    let tint: Color?

    @ViewBuilder
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            content.glassEffect(tint.map { Glass.regular.tint($0) } ?? .regular, in: shape)
        } else {
            fallback(content)
        }
        #else
        fallback(content)
        #endif
    }

    private func fallback(_ content: Content) -> some View {
        content
            .background((tint ?? .clear).opacity(0.18), in: shape)
            .background(.regularMaterial, in: shape)
            .overlay(shape.strokeBorder(.white.opacity(0.12), lineWidth: 1))
    }
}

private struct GlassButton: ViewModifier {
    let prominent: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            if prominent {
                content.buttonStyle(.glassProminent)
            } else {
                content.buttonStyle(.glass)
            }
        } else {
            fallback(content)
        }
        #else
        fallback(content)
        #endif
    }

    @ViewBuilder
    private func fallback(_ content: Content) -> some View {
        if prominent {
            content.buttonStyle(.borderedProminent)
        } else {
            content.buttonStyle(.bordered)
        }
    }
}

/// Groups glass shapes so they blend into each other on macOS 26.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder var content: Content

    var body: some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
        #else
        content
        #endif
    }
}
