import AppKit
import SwiftUI
import UniformTypeIdentifiers
import TokenmonDomain
import TokenmonPersistence
import TokenmonProviders


struct TokenmonSceneDebugPanel: View {
    @ObservedObject private var debugController = TokenmonSceneDebugController.shared
    var embedded: Bool = false
    var companionAssetKeysByField: [TokenmonSceneFieldKind: [String]] = [:]

    private let fields: [TokenmonSceneFieldKind] = [.grassland, .ice, .coast, .sky]

    @ViewBuilder
    var body: some View {
        if embedded {
            content
        } else {
            ScrollView {
                content
                    .padding(20)
            }
            .frame(minWidth: 920, minHeight: 680)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(TokenmonL10n.string("developer.visual.scene_debugger.title"))
                    .font(.title2.weight(.bold))
                Text(TokenmonL10n.string("developer.visual.scene_debugger.subtitle"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            GroupBox(TokenmonL10n.string("common.state")) {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(TokenmonL10n.string("developer.visual.scene_debugger.apply_to_menu_bar"), isOn: $debugController.applyToMenuBar)

                    Picker("Scene", selection: $debugController.previewSceneState) {
                        Text(TokenmonL10n.string("now.phase.exploring")).tag(TokenmonSceneState.exploring)
                        Text(TokenmonL10n.string("developer.visual.scene_state.rustle")).tag(TokenmonSceneState.rustle)
                        Text(TokenmonL10n.string("developer.visual.scene_state.alert")).tag(TokenmonSceneState.alert)
                        Text(TokenmonL10n.string("developer.visual.scene_state.resolve_success")).tag(TokenmonSceneState.resolveSuccess)
                        Text(TokenmonL10n.string("developer.visual.scene_state.resolve_escape")).tag(TokenmonSceneState.resolveEscape)
                    }
                    .pickerStyle(.segmented)

                    HStack(spacing: 12) {
                        Picker("Field Motion", selection: $debugController.previewFieldState) {
                            Text(TokenmonL10n.string("developer.visual.field_motion.calm")).tag(TokenmonFieldState.calm)
                            Text(TokenmonL10n.string("now.phase.exploring")).tag(TokenmonFieldState.exploring)
                            Text(TokenmonL10n.string("developer.visual.scene_state.rustle")).tag(TokenmonFieldState.rustle)
                            Text(TokenmonL10n.string("developer.visual.field_motion.settle")).tag(TokenmonFieldState.settle)
                        }

                        Picker("Effect", selection: $debugController.previewEffectState) {
                            Text(TokenmonL10n.string("common.none")).tag(TokenmonEffectState.none)
                            Text(TokenmonL10n.string("developer.visual.scene_state.alert")).tag(TokenmonEffectState.alert)
                            Text(TokenmonL10n.string("outcome.captured")).tag(TokenmonEffectState.captureSnap)
                            Text(TokenmonL10n.string("outcome.escaped")).tag(TokenmonEffectState.escapeDash)
                        }
                    }

                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(TokenmonL10n.string("developer.visual.scene_debugger.menu_bar_x_offset"))
                                .font(.caption.weight(.semibold))
                            HStack {
                                Slider(
                                    value: Binding(
                                        get: {
                                            debugController.statusOffsetX(for: debugController.previewFieldKind)
                                        },
                                        set: { newValue in
                                            debugController.setStatusOffsetX(newValue, for: debugController.previewFieldKind)
                                        }
                                    ),
                                    in: -8...8,
                                    step: 0.5
                                )
                                Text(debugOffsetLabel(debugController.statusOffsetX(for: debugController.previewFieldKind)))
                                    .font(.caption.monospacedDigit())
                                    .frame(width: 44, alignment: .trailing)
                            }
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text(TokenmonL10n.string("developer.visual.scene_debugger.menu_bar_y_offset"))
                                .font(.caption.weight(.semibold))
                            HStack {
                                Slider(
                                    value: Binding(
                                        get: {
                                            debugController.statusOffsetY(for: debugController.previewFieldKind)
                                        },
                                        set: { newValue in
                                            debugController.setStatusOffsetY(newValue, for: debugController.previewFieldKind)
                                        }
                                    ),
                                    in: -8...8,
                                    step: 0.5
                                )
                                Text(debugOffsetLabel(debugController.statusOffsetY(for: debugController.previewFieldKind)))
                                    .font(.caption.monospacedDigit())
                                    .frame(width: 44, alignment: .trailing)
                            }
                        }

                        Button(TokenmonL10n.string("developer.visual.scene_debugger.reset_offsets")) {
                            debugController.resetStatusOffsets()
                        }
                        .controlSize(.small)
                    }

                    Text(TokenmonL10n.format("developer.visual.scene_debugger.selected_field", debugController.previewFieldKind.debugTitle))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(TokenmonL10n.string("developer.visual.scene_debugger.field_effect_note"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text(TokenmonL10n.string("settings.general.section.menu_bar"))
                    .font(.headline)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(fields, id: \.rawValue) { field in
                            TokenmonSceneDebugCard(
                                title: field.debugTitle,
                                subtitle: field == debugController.previewFieldKind ? "Selected for live override" : "Click to select field",
                                isSelected: field == debugController.previewFieldKind,
                                action: {
                                    debugController.selectField(field)
                                },
                                content: AnyView(
                                    TokenmonSceneStatusPreview(
                                        context: debugContext(for: field),
                                        debugController: debugController
                                    )
                                )
                            )
                            .frame(width: 180)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Text(TokenmonL10n.string("developer.visual.scene_debugger.now_tab_hero"))
                    .font(.headline)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(fields, id: \.rawValue) { field in
                            TokenmonSceneDebugCard(
                                title: field.debugTitle,
                                subtitle: field == debugController.previewFieldKind ? "Selected for live override" : "Hero card preview",
                                isSelected: field == debugController.previewFieldKind,
                                action: {
                                    debugController.selectField(field)
                                },
                                content: AnyView(
                                    TokenmonNowFieldHeroCard(
                                        sceneContext: debugContext(for: field),
                                        companionAssetKeys: debugCompanionAssetKeys(for: field)
                                    )
                                    .frame(width: 272)
                                )
                            )
                            .frame(width: 344)
                        }
                    }
                }
            }
        }
    }

    private func debugContext(for field: TokenmonSceneFieldKind) -> TokenmonSceneContext {
        TokenmonSceneContext(
            sceneState: debugController.previewSceneState,
            fieldKind: field,
            fieldState: debugController.previewFieldState,
            effectState: debugController.previewEffectState,
            wildState: .hidden
        )
    }

    private func debugOffsetLabel(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }

    private func debugCompanionAssetKeys(
        for field: TokenmonSceneFieldKind
    ) -> [String] {
        if let provided = companionAssetKeysByField[field], provided.isEmpty == false {
            return provided
        }

        guard field != .unavailable else {
            return []
        }

        return SpeciesCatalog.all
            .filter { $0.isActive && $0.field == field.debugFieldType }
            .prefix(6)
            .map(\.assetKey)
    }
}

private struct TokenmonSceneDebugCard: View {
    let title: String
    let subtitle: String
    var isSelected: Bool = false
    var action: (() -> Void)? = nil
    let content: AnyView

    var body: some View {
        Button(action: { action?() }) {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                content
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        isSelected ? Color.accentColor.opacity(0.65) : Color.clear,
                        lineWidth: isSelected ? 2 : 0
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

private struct TokenmonSceneStatusPreview: View {
    let context: TokenmonSceneContext
    @ObservedObject var debugController: TokenmonSceneDebugController
    @State private var renderedImage: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(nsColor: .windowBackgroundColor),
                            Color(nsColor: .controlBackgroundColor),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            HStack {
                if let renderedImage {
                    Image(nsImage: renderedImage)
                        .interpolation(.none)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
        }
        .frame(height: 34)
        .onAppear(perform: render)
        .onChange(of: context, initial: false) { _, _ in
            render()
        }
    }

    private func render() {
        renderedImage = TokenmonStatusItemImageRenderer.render(
            context: context,
            at: Date(),
            buttonBounds: NSRect(x: 0, y: 0, width: 44, height: NSStatusBar.system.thickness),
            debugController: debugController
        )
    }
}

struct TokenmonMenuHeroSceneCard: View {
    let context: TokenmonSceneContext
    var companionAssetKeys: [String] = []

    var body: some View {
        let clipShape = RoundedRectangle(cornerRadius: 18, style: .continuous)

        ZStack(alignment: .topLeading) {
            TokenmonHeroFieldStage(
                context: context,
                companionAssetKeys: companionAssetKeys
            )

            fieldBadge
                .padding(.leading, 10)
                .padding(.top, 8)
        }
        .clipShape(clipShape)
        .overlay(
            clipShape
                .stroke(fieldTint.opacity(0.16), lineWidth: 1)
        )
        .frame(maxWidth: .infinity)
        .frame(height: 124)
        .accessibilityLabel(companionAssetKeys.isEmpty ? "\(fieldTitle) scene preview" : "\(fieldTitle) scene preview with ambient companion")
    }

    private var fieldTitle: String {
        context.fieldKind.localizedTitle
    }

    private var fieldSystemImage: String {
        context.fieldKind.systemImage
    }

    private var fieldTint: Color {
        switch context.fieldKind {
        case .grassland:
            return Color(red: 0.23, green: 0.63, blue: 0.33)
        case .sky:
            return Color(red: 0.34, green: 0.61, blue: 0.95)
        case .coast:
            return Color(red: 0.18, green: 0.59, blue: 0.84)
        case .ice:
            return Color(red: 0.53, green: 0.79, blue: 0.98)
        case .unavailable:
            return .secondary
        }
    }

    private var fieldBadge: some View {
        Label(fieldTitle, systemImage: fieldSystemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.82))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(fieldTint.opacity(0.24), lineWidth: 0.8)
            )
    }
}

private struct TokenmonHeroFieldStage: View {
    let context: TokenmonSceneContext
    let companionAssetKeys: [String]

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation(minimumInterval: TokenmonSceneTiming.interval(for: context.sceneState), paused: false)) { timeline in
                let tick = TokenmonSceneTiming.tick(for: context, at: timeline.date)
                let layout = fieldLayout

                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(layout.background)

                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.10),
                                    Color.clear,
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    if let popoverBackground = TokenmonFieldSpriteLoader.popoverBackgroundImage(field: context.fieldKind) {
                        Image(nsImage: popoverBackground)
                            .resizable()
                            .interpolation(.none)
                            .scaledToFill()
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .clipped()
                    } else {
                        ForEach(Array(layout.items.enumerated()), id: \.offset) { _, item in
                            TokenmonFieldSpriteImage(field: context.fieldKind, variant: item.variant)
                                .aspectRatio(contentMode: .fit)
                                .frame(width: geometry.size.width * item.widthFactor)
                                .opacity(item.opacity)
                                .shadow(color: Color.black.opacity(0.10), radius: 3, y: 2)
                                .position(
                                    x: geometry.size.width * item.center.x + fieldDrift(tick: tick, phase: item.phase).width,
                                    y: geometry.size.height * item.center.y + fieldDrift(tick: tick, phase: item.phase).height
                                )
                        }
                    }

