import SwiftUI
import TokenmonDomain
import TokenmonPersistence

/// Small dot + label indicating one provider's status. Encapsulates the color mapping rule.
struct TokenmonProviderIndicator: View {
    let provider: ProviderCode
    /// `nil` means no health row yet → render as gray "Not installed".
    let healthState: String?
    let cliInstalled: Bool
    let onClick: () -> Void

    private enum ColorState {
        case green, yellow, red, gray

        var color: Color {
            switch self {
            case .green: return .green
            case .yellow: return .yellow
            case .red: return .red
            case .gray: return .gray
            }
        }

        var statusWord: String {
            switch self {
            case .green: return TokenmonL10n.string("provider.indicator.on")
            case .yellow: return TokenmonL10n.string("provider.indicator.setup")
            case .red: return TokenmonL10n.string("provider.indicator.error")
            case .gray: return TokenmonL10n.string("provider.indicator.off")
            }
        }

        var description: String {
            switch self {
            case .green: return TokenmonL10n.string("provider.indicator.active")
            case .yellow: return TokenmonL10n.string("provider.indicator.needs_attention")
            case .red: return TokenmonL10n.string("provider.indicator.connection_issue")
            case .gray: return TokenmonL10n.string("provider.indicator.not_installed")
            }
        }
    }

    private var state: ColorState {
        guard let healthState else {
            return cliInstalled ? .yellow : .gray
        }
        switch healthState {
        case "active", "connected": return .green
        case "experimental", "missing_configuration": return .yellow
        case "degraded", "unsupported": return .red
        default: return .yellow
        }
    }

    private var label: String {
        switch provider {
        case .claude: return "Claude"
        case .codex: return "Codex"
        case .gemini: return "Gemini"
        case .cursor: return "Cursor"
        case .openclaw: return "OpenClaw"
        }
    }

    private var tooltip: String {
        let action: String
        switch state {
        case .green: action = ""
        case .yellow: action = TokenmonL10n.string("provider.indicator.action.open")
        case .red: action = TokenmonL10n.string("provider.indicator.action.fix")
        case .gray: action = TokenmonL10n.string("provider.indicator.action.install")
        }
        return TokenmonL10n.format("provider.indicator.tooltip", label, state.description, action)
    }

    var body: some View {
        Button(action: onClick) {
            HStack(spacing: 6) {
                Circle()
                    .fill(state.color)
                    .frame(width: 9, height: 9)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.35), lineWidth: 0.5)
                    )
                Text(label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                Text(state.statusWord)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(state.color)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(
                        Capsule().fill(state.color.opacity(0.15))
                    )
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(Color.secondary.opacity(0.10))
            )
            .overlay(
                Capsule()
                    .stroke(state.color.opacity(0.35), lineWidth: 0.75)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(tooltip)
        .accessibilityLabel(TokenmonL10n.format("provider.indicator.accessibility", label, state.description))
    }
}
