import Foundation
import TokenmonDomain

public struct OpenclawSessionBackfillAdapterConfig: Sendable {
    public let sessionIDFallback: String?
    public let nowProvider: @Sendable () -> String
    public let sourceMode: String
    public let rawReferenceKind: String
    public let sessionOriginHint: ProviderSessionOriginHint

    public init(
        sessionIDFallback: String? = nil,
        sourceMode: String = "openclaw_session_backfill",
        rawReferenceKind: String = "session_backfill",
        sessionOriginHint: ProviderSessionOriginHint = .unknown,
        nowProvider: @escaping @Sendable () -> String = {
            ISO8601DateFormatter().string(from: Date())
        }
    ) {
        self.sessionIDFallback = sessionIDFallback
        self.sourceMode = sourceMode
        self.rawReferenceKind = rawReferenceKind
        self.sessionOriginHint = sessionOriginHint
        self.nowProvider = nowProvider
    }
}

public struct OpenclawSessionBackfillDeltaResult: Sendable {
    public let sessionID: String?
    public let events: [ProviderUsageSampleEvent]
    public let lastOffset: Int64
    public let lastLineNumber: Int
    public let lastEventFingerprint: String?
}

public struct OpenclawSessionMetadata: Sendable {
    public let sessionID: String?
    public let lastOffset: Int64
    public let lastLineNumber: Int
}

public enum OpenclawSessionBackfillAdapterError: Error, LocalizedError {
    case missingSessionID
    case malformedLine(lineNumber: Int)
    case noUsageSamplesFound

    public var errorDescription: String? {
        switch self {
        case .missingSessionID:
            return "openclaw session backfill requires a session id derived from the file path"
        case .malformedLine(let lineNumber):
            return "openclaw session line \(lineNumber) is not valid JSON"
        case .noUsageSamplesFound:
            return "openclaw session file does not contain any recoverable usage events"
        }
    }
}