                    if let selectedCompanionAssetKey {
                        TokenmonAmbientCompanionPortrait(
                            assetKey: selectedCompanionAssetKey,
                            fieldKind: context.fieldKind,
                            sceneState: context.sceneState,
                            tick: tick,
                            sizeMultiplier: layout.companionScale
                        )
                        .position(companionPosition(in: geometry.size, layout: layout, tick: tick))
                    }
                }
            }
        }
        .padding(0)
    }

    private var selectedCompanionAssetKey: String? {
        guard companionAssetKeys.isEmpty == false else {
            return nil
        }

        let cycle = Int(Date().timeIntervalSinceReferenceDate / 18)
        let seed = stableCompanionSeed(for: cycle)
        return companionAssetKeys[seed % companionAssetKeys.count]
    }

    private func companionPosition(
        in size: CGSize,
        layout: TokenmonPopoverFieldLayout,
        tick: Int
    ) -> CGPoint {
        let base = CGPoint(
            x: size.width * layout.companionAnchor.x,
            y: size.height * layout.companionAnchor.y
        )
        let roam = companionRoamOffset(layout: layout)

        return CGPoint(
            x: base.x + roam.width + fieldDrift(tick: tick, phase: 2).width,
            y: base.y + roam.height + fieldDrift(tick: tick, phase: 1).height
        )
    }

    private func fieldDrift(tick: Int, phase: Int) -> CGSize {
        switch context.fieldState {
        case .calm, .unavailable:
            return .zero
        case .exploring:
            let pattern = [
                CGSize(width: -2, height: 0),
                CGSize(width: 0, height: -1),
                CGSize(width: 2, height: 0),
                CGSize(width: 0, height: 0),
            ]
            return pattern[(tick + phase) % pattern.count]
        case .rustle:
            let pattern = [
                CGSize(width: -3, height: -1),
                CGSize(width: 0, height: -2),
                CGSize(width: 3, height: -1),
                CGSize(width: 0, height: 0),
            ]
            return pattern[(tick + phase) % pattern.count]
        case .settle:
            let pattern = [
                CGSize(width: -1, height: 0),
                CGSize(width: 0, height: 0),
                CGSize(width: 1, height: 0),
                CGSize(width: 0, height: 0),
            ]
            return pattern[(tick + phase) % pattern.count]
        }
    }

    private func companionRoamOffset(layout: TokenmonPopoverFieldLayout) -> CGSize {
        let points = layout.companionWaypoints
        guard points.count > 1 else {
            return .zero
        }

        let raw = Date().timeIntervalSinceReferenceDate / 1.8
        let segment = Int(floor(raw))
        let progress = raw - floor(raw)
        let current = points[segment % points.count]
        let next = points[(segment + 1) % points.count]
        let eased = 0.5 - (cos(progress * .pi) / 2)

        return CGSize(
            width: current.width + ((next.width - current.width) * eased),
            height: current.height + ((next.height - current.height) * eased)
        )
    }

    private func stableCompanionSeed(for cycle: Int) -> Int {
        var hash = 17
        for byte in "\(context.fieldKind.rawValue):\(cycle)".utf8 {
            hash = (hash &* 31 &+ Int(byte)) & 0x7fffffff
        }
        return hash
    }

    private var fieldLayout: TokenmonPopoverFieldLayout {
        switch context.fieldKind {
        case .grassland:
            return TokenmonPopoverFieldLayout(
                background: LinearGradient(
                    colors: [
                        Color(red: 0.18, green: 0.29, blue: 0.19),
                        Color(red: 0.31, green: 0.43, blue: 0.28),
                        Color(red: 0.67, green: 0.82, blue: 0.58).opacity(0.35),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                items: [
                    TokenmonPopoverFieldItem(variant: .grasslandTuft, widthFactor: 0.16, center: CGPoint(x: 0.32, y: 0.78), opacity: 0.78, phase: 0),
                    TokenmonPopoverFieldItem(variant: .grasslandTuft, widthFactor: 0.22, center: CGPoint(x: 0.18, y: 0.74), opacity: 0.94, phase: 1),
                    TokenmonPopoverFieldItem(variant: .grasslandTuft, widthFactor: 0.34, center: CGPoint(x: 0.50, y: 0.68), opacity: 1.0, phase: 2),
                    TokenmonPopoverFieldItem(variant: .grasslandTuft, widthFactor: 0.24, center: CGPoint(x: 0.82, y: 0.74), opacity: 0.94, phase: 4),
                ],
                companionAnchor: CGPoint(x: 0.50, y: 0.54),
                companionWaypoints: [
                    CGSize(width: -42, height: 6),
                    CGSize(width: -20, height: -8),
                    CGSize(width: 4, height: 2),
                    CGSize(width: 30, height: -10),
                    CGSize(width: 48, height: 4),
                    CGSize(width: 16, height: 8),
                    CGSize(width: -18, height: 0),
                ],
                companionScale: 1.0
            )
        case .coast:
            return TokenmonPopoverFieldLayout(
                background: LinearGradient(
                    colors: [
                        Color(red: 0.14, green: 0.24, blue: 0.37),
                        Color(red: 0.21, green: 0.38, blue: 0.57),
                        Color(red: 0.63, green: 0.82, blue: 0.98).opacity(0.26),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                items: [
                    TokenmonPopoverFieldItem(variant: .coastWave, widthFactor: 0.14, center: CGPoint(x: 0.34, y: 0.82), opacity: 0.72, phase: 0),
                    TokenmonPopoverFieldItem(variant: .coastWave, widthFactor: 0.18, center: CGPoint(x: 0.20, y: 0.76), opacity: 0.92, phase: 1),
                    TokenmonPopoverFieldItem(variant: .coastWave, widthFactor: 0.40, center: CGPoint(x: 0.54, y: 0.70), opacity: 1.0, phase: 2),
                    TokenmonPopoverFieldItem(variant: .coastWave, widthFactor: 0.22, center: CGPoint(x: 0.82, y: 0.76), opacity: 0.92, phase: 4),
                ],
                companionAnchor: CGPoint(x: 0.54, y: 0.52),
                companionWaypoints: [
                    CGSize(width: -48, height: 10),
                    CGSize(width: -24, height: -10),
                    CGSize(width: 6, height: -2),
                    CGSize(width: 34, height: -12),
                    CGSize(width: 52, height: 2),
                    CGSize(width: 18, height: 10),
                    CGSize(width: -16, height: 2),
                ],
                companionScale: 1.0
            )
        case .ice:
            return TokenmonPopoverFieldLayout(
                background: LinearGradient(
                    colors: [
                        Color(red: 0.26, green: 0.33, blue: 0.45),
                        Color(red: 0.42, green: 0.56, blue: 0.72),
                        Color(red: 0.86, green: 0.95, blue: 1.0).opacity(0.28),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                items: [
                    TokenmonPopoverFieldItem(variant: .iceSnowflake, widthFactor: 0.11, center: CGPoint(x: 0.18, y: 0.54), opacity: 0.88, phase: 0),
                    TokenmonPopoverFieldItem(variant: .iceSnowflake, widthFactor: 0.15, center: CGPoint(x: 0.50, y: 0.58), opacity: 0.96, phase: 2),
                    TokenmonPopoverFieldItem(variant: .iceSnowflake, widthFactor: 0.13, center: CGPoint(x: 0.80, y: 0.56), opacity: 0.92, phase: 4),
                ],
                companionAnchor: CGPoint(x: 0.50, y: 0.44),
                companionWaypoints: [
                    CGSize(width: -28, height: 6),
                    CGSize(width: -10, height: -8),
                    CGSize(width: 6, height: 0),
                    CGSize(width: 24, height: -10),
                    CGSize(width: 34, height: 2),
                    CGSize(width: 8, height: 8),
                    CGSize(width: -12, height: 2),
                ],
                companionScale: 0.96
            )
        case .sky:
            return TokenmonPopoverFieldLayout(
                background: LinearGradient(
                    colors: [
                        Color(red: 0.71, green: 0.82, blue: 0.97),
                        Color(red: 0.86, green: 0.93, blue: 1.0),
                        Color.white.opacity(0.72),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                items: [
                    TokenmonPopoverFieldItem(variant: .skyCloud, widthFactor: 0.12, center: CGPoint(x: 0.20, y: 0.56), opacity: 0.90, phase: 0),
                    TokenmonPopoverFieldItem(variant: .skyCloud, widthFactor: 0.30, center: CGPoint(x: 0.50, y: 0.40), opacity: 1.0, phase: 2),
                    TokenmonPopoverFieldItem(variant: .skyCloud, widthFactor: 0.18, center: CGPoint(x: 0.80, y: 0.52), opacity: 0.92, phase: 4),
                ],
                companionAnchor: CGPoint(x: 0.52, y: 0.34),
                companionWaypoints: [
                    CGSize(width: -34, height: 6),
                    CGSize(width: -16, height: -10),
                    CGSize(width: 6, height: -18),
                    CGSize(width: 28, height: -8),
                    CGSize(width: 40, height: 2),
                    CGSize(width: 14, height: 8),
                    CGSize(width: -10, height: 0),
                ],
                companionScale: 0.95
            )
        case .unavailable:
            return TokenmonPopoverFieldLayout(
                background: LinearGradient(
                    colors: [
                        Color(nsColor: .controlBackgroundColor),
                        Color(nsColor: .windowBackgroundColor),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                items: [],
                companionAnchor: CGPoint(x: 0.50, y: 0.50),
                companionWaypoints: [.zero],
                companionScale: 0.9
            )
        }
    }
}

private struct TokenmonPopoverFieldLayout {
    let background: LinearGradient
    let items: [TokenmonPopoverFieldItem]
    let companionAnchor: CGPoint
    let companionWaypoints: [CGSize]
    let companionScale: CGFloat
}

private struct TokenmonPopoverFieldItem {
    let variant: TokenmonFieldSpriteVariant
    let widthFactor: CGFloat
    let center: CGPoint
    let opacity: Double
    let phase: Int
}

private struct TokenmonAmbientCompanionPortrait: View {
    let assetKey: String
    let fieldKind: TokenmonSceneFieldKind
    let sceneState: TokenmonSceneState
    let tick: Int
    let sizeMultiplier: CGFloat

    var body: some View {
        Group {
            if isVisible {
                TokenmonHeroCompanionImage(assetKey: assetKey)
                    .frame(width: portraitSize.width, height: portraitSize.height)
            }
        }
        .scaleEffect(
            x: facingScaleX * companionScale,
            y: companionScale * yStretch,
            anchor: .bottom
        )
        .offset(x: xOffset, y: yOffset)
        .opacity(opacity)
        .shadow(color: Color.black.opacity(0.12), radius: 4, y: 2)
        .allowsHitTesting(false)
        .zIndex(2)
    }

    private var isVisible: Bool {
        switch sceneState {
        case .unavailable:
            return false
        default:
            return true
        }
    }

    private var opacity: Double {
        switch sceneState {
        case .spawn:
            return 0.32
        case .resolveEscape:
            return 0.74
        default:
            return 1
        }
    }

    private var facingScaleX: CGFloat {
        switch sceneState {
        case .alert, .resolveEscape:
            return -1
        default:
            return 1
        }
    }

    private var portraitSize: CGSize {
        switch fieldKind {
        case .sky:
            return CGSize(width: 42 * sizeMultiplier, height: 42 * sizeMultiplier)
        case .coast:
            return CGSize(width: 50 * sizeMultiplier, height: 50 * sizeMultiplier)
        case .grassland, .ice:
            return CGSize(width: 46 * sizeMultiplier, height: 46 * sizeMultiplier)
        case .unavailable:
            return CGSize(width: 32 * sizeMultiplier, height: 32 * sizeMultiplier)
        }
    }

    private var companionScale: CGFloat {
        switch sceneState {
        case .resolveSuccess:
            return 1.04
        case .resolveEscape:
            return 0.98
        default:
            return 1
        }
    }

    private var yStretch: CGFloat {
        switch sceneState {
        case .resolveSuccess:
            return [1.0, 1.10, 0.94, 1.02][tick % 4]
        case .resolveEscape:
            return [1.0, 0.92, 0.96, 0.92][tick % 4]
        case .rustle:
            return [1.0, 1.03, 1.0, 1.02][tick % 4]
        default:
            return [1.0, 1.02, 1.0, 1.01][tick % 4]
        }
    }

    private var xOffset: CGFloat {
        switch sceneState {
        case .loading, .exploring, .settle:
            return [-2, -1, 0, 1, 2, 1, 0, -1][tick % 8]
        case .rustle:
            return [-1, 0, 1, 1, 0, -1][tick % 6]
        case .alert:
            return 1
        case .resolveEscape:
            return [-1, -2, -1, 0][tick % 4]
        default:
            return 0
        }
    }

    private var yOffset: CGFloat {
        switch sceneState {
        case .loading, .exploring, .settle:
            return [0, -1, 0, 0][tick % 4]
        case .rustle:
            return [0, -1, -1, 0][tick % 4]
        case .alert:
            return -1
        case .resolveSuccess:
            return [0, -4, -2, 0][tick % 4]
        case .resolveEscape:
            return [1, 2, 1, 0][tick % 4]
        default:
            return 0
        }
    }
}

private struct TokenmonHeroCompanionImage: View {
    let assetKey: String

    var body: some View {
        if let approvedPortrait = TokenmonSpeciesSpriteLoader.approvedPortraitImage(assetKey: assetKey) {
            Image(nsImage: approvedPortrait)
                .resizable()
                .interpolation(.none)
                .scaledToFit()
        } else {
            TokenmonSpeciesSpriteImage(
                assetKey: assetKey,
                variants: [.portrait64, .portrait32],
                revealStage: .revealed
            )
            .scaledToFit()
        }
    }
}

struct TokenmonSettingsPanel: View {
    @ObservedObject var model: TokenmonMenuModel
    @ObservedObject var appUpdater: TokenmonAppUpdater
    let onOpenWelcomeGuide: () -> Void
    @State private var pendingPathSelection: TokenmonSettingsPathSelection?

    var body: some View {
        TokenmonSettingsShell(selection: $model.selectedSettingsPane) {
                TokenmonGeneralSettingsPane(
                    appSettings: model.appSettings,
                    launchAtLoginState: model.launchAtLoginState,
                    notificationAuthorizationState: model.notificationAuthorizationState,
                    appUpdater: appUpdater,
                    settingsMessage: model.settingsMessage,
                    settingsError: model.settingsError,
                    onSetLaunchAtLogin: model.setLaunchAtLogin,
                    onOpenLoginItemsSettings: model.openLoginItemsSettings,
                    onUpdateAppearancePreference: model.updateAppearancePreference,
                    onUpdateLanguagePreference: model.updateLanguagePreference,
                    onUpdateProviderStatusVisibility: model.updateProviderStatusVisibility,
                    onUpdateFieldBackplateEnabled: model.updateFieldBackplateEnabled,
                    onUpdateNotificationsEnabled: model.updateNotificationsEnabled,
                    onRequestNotificationPermission: model.requestCaptureNotificationPermission,
                    onUpdateUsageAnalyticsEnabled: model.updateUsageAnalyticsEnabled,
                    onOpenSystemNotificationSettings: model.openSystemNotificationSettings,
                    onOpenWelcomeGuide: onOpenWelcomeGuide
                )
        } providers: {
            TokenmonProviderSettingsPane(
                onboardingStatuses: model.onboardingStatuses,
                providerHealthSummaries: model.providerHealthSummaries,
                geminiReceiverState: model.geminiReceiverState,
                settingsMessage: model.settingsMessage,
                settingsError: model.settingsError,
                onConnectProvider: model.connectProvider,
                onDetectAgain: model.redetectProviders,
                onChooseExecutable: { provider in
                    pendingPathSelection = .executable(provider)
                },
                onChooseConfiguration: { provider in
                    pendingPathSelection = .configuration(provider)
                },
                onResetToAuto: model.resetProviderOverrides
            )
        }
        .frame(minWidth: 760, minHeight: 560)
        .environment(\.locale, TokenmonL10n.activeLocale)
        .onAppear {
            model.surfaceOpened(.settings, entrypoint: "window_content", emitAnalytics: false)
        }
        .fileImporter(
            isPresented: Binding(
                get: { pendingPathSelection != nil },
                set: { isPresented in
                    if isPresented == false {
                        pendingPathSelection = nil
                    }
                }
            ),
            allowedContentTypes: importerAllowedContentTypes
        ) { result in
            handleImporterResult(result)
        }
    }

    private var importerAllowedContentTypes: [UTType] {
        switch pendingPathSelection {
        case .configuration(_):
            return TokenmonFileImportRequirement.directory.allowedContentTypes
        case .executable(_), .none:
            return TokenmonFileImportRequirement.file.allowedContentTypes
        }
    }

    private func handleImporterResult(_ result: Result<URL, Error>) {
        let selection = pendingPathSelection
        pendingPathSelection = nil
        guard let selection else {
            return
        }

        switch result {
        case .success, .failure:
            switch selection {
            case .executable(let provider):
                let outcome = TokenmonFileImportSupport.resolve(
                    result: result,
                    requirement: .file,
                    invalidSelectionMessage: "Choose an executable file, not a folder."
                )
                applyImportOutcome(outcome) { path in
                    model.setProviderExecutableOverride(path, for: provider)
                }
            case .configuration(let provider):
                let outcome = TokenmonFileImportSupport.resolve(
                    result: result,
                    requirement: .directory,
                    invalidSelectionMessage: "Choose a configuration folder."
                )
                applyImportOutcome(outcome) { path in
                    model.setProviderConfigurationOverride(path, for: provider)
                }
            }
        }
    }

    private func applyImportOutcome(
        _ outcome: TokenmonFileImportOutcome,
        applyPath: (String) -> Void
    ) {
        switch outcome {
        case .imported(let path):
            applyPath(path)
        case .cancelled:
            return
        case .failure(let message):
            model.presentSettingsFeedback(message: nil, error: message)
        }
    }
}

private enum TokenmonSettingsPathSelection: Hashable {
    case executable(ProviderCode)
    case configuration(ProviderCode)
}

struct TokenmonSettingsShell<GeneralContent: View, ProviderContent: View>: View {
    @Binding var selection: TokenmonSettingsPane
    @ViewBuilder let general: () -> GeneralContent
    @ViewBuilder let providers: () -> ProviderContent

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(TokenmonSettingsPane.allCases, id: \.self) { pane in
                    TokenmonSettingsSidebarRow(pane: pane)
                        .tag(pane)
                }
            }
            .listStyle(.sidebar)
            .frame(minWidth: 176, idealWidth: 184)
        } detail: {
            Group {
                switch selection {
                case .general:
                    general()
                case .providers:
                    providers()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .navigationSplitViewStyle(.balanced)
    }
}

private struct TokenmonSettingsSidebarRow: View {
    let pane: TokenmonSettingsPane

    var body: some View {
        Label(pane.title, systemImage: pane.systemImage)
            .font(.headline)
            .padding(.vertical, 4)
    }
}

struct TokenmonGeneralSettingsPane: View {
    let appSettings: AppSettings
    let launchAtLoginState: TokenmonLaunchAtLoginState
    let notificationAuthorizationState: TokenmonNotificationAuthorizationState
    @ObservedObject var appUpdater: TokenmonAppUpdater
    let settingsMessage: String?
    let settingsError: String?
    let onSetLaunchAtLogin: (Bool) -> Void
    let onOpenLoginItemsSettings: () -> Void
    let onUpdateAppearancePreference: (AppAppearancePreference) -> Void
    let onUpdateLanguagePreference: (AppLanguagePreference) -> Void
    let onUpdateProviderStatusVisibility: (Bool) -> Void
    let onUpdateFieldBackplateEnabled: (Bool) -> Void
    let onUpdateNotificationsEnabled: (Bool) -> Void
    let onRequestNotificationPermission: () -> Void
    let onUpdateUsageAnalyticsEnabled: (Bool) -> Void
    let onOpenSystemNotificationSettings: () -> Void
    let onOpenWelcomeGuide: () -> Void
    private let buildInfo = TokenmonBuildInfo.current

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                TokenmonSettingsPaneHeader(
                    title: TokenmonL10n.string("settings.general.header.title"),
                    subtitle: TokenmonL10n.string("settings.general.header.subtitle"),
                    actionTitle: TokenmonL10n.string("settings.general.open_welcome_guide"),
                    action: onOpenWelcomeGuide
                )

                TokenmonSettingsBanner(
                    banner: TokenmonSettingsPresentationBuilder.banner(
                        message: settingsMessage,
                        error: settingsError
                    )
                )

                if shouldShowSetupRecommendations {
                    TokenmonSettingsSectionCard(
                        title: TokenmonL10n.string("settings.general.section.quick_setup"),
                        systemImage: "sparkles"
                    ) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(TokenmonL10n.string("settings.general.quick_setup.note"))
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            TokenmonSetupRecommendationList(
                                items: setupRecommendations,
                                onPerformAction: performSetupRecommendation
                            )
                        }
                    }
                }

                TokenmonSettingsSectionCard(title: TokenmonL10n.string("settings.general.section.startup"), systemImage: "power") {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle(
                            TokenmonL10n.string("settings.general.toggle.launch_at_login"),
                            isOn: Binding(
                                get: { launchAtLoginState.isEnabled },
                                set: { newValue in
                                    onSetLaunchAtLogin(newValue)
                                }
                            )
                        )
                        .disabled(launchAtLoginState.isSupported == false)

                        TokenmonSettingsStatusRow(
                            text: launchAtLoginState.reason,
                            systemImage: launchStatusSymbol,
                            tint: launchStatusTint
                        )

                        Button(TokenmonL10n.string("settings.general.open_login_items_settings")) {
                            onOpenLoginItemsSettings()
                        }
                        .tokenmonAdaptiveButtonStyle()
                        .disabled(launchAtLoginState.isSupported == false)
                    }
                }

                TokenmonSettingsSectionCard(title: TokenmonL10n.string("settings.general.section.appearance"), systemImage: "circle.lefthalf.filled") {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker(
                            TokenmonL10n.string("settings.appearance.picker"),
                            selection: Binding(
                                get: { appSettings.appearancePreference },
                                set: { newValue in
                                    onUpdateAppearancePreference(newValue)
                                }
                            )
                        ) {
                            ForEach(AppAppearancePreference.allCases, id: \.self) { option in
                                Text(option.displayName).tag(option)
                            }
                        }

                        Text(TokenmonL10n.string("settings.appearance.note"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                TokenmonSettingsSectionCard(title: TokenmonL10n.string("settings.general.section.menu_bar"), systemImage: "menubar.rectangle") {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker(
                            TokenmonL10n.string("settings.language.picker"),
                            selection: Binding(
                                get: { appSettings.languagePreference },
                                set: { newValue in
                                    onUpdateLanguagePreference(newValue)
                                }
                            )
                        ) {
                            ForEach(AppLanguagePreference.allCases, id: \.self) { option in
                                Text(option.displayName).tag(option)
                            }
                        }

                        Toggle(
                            TokenmonL10n.string("settings.general.toggle.show_provider_status"),
                            isOn: Binding(
                                get: { appSettings.providerStatusVisibility },
                                set: { newValue in
                                    onUpdateProviderStatusVisibility(newValue)
                                }
                            )
                        )

                        Toggle(
                            TokenmonL10n.string("settings.general.toggle.field_backplate"),
                            isOn: Binding(
                                get: { appSettings.fieldBackplateEnabled },
                                set: { newValue in
                                    onUpdateFieldBackplateEnabled(newValue)
                                }
                            )
                        )

                        Text(TokenmonL10n.string("settings.general.menu_bar.note"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(TokenmonL10n.string("settings.language.note"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                TokenmonSettingsSectionCard(title: TokenmonL10n.string("settings.general.section.notifications"), systemImage: "bell.badge") {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle(
                            TokenmonL10n.string("settings.general.toggle.notify_on_capture"),
                            isOn: Binding(
                                get: { appSettings.notificationsEnabled },
                                set: { newValue in
                                    onUpdateNotificationsEnabled(newValue)
                                }
                            )
                        )

                        Button(TokenmonL10n.string("settings.general.open_notification_settings")) {
                            onOpenSystemNotificationSettings()
                        }
                        .tokenmonAdaptiveButtonStyle()

                        TokenmonSettingsStatusRow(
                            text: notificationAuthorizationDetail,
                            systemImage: notificationAuthorizationSymbol,
                            tint: notificationAuthorizationTint
                        )

                        Text(TokenmonL10n.string("settings.general.notifications.note"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                TokenmonSettingsSectionCard(title: TokenmonL10n.string("settings.general.section.analytics"), systemImage: "chart.bar") {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle(
                            TokenmonL10n.string("settings.general.toggle.usage_analytics"),
                            isOn: Binding(
                                get: { appSettings.usageAnalyticsEnabled },
                                set: { newValue in
                                    onUpdateUsageAnalyticsEnabled(newValue)
                                }
                            )
                        )

                        Text(TokenmonL10n.string("settings.general.analytics.note"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                TokenmonSettingsSectionCard(title: TokenmonL10n.string("settings.general.section.updates"), systemImage: "arrow.down.circle") {
                    TokenmonAppUpdateSettingsView(appUpdater: appUpdater)
                }

                TokenmonSettingsSectionCard(title: TokenmonL10n.string("settings.general.section.about"), systemImage: "info.circle") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(TokenmonL10n.string("settings.general.about.local_build"))
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            TokenmonBuildVersionBadge()
                        }

                        Divider()

                        TokenmonSettingsValueRow(label: TokenmonL10n.string("common.version"), value: buildInfo.versionSummary)
                        TokenmonSettingsValueRow(label: TokenmonL10n.string("common.revision"), value: buildInfo.revisionSummary)
                        TokenmonSettingsValueRow(
                            label: TokenmonL10n.string("common.built"),
                            value: buildInfo.buildTimestampSummary ?? TokenmonL10n.string("common.unavailable")
                        )

                        Divider()

                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(TokenmonBrandLink.allCases) { link in
                                TokenmonSettingsLinkRow(
                                    label: TokenmonL10n.string(link.titleKey),
                                    value: link.displayValue,
                                    destination: link.destination
                                )
                            }
                        }

                        Text(TokenmonL10n.string("settings.general.about.note"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var launchStatusSymbol: String {
        TokenmonSetupRecommendationsBuilder.launchStatusSymbol(launchAtLoginState)
    }

    private var launchStatusTint: Color {
        TokenmonSetupRecommendationsBuilder.launchStatusTint(launchAtLoginState).color
    }

    private var shouldShowSetupRecommendations: Bool {
        setupRecommendations.isEmpty == false
    }

    private var notificationAuthorizationDetail: String {
        TokenmonSetupRecommendationsBuilder.notificationAuthorizationDetail(notificationAuthorizationState)
    }

    private var notificationAuthorizationSymbol: String {
        TokenmonSetupRecommendationsBuilder.notificationAuthorizationSymbol(notificationAuthorizationState)
    }

    private var notificationAuthorizationTint: Color {
        TokenmonSetupRecommendationsBuilder.notificationAuthorizationTint(notificationAuthorizationState).color
    }

    private var setupRecommendations: [TokenmonSetupRecommendationItem] {
        TokenmonSetupRecommendationsBuilder.items(
            appSettings: appSettings,
            launchAtLoginState: launchAtLoginState,
            notificationAuthorizationState: notificationAuthorizationState
        )
    }

    private func performSetupRecommendation(_ action: TokenmonSetupRecommendationAction) {
        switch action {
        case .enableLaunchAtLogin:
            onSetLaunchAtLogin(true)
        case .openLoginItemsSettings:
            onOpenLoginItemsSettings()
        case .enableCaptureNotifications:
            onUpdateNotificationsEnabled(true)
        case .requestCaptureNotificationPermission:
            onRequestNotificationPermission()
        case .openNotificationSettings:
            onOpenSystemNotificationSettings()
        }
    }
}

private struct TokenmonAppUpdateSettingsView: View {
    @ObservedObject var appUpdater: TokenmonAppUpdater
    @State private var automaticallyChecksForUpdates: Bool
    @State private var automaticallyDownloadsUpdates: Bool

    init(appUpdater: TokenmonAppUpdater) {
        self.appUpdater = appUpdater
        _automaticallyChecksForUpdates = State(initialValue: appUpdater.automaticallyChecksForUpdates)
        _automaticallyDownloadsUpdates = State(initialValue: appUpdater.automaticallyDownloadsUpdates)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if appUpdater.isAvailable {
                Button(TokenmonL10n.string("settings.updates.action.check_now")) {
                    appUpdater.checkForUpdates()
                }
                .tokenmonAdaptiveButtonStyle()
                .disabled(appUpdater.canCheckForUpdates == false)

                Toggle(
                    TokenmonL10n.string("settings.updates.toggle.automatically_check"),
                    isOn: $automaticallyChecksForUpdates
                )
                .onChange(of: automaticallyChecksForUpdates) { _, newValue in
                    appUpdater.setAutomaticallyChecksForUpdates(newValue)
                    if newValue == false {
                        automaticallyDownloadsUpdates = false
                    }
                }

                Toggle(
                    TokenmonL10n.string("settings.updates.toggle.automatically_download"),
                    isOn: $automaticallyDownloadsUpdates
                )
                .disabled(automaticallyChecksForUpdates == false)
                .onChange(of: automaticallyDownloadsUpdates) { _, newValue in
                    appUpdater.setAutomaticallyDownloadsUpdates(newValue)
                }
            } else if let reasonKey = appUpdater.unavailabilityReasonKey {
                TokenmonSettingsStatusRow(
                    text: TokenmonL10n.string(reasonKey),
                    systemImage: "info.circle.fill",
                    tint: .secondary
                )
            }

            if let configuredFeedURL = appUpdater.configuredFeedURL {
                TokenmonSettingsStatusRow(
                    text: TokenmonL10n.format("settings.updates.feed", configuredFeedURL.absoluteString),
                    systemImage: appUpdater.isAvailable ? "checkmark.circle.fill" : "info.circle.fill",
                    tint: appUpdater.isAvailable ? .green : .secondary
                )
            }

            if let feedURLSource = appUpdater.feedURLSource {
                TokenmonSettingsStatusRow(
                    text: TokenmonL10n.format(
                        "settings.updates.feed_source",
                        TokenmonL10n.string(feedURLSource.localizationKey)
                    ),
                    systemImage: "point.topleft.down.curvedto.point.bottomright.up.fill",
                    tint: feedURLSource == .bundleMetadata ? .secondary : .orange
                )
            }

            if let publicEDKeySource = appUpdater.publicEDKeySource {
                TokenmonSettingsStatusRow(
                    text: TokenmonL10n.format(
                        "settings.updates.public_key_source",
                        TokenmonL10n.string(publicEDKeySource.localizationKey)
                    ),
                    systemImage: "key.fill",
                    tint: publicEDKeySource == .bundleMetadata ? .secondary : .orange
                )
            }

            if appUpdater.hasNonBundledConfiguration {
                TokenmonSettingsStatusRow(
                    text: TokenmonL10n.string("settings.updates.override_active"),
                    systemImage: "exclamationmark.triangle.fill",
                    tint: .orange
                )
            }

            if appUpdater.overrideFileExists || appUpdater.overrideLoadErrorDescription != nil {
                TokenmonSettingsStatusRow(
                    text: TokenmonL10n.format("settings.updates.override_file", appUpdater.overrideFilePath),
                    systemImage: "doc.text.fill",
                    tint: .secondary
                )
            }

            Text(
                appUpdater.isAvailable
                    ? TokenmonL10n.string("settings.updates.note")
                    : TokenmonL10n.string("settings.updates.unavailable.note")
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .onAppear(perform: refreshFromUpdater)
    }

    private func refreshFromUpdater() {
        automaticallyChecksForUpdates = appUpdater.automaticallyChecksForUpdates
        automaticallyDownloadsUpdates = appUpdater.automaticallyDownloadsUpdates
    }
}

struct TokenmonProviderSettingsPane: View {
    let onboardingStatuses: [TokenmonProviderOnboardingStatus]
    let providerHealthSummaries: [ProviderHealthSummary]
    let geminiReceiverState: GeminiOtelReceiverSupervisor.State
    let settingsMessage: String?
    let settingsError: String?
    let onConnectProvider: (ProviderCode) -> Void
    let onDetectAgain: () -> Void
    let onChooseExecutable: (ProviderCode) -> Void
    let onChooseConfiguration: (ProviderCode) -> Void
    let onResetToAuto: (ProviderCode) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                TokenmonSettingsPaneHeader(
                    title: TokenmonL10n.string("settings.providers.header.title"),
                    subtitle: TokenmonL10n.string("settings.providers.header.subtitle"),
                    actionTitle: TokenmonL10n.string("settings.providers.action.detect_again"),
                    action: onDetectAgain
                )

                TokenmonSettingsBanner(
                    banner: TokenmonSettingsPresentationBuilder.banner(
                        message: settingsMessage,
                        error: settingsError
                    )
                )

                TokenmonProviderOverviewRow(
                    summary: TokenmonSettingsPresentationBuilder.providerOverviewSummary(
                        onboardingStatuses: onboardingStatuses
                    )
                )

                ForEach(onboardingStatuses, id: \.provider) { status in
                    TokenmonProviderSettingsCard(
                        status: status,
                        healthSummary: providerHealthSummaries.first(where: { $0.provider == status.provider }),
                        geminiReceiverState: status.provider == .gemini ? geminiReceiverState : nil,
                        onConnectProvider: onConnectProvider,
                        onChooseExecutable: onChooseExecutable,
                        onChooseConfiguration: onChooseConfiguration,
                        onResetToAuto: onResetToAuto
                    )
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

struct TokenmonSettingsBannerModel: Equatable {
    enum Kind: Equatable {
        case success
        case error
    }

    let title: String
    let message: String
    let kind: Kind
}

struct TokenmonProviderOverviewSummary: Equatable {
    let providerCount: Int
    let connectedCount: Int
    let needsAttentionCount: Int
}

enum TokenmonProviderCardState: Equatable {
    case connected
    case repair
    case needsSetup
    case notFound
}

enum TokenmonSettingsPresentationBuilder {
    static func banner(message: String?, error: String?) -> TokenmonSettingsBannerModel? {
        if let error, error.isEmpty == false {
            return TokenmonSettingsBannerModel(
                title: TokenmonL10n.string("settings.banner.error"),
                message: error,
                kind: .error
            )
        }

        guard let message, message.isEmpty == false else {
            return nil
        }

        return TokenmonSettingsBannerModel(
            title: TokenmonL10n.string("settings.banner.updated"),
            message: message,
            kind: .success
        )
    }

    static func providerOverviewSummary(
        onboardingStatuses: [TokenmonProviderOnboardingStatus]
    ) -> TokenmonProviderOverviewSummary {
        TokenmonProviderOverviewSummary(
            providerCount: onboardingStatuses.count,
            connectedCount: onboardingStatuses.filter(\.isConnected).count,
            needsAttentionCount: onboardingStatuses.filter { $0.isConnected == false }.count
        )
    }

    static func providerCardState(for status: TokenmonProviderOnboardingStatus) -> TokenmonProviderCardState {
        if status.isConnected {
            return .connected
        }
        if status.isPartial {
            return .repair
        }
        return status.cliInstalled ? .needsSetup : .notFound
    }

    static func providerMetadataLine(
        status: TokenmonProviderOnboardingStatus,
        healthSummary: ProviderHealthSummary?
    ) -> String {
        var pieces: [String] = []
        let supportLevel = healthSummary?.supportLevel ?? status.provider.defaultSupportLevel
        pieces.append(TokenmonL10n.format("settings.providers.metadata.support", formattedSupportLevel(supportLevel)))

        if let sourceMode = healthSummary?.sourceMode {
            pieces.append(TokenmonL10n.format("settings.providers.metadata.mode", formattedSourceMode(sourceMode)))
        } else if status.provider == .codex, let codexMode = status.codexMode {
            pieces.append(TokenmonL10n.format("settings.providers.metadata.mode", formattedCodexMode(codexMode)))
        }

        if status.provider == .codex {
            pieces.append(TokenmonL10n.string("settings.providers.metadata.local_follow"))
        }

        return pieces.joined(separator: " · ")
    }

    private static func formattedSupportLevel(_ rawValue: String) -> String {
        switch rawValue {
        case "first_class":
            return TokenmonL10n.string("settings.providers.support.first_class")
        case "best_effort":
            return TokenmonL10n.string("settings.providers.support.best_effort")
        default:
            return rawValue
                .replacingOccurrences(of: "_", with: " ")
                .capitalized
        }
    }

    private static func formattedCodexMode(_ mode: CodexConnectionMode) -> String {
        switch mode {
        case .auto:
            return TokenmonL10n.string("settings.providers.codex_mode.auto")
        case .accurate:
            return TokenmonL10n.string("settings.providers.codex_mode.accurate")
        }
    }

    private static func formattedSourceMode(_ rawValue: String) -> String {
        switch rawValue {
        case "claude_statusline_live":
            return TokenmonL10n.string("settings.providers.source_mode.claude_statusline_live")
        case "claude_transcript_backfill":
            return TokenmonL10n.string("settings.providers.source_mode.transcript_backfill")
        case "codex_exec_json":
            return TokenmonL10n.string("settings.providers.source_mode.codex_exec_json")
        case "codex_session_store_recovery":
            return TokenmonL10n.string("settings.providers.source_mode.codex_session_store_recovery")
        case "codex_session_store_live":
            return TokenmonL10n.string("settings.providers.source_mode.codex_session_store_live")
        case "codex_interactive_observer":
            return TokenmonL10n.string("settings.providers.source_mode.codex_interactive_observer")
        case "codex_transcript_backfill":
            return TokenmonL10n.string("settings.providers.source_mode.transcript_backfill")
        default:
            return rawValue
                .replacingOccurrences(of: "_", with: " ")
                .capitalized
        }
    }
}

struct TokenmonSettingsPaneHeader: View {
    let title: String
    let subtitle: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.largeTitle.weight(.semibold))
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .tokenmonAdaptiveButtonStyle()
                    .controlSize(.regular)
            }
        }
    }
}

struct TokenmonSettingsBanner: View {
    let banner: TokenmonSettingsBannerModel?

    var body: some View {
        if let banner {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: banner.kind == .error ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(banner.kind == .error ? .red : .green)

                VStack(alignment: .leading, spacing: 2) {
                    Text(banner.title)
                        .font(.subheadline.weight(.semibold))
                    Text(banner.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .tokenmonAdaptiveSurface(
                cornerRadius: 16,
                strokeColor: (banner.kind == .error ? Color.red : Color.green).opacity(0.22)
            )
        }
    }
}

struct TokenmonSettingsFeedbackSection: View {
    let settingsMessage: String?
    let settingsError: String?

    var body: some View {
        TokenmonSettingsBanner(
            banner: TokenmonSettingsPresentationBuilder.banner(
                message: settingsMessage,
                error: settingsError
            )
        )
    }
}

struct TokenmonSettingsSectionCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .tokenmonAdaptiveSurface(
            cornerRadius: 18,
            strokeColor: Color.secondary.opacity(0.10)
        )
    }
}

private struct TokenmonSettingsStatusRow: View {
    let text: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label {
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
        }
    }
}

private struct TokenmonSettingsValueRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .font(.subheadline)
    }
}

private struct TokenmonSettingsLinkRow: View {
    let label: String
    let value: String
    let destination: URL

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Link(destination: destination) {
                HStack(spacing: 6) {
                    Text(value)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Image(systemName: "arrow.up.forward.square")
                        .font(.caption.weight(.semibold))
                }
            }
            .buttonStyle(.plain)
        }
        .font(.subheadline)
    }
}

struct TokenmonProviderOverviewRow: View {
    let summary: TokenmonProviderOverviewSummary

    var body: some View {
        TokenmonSettingsSectionCard(title: TokenmonL10n.string("settings.providers.section.overview"), systemImage: "switch.2") {
            HStack(spacing: 12) {
                TokenmonProviderOverviewMetric(
                    title: TokenmonL10n.string("settings.providers.overview.providers"),
                    value: "\(summary.providerCount)"
                )
                TokenmonProviderOverviewMetric(
                    title: TokenmonL10n.string("settings.providers.overview.connected"),
                    value: "\(summary.connectedCount)"
                )
                TokenmonProviderOverviewMetric(
                    title: TokenmonL10n.string("settings.providers.overview.needs_attention"),
                    value: "\(summary.needsAttentionCount)"
                )
            }

            Text(TokenmonL10n.string("settings.providers.overview.codex_note"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct TokenmonProviderOverviewMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title3.weight(.semibold))
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TokenmonProviderSettingsCard: View {
    let status: TokenmonProviderOnboardingStatus
    let healthSummary: ProviderHealthSummary?
    let geminiReceiverState: GeminiOtelReceiverSupervisor.State?
    let onConnectProvider: (ProviderCode) -> Void
    let onChooseExecutable: (ProviderCode) -> Void
    let onChooseConfiguration: (ProviderCode) -> Void
    let onResetToAuto: (ProviderCode) -> Void

    @State private var troubleshootingExpanded = false

    var body: some View {
        TokenmonSettingsSectionCard(
            title: status.provider.displayName,
            systemImage: providerSystemImage
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(status.title)
                            .font(.title3.weight(.semibold))
                        Text(status.detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    TokenmonProviderStatusBadge(state: cardState)
                }

                Text(
                    TokenmonSettingsPresentationBuilder.providerMetadataLine(
                        status: status,
                        healthSummary: healthSummary
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                if let lastError = healthSummary?.lastErrorSummary,
                   cardState != .connected
                {
                    TokenmonSettingsStatusRow(
                        text: lastError,
                        systemImage: "wrench.and.screwdriver.fill",
                        tint: .orange
                    )
                }

                primaryActionButton

                if let receiverState = geminiReceiverState {
                    geminiReceiverStateLabel(receiverState)
                }

                DisclosureGroup(TokenmonL10n.string("settings.providers.troubleshooting"), isExpanded: $troubleshootingExpanded) {
                    VStack(alignment: .leading, spacing: 10) {
                        pathRow(
                            title: TokenmonL10n.string("settings.providers.path.executable"),
                            path: status.executablePath,
                            source: status.executableSource.title,
                            isMissing: status.cliInstalled == false
                        )
                        pathRow(
                            title: TokenmonL10n.string("settings.providers.path.config"),
                            path: status.configurationPath,
                            source: status.configurationSource.title,
                            isMissing: false
                        )

                        HStack(spacing: 10) {
                            Button(TokenmonL10n.string("settings.providers.action.change_executable")) {
                                onChooseExecutable(status.provider)
                            }
                            .tokenmonAdaptiveButtonStyle()

                            Button(TokenmonL10n.string("settings.providers.action.change_config")) {
                                onChooseConfiguration(status.provider)
                            }
                            .tokenmonAdaptiveButtonStyle()
                        }
                        .controlSize(.small)

                        if status.usesCustomExecutablePath || status.usesCustomConfigurationPath {
                            Button(TokenmonL10n.string("settings.providers.action.reset_auto")) {
                                onResetToAuto(status.provider)
                            }
                            .tokenmonAdaptiveButtonStyle()
                            .controlSize(.small)
                        }

                        Text(TokenmonL10n.string("settings.providers.custom_paths.note"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)
                }
            }
        }
    }

    private var providerSystemImage: String {
        switch status.provider {
        case .claude:
            return "bubble.left.and.bubble.right"
        case .codex:
            return "terminal"
        case .gemini:
            return "antenna.radiowaves.left.and.right"
        }
    }

    private var cardState: TokenmonProviderCardState {
        TokenmonSettingsPresentationBuilder.providerCardState(for: status)
    }

    @ViewBuilder
    private var primaryActionButton: some View {
        if let actionTitle = status.actionTitle {
            Button(actionTitle) {
                onConnectProvider(status.provider)
            }
            .tokenmonAdaptiveButtonStyle(.prominent)
            .controlSize(.small)
        } else if status.cliInstalled == false {
            Button(TokenmonL10n.string("settings.providers.action.choose_path")) {
                onChooseExecutable(status.provider)
            }
            .tokenmonAdaptiveButtonStyle()
            .controlSize(.small)
        }
    }

    @ViewBuilder
    private func pathRow(
        title: String,
        path: String?,
        source: String,
        isMissing: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(TokenmonL10n.format("settings.providers.path.source", title, source))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(path ?? TokenmonL10n.string("settings.providers.path.not_detected"))
                .font(.caption.monospaced())
                .foregroundStyle(isMissing ? .secondary : .primary)
                .textSelection(.enabled)
        }
    }

    private func geminiReceiverStateLabel(_ state: GeminiOtelReceiverSupervisor.State) -> some View {
        let (text, color): (String, Color) = {
            switch state {
            case .stopped:
                return (TokenmonL10n.string("settings.providers.gemini_receiver.stopped"), .secondary)
            case .starting:
                return (TokenmonL10n.string("settings.providers.gemini_receiver.starting"), .secondary)
            case .running(let host, let port):
                return (TokenmonL10n.format("settings.providers.gemini_receiver.running", host, port), .green)
            case .failed(let message):
                return (TokenmonL10n.format("settings.providers.gemini_receiver.failed", message), .red)
            }
        }()
        return Text(text)
            .font(.caption2)
            .foregroundStyle(color)
    }
}

private struct TokenmonProviderStatusBadge: View {
    let state: TokenmonProviderCardState

    var body: some View {
        Label(state.title, systemImage: state.systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(state.tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(state.tint.opacity(state == .notFound ? 0.10 : 0.16))
            )
    }
}

private extension TokenmonProviderCardState {
    var title: String {
        switch self {
        case .connected:
            return TokenmonL10n.string("provider.card_state.connected")
        case .repair:
            return TokenmonL10n.string("provider.card_state.repair")
        case .needsSetup:
            return TokenmonL10n.string("provider.card_state.needs_setup")
        case .notFound:
            return TokenmonL10n.string("provider.card_state.not_found")
        }
    }

    var systemImage: String {
        switch self {
        case .connected:
            return "checkmark.circle.fill"
        case .repair:
            return "wrench.and.screwdriver.fill"
        case .needsSetup:
            return "exclamationmark.circle.fill"
        case .notFound:
            return "magnifyingglass"
        }
    }

    var tint: Color {
        switch self {
        case .connected:
            return .green
        case .repair:
            return .orange
        case .needsSetup:
            return .accentColor
        case .notFound:
            return .secondary
        }
    }
}

struct TokenmonCompactSection<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .tokenmonAdaptiveSurface(cornerRadius: 12)
    }
}


enum TokenmonDexSidebarSelection: String, CaseIterable, Hashable {
    case all
    case captured
    case seenUncaptured
    case unknown
    case party

    var title: String {
        switch self {
        case .all:
            return TokenmonL10n.string("dex.sidebar.all.title")
        case .captured:
            return TokenmonL10n.string("dex.sidebar.captured.title")
        case .seenUncaptured:
            return TokenmonL10n.string("dex.sidebar.seen.title")
        case .unknown:
            return TokenmonL10n.string("dex.sidebar.hidden.title")
        case .party:
            return TokenmonL10n.string("dex.sidebar.party.title")
        }
    }

    var subtitle: String {
        switch self {
        case .all:
            return TokenmonL10n.string("dex.sidebar.all.subtitle")
        case .captured:
            return TokenmonL10n.string("dex.sidebar.captured.subtitle")
        case .seenUncaptured:
            return TokenmonL10n.string("dex.sidebar.seen.subtitle")
        case .unknown:
            return TokenmonL10n.string("dex.sidebar.hidden.subtitle")
        case .party:
            return TokenmonL10n.string("dex.sidebar.party.subtitle")
        }
    }

    var systemImage: String {
        switch self {
        case .all:
            return "square.grid.2x2.fill"
        case .captured:
            return "checkmark.seal.fill"
        case .seenUncaptured:
            return "eye.fill"
        case .unknown:
            return "lock.fill"
        case .party:
            return "bag.fill"
        }
    }

    var emptyTitle: String {
        switch self {
        case .all:
            return TokenmonL10n.string("dex.sidebar.all.empty_title")
        case .captured:
            return TokenmonL10n.string("dex.sidebar.captured.empty_title")
        case .seenUncaptured:
            return TokenmonL10n.string("dex.sidebar.seen.empty_title")
        case .unknown:
            return TokenmonL10n.string("dex.sidebar.hidden.empty_title")
        case .party:
            return TokenmonL10n.string("dex.sidebar.party.empty_title")
        }
    }

    var emptyDescription: String {
        switch self {
        case .all:
            return TokenmonL10n.string("dex.sidebar.all.empty_description")
        case .captured:
            return TokenmonL10n.string("dex.sidebar.captured.empty_description")
        case .seenUncaptured:
            return TokenmonL10n.string("dex.sidebar.seen.empty_description")
        case .unknown:
            return TokenmonL10n.string("dex.sidebar.hidden.empty_description")
        case .party:
            return TokenmonL10n.string("dex.sidebar.party.empty_description")
        }
    }

    func matches(_ entry: DexEntrySummary) -> Bool {
        switch self {
        case .all, .party:
            return true
        default:
            return entry.status.sidebarSelection == self
        }
    }

    static func preferredSelection(for entries: [DexEntrySummary]) -> TokenmonDexSidebarSelection {
        entries.isEmpty ? .unknown : .all
    }
}

enum TokenmonDexFieldFilter: String, CaseIterable, Hashable {
    case all
    case grassland
    case ice
    case coast
    case sky

    var title: String {
        switch self {
        case .all: return TokenmonL10n.string("dex.filter.field.all")
        case .grassland: return FieldType.grassland.displayName
        case .ice: return FieldType.ice.displayName
        case .coast: return FieldType.coast.displayName
        case .sky: return FieldType.sky.displayName
        }
    }

    var field: FieldType? {
        switch self {
        case .all: return nil
        case .grassland: return .grassland
        case .ice: return .ice
        case .coast: return .coast
        case .sky: return .sky
        }
    }
}

enum TokenmonDexRarityFilter: String, CaseIterable, Hashable {
    case all
    case common
    case uncommon
    case rare
    case epic
    case legendary

    var title: String {
        switch self {
        case .all: return TokenmonL10n.string("dex.filter.rarity.all")
        case .common: return RarityTier.common.displayName
        case .uncommon: return RarityTier.uncommon.displayName
        case .rare: return RarityTier.rare.displayName
        case .epic: return RarityTier.epic.displayName
        case .legendary: return RarityTier.legendary.displayName
        }
    }

    var rarity: RarityTier? {
        switch self {
        case .all: return nil
        case .common: return .common
        case .uncommon: return .uncommon
        case .rare: return .rare
        case .epic: return .epic
        case .legendary: return .legendary
        }
    }
}

enum TokenmonDexSortMode: String, CaseIterable, Hashable {
    case number
    case rarity
    case field
    case name
    case status
    case lastSeen
    case capturedCount

    var title: String {
        switch self {
        case .number: return TokenmonL10n.string("dex.sort.number")
        case .rarity: return TokenmonL10n.string("dex.sort.rarity")
        case .field: return TokenmonL10n.string("dex.sort.field")
        case .name: return TokenmonL10n.string("dex.sort.name")
        case .status: return TokenmonL10n.string("dex.sort.status")
        case .lastSeen: return TokenmonL10n.string("dex.sort.last_seen")
        case .capturedCount: return TokenmonL10n.string("dex.sort.captured_count")
        }
    }
}

enum TokenmonDexPresentationMode: String, CaseIterable, Hashable {
    case grid
    case list
}

enum TokenmonDexBrowser {
    static func filteredEntries(
        entries: [DexEntrySummary],
        statusSelection: TokenmonDexSidebarSelection,
        fieldFilter: TokenmonDexFieldFilter,
        rarityFilter: TokenmonDexRarityFilter,
        searchQuery: String,
        sortMode: TokenmonDexSortMode
    ) -> [DexEntrySummary] {
        let trimmedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)

        return entries
            .filter { statusSelection.matches($0) }
            .filter { entry in
                guard let field = fieldFilter.field else { return true }
                return entry.field == field
            }
            .filter { entry in
                guard let rarity = rarityFilter.rarity else { return true }
                return entry.rarity == rarity
            }
            .filter { entry in
                guard trimmedQuery.isEmpty == false else { return true }
                return searchIndex(for: entry).localizedCaseInsensitiveContains(trimmedQuery)
            }
            .sorted { lhs, rhs in
                switch sortMode {
                case .number:
                    return lhs.sortOrder < rhs.sortOrder
                case .rarity:
                    let left = rarityRank(lhs.rarity)
                    let right = rarityRank(rhs.rarity)
                    return left == right ? lhs.sortOrder < rhs.sortOrder : left > right
                case .field:
                    let left = fieldRank(lhs.field)
                    let right = fieldRank(rhs.field)
                    return left == right ? lhs.sortOrder < rhs.sortOrder : left < right
                case .name:
                    let leftUnlocked = TokenmonDexPresentation.isNameUnlocked(capturedCount: lhs.capturedCount)
                    let rightUnlocked = TokenmonDexPresentation.isNameUnlocked(capturedCount: rhs.capturedCount)
                    if leftUnlocked != rightUnlocked {
                        return leftUnlocked && rightUnlocked == false
                    }
                    if leftUnlocked {
                        return lhs.speciesName.localizedCompare(rhs.speciesName) == .orderedAscending
                    }
                    return lhs.sortOrder < rhs.sortOrder
                case .status:
                    let left = statusRank(lhs.status)
                    let right = statusRank(rhs.status)
                    return left == right ? lhs.sortOrder < rhs.sortOrder : left < right
                case .lastSeen:
                    let left = lhs.lastSeenAt ?? ""
                    let right = rhs.lastSeenAt ?? ""
                    return left == right ? lhs.sortOrder < rhs.sortOrder : left > right
                case .capturedCount:
                    return lhs.capturedCount == rhs.capturedCount ? lhs.sortOrder < rhs.sortOrder : lhs.capturedCount > rhs.capturedCount
                }
            }
    }

    private static func searchIndex(for entry: DexEntrySummary) -> String {
        [
            entry.speciesID,
            "#\(entry.sortOrder)",
            String(format: "%03d", entry.sortOrder),
            TokenmonDexPresentation.isNameUnlocked(capturedCount: entry.capturedCount) ? entry.speciesName : "",
            entry.field.rawValue,
            entry.field.displayName,
            entry.rarity.rawValue,
            entry.rarity.displayName,
            entry.status.rawValue,
            entry.status.detailTitle,
        ]
        .joined(separator: " ")
    }

    private static func rarityRank(_ rarity: RarityTier) -> Int {
        switch rarity {
        case .legendary: return 5
        case .epic: return 4
        case .rare: return 3
        case .uncommon: return 2
        case .common: return 1
        }
    }

    private static func fieldRank(_ field: FieldType) -> Int {
        switch field {
        case .grassland: return 0
        case .ice: return 1
        case .coast: return 2
        case .sky: return 3
        }
    }

    private static func statusRank(_ status: DexEntryStatus) -> Int {
        switch status {
        case .captured: return 0
        case .seenUncaptured: return 1
        case .unknown: return 2
        }
    }
}

extension DexEntryStatus {
    var sidebarSelection: TokenmonDexSidebarSelection {
        switch self {
        case .captured:
            return .captured
        case .seenUncaptured:
            return .seenUncaptured
        case .unknown:
            return .unknown
        }
    }
}

struct TokenmonDexPanel: View {
    @ObservedObject var model: TokenmonMenuModel
    @State private var sidebarSelection: TokenmonDexSidebarSelection = .all
    @State private var fieldFilter: TokenmonDexFieldFilter = .all
    @State private var rarityFilter: TokenmonDexRarityFilter = .all
    @State private var sortMode: TokenmonDexSortMode = .number
    @State private var presentationMode: TokenmonDexPresentationMode = .grid
    @State private var searchQuery = ""
    @State private var selectedSpeciesID: String?
    @StateObject private var cardTuning = TokenmonDexCardTuningStore()

    private var filteredEntries: [DexEntrySummary] {
        if sidebarSelection == .party {
            let byID = Dictionary(uniqueKeysWithValues: model.dexEntries.map { ($0.speciesID, $0) })
            return model.partyMembers.compactMap { byID[$0.speciesID] }
        }
        return TokenmonDexBrowser.filteredEntries(
            entries: model.dexEntries,
            statusSelection: sidebarSelection,
            fieldFilter: fieldFilter,
            rarityFilter: rarityFilter,
            searchQuery: searchQuery,
            sortMode: sortMode
        )
    }

    private var browserProgress: TokenmonDexCollectionProgress {
        TokenmonDexPresentation.progress(for: model.dexEntries)
    }

    private var filterSummary: String {
        var components = ["\(filteredEntries.count) shown"]
        if fieldFilter != .all {
            components.append(fieldFilter.title)
        }
        if rarityFilter != .all {
            components.append(rarityFilter.title)
        }
        if sortMode != .number {
            components.append("Sorted by \(sortMode.title)")
        }
        return components.joined(separator: " • ")
    }

    private var selectedEntry: DexEntrySummary? {
        guard let selectedSpeciesID else {
            return filteredEntries.first
        }
        return filteredEntries.first(where: { $0.speciesID == selectedSpeciesID }) ?? filteredEntries.first
    }

    var body: some View {
        NavigationSplitView {
            TokenmonDexSidebarList(
                selection: $sidebarSelection,
                dexEntries: model.dexEntries,
                partyMembers: model.partyMembers
            )
        } content: {
            TokenmonDexBrowserPane(
                model: model,
                title: sidebarSelection.title,
                subtitle: sidebarSelection.subtitle,
                filterSummary: filterSummary,
                emptyTitle: sidebarSelection.emptyTitle,
                emptyDescription: sidebarSelection.emptyDescription,
                allEntries: model.dexEntries,
                entries: filteredEntries,
                progress: browserProgress,
                sidebarSelection: sidebarSelection,
                presentationMode: $presentationMode,
                selectedSpeciesID: $selectedSpeciesID,
                fieldFilter: $fieldFilter,
                rarityFilter: $rarityFilter,
                sortMode: $sortMode,
                onRefresh: { model.refresh(reason: .manual) }
            )
        } detail: {
            TokenmonDexDetailPane(entry: selectedEntry)
                .navigationSplitViewColumnWidth(ideal: tokenmonDexSupportingWidth + 24, max: tokenmonDexSupportingWidth + 24)
        }
        .navigationSplitViewStyle(.balanced)
        .environmentObject(cardTuning)
        .overlay(alignment: .bottomLeading) {
            if TokenmonDexCardTuningGate.isEnabled && cardTuning.panelVisible {
                TokenmonDexCardTuningPanel(store: cardTuning)
                    .padding(16)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .background {
            if TokenmonDexCardTuningGate.isEnabled {
                Button("") { cardTuning.panelVisible.toggle() }
                    .keyboardShortcut("t", modifiers: [.command, .option])
                    .hidden()
            }
        }
        .animation(.easeOut(duration: 0.2), value: cardTuning.panelVisible)
        .toolbar {
            dexToolbarContent
        }
        .onAppear {
            model.surfaceOpened(.dex, entrypoint: "window_content", emitAnalytics: false)
            normalizeSelection()
            applyPendingDexNavigationRequest()
        }
        .onChange(of: model.dexEntries) { _, _ in
            normalizeSelection()
        }
        .onChange(of: model.dexNavigationRequest) { _, _ in
            applyPendingDexNavigationRequest()
        }
        .onChange(of: sidebarSelection) { _, _ in
            normalizeSelection()
        }
        .onChange(of: fieldFilter) { _, _ in
            normalizeSelection()
        }
        .onChange(of: rarityFilter) { _, _ in
            normalizeSelection()
        }
        .onChange(of: searchQuery) { _, _ in
            normalizeSelection()
        }
    }

    @ToolbarContentBuilder
    private var dexToolbarContent: some ToolbarContent {
        tokenmonAdaptiveSharedBackgroundHidden(
            ToolbarItem {
                TokenmonBuildVersionBadge()
            }
        )
    }

    private func normalizeSelection() {
        // Party is a curated view: don't auto-switch off of it, even when empty.
        if sidebarSelection != .party,
           model.dexEntries.contains(where: { sidebarSelection.matches($0) }) == false {
            sidebarSelection = TokenmonDexSidebarSelection.preferredSelection(for: model.dexEntries)
        }

        let currentIDs = Set(filteredEntries.map(\.speciesID))
        if let selectedSpeciesID, currentIDs.contains(selectedSpeciesID) {
            return
        }
        selectedSpeciesID = filteredEntries.first?.speciesID
    }

    private func applyPendingDexNavigationRequest() {
        guard let request = model.dexNavigationRequest else {
            return
        }
        sidebarSelection = .all
        fieldFilter = .all
        rarityFilter = .all
        sortMode = .number
        searchQuery = ""
        selectedSpeciesID = request.speciesID
        model.clearDexNavigationRequest(request)
    }
}

private struct TokenmonDexSidebarList: View {
    @Binding var selection: TokenmonDexSidebarSelection
    let dexEntries: [DexEntrySummary]
    let partyMembers: [PartyMemberSummary]

    var body: some View {
        List(selection: $selection) {
            Section(TokenmonL10n.string("dex.section.collection")) {
                TokenmonDexSidebarRow(
                    title: TokenmonDexSidebarSelection.all.title,
                    systemImage: TokenmonDexSidebarSelection.all.systemImage,
                    count: dexEntries.count
                )
                .tag(TokenmonDexSidebarSelection.all)

                TokenmonDexSidebarRow(
                    title: TokenmonDexSidebarSelection.captured.title,
                    systemImage: TokenmonDexSidebarSelection.captured.systemImage,
                    count: dexEntries.filter { $0.status == .captured }.count
                )
                .tag(TokenmonDexSidebarSelection.captured)

                TokenmonDexSidebarRow(
                    title: TokenmonDexSidebarSelection.seenUncaptured.title,
                    systemImage: TokenmonDexSidebarSelection.seenUncaptured.systemImage,
                    count: dexEntries.filter { $0.status == .seenUncaptured }.count
                )
                .tag(TokenmonDexSidebarSelection.seenUncaptured)

                TokenmonDexSidebarRow(
                    title: TokenmonDexSidebarSelection.unknown.title,
                    systemImage: TokenmonDexSidebarSelection.unknown.systemImage,
                    count: dexEntries.filter { $0.status == .unknown }.count
                )
                .tag(TokenmonDexSidebarSelection.unknown)
            }

            Section {
                TokenmonDexSidebarRow(
                    title: TokenmonDexSidebarSelection.party.title,
                    systemImage: TokenmonDexSidebarSelection.party.systemImage,
                    count: partyMembers.count,
                    countText: partyCountText
                )
                .tag(TokenmonDexSidebarSelection.party)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle(TokenmonL10n.string("window.title.dex"))
    }

    private var partyCountText: String {
        String(
            format: TokenmonL10n.string("dex.sidebar.party.counter_format"),
            Int64(partyMembers.count)
        )
    }
}

private struct TokenmonDexSidebarRow: View {
    let title: String
    let systemImage: String
    let count: Int
    var countText: String? = nil

    var body: some View {
        HStack {
            Label(title, systemImage: systemImage)
                .lineLimit(1)
                .layoutPriority(1)
            Spacer(minLength: 4)
            Text(countText ?? "\(count)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

private struct TokenmonDexBrowserPane: View {
    @ObservedObject var model: TokenmonMenuModel
    @State private var partyToast: PartyToast?
    let title: String
    let subtitle: String
    let filterSummary: String
    let emptyTitle: String
    let emptyDescription: String
    let allEntries: [DexEntrySummary]
    let entries: [DexEntrySummary]
    let progress: TokenmonDexCollectionProgress
    let sidebarSelection: TokenmonDexSidebarSelection
    @Binding var presentationMode: TokenmonDexPresentationMode
    @Binding var selectedSpeciesID: String?
    @Binding var fieldFilter: TokenmonDexFieldFilter
    @Binding var rarityFilter: TokenmonDexRarityFilter
    @Binding var sortMode: TokenmonDexSortMode
    let onRefresh: () -> Void

    private var shouldShowFilters: Bool {
        sidebarSelection != .party
    }

    private let columns = [
        GridItem(.adaptive(minimum: 152, maximum: 192), spacing: 16),
    ]

    private var filterDropdowns: some View {
        HStack(spacing: 6) {
            filterDropdown(
                label: TokenmonL10n.string("now.meta.field"),
                value: fieldFilter.title,
                isActive: fieldFilter != .all
            ) {
                Picker("Field", selection: $fieldFilter) {
                    ForEach(TokenmonDexFieldFilter.allCases, id: \.self) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }

            filterDropdown(
                label: TokenmonL10n.string("now.meta.rarity"),
                value: rarityFilter.title,
                isActive: rarityFilter != .all
            ) {
                Picker("Rarity", selection: $rarityFilter) {
                    ForEach(TokenmonDexRarityFilter.allCases, id: \.self) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }

            filterDropdown(
                label: TokenmonL10n.string("dex.sort.title"),
                value: sortMode.title,
                isActive: sortMode != .number
            ) {
                Picker("Sort", selection: $sortMode) {
                    ForEach(TokenmonDexSortMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }

            if hasActiveFilters {
                Button {
                    fieldFilter = .all
                    rarityFilter = .all
                    sortMode = .number
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(TokenmonL10n.string("dex.filter.reset"))
            }
        }
    }

    @ViewBuilder
    private func filterDropdown<Content: View>(
        label: String,
        value: String,
        isActive: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Menu {
            content()
        } label: {
            HStack(spacing: 4) {
                Text(isActive ? value : label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isActive ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(isActive ? Color.accentColor.opacity(0.35) : Color.secondary.opacity(0.18), lineWidth: 1)
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var refreshButton: some View {
        Button(action: onRefresh) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.secondary.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help(TokenmonL10n.string("common.refresh"))
    }

    private var presentationPicker: some View {
        Picker("View", selection: $presentationMode) {
            Image(systemName: "square.grid.2x2")
                .tag(TokenmonDexPresentationMode.grid)
            Image(systemName: "list.bullet")
                .tag(TokenmonDexPresentationMode.list)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 72)
    }

    private var hasActiveFilters: Bool {
        fieldFilter != .all || rarityFilter != .all || sortMode != .number
    }

    private func gridLeadingOffset(for containerWidth: CGFloat) -> CGFloat {
        let cardMax: CGFloat = 192
        let cardMin: CGFloat = 152
        let spacing: CGFloat = 16
        let cardsPerRow = max(1, Int((containerWidth + spacing) / (cardMin + spacing)))
        let actualCardWidth = min(cardMax, (containerWidth - spacing * CGFloat(cardsPerRow - 1)) / CGFloat(cardsPerRow))
        let totalUsedWidth = actualCardWidth * CGFloat(cardsPerRow) + spacing * CGFloat(cardsPerRow - 1)
        return max(0, (containerWidth - totalUsedWidth) / 2)
    }

    var body: some View {
        GeometryReader { geo in
            let contentWidth = max(0, geo.size.width - 32) // 16 padding each side
            let gridOffset = gridLeadingOffset(for: contentWidth)

        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.title2.weight(.semibold))

                HStack(alignment: .center, spacing: 6) {
                    if shouldShowFilters {
                        filterDropdowns
                    }
                    Spacer(minLength: 8)
                    refreshButton
                    presentationPicker
                }
            }
            .padding(.leading, 16 + gridOffset)
            .padding(.trailing, 16 + gridOffset * 0.5)
            .padding(.top, 16)

            if entries.isEmpty {
                ContentUnavailableView(
                    emptyTitle,
                    systemImage: "tray",
                    description: Text(emptyDescription)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            if presentationMode == .grid {
                                LazyVGrid(columns: columns, spacing: 16) {
                                    ForEach(entries, id: \.speciesID) { entry in
                                        Button {
                                            selectedSpeciesID = entry.speciesID
                                        } label: {
                                            TokenmonDexCard(
                                                entry: entry,
                                                isSelected: selectedSpeciesID == entry.speciesID
                                            )
                                        }
                                        .buttonStyle(.plain)
                                        .id(entry.speciesID)
                                        .partyMembershipBorder(
                                            isMember: model.partySpeciesIDs.contains(entry.speciesID),
                                            cornerRadius: 16,
                                            lineWidth: 3
                                        )
                                        .accessibilityLabel(Text(entry.speciesName))
                                        .accessibilityValue(
                                            model.partySpeciesIDs.contains(entry.speciesID)
                                                ? Text(TokenmonL10n.string("dex.card.accessibility.party_suffix"))
                                                : Text("")
                                        )
                                        .contextMenu {
                                            let isMember = model.partySpeciesIDs.contains(entry.speciesID)
                                            let isCaptured = entry.status == .captured

                                            if isMember {
                                                Button {
                                                    _ = model.removeSpeciesFromParty(entry.speciesID)
                                                } label: {
                                                    Label(TokenmonL10n.string("dex.context_menu.remove_from_party"), systemImage: "bag.badge.minus")
                                                }
                                            } else {
                                                Button {
                                                    let outcome = model.addSpeciesToParty(entry.speciesID)
                                                    if outcome == .partyFull {
                                                        partyToast = PartyToast(message: TokenmonL10n.string("party.full.toast"))
                                                    }
                                                } label: {
                                                    Label(TokenmonL10n.string("dex.context_menu.add_to_party"), systemImage: "bag.badge.plus")
                                                }
                                                .disabled(isCaptured == false)
                                                .help(isCaptured ? "" : TokenmonL10n.string("dex.context_menu.add_to_party.disabled_help"))
                                            }
                                        }
                                    }
                                }
                            } else {
                                TokenmonDexListPane(entries: entries, selectedSpeciesID: $selectedSpeciesID)
                            }
                        }
                        .padding(.top, 2)
                    }
                    .onAppear {
                        scrollToSelectedSpecies(with: proxy)
                    }
                    .onChange(of: selectedSpeciesID) { _, _ in
                        scrollToSelectedSpecies(with: proxy)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 540, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .partyToast($partyToast)
    }

    private func scrollToSelectedSpecies(with proxy: ScrollViewProxy) {
        guard let selectedSpeciesID else {
            return
        }
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.2)) {
                proxy.scrollTo(selectedSpeciesID, anchor: .center)
            }
        }
    }
}

private struct TokenmonDexListPane: View {
    let entries: [DexEntrySummary]
    @Binding var selectedSpeciesID: String?

    var body: some View {
        LazyVStack(spacing: 8) {
            ForEach(entries, id: \.speciesID) { entry in
                Button {
                    selectedSpeciesID = entry.speciesID
                } label: {
                    TokenmonDexListRow(entry: entry, isSelected: selectedSpeciesID == entry.speciesID)
                }
                .buttonStyle(.plain)
                .id(entry.speciesID)
            }
        }
    }
}

struct TokenmonDexListRow: View {
    let entry: DexEntrySummary
    let isSelected: Bool
    var compact: Bool = false
    var showsCountMetrics: Bool = true

    private var displayName: String {
        TokenmonDexPresentation.visibleSpeciesName(for: entry)
    }

    private var metadataLine: String {
        let base = TokenmonDexPresentation.metadataLine(for: entry)
        guard showsCountMetrics else {
            return base
        }
        return "\(base) · Seen \(entry.seenCount) · Captured \(entry.capturedCount)"
    }

    var body: some View {
        HStack(alignment: .center, spacing: compact ? 10 : 12) {
            Text(String(format: "#%03d", entry.sortOrder))
                .font(compact ? .subheadline.monospacedDigit().weight(.semibold) : .title3.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: compact ? 44 : 56, alignment: .leading)

            TokenmonDexSpritePreview(
                status: entry.status,
                revealStage: TokenmonDexPresentation.revealStage(for: entry),
                field: entry.field,
                rarity: entry.rarity,
                assetKey: entry.assetKey,
                cardSize: compact ? 46 : 52,
                spriteSize: compact ? 30 : 34
            )

            VStack(alignment: .leading, spacing: compact ? 3 : 4) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(displayName)
                        .font(compact ? .subheadline.weight(.semibold) : .headline)
                        .foregroundStyle(entry.status == .unknown ? .secondary : .primary)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    TokenmonDexStatusBadge(status: entry.status, compact: compact)
                }

                Text(metadataLine)
                    .font(compact ? .caption2 : .caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, compact ? 12 : 14)
        .padding(.vertical, compact ? 10 : 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: compact ? 14 : 16)
                .fill(isSelected ? Color.accentColor.opacity(0.10) : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: compact ? 14 : 16)
                .stroke(
                    isSelected ? Color.accentColor.opacity(0.55) : Color.secondary.opacity(0.12),
                    lineWidth: isSelected ? 1.5 : 1
                )
        )
    }
}

enum TokenmonDexCompletionStripLayout {
    case horizontal
    case compactGrid
}

struct TokenmonDexCompletionStrip: View {
    let progress: TokenmonDexCollectionProgress
    var layout: TokenmonDexCompletionStripLayout = .horizontal

    private let compactColumns = [
        GridItem(.flexible(minimum: 0), spacing: 8),
        GridItem(.flexible(minimum: 0), spacing: 8),
    ]

    var body: some View {
        Group {
            switch layout {
            case .horizontal:
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        chip(title: TokenmonL10n.string("dex.completion.completion"), value: "\(Int((progress.completionFraction * 100).rounded()))%", tint: .accentColor)
                        chip(title: TokenmonL10n.string("dex.status.captured"), value: "\(progress.captured)", tint: .green)
                        chip(title: TokenmonL10n.string("dex.status.seen"), value: "\(progress.seen)", tint: .orange)
                        chip(title: TokenmonL10n.string("dex.status.hidden"), value: "\(progress.hidden)", tint: .secondary)
                    }
                }
            case .compactGrid:
                LazyVGrid(columns: compactColumns, spacing: 8) {
                    chip(title: TokenmonL10n.string("dex.completion.completion"), value: "\(Int((progress.completionFraction * 100).rounded()))%", tint: .accentColor, fillsWidth: true)
                    chip(title: TokenmonL10n.string("dex.status.captured"), value: "\(progress.captured)", tint: .green, fillsWidth: true)
                    chip(title: TokenmonL10n.string("dex.status.seen"), value: "\(progress.seen)", tint: .orange, fillsWidth: true)
                    chip(title: TokenmonL10n.string("dex.status.hidden"), value: "\(progress.hidden)", tint: .secondary, fillsWidth: true)
                }
            }
        }
    }

    @ViewBuilder
    private func chip(title: String, value: String, tint: Color, fillsWidth: Bool = false) -> some View {
        TokenmonDexCompletionChip(title: title, value: value, tint: tint, fillsWidth: fillsWidth)
    }
}

private struct TokenmonDexCompletionChip: View {
    let title: String
    let value: String
    let tint: Color
    var fillsWidth: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 0)

            Text(value)
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(minHeight: 42)
        .frame(maxWidth: fillsWidth ? .infinity : nil, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(tint.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(tint.opacity(0.24), lineWidth: 1)
        )
    }
}

private struct FieldText: View {
    let field: FieldType

    var body: some View {
        Label(field.displayName, systemImage: field.systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(field.tint)
    }
}

private struct RarityText: View {
    let rarity: RarityTier

    var body: some View {
        Label(rarity.displayName, systemImage: rarity.systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(rarity.tint)
    }
}

struct TokenmonDexCard: View {
    let entry: DexEntrySummary
    let isSelected: Bool

    private var displayName: String {
        TokenmonDexPresentation.visibleSpeciesName(for: entry)
    }

    private var albumStyle: TokenmonDexAlbumStyle {
        TokenmonDexAlbumStyle.make(for: entry.rarity)
    }

    private var fieldLabel: String {
        entry.field.displayName
    }

    private var rarityLabel: String {
        entry.rarity.displayName
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Text(String(format: "#%03d", entry.sortOrder))
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 6) {
                    TokenmonDexAlbumRarityPill(rarity: entry.rarity, albumStyle: albumStyle)
                    TokenmonDexAlbumStatusPill(status: entry.status)
                }
            }

            HStack {
                Spacer()
                TokenmonDexSpritePreview(
                    status: entry.status,
                    revealStage: TokenmonDexPresentation.revealStage(for: entry),
                    field: entry.field,
                    rarity: entry.rarity,
                    assetKey: entry.assetKey
                )
                .frame(width: 120, height: 120)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(entry.status == .unknown ? .secondary : .primary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(fieldLabel)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("•")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary.opacity(0.8))
                    Text(rarityLabel)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(entry.rarity.tint)
                        .lineLimit(1)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 184, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(cardBackground)
        )
        .shadow(
            color: entry.rarity.tint.opacity(albumStyle.glowOpacity),
            radius: albumStyle.emphasisLevel >= 3 ? 7 : 4,
            y: albumStyle.emphasisLevel >= 3 ? 2 : 1
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    isSelected ? Color.accentColor : entry.rarity.tint.opacity(albumStyle.borderOpacity),
                    lineWidth: isSelected ? 2 : 1
                )
        )
    }

    private var cardBackground: LinearGradient {
        LinearGradient(
            colors: [
                entry.rarity.tint.opacity(albumStyle.rarityFillOpacity),
                entry.field.tint.opacity(0.08),
                Color(nsColor: .controlBackgroundColor),
            ],
            startPoint: .topLeading,
            endPoint: .bottom
        )
    }
}

private struct TokenmonDexAlbumRarityPill: View {
    let rarity: RarityTier
    let albumStyle: TokenmonDexAlbumStyle

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: albumStyle.primarySymbol)
                .font(.caption2.weight(.bold))
        }
        .foregroundStyle(rarity.tint)
        .frame(width: 30, height: 28)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(rarity.tint.opacity(0.12 + (Double(albumStyle.emphasisLevel) * 0.03)))
        )
    }
}

private struct TokenmonDexAlbumStatusPill: View {
    let status: DexEntryStatus

    var body: some View {
        Image(systemName: status.systemImage)
            .font(.caption2.weight(.bold))
            .foregroundStyle(status.tint)
            .frame(width: 30, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(status.tint.opacity(0.12))
            )
    }
}

struct TokenmonDexDetailPane: View {
    let entry: DexEntrySummary?

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 0) {
                if let entry {
                    VStack(alignment: .leading, spacing: 0) {
                        TokenmonDexDetailCard(entry: entry)

                        VStack(spacing: 10) {
                            TokenmonDexProgressPanel(entry: entry)

                            TokenmonDexFieldNotesPanel(entry: entry)
                        }
                        .padding(.top, 14)
                    }
                } else {
                    ContentUnavailableView(
                        TokenmonL10n.string("dex.detail.empty_title"),
                        systemImage: "books.vertical",
                        description: Text(TokenmonL10n.string("dex.detail.empty_description"))
                    )
                    .frame(maxWidth: tokenmonDexSupportingWidth, minHeight: 220, alignment: .topLeading)
                }
            }
            .frame(maxWidth: tokenmonDexSupportingWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .frame(minWidth: tokenmonDexSupportingWidth + 24, maxWidth: tokenmonDexSupportingWidth + 24, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct TokenmonMetricRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }
}

enum TokenmonDexSpriteContent: Equatable {
    case mystery
    case speciesPortrait
    case fallback

    static func resolve(
        revealStage: TokenmonSpeciesArtRevealStage,
        portraitAvailable: Bool
    ) -> TokenmonDexSpriteContent {
        if portraitAvailable {
            return .speciesPortrait
        }

        switch revealStage {
        case .silhouette:
            return .mystery
        case .heavyBlur, .mediumBlur, .lightBlur, .revealed:
            return .fallback
        }
    }
}

private enum TokenmonDexMysteryArt {
    static func silhouette(color: Color) -> [PixelDot] {
        let points = [
            (3, 0), (7, 0),
            (2, 1), (3, 1), (4, 1), (5, 1), (6, 1), (7, 1), (8, 1),
            (2, 2), (3, 2), (4, 2), (5, 2), (6, 2), (7, 2), (8, 2),
            (1, 3), (2, 3), (3, 3), (4, 3), (5, 3), (6, 3), (7, 3), (8, 3), (9, 3),
            (1, 4), (2, 4), (3, 4), (4, 4), (5, 4), (6, 4), (7, 4), (8, 4), (9, 4),
            (2, 5), (3, 5), (4, 5), (5, 5), (6, 5), (7, 5), (8, 5),
            (2, 6), (3, 6), (4, 6), (5, 6), (6, 6), (7, 6), (8, 6),
            (3, 7), (4, 7), (5, 7), (6, 7), (7, 7),
            (2, 8), (3, 8), (7, 8), (8, 8),
        ]

        return points.map { PixelDot(x: $0.0, y: $0.1, color: color) }
    }
}

private struct TokenmonDexMysterySilhouette: View {
    let field: FieldType
    let rarity: RarityTier
    let spriteSize: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(field.tint.opacity(0.10))
                .frame(width: spriteSize * 0.94, height: spriteSize * 0.94)

            Circle()
                .stroke(rarity.tint.opacity(0.18), lineWidth: spriteSize >= 72 ? 1.5 : 1)
                .frame(width: spriteSize * 0.94, height: spriteSize * 0.94)

            PixelSprite(
                dots: TokenmonDexMysteryArt.silhouette(color: Color.black.opacity(0.78)),
                pixelSize: pixelSize
            )
            .shadow(color: Color.black.opacity(0.08), radius: 2, y: 1)
        }
        .frame(width: spriteSize, height: spriteSize)
    }

    private var pixelSize: CGFloat {
        max(2, floor(spriteSize / 11))
    }
}

private struct TokenmonDexFallbackGlyph: View {
    let field: FieldType
    let rarity: RarityTier
    let status: DexEntryStatus
    let spriteSize: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(field.tint.opacity(status == .captured ? 0.18 : 0.10))
                .frame(width: spriteSize * 0.94, height: spriteSize * 0.94)

            Circle()
                .stroke(rarity.tint.opacity(status == .captured ? 0.34 : 0.20), lineWidth: spriteSize >= 72 ? 1.5 : 1)
                .frame(width: spriteSize * 0.94, height: spriteSize * 0.94)

            Image(systemName: field.systemImage)
                .font(.system(size: spriteSize * 0.42, weight: .bold))
                .foregroundStyle(status == .captured ? field.tint : field.tint.opacity(0.62))
        }
        .frame(width: spriteSize, height: spriteSize)
    }
}

struct TokenmonDexSpritePreview: View {
    let status: DexEntryStatus
    let revealStage: TokenmonSpeciesArtRevealStage
    let field: FieldType
    let rarity: RarityTier
    let assetKey: String
    var cardSize: CGFloat = 66
    var spriteSize: CGFloat = 44
    var showsBackground: Bool = true
    var showsBorder: Bool = true

    var body: some View {
        let portraitAvailable = TokenmonSpeciesSpriteLoader.hasImage(
            assetKey: assetKey,
            variants: [.portrait64, .portrait32]
        )

        return ZStack {
            if showsBackground {
                RoundedRectangle(cornerRadius: cardCornerRadius)
                    .fill(backgroundFill)
            }
            if showsBorder {
                RoundedRectangle(cornerRadius: cardCornerRadius)
                    .stroke(borderColor, lineWidth: 1.5)
            }

            VStack {
                Spacer()
                Group {
                    switch TokenmonDexSpriteContent.resolve(revealStage: revealStage, portraitAvailable: portraitAvailable) {
                    case .mystery:
                        TokenmonDexMysterySilhouette(
                            field: field,
                            rarity: rarity,
                            spriteSize: spriteSize
                        )
                    case .speciesPortrait:
                        TokenmonSpeciesSpriteImage(
                            assetKey: assetKey,
                            variants: [.portrait64, .portrait32],
                            revealStage: revealStage
                        )
                        .frame(width: spriteSize, height: spriteSize)
                    case .fallback:
                        TokenmonDexFallbackGlyph(
                            field: field,
                            rarity: rarity,
                            status: status,
                            spriteSize: spriteSize
                        )
                    }
                }
                .shadow(color: Color.black.opacity(revealStage == .silhouette ? 0.04 : 0.10), radius: 3, y: 2)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: cardSize, height: cardSize)
    }

    private var cardCornerRadius: CGFloat {
        max(14, cardSize * 0.24)
    }

    private var backgroundFill: LinearGradient {
        let top = field.tint.opacity(revealStage == .silhouette ? 0.12 : 0.18)
        let bottom = status.tint.opacity(revealStage == .silhouette ? 0.08 : 0.14)
        return LinearGradient(
            colors: [top, bottom],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var borderColor: Color {
        revealStage == .silhouette ? .secondary.opacity(0.22) : status.tint.opacity(0.40)
    }

}

struct TokenmonDexHeroArt: View {
    let status: DexEntryStatus
    let revealStage: TokenmonSpeciesArtRevealStage
    let field: FieldType
    let rarity: RarityTier
    let assetKey: String
    var cardSize: CGFloat = 140
    var spriteSize: CGFloat = 102
    var showsBackground: Bool = true
    var showsBorder: Bool = true

    var body: some View {
        TokenmonDexSpritePreview(
            status: status,
            revealStage: revealStage,
            field: field,
            rarity: rarity,
            assetKey: assetKey,
            cardSize: cardSize,
            spriteSize: spriteSize,
            showsBackground: showsBackground,
            showsBorder: showsBorder
        )
    }
}

struct TokenmonRarityBadge: View {
    let rarity: RarityTier
    let compact: Bool

    var body: some View {
        Group {
            if compact {
                Image(systemName: rarity.systemImage)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(rarity.tint)
            } else {
                Label(rarity.displayName, systemImage: rarity.systemImage)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(rarity.tint)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, compact ? 6 : 10)
        .padding(.vertical, compact ? 4 : 6)
        .background(Capsule().fill(rarity.tint.opacity(0.14)))
        .fixedSize(horizontal: true, vertical: false)
        .help(rarity.displayName)
    }
}

struct TokenmonFieldGlyph: View {
    let field: FieldType

    var body: some View {
        Image(systemName: field.systemImage)
            .font(.caption.weight(.bold))
            .foregroundStyle(field.tint)
            .help(field.displayName)
    }
}

struct TokenmonFieldBadge: View {
    let field: FieldType
    var compact: Bool = false
    var iconOnly: Bool = false

    var body: some View {
        Group {
            if iconOnly {
                Image(systemName: field.systemImage)
                    .font(compact ? .caption.weight(.bold) : .caption.weight(.semibold))
                    .foregroundStyle(field.tint)
                    .frame(width: compact ? 24 : 28, height: compact ? 24 : 28)
                    .background(
                        RoundedRectangle(cornerRadius: compact ? 8 : 10, style: .continuous)
                            .fill(field.tint.opacity(0.12))
                    )
                    .help(field.displayName)
            } else {
                Label(field.displayName, systemImage: field.systemImage)
                    .font(compact ? .caption2.weight(.semibold) : .caption.weight(.semibold))
                    .foregroundStyle(field.tint)
                    .lineLimit(1)
                    .padding(.horizontal, compact ? 8 : 10)
                    .padding(.vertical, compact ? 4 : 6)
                    .background(
                        Capsule()
                            .fill(field.tint.opacity(0.12))
                    )
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
    }
}

struct TokenmonDexStatusBadge: View {
    let status: DexEntryStatus
    let compact: Bool

    var body: some View {
        Group {
            if compact {
                if status == .unknown {
                    Text(status.detailTitle)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(status.tint)
                        .lineLimit(1)
                } else {
                    Image(systemName: status.systemImage)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(status.tint)
                }
            } else {
                Label(status.detailTitle, systemImage: status.systemImage)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(status.tint)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, compact ? 6 : 10)
        .padding(.vertical, compact ? 4 : 6)
        .background(Capsule().fill(status.tint.opacity(0.14)))
        .fixedSize(horizontal: true, vertical: false)
        .help(status.detailTitle)
    }
}

private struct TokenmonBuildVersionBadge: View {
    private let buildInfo = TokenmonBuildInfo.current

    var body: some View {
        Text(buildInfo.toolbarBadgeLabel())
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color.secondary.opacity(0.08))
            )
            .accessibilityLabel(buildInfo.accessibilityLabel)
            .help(helpText)
    }

    private var helpText: String {
        var components = [buildInfo.versionSummary, buildInfo.revisionSummary]
        if let buildTimestampSummary = buildInfo.buildTimestampSummary {
            components.append("Built \(buildTimestampSummary)")
        }
        return components.joined(separator: " • ")
    }
}
