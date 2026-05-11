import Foundation

public enum ProviderAccountingConfidence: String, Sendable {
    case providerReportedTotal = "provider_reported_total"
    case componentDerivedTotal = "component_derived_total"
}

public enum ProviderAccountingSemantics: String, Sendable {
    case claudeOtelApiRequest = "claude_otel_api_request"
    case claudeStatusLineCumulativeTotals = "claude_statusline_cumulative_totals"
    case claudeTranscriptComponentTotals = "claude_transcript_component_totals"
    case codexProviderTotal = "codex_provider_total"
    case codexInputOutputFallback = "codex_input_output_fallback"
    case geminiProviderTotal = "gemini_provider_total"
    case cursorExportTotal = "cursor_export_total"
    case cursorComponentFallback = "cursor_component_fallback"
    case openclawProviderTotal = "openclaw_provider_total"
    case openclawInputOutputFallback = "openclaw_input_output_fallback"
}

public struct ProviderAccountingSample: Sendable {
    public let totalInputTokens: Int64
    public let totalOutputTokens: Int64
    public let totalCachedInputTokens: Int64
    public let normalizedTotalTokens: Int64
    public let currentInputTokens: Int64?
    public let currentOutputTokens: Int64?
    public let confidence: ProviderAccountingConfidence
    public let semantics: ProviderAccountingSemantics
}

public enum ProviderTokenAccounting {
    public static func claudeOtel(
        totalInputTokens: Int64,
        totalOutputTokens: Int64,
        totalCachedInputTokens: Int64,
        normalizedTotalTokens: Int64,
        currentInputTokens: Int64?,
        currentOutputTokens: Int64?
    ) -> ProviderAccountingSample {
        ProviderAccountingSample(
            totalInputTokens: totalInputTokens,
            totalOutputTokens: totalOutputTokens,
            totalCachedInputTokens: totalCachedInputTokens,
            normalizedTotalTokens: normalizedTotalTokens,
            currentInputTokens: currentInputTokens,
            currentOutputTokens: currentOutputTokens,
            confidence: .providerReportedTotal,
            semantics: .claudeOtelApiRequest
        )
    }

    public static func claudeStatusLine(
        totalInputTokens: Int64,
        totalOutputTokens: Int64,
        currentInputTokens: Int64?,
        currentOutputTokens: Int64?
    ) -> ProviderAccountingSample {
        ProviderAccountingSample(
            totalInputTokens: totalInputTokens,
            totalOutputTokens: totalOutputTokens,
            totalCachedInputTokens: 0,
            normalizedTotalTokens: totalInputTokens + totalOutputTokens,
            currentInputTokens: currentInputTokens,
            currentOutputTokens: currentOutputTokens,
            confidence: .componentDerivedTotal,
            semantics: .claudeStatusLineCumulativeTotals
        )
    }

    public static func claudeTranscript(
        totalInputTokens: Int64,
        totalOutputTokens: Int64,
        totalCachedInputTokens: Int64,
        currentInputTokens: Int64?,
        currentOutputTokens: Int64?
    ) -> ProviderAccountingSample {
        ProviderAccountingSample(
            totalInputTokens: totalInputTokens,
            totalOutputTokens: totalOutputTokens,
            totalCachedInputTokens: totalCachedInputTokens,
            normalizedTotalTokens: totalInputTokens + totalOutputTokens + totalCachedInputTokens,
            currentInputTokens: currentInputTokens,
            currentOutputTokens: currentOutputTokens,
            confidence: .componentDerivedTotal,
            semantics: .claudeTranscriptComponentTotals
        )
    }

    public static func codex(
        totalInputTokens: Int64,
        totalOutputTokens: Int64,
        totalCachedInputTokens: Int64,
        providerTotalTokens: Int64?,
        currentInputTokens: Int64?,
        currentOutputTokens: Int64?
    ) -> ProviderAccountingSample {
        let normalizedTotalTokens = providerTotalTokens ?? (totalInputTokens + totalOutputTokens)
        return ProviderAccountingSample(
            totalInputTokens: totalInputTokens,
            totalOutputTokens: totalOutputTokens,
            totalCachedInputTokens: totalCachedInputTokens,
            normalizedTotalTokens: normalizedTotalTokens,
            currentInputTokens: currentInputTokens,
            currentOutputTokens: currentOutputTokens,
            confidence: providerTotalTokens == nil ? .componentDerivedTotal : .providerReportedTotal,
            semantics: providerTotalTokens == nil ? .codexInputOutputFallback : .codexProviderTotal
        )
    }

    public static func gemini(
        totalInputTokens: Int64,
        totalOutputTokens: Int64,
        totalCachedInputTokens: Int64,
        normalizedTotalTokens: Int64,
        currentInputTokens: Int64?,
        currentOutputTokens: Int64?
    ) -> ProviderAccountingSample {
        ProviderAccountingSample(
            totalInputTokens: totalInputTokens,
            totalOutputTokens: totalOutputTokens,
            totalCachedInputTokens: totalCachedInputTokens,
            normalizedTotalTokens: normalizedTotalTokens,
            currentInputTokens: currentInputTokens,
            currentOutputTokens: currentOutputTokens,
            confidence: .providerReportedTotal,
            semantics: .geminiProviderTotal
        )
    }

    public static func cursor(
        totalInputTokens: Int64,
        totalOutputTokens: Int64,
        totalCachedInputTokens: Int64,
        normalizedTotalTokens: Int64,
        currentInputTokens: Int64?,
        currentOutputTokens: Int64?,
        usedExplicitTotal: Bool
    ) -> ProviderAccountingSample {
        ProviderAccountingSample(
            totalInputTokens: totalInputTokens,
            totalOutputTokens: totalOutputTokens,
            totalCachedInputTokens: totalCachedInputTokens,
            normalizedTotalTokens: normalizedTotalTokens,
            currentInputTokens: currentInputTokens,
            currentOutputTokens: currentOutputTokens,
            confidence: usedExplicitTotal ? .providerReportedTotal : .componentDerivedTotal,
            semantics: usedExplicitTotal ? .cursorExportTotal : .cursorComponentFallback
        )
    }

    public static func openclaw(
        totalInputTokens: Int64,
        totalOutputTokens: Int64,
        totalCachedInputTokens: Int64,
        providerTotalTokens: Int64?
    ) -> ProviderAccountingSample {
        let normalizedTotalTokens = providerTotalTokens ?? (totalInputTokens + totalOutputTokens)
        return ProviderAccountingSample(
            totalInputTokens: totalInputTokens,
            totalOutputTokens: totalOutputTokens,
            totalCachedInputTokens: totalCachedInputTokens,
            normalizedTotalTokens: normalizedTotalTokens,
            currentInputTokens: nil,
            currentOutputTokens: nil,
            confidence: providerTotalTokens == nil ? .componentDerivedTotal : .providerReportedTotal,
            semantics: providerTotalTokens == nil ? .openclawInputOutputFallback : .openclawProviderTotal
        )
    }
}
