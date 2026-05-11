import SwiftUI
import TokenmonDomain
import TokenmonPersistence

/// Tokens tab content: today / all-time counters, today provider split,
/// rolling 24h hourly bars, and a scrollable recent-sessions list.
struct TokenmonTokensTab: View {
    @ObservedObject var model: TokenmonMenuModel
    let contentWidth: CGFloat

    private var totals: TokenUsageTotals {
        model.tokenTotals ?? TokenUsageTotals(todayTokens: 0, allTimeTokens: 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            countersBlock
            Text(tokenSourceNote)
                .font(.caption2)
                .foregroundStyle(.secondary)
            providerSplitSection
            hourlySection
            recentSessionsSection
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .frame(width: contentWidth, alignment: .topLeading)
    }

    private var tokenSourceNote: String {
        let summary = model.tokenUsageSourceSummary
        if summary.hasAccountUsage {
            let providers = summary.accountBackedProvidersToday
                .map(providerShortName)
                .joined(separator: ", ")
            if providers.isEmpty {
                return TokenmonL10n.string("tokens.source_note.account_available")
            }
            return TokenmonL10n.format("tokens.source_note.account_today", providers)
        }
        if summary.hasLocalUsage {
            return TokenmonL10n.string("tokens.source_note.local_observed")
        }
        return TokenmonL10n.string("tokens.source_note.empty")
    }

    // MARK: - ① Counters

    private var countersBlock: some View {
        HStack(spacing: 0) {
            counterCell(label: TokenmonL10n.string("tokens.counter.today"), value: totals.todayTokens)
            Divider()
                .frame(height: 36)
            counterCell(label: TokenmonL10n.string("tokens.counter.all_time"), value: totals.allTimeTokens)
        }
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    @ViewBuilder
    private func counterCell(label: String, value: Int64) -> some View {
        VStack(spacing: 2) {
            Text(TokenmonCompactCountFormatter.string(for: value))
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(TokenmonL10n.format("tokens.counter.label", label))
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(0.6)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - ② Provider split (today)

    private var providerSplitSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(TokenmonL10n.string("tokens.by_provider_today"))
                .font(.subheadline.weight(.semibold))

            providerSplitBar
        }
    }

    private var providerSplitOrder: [ProviderCode] { [.claude, .codex, .gemini, .cursor, .openclaw] }

    private func providerColor(_ provider: ProviderCode) -> Color {
        switch provider {
        case .claude: return .orange
        case .codex: return .teal
        case .gemini: return .indigo
        case .cursor: return .green
        case .openclaw: return .purple
        }
    }

    private func providerShortName(_ provider: ProviderCode) -> String {
        switch provider {
        case .claude: return "Claude"
        case .codex: return "Codex"
        case .gemini: return "Gemini"
        case .cursor: return "Cursor"
        case .openclaw: return "OpenClaw"
        }
    }

    private var providerSplitTotal: Int64 {
        providerSplitOrder.reduce(0) { $0 + (model.tokenByProviderToday[$1] ?? 0) }
    }

    @ViewBuilder
    private var providerSplitBar: some View {
        let total = providerSplitTotal
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                HStack(spacing: 1) {
                    ForEach(providerSplitOrder, id: \.self) { provider in
                        let value = model.tokenByProviderToday[provider] ?? 0
                        let width = total > 0
                            ? geo.size.width * Double(value) / Double(total)
                            : 0
                        Rectangle()
                            .fill(providerColor(provider))
                            .frame(width: max(0, width - 1))
                    }
                    if total == 0 {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.18))
                    } else {
                        Spacer(minLength: 0)
                    }
                }
            }
            .frame(height: 12)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(Color.secondary.opacity(0.12), lineWidth: 0.5)
            )

            LazyVGrid(
                columns: [
                    GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 8),
                    GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 8),
                ],
                alignment: .leading,
                spacing: 6
            ) {
                ForEach(providerSplitOrder, id: \.self) { provider in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(providerColor(provider))
                                .frame(width: 7, height: 7)
                            Text(providerShortName(provider))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.95)
                        }

                        Text(TokenmonCompactCountFormatter.string(for: model.tokenByProviderToday[provider] ?? 0))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.secondary.opacity(0.08))
                    )
                }
            }
        }
    }

    // MARK: - ③ Rolling 24h hourly bars

    private var hourlySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(TokenmonL10n.string("tokens.last_24_hours"))
                .font(.subheadline.weight(.semibold))

            hourlyBars
        }
    }

    private var hourlyMax: Int64 {
        max(1, model.tokenHourlyRolling.map { $0.tokens }.max() ?? 0)
    }

    @ViewBuilder
    private var hourlyBars: some View {
        let buckets = model.tokenHourlyRolling
        let maxValue = hourlyMax
        HStack(alignment: .bottom, spacing: 0) {
            ForEach(buckets.indices, id: \.self) { index in
                let bucket = buckets[index]
                let isCurrentHour = index == buckets.count - 1
                GeometryReader { geo in
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(isCurrentHour ? Color.accentColor : Color.accentColor.opacity(0.55))
                            .frame(
                                height: max(2, geo.size.height * Double(bucket.tokens) / Double(maxValue))
                            )
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 1)
                .help(TokenmonL10n.format("tokens.hourly.help", formatHour(bucket.date), TokenmonCompactCountFormatter.string(for: bucket.tokens)))
            }
        }
        .frame(height: 60)
    }

    private func formatHour(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:00"
        return formatter.string(from: date)
    }

    // MARK: - ④ Recent sessions

    private var recentSessionsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(TokenmonL10n.string("tokens.recent_sessions"))
                .font(.subheadline.weight(.semibold))

            if model.recentSessions.isEmpty {
                Text(TokenmonL10n.string("tokens.no_sessions"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: 6) {
                        ForEach(model.recentSessions, id: \.providerSessionRowID) { session in
                            sessionRow(session)
                        }
                    }
                    .padding(.bottom, 4)
                }
                .frame(maxHeight: .infinity)
            }
        }
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private func sessionRow(_ session: ProviderSessionTokens) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(providerColor(session.provider))
                .frame(width: 7, height: 7)
            Text(providerShortName(session.provider))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .leading)
            Text(formatSessionTime(session.lastSeenAt))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text(TokenmonCompactCountFormatter.string(for: session.totalTokens))
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.secondary.opacity(0.06))
        )
    }

    private func formatSessionTime(_ iso: String) -> String {
        let inputFormatter = ISO8601DateFormatter()
        inputFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = inputFormatter.date(from: iso)
            ?? ISO8601DateFormatter().date(from: iso)
        guard let date else {
            return iso
        }
        let now = Date()
        let interval = now.timeIntervalSince(date)
        if interval < 60 {
            return TokenmonL10n.string("time.just_now")
        }
        if interval < 3600 {
            return TokenmonL10n.format("time.minutes_ago", Int(interval / 60))
        }
        if interval < 86_400 {
            return TokenmonL10n.format("time.hours_ago", Int(interval / 3600))
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d HH:mm"
        return formatter.string(from: date)
    }
}
