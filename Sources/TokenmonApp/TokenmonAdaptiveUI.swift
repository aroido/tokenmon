import AppKit
import SwiftUI

@MainActor
final class TokenmonAdaptiveChromeController: ObservableObject {
    static let shared = TokenmonAdaptiveChromeController()

    @Published var forceCompatibilityChrome = false

    private init() {}

    var runtimeSupportsNativeGlass: Bool {
        Self.runtimeSupportsNativeGlass
    }

    var shouldUseCompatibilityChrome: Bool {
        Self.shouldUseCompatibilityChrome(
            forceCompatibilityChrome: forceCompatibilityChrome,
            runtimeSupportsNativeGlass: runtimeSupportsNativeGlass
        )
    }

    nonisolated static var runtimeSupportsNativeGlass: Bool {
        if #available(macOS 26.0, *) {
            return true
        }

        return false
    }

    nonisolated static func shouldUseCompatibilityChrome(
        forceCompatibilityChrome: Bool,
        runtimeSupportsNativeGlass: Bool
    ) -> Bool {
        forceCompatibilityChrome || !runtimeSupportsNativeGlass
    }
}

enum TokenmonAdaptiveButtonProminence {
    case standard
    case prominent
}

enum TokenmonAdaptiveButtonPadding {
    case automatic
    case labelProvided
}

private struct TokenmonAdaptiveSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat
    let strokeColor: Color?
    let tintOpacity: Double
    let shadowOpacity: Double
    @ObservedObject private var chromeController = TokenmonAdaptiveChromeController.shared

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        if #available(macOS 26.0, *), chromeController.shouldUseCompatibilityChrome == false {
            content
                .background(
                    shape
                        .fill(Color.clear)
                        .glassEffect(in: shape)
                )
                .overlay {
                    if let strokeColor {
                        shape.stroke(strokeColor, lineWidth: 1)
                    }
                }
        } else {
            content
                .background(
                    shape
                        .fill(.regularMaterial)
                        .overlay(
                            shape.fill(Color(nsColor: .controlBackgroundColor).opacity(tintOpacity))
                        )
                        .shadow(
                            color: Color.black.opacity(shadowOpacity),
                            radius: 14,
                            x: 0,
                            y: 4
                        )
                )
                .overlay {
                    if let strokeColor {
                        shape.stroke(strokeColor, lineWidth: 1)
                    }
                }
        }
    }
}

private struct TokenmonAdaptiveButtonStyleModifier: ViewModifier {
    let prominence: TokenmonAdaptiveButtonProminence
    let paddingMode: TokenmonAdaptiveButtonPadding
    @ObservedObject private var chromeController = TokenmonAdaptiveChromeController.shared

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *), chromeController.shouldUseCompatibilityChrome == false {
            switch prominence {
            case .standard:
                content.buttonStyle(.glass)
            case .prominent:
                content.buttonStyle(.glassProminent)
            }
        } else {
            content.buttonStyle(
                TokenmonFallbackGlassButtonStyle(
                    prominence: prominence,
                    paddingMode: paddingMode
                )
            )
        }
    }
}

private struct TokenmonFallbackGlassButtonStyle: ButtonStyle {
    let prominence: TokenmonAdaptiveButtonProminence
    let paddingMode: TokenmonAdaptiveButtonPadding

    @Environment(\.controlSize) private var controlSize
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        configuration.label
            .padding(contentInsets)
            .foregroundStyle(foregroundColor)
            .background(
                shape
                    .fill(backgroundStyle)
                    .overlay(
                        shape.fill(backgroundTint)
                    )
            )
            .overlay(
                shape.stroke(strokeColor, lineWidth: 1)
            )
            .shadow(
                color: shadowColor(configuration.isPressed),
                radius: configuration.isPressed ? 6 : 12,
                x: 0,
                y: configuration.isPressed ? 1 : 4
            )
            .opacity(isEnabled ? 1 : 0.55)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private var cornerRadius: CGFloat {
        switch controlSize {
        case .mini:
            return 8
        case .small:
            return 10
        case .regular:
            return 12
        case .large:
            return 14
        case .extraLarge:
            return 16
        @unknown default:
            return 12
        }
    }

    private var contentInsets: EdgeInsets {
        guard paddingMode == .automatic else {
            return EdgeInsets()
        }

        switch controlSize {
        case .mini:
            return EdgeInsets(top: 3, leading: 8, bottom: 3, trailing: 8)
        case .small:
            return EdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10)
        case .regular:
            return EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
        case .large:
            return EdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14)
        case .extraLarge:
            return EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16)
        @unknown default:
            return EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
        }
    }

    private var foregroundColor: Color {
        switch prominence {
        case .standard:
            return .primary
        case .prominent:
            return Color.white.opacity(isEnabled ? 0.98 : 0.72)
        }
    }

    private var backgroundStyle: AnyShapeStyle {
        switch prominence {
        case .standard:
            return AnyShapeStyle(.regularMaterial)
        case .prominent:
            return AnyShapeStyle(.thickMaterial)
        }
    }

    private var backgroundTint: Color {
        switch prominence {
        case .standard:
            return Color(nsColor: .controlBackgroundColor).opacity(isEnabled ? 0.18 : 0.08)
        case .prominent:
            return Color.accentColor.opacity(isEnabled ? 0.82 : 0.38)
        }
    }

    private var strokeColor: Color {
        switch prominence {
        case .standard:
            return Color.secondary.opacity(isEnabled ? 0.16 : 0.08)
        case .prominent:
            return Color.white.opacity(isEnabled ? 0.18 : 0.08)
        }
    }

    private func shadowColor(_ isPressed: Bool) -> Color {
        switch prominence {
        case .standard:
            return Color.black.opacity(isEnabled ? (isPressed ? 0.06 : 0.10) : 0.03)
        case .prominent:
            return Color.accentColor.opacity(isEnabled ? (isPressed ? 0.16 : 0.28) : 0.08)
        }
    }
}

extension View {
    func tokenmonAdaptiveSurface(
        cornerRadius: CGFloat,
        strokeColor: Color? = nil,
        tintOpacity: Double = 0.16,
        shadowOpacity: Double = 0.10
    ) -> some View {
        modifier(
            TokenmonAdaptiveSurfaceModifier(
                cornerRadius: cornerRadius,
                strokeColor: strokeColor,
                tintOpacity: tintOpacity,
                shadowOpacity: shadowOpacity
            )
        )
    }

    @ViewBuilder
    func tokenmonAdaptiveButtonStyle(
        _ prominence: TokenmonAdaptiveButtonProminence = .standard,
        paddingMode: TokenmonAdaptiveButtonPadding = .automatic
    ) -> some View {
        modifier(
            TokenmonAdaptiveButtonStyleModifier(
                prominence: prominence,
                paddingMode: paddingMode
            )
        )
    }
}

private struct TokenmonAdaptiveSharedBackgroundHidden<Content: ToolbarContent>: ToolbarContent {
    let content: Content
    @ObservedObject private var chromeController = TokenmonAdaptiveChromeController.shared

    @ToolbarContentBuilder
    var body: some ToolbarContent {
        if #available(macOS 26.0, *), chromeController.shouldUseCompatibilityChrome == false {
            content.sharedBackgroundVisibility(.hidden)
        } else {
            content
        }
    }
}

@MainActor
@ToolbarContentBuilder
func tokenmonAdaptiveSharedBackgroundHidden<Content: ToolbarContent>(
    _ content: Content
) -> some ToolbarContent {
    TokenmonAdaptiveSharedBackgroundHidden(content: content)
}