public enum OpenclawSessionBackfillAdapter {
    /// Extracts the session ID from the file basename (UUID before .jsonl extension).
    /// Skips *.checkpoint.*.jsonl replay files.
    public static func sessionID(from transcriptPath: String) -> String? {
        let url = URL(fileURLWithPath: transcriptPath)
        let name = url.deletingPathExtension().lastPathComponent
        // Skip checkpoint replay files: <name>.checkpoint.<N>
        guard name.contains(".checkpoint.") == false else {
            return nil
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    public static func scanSessionMetadata(
        from transcriptPath: String,
        config: OpenclawSessionBackfillAdapterConfig = OpenclawSessionBackfillAdapterConfig()
    ) throws -> OpenclawSessionMetadata {
        let readResult = try ProviderInboxReader.read(from: transcriptPath, startingAt: 0)

        var lastOffset: Int64 = 0
        var lastLineNumber = 0

        for line in readResult.lines {
            let lineNumber = lastLineNumber + 1
            let trimmed = line.rawLine.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmed.isEmpty {
                if line.newlineTerminated {
                    lastOffset = line.nextOffset
                    lastLineNumber = lineNumber
                }
                continue
            }

            if line.newlineTerminated == false {
                continue
            }

            lastOffset = line.nextOffset
            lastLineNumber = lineNumber
        }

        let sessionID = config.sessionIDFallback ?? Self.sessionID(from: transcriptPath)
        return OpenclawSessionMetadata(
            sessionID: sessionID,
            lastOffset: lastOffset,
            lastLineNumber: lastLineNumber
        )
    }

    public static func scanSessionDelta(
        from transcriptPath: String,
        startingAt offset: Int64,
        startingLineNumber: Int,
        config: OpenclawSessionBackfillAdapterConfig = OpenclawSessionBackfillAdapterConfig()
    ) throws -> OpenclawSessionBackfillDeltaResult {
        let readResult = try ProviderInboxReader.read(from: transcriptPath, startingAt: offset)

        let resolvedSessionID = config.sessionIDFallback ?? Self.sessionID(from: transcriptPath)

        var events: [ProviderUsageSampleEvent] = []
        var lastOffset = offset
        var lastLineNumber = startingLineNumber
        var lastEventFingerprint: String?

        for line in readResult.lines {
            let lineNumber = lastLineNumber + 1
            let trimmed = line.rawLine.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmed.isEmpty {
                if line.newlineTerminated {
                    lastOffset = line.nextOffset
                    lastLineNumber = lineNumber
                }
                continue
            }

            if line.newlineTerminated == false {
                continue
            }

            guard let jsonObject = try jsonObject(from: trimmed) else {
                throw OpenclawSessionBackfillAdapterError.malformedLine(lineNumber: lineNumber)
            }

            // Only process message events with assistant role and usage
            guard
                jsonObject["type"] as? String == "message",
                let messageDict = jsonObject["message"] as? [String: Any],
                messageDict["role"] as? String == "assistant",
                let usageDict = messageDict["usage"] as? [String: Any]
            else {
                lastOffset = line.nextOffset
                lastLineNumber = lineNumber
                continue
            }

            let inputTokens = int64Value(usageDict["input"]) ?? 0
            let outputTokens = int64Value(usageDict["output"]) ?? 0
            let cacheRead = int64Value(usageDict["cacheRead"]) ?? 0
            let cacheWrite = int64Value(usageDict["cacheWrite"]) ?? 0
            let totalTokens = int64Value(usageDict["totalTokens"])
            let modelSlug = stringValue(messageDict["model"])
            let observedAt = stringValue(jsonObject["timestamp"]) ?? config.nowProvider()

            guard let sessionID = resolvedSessionID, sessionID.isEmpty == false else {
                throw OpenclawSessionBackfillAdapterError.missingSessionID
            }

            let accounting = ProviderTokenAccounting.openclaw(
                totalInputTokens: inputTokens,
                totalOutputTokens: outputTokens,
                totalCachedInputTokens: cacheRead + cacheWrite,
                providerTotalTokens: totalTokens
            )

            let fingerprint = "openclaw:\(sessionID):\(lineNumber):\(inputTokens):\(outputTokens)"
            let event = ProviderUsageSampleEvent(
                eventType: "provider_usage_sample",
                provider: .openclaw,
                sourceMode: config.sourceMode,
                providerSessionID: sessionID,
                observedAt: observedAt,
                workspaceDir: nil,
                modelSlug: modelSlug,
                transcriptPath: transcriptPath,
                totalInputTokens: accounting.totalInputTokens,
                totalOutputTokens: accounting.totalOutputTokens,
                totalCachedInputTokens: accounting.totalCachedInputTokens,
                normalizedTotalTokens: accounting.normalizedTotalTokens,
                providerEventFingerprint: fingerprint,
                rawReference: ProviderRawReference(
                    kind: config.rawReferenceKind,
                    offset: String(lineNumber),
                    eventName: "message"
                ),
                currentInputTokens: nil,
                currentOutputTokens: nil,
                sessionOriginHint: config.sessionOriginHint
            )
            events.append(event)
            lastEventFingerprint = fingerprint

            lastOffset = line.nextOffset
            lastLineNumber = lineNumber
        }

        return OpenclawSessionBackfillDeltaResult(
            sessionID: resolvedSessionID,
            events: events,
            lastOffset: lastOffset,
            lastLineNumber: lastLineNumber,
            lastEventFingerprint: lastEventFingerprint
        )
    }

    private static func jsonObject(from rawLine: String) throws -> [String: Any]? {
        let data = Data(rawLine.utf8)
        let object = try JSONSerialization.jsonObject(with: data)
        return object as? [String: Any]
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let string = value as? String, string.isEmpty == false {
            return string
        }
        return nil
    }

    private static func int64Value(_ value: Any?) -> Int64? {
        if let number = value as? NSNumber {
            return number.int64Value
        }
        if let string = value as? String, let parsed = Int64(string) {
            return parsed
        }
        return nil
    }
}
