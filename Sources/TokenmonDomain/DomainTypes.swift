import Foundation

public enum ProviderCode: String, CaseIterable, Codable, Sendable {
    case claude
    case codex
    case gemini
    case cursor
    case openclaw

    public static var allCases: [ProviderCode] {
        [.claude, .codex, .gemini, .cursor, .openclaw]
    }

    public var displayName: String {
        switch self {
        case .claude:
            return "Claude Code"
        case .codex:
            return "Codex"
        case .gemini:
            return "Gemini CLI"
        case .cursor:
            return "Cursor"
        case .openclaw:
            return "OpenClaw"
        }
    }

    public var defaultSupportLevel: String {
        switch self {
        case .claude:
            return "first_class"
        case .codex:
            return "best_effort"
        case .gemini:
            return "first_class"
        case .cursor:
            return "managed_only"
        case .openclaw:
            return "best_effort"
        }
    }
}

public enum FieldType: String, CaseIterable, Codable, Sendable {
    case grassland
    case ice
    case coast
    case sky
}

public enum RarityTier: String, CaseIterable, Codable, Sendable {
    case common
    case uncommon
    case rare
    case epic
    case legendary
}

public enum EncounterOutcome: String, CaseIterable, Codable, Sendable {
    case captured
    case escaped
}

public enum TrainingTrait: String, CaseIterable, Codable, Sendable {
    case trail
    case scout
    case capture
    case raider

    public var displayName: String {
        switch self {
        case .trail: return "Trail"
        case .scout: return "Scout"
        case .capture: return "Capture"
        case .raider: return "Raider"
        }
    }
}

public enum TrainingRank: Int, CaseIterable, Codable, Sendable {
    case rankI = 1
    case rankII = 2
    case rankIII = 3
    case rankIV = 4
    case rankV = 5

    public init?(storageValue: Int64) {
        self.init(rawValue: Int(storageValue))
    }

    public var storageValue: Int64 {
        Int64(rawValue)
    }

    public var romanNumeral: String {
        switch self {
        case .rankI: return "I"
        case .rankII: return "II"
        case .rankIII: return "III"
        case .rankIV: return "IV"
        case .rankV: return "V"
        }
    }

    public var rankPower: Int {
        max(0, rawValue - 1)
    }

    public var next: TrainingRank? {
        TrainingRank(rawValue: rawValue + 1)
    }
}

public enum UsageSampleGameplayEligibility: String, CaseIterable, Codable, Sendable {
    case outsideLiveRuntime = "outside_live_runtime"
    case recoveryOnly = "recovery_only"
    case runtimeBaseline = "runtime_baseline"
    case eligibleLive = "eligible_live"
}

public struct GeminiSessionRunningTotals: Equatable, Sendable {
    public let totalInputTokens: Int64
    public let totalOutputTokens: Int64
    public let totalCachedInputTokens: Int64
    public let normalizedTotalTokens: Int64

    public init(
        totalInputTokens: Int64,
        totalOutputTokens: Int64,
        totalCachedInputTokens: Int64,
        normalizedTotalTokens: Int64
    ) {
        self.totalInputTokens = totalInputTokens
        self.totalOutputTokens = totalOutputTokens
        self.totalCachedInputTokens = totalCachedInputTokens
        self.normalizedTotalTokens = normalizedTotalTokens
    }
}

public struct SpeciesDefinition: Equatable, Codable, Sendable {
    public let id: String
    public let name: String
    public let field: FieldType
    public let rarity: RarityTier
    public let assetKey: String
    public let flavorText: String?
    public let sortOrder: Int
    public let introducedInVersion: String
    public let isActive: Bool
    public let stats: SpeciesStatBlock
    public let trainingTrait: TrainingTrait

    public init(
        id: String,
        name: String,
        field: FieldType,
        rarity: RarityTier,
        assetKey: String,
        flavorText: String? = nil,
        sortOrder: Int,
        introducedInVersion: String = "0.1.0",
        isActive: Bool = true,
        stats: SpeciesStatBlock = SpeciesStatBlock(
            planning: 1, design: 1, frontend: 1,
            backend: 1, pm: 1, infra: 1
        ),
        trainingTrait: TrainingTrait
    ) {
        self.id = id
        self.name = name
        self.field = field
        self.rarity = rarity
        self.assetKey = assetKey
        self.flavorText = flavorText
        self.sortOrder = sortOrder
        self.introducedInVersion = introducedInVersion
        self.isActive = isActive
        self.stats = stats
        self.trainingTrait = trainingTrait
    }
}
