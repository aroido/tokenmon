import Foundation
import Testing
@testable import TokenmonApp
@testable import TokenmonGameEngine
@testable import TokenmonOtelProviders
@testable import TokenmonPersistence
@testable import TokenmonProviders
import TokenmonDomain

@Suite(.serialized)
@MainActor
struct TokenmonPresentationTests {
    init() {
        TokenmonL10n.setLocaleOverride("en")
    }

    @Test
    func sceneContextShowsResolveSuccessForRecentCapture() {
        let summary = makeSummary(
            totalNormalizedTokens: 8_400,
            tokensSinceLastEncounter: 200,
            tokensUntilNextEncounter: 2_800,
            totalEncounters: 6,
            totalCaptures: 5,
            seenSpeciesCount: 4,
            capturedSpeciesCount: 3
        )
        let encounter = makeEncounter(outcome: .captured)

        let context = TokenmonSceneContextBuilder.context(summary: summary, latestEncounter: encounter)

        #expect(
            context == TokenmonSceneContext(
                sceneState: .resolveSuccess,
                fieldKind: .sky,
                fieldState: .settle,
                effectState: .captureSnap,
                wildState: .captured,
                wildAssetKey: "sky_012_nimbusray"
            )
        )
    }

    @Test
    func sceneContextShowsRustleWhenEncounterNear() {
        let summary = makeSummary(
            totalNormalizedTokens: 24_000,
            tokensSinceLastEncounter: 2_400,
            tokensUntilNextEncounter: 400,
            totalEncounters: 8,
            totalCaptures: 5,
            seenSpeciesCount: 5,
            capturedSpeciesCount: 3
        )

        let context = TokenmonSceneContextBuilder.context(summary: summary, latestEncounter: nil)

        #expect(
            context == TokenmonSceneContext(
                sceneState: .rustle,
                fieldKind: .grassland,
                fieldState: .rustle,
                effectState: .none,
                wildState: .hidden
            )
        )
    }

    @Test
    func sceneContextUsesLiveActivityPulseBeforeFirstTokenCount() {
        let summary = makeSummary(
            totalNormalizedTokens: 0,
            tokensSinceLastEncounter: 0,
            tokensUntilNextEncounter: 3_000,
            totalEncounters: 0,
            totalCaptures: 0,
            seenSpeciesCount: 0,
            capturedSpeciesCount: 0
        )

        let context = TokenmonSceneContextBuilder.context(
            summary: summary,
            latestEncounter: nil,
            liveActivityUntil: Date().addingTimeInterval(1),
            now: Date()
        )

        #expect(
            context == TokenmonSceneContext(
                sceneState: .exploring,
                fieldKind: .grassland,
                fieldState: .exploring,
                effectState: .none,
                wildState: .hidden
            )
        )
    }

    @Test
    func statusStripLayoutUsesExplicitPixelContract() {
        let layout = TokenmonSceneLayout.statusStrip(forThickness: 22)

        #expect(layout.canvasSize.height == 22)
        #expect(layout.canvasSize.width == 44)
        #expect(layout.safeRect == CGRect(origin: .zero, size: layout.canvasSize))
        #expect(layout.fieldFrame == CGRect(origin: .zero, size: layout.canvasSize))
        #expect(layout.wildFrame == CGRect(x: 28, y: 3, width: 16, height: 16))
        #expect(layout.effectFrame == CGRect(x: 0, y: 0, width: 16, height: 16))
        #expect(layout.previewScale == 3)
    }

    @Test
    func statusStripContractKeepsFramesInsideCanvas() {
        let layout = TokenmonSceneLayout.statusStrip(forThickness: 22)

        #expect(layout.safeRect.minX >= 0)
        #expect(layout.safeRect.minY >= 0)
        #expect(layout.safeRect.maxX <= layout.canvasSize.width)
        #expect(layout.safeRect.maxY <= layout.canvasSize.height)
        #expect(layout.fieldFrame.maxX <= layout.safeRect.maxX)
        #expect(layout.fieldFrame.maxY <= layout.safeRect.maxY)
        #expect(layout.wildFrame.maxX <= layout.safeRect.maxX)
        #expect(layout.wildFrame.maxY <= layout.safeRect.maxY)
        #expect(layout.effectFrame.width > 0)
        #expect(layout.effectFrame.height > 0)
    }

    @Test
    func statusStripLayoutScalesWithMenuBarThickness() {
        let compact = TokenmonSceneLayout.statusStrip(forThickness: 22)
        let expanded = TokenmonSceneLayout.statusStrip(forThickness: 26)

        #expect(expanded.canvasSize.height == 26)
        #expect(expanded.canvasSize.width > compact.canvasSize.width)
        #expect(expanded.fieldFrame.width > compact.fieldFrame.width)
        #expect(expanded.fieldFrame.height > compact.fieldFrame.height)
        #expect(expanded.effectFrame == compact.effectFrame)
        #expect(expanded.canvasSize.width == 52)
    }

    @Test
    func statusItemRendererUsesExactCanvasSizeAtStandardHeight() {
        let context = TokenmonSceneContext(
            sceneState: .exploring,
            fieldKind: .grassland,
            fieldState: .exploring,
            effectState: .none,
            wildState: .hidden
        )

        let image = TokenmonStatusItemImageRenderer.render(
            context: context,
            at: Date(timeIntervalSinceReferenceDate: 10_000),
            buttonBounds: NSRect(x: 0, y: 0, width: 56, height: 22)
        )

        #expect(image != nil)
        #expect(image?.size.width == 44)
        #expect(image?.size.height == 22)
    }

    @Test
    func statusItemRendererSupportsFieldBackplateDisabled() {
        let context = TokenmonSceneContext(
            sceneState: .exploring,
            fieldKind: .coast,
            fieldState: .exploring,
            effectState: .none,
            wildState: .hidden,
            showsFieldBackplate: false
        )

        let image = TokenmonStatusItemImageRenderer.render(
            context: context,
            at: Date(timeIntervalSinceReferenceDate: 12_000),
            buttonBounds: NSRect(x: 0, y: 0, width: 56, height: 22)
        )

        #expect(image != nil)
        #expect(image?.size == CGSize(width: 44, height: 22))
    }

    @Test
    func fieldVisualSpecsKeepDistinctDominantCuesAndSafeEffectRects() {
        let fields: [TokenmonSceneFieldKind] = [.grassland, .ice, .coast, .sky]
        let specs = fields.map(\.visualSpec)
        let layout = TokenmonSceneLayout.statusStrip(forThickness: 22)

        #expect(Set(specs.map { dominantCueToken($0.dominantCue) }).count == fields.count)

        for spec in specs {
            #expect(spec.spawnPocket.minX >= 0)
            #expect(spec.spawnPocket.minY >= 0)
            #expect(spec.spawnPocket.maxX <= layout.fieldFrame.width)
            #expect(spec.spawnPocket.maxY <= layout.fieldFrame.height)

            let effectRect = spec.effectRect(in: layout)

            #expect(effectRect.minX >= layout.fieldPatchRect.minX)
            #expect(effectRect.minY >= layout.fieldPatchRect.minY)
            #expect(effectRect.maxX <= layout.fieldPatchRect.maxX)
            #expect(effectRect.maxY <= layout.fieldPatchRect.maxY)
            #expect(abs(effectRect.midX - layout.fieldPatchRect.midX) <= 1)
            #expect(abs(effectRect.midY - layout.fieldPatchRect.midY) <= 1)

            #expect(spec.kind.previewSpecies != nil)
        }
    }

    @Test
    func nowCampHeroPresentationBuildsLeadAndSupportSlots() {
        let lead = sampleSpecies(field: .grassland, offset: 0)
        let supportOne = sampleSpecies(field: .grassland, offset: 1)
        let supportTwo = sampleSpecies(field: .grassland, offset: 2)
        let presentation = NowCampHeroPresentation.make(
            nowCamp: makeNowCampSummary(
                lead: lead,
                supports: [supportOne, supportTwo],
                focusEnergy: 50,
                affinityLevel: 3,
                trainingRank: .rankII
            ),
            partyMembers: [],
            sceneContext: makeNowCampSceneContext(field: .grassland)
        )

        #expect(presentation.lead?.speciesID == lead.id)
        #expect(presentation.supportSlots.count == 2)
        #expect(presentation.trainAction.isEnabled)
        #expect(presentation.trainAction.acceptsTapForFeedback)
        #expect(presentation.careAction.availability == .careCharging(remainingSeconds: NowCampCarePolicy.intervalSeconds))
        #expect(presentation.careAction.acceptsTapForFeedback)
        #expect(presentation.careStatusLine == TokenmonL10n.format("now.camp.care.minutes_remaining", Int64(60)))
        #expect(presentation.trainingLevelText == TokenmonL10n.format("now.camp.training_level", Int64(2), Int64(5)))
        #expect(presentation.headerLeadDetail == presentation.trainingLevelText)
        #expect(presentation.trainTargetLine == TokenmonL10n.format("now.camp.train.target", "II", "III"))
        #expect(presentation.targetLevelText == TokenmonL10n.format("now.camp.practice.target_level", Int64(2), Int64(3)))
        #expect(presentation.trainRewardLine == TokenmonL10n.format(
            "now.camp.train.reward",
            expectedNowCampRewardName(for: lead.trainingTrait)
        ))
        #expect(presentation.trainRewardShortLine == expectedNowCampRewardShortName(for: lead.trainingTrait))
        #expect(presentation.trainRewardSystemImage == expectedNowCampRewardSystemImage(for: lead.trainingTrait))
        #expect(presentation.trainBenefitLine == TokenmonL10n.format(
            "now.camp.train.benefit",
            expectedNowCampRewardShortName(for: lead.trainingTrait)
        ))
        #expect(presentation.benefitText == expectedNowCampBenefitText(for: lead))
        #expect(presentation.practiceControlTitleText == TokenmonL10n.string("now.camp.practice.action"))
        #expect(presentation.practiceControlDetailText == TokenmonL10n.format("now.camp.practice.target_level", Int64(2), Int64(3)))
        #expect(presentation.practiceProgressFraction == 1.0)
        #expect(presentation.practiceReadinessText == TokenmonL10n.format("now.camp.practice.readiness", Int64(50), Int64(50)))
        #expect(presentation.practiceStatusText == TokenmonL10n.string("now.camp.practice.status.ready"))
        #expect(presentation.attemptHelpText.contains("success rate"))
        #expect(presentation.campStatusLine == TokenmonL10n.string("now.camp.status.ready"))
        #expect(presentation.energySourceLine == TokenmonL10n.string("now.camp.energy.source.ready"))
        #expect(presentation.trainingLevelPipCount == 2)
        #expect(presentation.v2.focusValueText == "50/50")
        #expect(presentation.v2.practiceTitleText == TokenmonL10n.string("now.camp.v2.practice.title"))
        #expect(presentation.v2.practiceChanceText == expectedNowCampV2PracticeChance(
            rarity: lead.rarity,
            trainingRank: .rankII
        ))
        #expect(presentation.v2.resonanceValueText == expectedNowCampV2Resonance(
            rarity: lead.rarity,
            trainingRank: .rankII
        ))
        #expect(presentation.v2.scoutActionTitleText == TokenmonL10n.string("now.camp.v2.scout"))
        #expect(presentation.v2.scoutActionHelpText == TokenmonL10n.string("now.camp.v2.scout.help"))

        let rewardPreview = LeaderTraitBonusResolver().previewBonus(
            lead: LeaderTraitContext(
                speciesID: lead.id,
                homeField: lead.field,
                rarity: lead.rarity,
                trait: lead.trainingTrait,
                trainingRank: .rankII
            )
        )
        let nextRewardPreview = LeaderTraitBonusResolver().previewBonus(
            lead: LeaderTraitContext(
                speciesID: lead.id,
                homeField: lead.field,
                rarity: lead.rarity,
                trait: lead.trainingTrait,
                trainingRank: .rankIII
            )
        )
        #expect(presentation.v2.rewardPreview.valueText == expectedNowCampV2LeadEffectValue(
            current: rewardPreview
        ))
        #expect(presentation.v2.rewardPreview.detailText == expectedNowCampV2LeadEffectDetail(
            current: rewardPreview,
            next: nextRewardPreview,
            nextRank: .rankIII
        ))
        #expect(presentation.v2.rewardPreview.compactValueText == expectedNowCampV2LeadEffectCompactValue(
            current: rewardPreview,
            next: nextRewardPreview
        ))
        #expect(presentation.v2.rewardPreview.compactDetailText == expectedNowCampV2LeadEffectCompactDetail(
            current: rewardPreview,
            next: nextRewardPreview
        ))
        #expect(presentation.v2.rewardPreview.currentLine.labelText == TokenmonL10n.string("now.camp.v2.reward.current.label"))
        #expect(presentation.v2.rewardPreview.currentLine.valueText == (
            rewardPreview.isActive
                ? expectedNowCampV2EffectLineText(for: rewardPreview)
                : TokenmonL10n.string("now.camp.v2.reward.current.none")
        ))
        #expect(presentation.v2.rewardPreview.successLine.labelText == TokenmonL10n.string("now.camp.v2.reward.success.label"))
        #expect(presentation.v2.rewardPreview.successLine.valueText == (
            nextRewardPreview.isActive
                ? expectedNowCampV2EffectLineText(for: nextRewardPreview)
                : TokenmonL10n.string("now.camp.v2.reward.success.none")
        ))
        #expect(presentation.v2.rewardPreview.isActive == rewardPreview.isActive)

        guard case .occupied(let firstSupport, index: 0) = presentation.supportSlots[0] else {
            Issue.record("expected occupied first support slot")
            return
        }
        #expect(firstSupport.speciesID == supportOne.id)

        guard case .occupied(let secondSupport, index: 1) = presentation.supportSlots[1] else {
            Issue.record("expected occupied second support slot")
            return
        }
        #expect(secondSupport.speciesID == supportTwo.id)
    }

    @Test
    func nowCampHeroPresentationKeepsEmptySupportSlotsWhenPartyIsShort() {
        let lead = sampleSpecies(field: .coast, offset: 0)
        let presentation = NowCampHeroPresentation.make(
            nowCamp: makeNowCampSummary(
                lead: lead,
                supports: [],
                focusEnergy: 44,
                affinityLevel: 2,
                trainingRank: .rankI
            ),
            partyMembers: [makePartyMember(from: lead)],
            sceneContext: makeNowCampSceneContext(field: .coast)
        )

        #expect(presentation.supportSlots.count == 2)
        #expect(presentation.supportSlots.allSatisfy { slot in
            if case .empty = slot {
                return true
            }
            return false
        })
    }

    @Test
    func nowCampHeroPresentationShowsSharedFocusAndPerLeadTrainingStatus() {
        let selectedLead = sampleSpecies(field: .grassland, offset: 0)
        let trainableLead = sampleSpecies(field: .grassland, offset: 1)
        let maxLead = sampleSpecies(field: .grassland, offset: 2)
        let presentation = NowCampHeroPresentation.make(
            nowCamp: makeNowCampSummary(
                lead: selectedLead,
                supports: [],
                focusEnergy: 50,
                affinityLevel: 2,
                trainingRank: .rankII,
                careReady: true,
                careElapsedSeconds: NowCampCarePolicy.intervalSeconds
            ),
            partyMembers: [
                makePartyMember(from: selectedLead, affinityLevel: 2, trainingRank: .rankII),
                makePartyMember(from: trainableLead, slotOrder: 2, affinityLevel: 2, trainingRank: .rankI),
                makePartyMember(from: maxLead, slotOrder: 3, affinityLevel: 5, trainingRank: .rankV),
            ],
            sceneContext: makeNowCampSceneContext(field: .grassland)
        )

        #expect(presentation.trainAction.availability == .rankAtAffinityGate(current: 2, required: 3))
        #expect(presentation.careAction.availability == .focusFull(capacity: 50))
        #expect(presentation.practiceControlDetailText == TokenmonL10n.format(
            "now.camp.practice.bond_gate.alternative",
            Int64(2),
            Int64(3)
        ))

        let selectedStatus = presentation.leadMenuStatus(for: selectedLead.id)
        #expect(selectedStatus?.statusText == TokenmonL10n.format(
            "now.camp.lead_picker.status.bond",
            "II"
        ))
        #expect(selectedStatus?.titleText == "\(selectedLead.name) · \(selectedStatus?.statusText ?? "")")
        #expect(selectedStatus?.systemImage == "lock.fill")
        #expect(selectedStatus?.isSelected == true)
        #expect(selectedStatus?.isTrainable == false)

        let trainableStatus = presentation.leadMenuStatus(for: trainableLead.id)
        #expect(trainableStatus?.statusText == TokenmonL10n.format(
            "now.camp.lead_picker.status.ready",
            "I"
        ))
        #expect(trainableStatus?.titleText == "\(trainableLead.name) · \(trainableStatus?.statusText ?? "")")
        #expect(trainableStatus?.systemImage == "lock.open.fill")
        #expect(trainableStatus?.isTrainable == true)

        let maxStatus = presentation.leadMenuStatus(for: maxLead.id)
        #expect(maxStatus?.statusText == TokenmonL10n.format("now.camp.lead_picker.status.max", "V"))
        #expect(maxStatus?.systemImage == "lock.fill")
        #expect(maxStatus?.isTrainable == false)

        let focusLimited = NowCampHeroPresentation.make(
            nowCamp: makeNowCampSummary(
                lead: selectedLead,
                supports: [],
                focusEnergy: 12,
                affinityLevel: 3,
                trainingRank: .rankI
            ),
            partyMembers: [
                makePartyMember(from: selectedLead, affinityLevel: 3, trainingRank: .rankI),
            ],
            sceneContext: makeNowCampSceneContext(field: .grassland)
        )

        #expect(focusLimited.leadMenuStatus(for: selectedLead.id)?.statusText == TokenmonL10n.format(
            "now.camp.lead_picker.status.focus_needed",
            "I"
        ))
        #expect(focusLimited.leadMenuStatus(for: selectedLead.id)?.systemImage == "lock.open.fill")
        #expect(focusLimited.leadMenuStatus(for: selectedLead.id)?.isTrainable == false)
    }

    @Test
    func nowCampHeroPresentationExplainsMissingLeadForExternalPracticeControl() {
        let presentation = NowCampHeroPresentation.make(
            nowCamp: nil,
            partyMembers: [],
            sceneContext: makeNowCampSceneContext(field: .grassland)
        )

        #expect(presentation.lead == nil)
        #expect(presentation.trainAction.availability == .missingLead)
        #expect(presentation.trainAction.acceptsTapForFeedback)
        #expect(presentation.careAction.availability == .missingLead)
        #expect(presentation.careAction.acceptsTapForFeedback == false)
        #expect(presentation.practiceControlTitleText == TokenmonL10n.string("now.camp.practice.status.no_lead"))
        #expect(presentation.practiceControlDetailText == TokenmonL10n.string("now.camp.action.no_lead.short"))
        #expect(presentation.campStatusLine == TokenmonL10n.string("now.camp.status.no_lead"))
        #expect(presentation.trainingLevelPipCount == 0)
        #expect(presentation.practiceProgressFraction == 0.0)
        #expect(presentation.v2.focusValueText == "0/50")
        #expect(presentation.v2.practiceChanceText == TokenmonL10n.string("now.camp.v2.unavailable"))
        #expect(presentation.v2.resonanceValueText == TokenmonL10n.string("now.camp.v2.unavailable"))
        #expect(presentation.v2.rewardPreview.valueText == TokenmonL10n.string("now.camp.v2.unavailable"))
        #expect(presentation.v2.rewardPreview.isActive == false)
        #expect(presentation.v2.scoutActionHelpText.contains("Dex"))
    }

    @Test
    func nowCampHeroPresentationExplainsFocusAndRankLimitedActions() {
        let lead = sampleSpecies(field: .ice, offset: 0)
        let focusLimited = NowCampHeroPresentation.make(
            nowCamp: makeNowCampSummary(
                lead: lead,
                supports: [],
                focusEnergy: 12,
                affinityLevel: 3,
                trainingRank: .rankI
            ),
            partyMembers: [],
            sceneContext: makeNowCampSceneContext(field: .ice)
        )
        #expect(focusLimited.trainAction.availability == .insufficientFocus(current: 12, required: 50))
        #expect(focusLimited.trainAction.acceptsTapForFeedback)
        #expect(focusLimited.careAction.availability == .careCharging(remainingSeconds: NowCampCarePolicy.intervalSeconds))
        #expect(focusLimited.careAction.isEnabled == false)
        #expect(focusLimited.careAction.acceptsTapForFeedback)
        #expect(focusLimited.trainTargetLine == TokenmonL10n.format("now.camp.train.target", "I", "II"))
        #expect(focusLimited.trainingLevelText == TokenmonL10n.format("now.camp.training_level", Int64(1), Int64(5)))
        #expect(focusLimited.headerLeadDetail == focusLimited.trainingLevelText)
        #expect(focusLimited.targetLevelText == TokenmonL10n.format("now.camp.practice.target_level", Int64(1), Int64(2)))
        #expect(focusLimited.practiceControlTitleText == TokenmonL10n.string("now.camp.practice.status.preparing"))
        #expect(focusLimited.practiceControlDetailText == TokenmonL10n.format(
            "now.camp.practice.shared_focus.detail",
            Int64(12),
            Int64(50)
        ))
        #expect(abs(focusLimited.practiceProgressFraction - 0.24) < 0.0001)
        #expect(focusLimited.practiceReadinessText == TokenmonL10n.format("now.camp.practice.need_more", Int64(38)))
        #expect(focusLimited.practiceStatusText == TokenmonL10n.string("now.camp.practice.status.preparing"))
        #expect(focusLimited.trainRewardShortLine == expectedNowCampRewardShortName(for: lead.trainingTrait))
        #expect(focusLimited.trainRewardSystemImage == expectedNowCampRewardSystemImage(for: lead.trainingTrait))
        #expect(focusLimited.campStatusLine == TokenmonL10n.string("now.camp.status.gathering"))
        #expect(focusLimited.energySourceLine == TokenmonL10n.string("now.camp.energy.source.live"))
        #expect(focusLimited.attemptHelpText.contains("Need 38"))
        #expect(focusLimited.v2.focusValueText == "12/50")
        #expect(focusLimited.v2.practiceChanceText == expectedNowCampV2PracticeChance(
            rarity: lead.rarity,
            trainingRank: .rankI
        ))
        #expect(focusLimited.v2.resonanceValueText == expectedNowCampV2Resonance(
            rarity: lead.rarity,
            trainingRank: .rankI
        ))
        let focusLimitedCurrentReward = LeaderTraitBonusResolver().previewBonus(
            lead: LeaderTraitContext(
                speciesID: lead.id,
                homeField: lead.field,
                rarity: lead.rarity,
                trait: lead.trainingTrait,
                trainingRank: .rankI
            )
        )
        let focusLimitedRewardPreview = LeaderTraitBonusResolver().previewBonus(
            lead: LeaderTraitContext(
                speciesID: lead.id,
                homeField: lead.field,
                rarity: lead.rarity,
                trait: lead.trainingTrait,
                trainingRank: .rankII
            )
        )
        #expect(focusLimited.v2.rewardPreview.valueText == expectedNowCampV2LeadEffectValue(
            current: focusLimitedCurrentReward
        ))
        #expect(focusLimited.v2.rewardPreview.detailText == expectedNowCampV2LeadEffectDetail(
            current: focusLimitedCurrentReward,
            next: focusLimitedRewardPreview,
            nextRank: .rankII
        ))
        #expect(focusLimited.v2.rewardPreview.compactValueText == expectedNowCampV2LeadEffectCompactValue(
            current: focusLimitedCurrentReward,
            next: focusLimitedRewardPreview
        ))
        #expect(focusLimited.v2.rewardPreview.compactDetailText == expectedNowCampV2LeadEffectCompactDetail(
            current: focusLimitedCurrentReward,
            next: focusLimitedRewardPreview
        ))
        #expect(focusLimited.v2.rewardPreview.currentLine.valueText == TokenmonL10n.string("now.camp.v2.reward.current.none"))
        #expect(focusLimited.v2.rewardPreview.successLine.valueText == (
            focusLimitedRewardPreview.isActive
                ? expectedNowCampV2EffectLineText(for: focusLimitedRewardPreview)
                : TokenmonL10n.string("now.camp.v2.reward.success.none")
        ))
        if focusLimitedRewardPreview.isActive {
            #expect(focusLimited.attemptHelpText.contains(TokenmonL10n.format(
                "now.camp.practice.help.reward",
                expectedNowCampV2EffectLineText(for: focusLimitedRewardPreview)
            )))
        }
        #expect(focusLimited.v2.rewardPreview.isActive == focusLimitedCurrentReward.isActive)

        let rankLimited = NowCampHeroPresentation.make(
            nowCamp: makeNowCampSummary(
                lead: lead,
                supports: [],
                focusEnergy: 50,
                affinityLevel: 2,
                trainingRank: .rankII
            ),
            partyMembers: [],
            sceneContext: makeNowCampSceneContext(field: .ice)
        )
        #expect(rankLimited.trainAction.availability == .rankAtAffinityGate(current: 2, required: 3))
        #expect(rankLimited.trainAction.acceptsTapForFeedback)
        #expect(rankLimited.practiceStatusText == TokenmonL10n.string("now.camp.practice.status.bond_gate"))
        #expect(rankLimited.practiceControlTitleText == TokenmonL10n.string("now.camp.practice.status.bond_gate"))
        #expect(rankLimited.practiceControlDetailText == TokenmonL10n.format("now.camp.action.rank_gate.short", Int64(2), Int64(3)))
        #expect(rankLimited.campStatusLine == TokenmonL10n.string("now.camp.status.gathering"))
        #expect(rankLimited.v2.practiceChanceText == TokenmonL10n.string("now.camp.v2.bond_gate"))
        #expect(rankLimited.v2.resonanceValueText == TokenmonL10n.string("now.camp.v2.bond_gate"))
        let rankLimitedCurrentReward = LeaderTraitBonusResolver().previewBonus(
            lead: LeaderTraitContext(
                speciesID: lead.id,
                homeField: lead.field,
                rarity: lead.rarity,
                trait: lead.trainingTrait,
                trainingRank: .rankII
            )
        )
        let rankLimitedNextReward = LeaderTraitBonusResolver().previewBonus(
            lead: LeaderTraitContext(
                speciesID: lead.id,
                homeField: lead.field,
                rarity: lead.rarity,
                trait: lead.trainingTrait,
                trainingRank: .rankIII
            )
        )
        #expect(rankLimited.v2.rewardPreview.valueText == expectedNowCampV2LeadEffectValue(
            current: rankLimitedCurrentReward
        ))
        #expect(rankLimited.v2.rewardPreview.detailText == expectedNowCampV2LeadEffectDetail(
            current: rankLimitedCurrentReward,
            next: rankLimitedNextReward,
            nextRank: .rankIII,
            nextIsBlocked: true,
            blockedCurrent: 2,
            blockedRequired: 3
        ))
        #expect(rankLimited.v2.rewardPreview.isActive == rankLimitedCurrentReward.isActive)

        let careReady = NowCampHeroPresentation.make(
            nowCamp: makeNowCampSummary(
                lead: lead,
                supports: [],
                focusEnergy: 44,
                affinityLevel: 3,
                trainingRank: .rankI,
                careReady: true,
                careElapsedSeconds: NowCampCarePolicy.intervalSeconds
            ),
            partyMembers: [],
            sceneContext: makeNowCampSceneContext(field: .ice)
        )
        #expect(careReady.careAction.availability == .enabled)
        #expect(careReady.careAction.acceptsTapForFeedback)
        #expect(careReady.careStatusLine == TokenmonL10n.format("now.camp.care.ready.amount", Int64(5)))
        #expect(careReady.practiceControlTitleText == TokenmonL10n.string("now.camp.practice.status.preparing"))
        #expect(careReady.campStatusLine == TokenmonL10n.string("now.camp.status.care_ready"))
        #expect(careReady.attemptHelpText.contains("+5%") == false)
        #expect(careReady.v2.practiceChanceText == expectedNowCampV2PracticeChance(
            rarity: lead.rarity,
            trainingRank: .rankI
        ))

        let careReadyAtFullFocus = NowCampHeroPresentation.make(
            nowCamp: makeNowCampSummary(
                lead: lead,
                supports: [],
                focusEnergy: 50,
                affinityLevel: 3,
                trainingRank: .rankI,
                careReady: true,
                careElapsedSeconds: NowCampCarePolicy.intervalSeconds
            ),
            partyMembers: [],
            sceneContext: makeNowCampSceneContext(field: .ice)
        )
        #expect(careReadyAtFullFocus.careAction.availability == .focusFull(capacity: 50))
        #expect(careReadyAtFullFocus.careAction.isEnabled == false)
        #expect(careReadyAtFullFocus.careAction.acceptsTapForFeedback)
        #expect(careReadyAtFullFocus.careStatusLine == TokenmonL10n.string("now.camp.care.focus_full.short"))

        let maxRank = NowCampHeroPresentation.make(
            nowCamp: makeNowCampSummary(
                lead: lead,
                supports: [],
                focusEnergy: 50,
                affinityLevel: 5,
                trainingRank: .rankV
            ),
            partyMembers: [],
            sceneContext: makeNowCampSceneContext(field: .ice)
        )
        #expect(maxRank.trainAction.availability == .rankMaximum)
        #expect(maxRank.practiceStatusText == TokenmonL10n.string("now.camp.practice.status.max_rank"))
        #expect(maxRank.v2.practiceChanceText == TokenmonL10n.string("now.camp.v2.max"))
        #expect(maxRank.v2.resonanceValueText == TokenmonL10n.string("now.camp.v2.max"))
        let maxRankCurrentReward = LeaderTraitBonusResolver().previewBonus(
            lead: LeaderTraitContext(
                speciesID: lead.id,
                homeField: lead.field,
                rarity: lead.rarity,
                trait: lead.trainingTrait,
                trainingRank: .rankV
            )
        )
        #expect(maxRank.v2.rewardPreview.valueText == expectedNowCampV2LeadEffectValue(
            current: maxRankCurrentReward
        ))
        #expect(maxRank.v2.rewardPreview.isActive == maxRankCurrentReward.isActive)
    }

    @Test
    func nowCampHeroPresentationSeparatesRandomFieldFromLeadTrainingBonus() throws {
        let lead = try #require(SpeciesCatalog.all.first {
            $0.field == .sky && $0.trainingTrait == .trail
        })
        let presentation = NowCampHeroPresentation.make(
            nowCamp: makeNowCampSummary(
                lead: lead,
                supports: [],
                focusEnergy: 12,
                affinityLevel: 2,
                trainingRank: .rankI
            ),
            partyMembers: [],
            sceneContext: makeNowCampSceneContext(field: .grassland)
        )

        #expect(presentation.field == .grassland)
        #expect(presentation.fieldTitle == FieldType.grassland.displayName)
        #expect(presentation.fieldSystemImage == FieldType.grassland.systemImage)
        #expect(presentation.v2.rewardPreview.currentLine.valueText == TokenmonL10n.string("now.camp.v2.reward.current.none"))
        #expect(presentation.v2.rewardPreview.successLine.valueText.contains(FieldType.sky.displayName))
        #expect(presentation.v2.rewardPreview.successLine.valueText.contains(FieldType.grassland.displayName) == false)
        #expect(presentation.attemptHelpText.contains(presentation.v2.rewardPreview.successLine.valueText))
    }

    @Test
    func nowCampHeroPresentationShowsSeedkitCapturePassiveAtRankII() throws {
        let seedkit = try #require(SpeciesCatalog.all.first { $0.id == "GRS_003" })
        #expect(seedkit.name == "Seedkit")
        #expect(seedkit.rarity == .common)
        #expect(seedkit.trainingTrait == .capture)

        let presentation = NowCampHeroPresentation.make(
            nowCamp: makeNowCampSummary(
                lead: seedkit,
                supports: [],
                focusEnergy: 50,
                affinityLevel: 2,
                trainingRank: .rankII
            ),
            partyMembers: [],
            sceneContext: makeNowCampSceneContext(field: .grassland)
        )

        let expectedEffect = TokenmonL10n.format(
            "now.camp.v2.reward.capture.effect_line",
            FieldType.grassland.displayName,
            TokenmonL10n.format("now.camp.v2.points", Int64(1))
        )
        #expect(presentation.v2.rewardPreview.currentLine.valueText == expectedEffect)
        #expect(presentation.v2.rewardPreview.isActive)
        #expect(presentation.v2.rewardPreview.compactValueText == TokenmonL10n.format(
            "now.camp.v2.reward.capture.compact_value",
            FieldType.grassland.displayName
        ))
        #expect(presentation.v2.rewardPreview.compactDetailText == TokenmonL10n.format(
            "now.camp.v2.reward.capture.compact_detail",
            TokenmonL10n.format("now.camp.v2.points", Int64(1))
        ))
    }

    @Test
    func nowCampHeroPresentationMapsTrainingRanksToLevels() {
        let lead = sampleSpecies(field: .grassland, offset: 0)

        for rank in TrainingRank.allCases {
            let presentation = NowCampHeroPresentation.make(
                nowCamp: makeNowCampSummary(
                    lead: lead,
                    supports: [],
                    focusEnergy: 50,
                    affinityLevel: 5,
                    trainingRank: rank
                ),
                partyMembers: [],
                sceneContext: makeNowCampSceneContext(field: .grassland)
            )

            #expect(presentation.trainingLevelText == TokenmonL10n.format(
                "now.camp.training_level",
                Int64(rank.rawValue),
                Int64(TrainingRank.rankV.rawValue)
            ))
            #expect(presentation.trainingLevelPipCount == rank.rawValue)

            if let next = rank.next {
                #expect(presentation.targetLevelText == TokenmonL10n.format(
                    "now.camp.practice.target_level",
                    Int64(rank.rawValue),
                    Int64(next.rawValue)
                ))
            } else {
                #expect(presentation.targetLevelText == TokenmonL10n.string("now.camp.train.target.empty"))
            }
        }
    }

    @Test
    func nowCampHeroPresentationUsesReadableBenefitTextForEachTrait() {
        for trait in TrainingTrait.allCases {
            let lead = sampleSpecies(trait: trait)
            let presentation = NowCampHeroPresentation.make(
                nowCamp: makeNowCampSummary(
                    lead: lead,
                    supports: [],
                    focusEnergy: 50,
                    affinityLevel: 3,
                    trainingRank: .rankI
                ),
                partyMembers: [],
                sceneContext: makeNowCampSceneContext(field: lead.field)
            )

            #expect(presentation.benefitText == expectedNowCampBenefitText(for: lead))
        }
    }

    @Test
    func nowCampTrainingFailureFeedbackShowsFailureBuffer() {
        let resolution = LeaderTrainingResolution(
            speciesID: "GRS_001",
            rarity: .common,
            previousRank: .rankI,
            newRank: .rankI,
            targetRank: .rankII,
            affinityGateRank: .rankV,
            probability: 0.68,
            roll: 0.99,
            resonanceBefore: 0,
            resonanceAfter: 1,
            ceilingFailures: 2,
            attemptCountAfter: 1,
            outcome: .failure
        )
        let result = NowCampTrainingAttemptResult(resolution: resolution, focusEnergyAfter: 0)
        let feedback = NowCampHeroFeedback.trainingAttempt(result)

        #expect(feedback.message == TokenmonL10n.string("now.camp.feedback.train_failure"))
        #expect(feedback.motion == .tilt)
    }

    @Test
    func nowCampEffectLoaderResolvesSplitFieldRuntimeAssets() {
        for field in FieldType.allCases {
            #expect(NowCampEffectSpriteLoader.image(scope: .field(field), variant: .campMat64) != nil)
            #expect(NowCampEffectSpriteLoader.image(scope: .field(field), variant: .campPropPrimary32) != nil)
            #expect(NowCampEffectSpriteLoader.image(scope: .field(field), variant: .campPropSecondary32) != nil)
            #expect(NowCampEffectSpriteLoader.image(scope: .field(field), variant: .campProp32) != nil)
        }
    }

    @Test
    func nowCampMenuModelReturnsActionResultsForHeroFeedback() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let databasePath = directory.appendingPathComponent("tokenmon.sqlite").path
        let manager = TokenmonDatabaseManager(path: databasePath)
        try manager.bootstrap()
        try manager.resetProgress(startedAt: "2026-04-01T00:00:00Z")
        _ = try manager.forgeEncounter(
            TokenmonDeveloperEncounterForgeRequest(
                provider: .codex,
                field: .grassland,
                rarity: .common,
                speciesID: "GRS_001",
                outcome: .captured,
                occurredAt: "2026-04-24T00:00:00Z"
            )
        )
        try manager.addToParty(speciesID: "GRS_001")

        let database = try manager.open()
        try database.execute(
            """
            UPDATE dex_captured
            SET affinity_level = 2
            WHERE species_id = 'GRS_001';
            """
        )
        try database.execute(
            """
            UPDATE now_camp_state
            SET focus_energy = 45,
                care_ready = 1,
                care_elapsed_seconds = 3600,
                updated_at = '2026-04-24T00:01:00Z'
            WHERE singleton_id = 1;
            """
        )

        let model = TokenmonMenuModel(
            databasePath: databasePath,
            providerInspector: { _, _, _ in [] },
            launchAtLoginStateProvider: {
                .unsupported(reason: "tests")
            }
        )
        await model.waitForRefreshToFinish()

        let careResult = model.applyNowCampCareToLead()
        guard case .applied(let care) = careResult else {
            Issue.record("expected care action result")
            return
        }
        #expect(care.focusGranted == 5)
        #expect(care.focusEnergyAfter == 50)
        await model.waitForRefreshToFinish()
        #expect(model.nowCampSummary?.focusEnergy == 50)
        #expect(model.nowCampSummary?.careReady == false)
        #expect(model.nowCampSummary?.careElapsedSeconds == 0)

        let trainResult = model.trainNowCampLead()
        guard case .resolved(let train) = trainResult else {
            Issue.record("expected train action result")
            return
        }
        #expect(train.focusEnergyAfter == 0)

        let chargingCareResult = model.applyNowCampCareToLead()
        guard case .failed(let chargingCareMessage) = chargingCareResult else {
            Issue.record("expected care charging failure")
            return
        }
        #expect(chargingCareMessage == TokenmonL10n.string("now.camp.feedback.care_not_ready"))

        try database.execute(
            """
            UPDATE now_camp_state
            SET focus_energy = 50,
                care_ready = 1,
                care_elapsed_seconds = 3600,
                updated_at = '2026-04-24T00:01:20Z'
            WHERE singleton_id = 1;
            """
        )
        let fullFocusCareResult = model.applyNowCampCareToLead()
        guard case .failed(let fullFocusCareMessage) = fullFocusCareResult else {
            Issue.record("expected care full-focus failure")
            return
        }
        #expect(fullFocusCareMessage == TokenmonL10n.string("now.camp.feedback.care_focus_full"))

        try database.execute(
            """
            UPDATE now_camp_state
            SET focus_energy = 0,
                updated_at = '2026-04-24T00:01:30Z'
            WHERE singleton_id = 1;
            """
        )
        try database.execute(
            """
            UPDATE dex_captured
            SET affinity_level = 3
            WHERE species_id = 'GRS_001';
            """
        )
        try database.execute(
            """
            UPDATE species_training
            SET training_rank = 1,
                training_resonance = 0
            WHERE species_id = 'GRS_001';
            """
        )

        let focusBlockedTrainResult = model.trainNowCampLead()
        guard case .failed(let focusBlockedTrainMessage) = focusBlockedTrainResult else {
            Issue.record("expected train focus failure")
            return
        }
        #expect(focusBlockedTrainMessage == TokenmonL10n.format(
            "now.camp.feedback.train_not_ready",
            Int64(0),
            Int64(50)
        ))

        try database.execute(
            """
            UPDATE now_camp_state
            SET focus_energy = 50,
                updated_at = '2026-04-24T00:02:00Z'
            WHERE singleton_id = 1;
            """
        )
        try database.execute(
            """
            UPDATE dex_captured
            SET affinity_level = 2
            WHERE species_id = 'GRS_001';
            """
        )
        try database.execute(
            """
            UPDATE species_training
            SET training_rank = 2,
                training_resonance = 0
            WHERE species_id = 'GRS_001';
            """
        )

        let bondBlockedTrainResult = model.trainNowCampLead()
        guard case .failed(let bondBlockedTrainMessage) = bondBlockedTrainResult else {
            Issue.record("expected train bond failure")
            return
        }
        #expect(bondBlockedTrainMessage == TokenmonL10n.format(
            "now.camp.feedback.train_bond_gate",
            Int64(2),
            Int64(3)
        ))
    }

    @Test
    func statusItemRendererRendersEveryFieldAndKeyEffectStates() {
        let fields: [TokenmonSceneFieldKind] = [.grassland, .ice, .coast, .sky]
        let states: [TokenmonEffectState] = [.none, .alert, .captureSnap, .escapeDash]
        let timestamp = Date(timeIntervalSinceReferenceDate: 20_000)

        for field in fields {
            for effectState in states {
                let context = TokenmonSceneContext(
                    sceneState: sceneState(for: effectState),
                    fieldKind: field,
                    fieldState: fieldState(for: effectState),
                    effectState: effectState,
                    wildState: .hidden
                )

                let image = TokenmonStatusItemImageRenderer.render(
                    context: context,
                    at: timestamp,
                    buttonBounds: NSRect(x: 0, y: 0, width: 56, height: 22)
                )

                #expect(image != nil)
                #expect(image?.size == CGSize(width: 44, height: 22))
            }
        }
    }

    @Test
    func menuPresentationSummarizesRecentCapture() {
        let summary = makeSummary(
            totalNormalizedTokens: 80_000,
            tokensSinceLastEncounter: 400,
            tokensUntilNextEncounter: 2_600,
            totalEncounters: 12,
            totalCaptures: 8,
            seenSpeciesCount: 7,
            capturedSpeciesCount: 5
        )
        let encounter = makeEncounter(outcome: .captured)

        let presentation = TokenmonMenuPresentationBuilder.build(
            snapshot: TokenmonMenuSnapshot(
                summary: summary,
                latestEncounter: encounter,
                providerHealthSummaries: [],
                onboardingStatuses: [],
                loadError: nil
            ),
            providerStatusVisible: true
        )

        #expect(presentation.headline == "Captured Nimbusray")
        #expect(presentation.detail == nil)
        #expect(presentation.statsLine == "Rare • Sky")
    }

    @Test
    func fileImportSupportResolvesFileSelection() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tokenmon-file-import-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let fileURL = tempDirectory.appendingPathComponent("tokenmon.json")
        try Data("{}".utf8).write(to: fileURL)

        let outcome = TokenmonFileImportSupport.resolve(
            result: .success(fileURL),
            requirement: .file,
            invalidSelectionMessage: "Choose a file."
        )

        #expect(outcome == .imported(fileURL.path))
    }

    @Test
    func fileImportSupportRejectsWrongSelectionType() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tokenmon-folder-import-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let outcome = TokenmonFileImportSupport.resolve(
            result: .success(tempDirectory),
            requirement: .file,
            invalidSelectionMessage: "Choose a file."
        )

        #expect(outcome == .failure("Choose a file."))
    }

    @Test
    func fileImportSupportTreatsCancellationAsCancelled() {
        let outcome = TokenmonFileImportSupport.resolve(
            result: .failure(
                NSError(
                    domain: NSCocoaErrorDomain,
                    code: NSUserCancelledError
                )
            ),
            requirement: .directory,
            invalidSelectionMessage: "Choose a folder."
        )

        #expect(outcome == .cancelled)
    }

    @Test
    func menuPresentationHidesUncapturedEscapeName() {
        let summary = makeSummary(
            totalNormalizedTokens: 80_000,
            tokensSinceLastEncounter: 400,
            tokensUntilNextEncounter: 2_600,
            totalEncounters: 12,
            totalCaptures: 8,
            seenSpeciesCount: 7,
            capturedSpeciesCount: 5
        )
        let encounter = makeEncounter(outcome: .escaped, seenCount: 1, capturedCount: 0)

        let presentation = TokenmonMenuPresentationBuilder.build(
            snapshot: TokenmonMenuSnapshot(
                summary: summary,
                latestEncounter: encounter,
                providerHealthSummaries: [],
                onboardingStatuses: [],
                loadError: nil
            ),
            providerStatusVisible: true
        )

        #expect(presentation.headline == "Unknown species escaped")
    }

    @Test
    func menuPresentationKeepsCapturedIdentityOnLaterEscape() {
        let summary = makeSummary(
            totalNormalizedTokens: 80_000,
            tokensSinceLastEncounter: 400,
            tokensUntilNextEncounter: 2_600,
            totalEncounters: 12,
            totalCaptures: 8,
            seenSpeciesCount: 7,
            capturedSpeciesCount: 5
        )
        let encounter = makeEncounter(outcome: .escaped, seenCount: 4, capturedCount: 1)

        let presentation = TokenmonMenuPresentationBuilder.build(
            snapshot: TokenmonMenuSnapshot(
                summary: summary,
                latestEncounter: encounter,
                providerHealthSummaries: [],
                onboardingStatuses: [],
                loadError: nil
            ),
            providerStatusVisible: true
        )

        #expect(presentation.headline == "Nimbusray escaped")
    }

    @Test
    func captureNotificationCandidatesOnlyIncludeNewCaptures() {
        let previous = makeRuntimeSnapshot(
            latestEncounter: makeEncounter(sequence: 2, outcome: .escaped),
            recentEncounterFeed: [
                makeEncounter(sequence: 2, outcome: .escaped),
                makeEncounter(sequence: 1, outcome: .captured),
            ]
        )
        let current = makeRuntimeSnapshot(
            latestEncounter: makeEncounter(sequence: 5, outcome: .captured),
            recentEncounterFeed: [
                makeEncounter(sequence: 5, outcome: .captured),
                makeEncounter(sequence: 4, outcome: .escaped),
                makeEncounter(sequence: 3, outcome: .captured),
                makeEncounter(sequence: 2, outcome: .escaped),
            ]
        )

        let candidates = TokenmonCaptureNotificationCoordinator.captureCandidates(
            previous: previous,
            current: current
        )

        #expect(candidates.map(\.encounterSequence) == [3, 5])
    }

    @Test
    func captureNotificationCandidatesSkipInitialLoad() {
        let current = makeRuntimeSnapshot(
            latestEncounter: makeEncounter(sequence: 1, outcome: .captured),
            recentEncounterFeed: [makeEncounter(sequence: 1, outcome: .captured)]
        )

        let candidates = TokenmonCaptureNotificationCoordinator.captureCandidates(
            previous: TokenmonRuntimeSnapshot(),
            current: current
        )

        #expect(candidates.isEmpty)
    }

    @Test
    func nowStatusSummaryUsesSceneAndPresentationForRecentCapture() {
        let summary = makeSummary(
            totalNormalizedTokens: 80_000,
            tokensSinceLastEncounter: 200,
            tokensUntilNextEncounter: 2_800,
            totalEncounters: 12,
            totalCaptures: 8,
            seenSpeciesCount: 7,
            capturedSpeciesCount: 5
        )
        let encounter = makeEncounter(outcome: .captured)
        let presentation = TokenmonMenuPresentationBuilder.build(
            snapshot: TokenmonMenuSnapshot(
                summary: summary,
                latestEncounter: encounter,
                providerHealthSummaries: [],
                onboardingStatuses: [],
                loadError: nil
            ),
            providerStatusVisible: true
        )
        let sceneContext = TokenmonSceneContextBuilder.context(summary: summary, latestEncounter: encounter)

        let statusSummary = TokenmonNowStatusSummary(
            presentation: presentation,
            sceneContext: sceneContext
        )

        #expect(statusSummary.fieldTitle == "Sky")
        #expect(statusSummary.fieldSystemImage == "wind")
        #expect(statusSummary.phaseTitle == "Captured")
        #expect(statusSummary.phaseSystemImage == "checkmark.seal.fill")
        #expect(statusSummary.headline == nil)
        #expect(statusSummary.supportingLine == nil)
    }

    @Test
    func nowStatusSummaryShowsWaitingStateBeforeFirstActivity() {
        let summary = makeSummary(
            totalNormalizedTokens: 0,
            tokensSinceLastEncounter: 0,
            tokensUntilNextEncounter: 3_000,
            totalEncounters: 0,
            totalCaptures: 0,
            seenSpeciesCount: 0,
            capturedSpeciesCount: 0
        )
        let presentation = TokenmonMenuPresentationBuilder.build(
            snapshot: TokenmonMenuSnapshot(
                summary: summary,
                latestEncounter: nil,
                providerHealthSummaries: [],
                onboardingStatuses: [],
                loadError: nil
            ),
            providerStatusVisible: true
        )
        let sceneContext = TokenmonSceneContextBuilder.context(summary: summary, latestEncounter: nil)

        let statusSummary = TokenmonNowStatusSummary(
            presentation: presentation,
            sceneContext: sceneContext
        )

        #expect(statusSummary.fieldTitle == "Grassland")
        #expect(statusSummary.phaseTitle == "Waiting")
        #expect(statusSummary.headline == "Waiting for activity")
        #expect(statusSummary.supportingLine == "Use Claude Code or Codex to start exploring.")
    }

    @Test
    func compactCountFormatterKeepsSmallValuesAndAbbreviatesLargeValues() {
        #expect(TokenmonCompactCountFormatter.string(for: 151) == "151")
        #expect(TokenmonCompactCountFormatter.string(for: 1_250) == "1.3K")
        #expect(TokenmonCompactCountFormatter.string(for: 90_021) == "90K")
        #expect(TokenmonCompactCountFormatter.string(for: 1_250_000) == "1.3M")
    }

    @Test
    func settingsPresentationSummarizesConnectedAndAttentionProviders() {
        let statuses = [
            makeOnboardingStatus(
                provider: .claude,
                cliInstalled: false,
                isConnected: false,
                isPartial: false,
                title: "Claude not detected"
            ),
            makeOnboardingStatus(
                provider: .codex,
                cliInstalled: true,
                isConnected: true,
                isPartial: false,
                title: "Codex connected"
            ),
        ]

        let summary = TokenmonSettingsPresentationBuilder.providerOverviewSummary(
            onboardingStatuses: statuses
        )

        #expect(summary.providerCount == 2)
        #expect(summary.connectedCount == 1)
        #expect(summary.needsAttentionCount == 1)
    }

    @Test
    func settingsPresentationFormatsCodexBestEffortMetadata() {
        let status = makeOnboardingStatus(
            provider: .codex,
            cliInstalled: true,
            isConnected: false,
            isPartial: true,
            title: "Codex needs repair",
            codexMode: .auto
        )
        let health = makeHealthSummary(
            provider: .codex,
            sourceMode: "codex_interactive_observer",
            healthState: "degraded",
            supportLevel: "best_effort"
        )

        #expect(TokenmonSettingsPresentationBuilder.providerCardState(for: status) == .repair)

        let metadata = TokenmonSettingsPresentationBuilder.providerMetadataLine(
            status: status,
            healthSummary: health
        )

        #expect(metadata.contains("Support: Best-effort"))
        #expect(metadata.contains("Reliability: Degraded"))
        #expect(metadata.contains("Mode: Interactive observer"))
        #expect(metadata.contains("Automatic local follow"))
    }

    @Test
    func settingsPresentationFormatsCursorAsStatsOnlyNoGameplay() {
        let status = makeOnboardingStatus(
            provider: .cursor,
            cliInstalled: true,
            isConnected: true,
            isPartial: true,
            title: "Cursor synced"
        )
        let health = makeHealthSummary(
            provider: .cursor,
            sourceMode: "cursor_usage_export_api",
            healthState: "connected",
            supportLevel: "managed_only"
        )

        let metadata = TokenmonSettingsPresentationBuilder.providerMetadataLine(
            status: status,
            healthSummary: health
        )

        #expect(metadata.contains("Support: Managed-only"))
        #expect(metadata.contains("Reliability: Stats-only"))
        #expect(metadata.contains("Mode: Usage export sync"))
        #expect(metadata.contains("Stats-only; gameplay disabled"))
    }

    @Test
    func settingsBannerPrefersErrorWhenBothMessageAndErrorExist() {
        let banner = TokenmonSettingsPresentationBuilder.banner(
            message: "Rescanned provider installations.",
            error: "Launch at login is unavailable."
        )

        #expect(banner?.kind == .error)
        #expect(banner?.title == "Settings Error")
        #expect(banner?.message == "Launch at login is unavailable.")
    }

    @Test
    func localizationResourcesExposeKoreanChromeStrings() {
        #expect(TokenmonL10n.localizedValue(forKey: "settings.pane.general.title", localeIdentifier: "ko-KR") == "일반")
        #expect(TokenmonL10n.localizedValue(forKey: "window.title.dex", localeIdentifier: "ko") == "Dex")
        #expect(TokenmonL10n.localizedValue(forKey: "outcome.captured", localeIdentifier: "ko") == "포획")
        #expect(TokenmonL10n.localizedValue(forKey: "now.camp.title", localeIdentifier: "ko") == "Now")
        #expect(TokenmonL10n.format("progress.steps.remaining", 42) == "42 steps left")
    }

    @Test
    func popoverSceneContextPrefersDisplayedMenuBarContextWhenAvailable() {
        let liveSceneContext = TokenmonSceneContext(
            sceneState: .exploring,
            fieldKind: .grassland,
            fieldState: .exploring,
            effectState: .none,
            wildState: .hidden
        )
        let displayedSceneContext = TokenmonSceneContext(
            sceneState: .resolveSuccess,
            fieldKind: .ice,
            fieldState: .settle,
            effectState: .captureSnap,
            wildState: .captured
        )

        let resolved = TokenmonSceneContextResolver.popoverContext(
            displayedSceneContext: displayedSceneContext,
            liveSceneContext: liveSceneContext
        )

        #expect(resolved == displayedSceneContext)
    }

    @Test
    func popoverBackgroundSlotResolvesLocalHourBoundaries() {
        #expect(TokenmonPopoverBackgroundSlot.resolve(hour: 4) == .night)
        #expect(TokenmonPopoverBackgroundSlot.resolve(hour: 5) == .morning)
        #expect(TokenmonPopoverBackgroundSlot.resolve(hour: 10) == .morning)
        #expect(TokenmonPopoverBackgroundSlot.resolve(hour: 11) == .day)
        #expect(TokenmonPopoverBackgroundSlot.resolve(hour: 16) == .day)
        #expect(TokenmonPopoverBackgroundSlot.resolve(hour: 17) == .evening)
        #expect(TokenmonPopoverBackgroundSlot.resolve(hour: 20) == .evening)
        #expect(TokenmonPopoverBackgroundSlot.resolve(hour: 21) == .night)
        #expect(TokenmonPopoverBackgroundSlot.resolve(hour: 23) == .night)
        #expect(TokenmonPopoverBackgroundSlot.resolve(hour: 0) == .night)
    }

    @Test
    func popoverBackgroundLookupUsesTimeOfDayForEveryField() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))

        for field in [TokenmonSceneFieldKind.grassland, .coast, .ice, .sky] {
            #expect(
                TokenmonFieldSpriteLoader.popoverBackgroundRelativePath(
                    field: field,
                    at: date(hour: 5, calendar: calendar),
                    calendar: calendar
                ) == "backgrounds/popover/\(field.rawValue)/morning.png"
            )
            #expect(
                TokenmonFieldSpriteLoader.popoverBackgroundRelativePath(
                    field: field,
                    at: date(hour: 11, calendar: calendar),
                    calendar: calendar
                ) == "backgrounds/popover/\(field.rawValue)/day.png"
            )
            #expect(
                TokenmonFieldSpriteLoader.popoverBackgroundRelativePath(
                    field: field,
                    at: date(hour: 17, calendar: calendar),
                    calendar: calendar
                ) == "backgrounds/popover/\(field.rawValue)/evening.png"
            )
            #expect(
                TokenmonFieldSpriteLoader.popoverBackgroundRelativePath(
                    field: field,
                    at: date(hour: 21, calendar: calendar),
                    calendar: calendar
                ) == "backgrounds/popover/\(field.rawValue)/night.png"
            )
        }

        #expect(TokenmonFieldSpriteLoader.popoverBackgroundRelativePath(field: .unavailable) == nil)
    }

    @Test
    func popoverHeroMotionRespectsReducedMotion() {
        let frame = TokenmonPopoverHeroMotionModel.motionFrame(
            fieldKind: .coast,
            sceneState: .spawn,
            fieldState: .rustle,
            phase: 42,
            itemIndex: 2,
            reduceMotion: true
        )

        #expect(frame.backgroundOffset == .zero)
        #expect(frame.backgroundScale == 1)
        #expect(frame.foregroundOffset == .zero)
        #expect(frame.foregroundOpacity == 0)
        #expect(frame.companionOffset == .zero)
        #expect(frame.companionScale == 1)
        #expect(frame.effectIntensity == 0)
    }

    @Test
    func popoverHeroMotionAddsEnergyForEncounterStates() {
        let exploring = TokenmonPopoverHeroMotionModel.motionFrame(
            fieldKind: .grassland,
            sceneState: .exploring,
            fieldState: .exploring,
            phase: 10,
            itemIndex: 0,
            reduceMotion: false
        )
        let rustle = TokenmonPopoverHeroMotionModel.motionFrame(
            fieldKind: .grassland,
            sceneState: .rustle,
            fieldState: .rustle,
            phase: 10,
            itemIndex: 0,
            reduceMotion: false
        )
        let spawn = TokenmonPopoverHeroMotionModel.motionFrame(
            fieldKind: .grassland,
            sceneState: .spawn,
            fieldState: .rustle,
            phase: 10,
            itemIndex: 0,
            reduceMotion: false
        )
        let alert = TokenmonPopoverHeroMotionModel.motionFrame(
            fieldKind: .grassland,
            sceneState: .alert,
            fieldState: .rustle,
            phase: 10,
            itemIndex: 0,
            reduceMotion: false
        )
        let resolveSuccess = TokenmonPopoverHeroMotionModel.motionFrame(
            fieldKind: .ice,
            sceneState: .resolveSuccess,
            fieldState: .settle,
            phase: 10,
            itemIndex: 0,
            reduceMotion: false
        )
        let resolveEscape = TokenmonPopoverHeroMotionModel.motionFrame(
            fieldKind: .coast,
            sceneState: .resolveEscape,
            fieldState: .settle,
            phase: 10,
            itemIndex: 0,
            reduceMotion: false
        )

        #expect(exploring.foregroundOffset != .zero)
        #expect(rustle.foregroundOpacity > exploring.foregroundOpacity)
        #expect(spawn.backgroundScale > 1)
        #expect(spawn.effectIntensity > exploring.effectIntensity)
        #expect(alert.effectIntensity > exploring.effectIntensity)
        #expect(resolveSuccess.effectIntensity > exploring.effectIntensity)
        #expect(resolveEscape.effectIntensity > exploring.effectIntensity)
    }

    @Test
    func popoverHeroMotionUsesDistinctFieldAxes() {
        let phase = 10.5
        let grassland = TokenmonPopoverHeroMotionModel.motionFrame(
            fieldKind: .grassland,
            sceneState: .exploring,
            fieldState: .exploring,
            phase: phase,
            itemIndex: 1,
            reduceMotion: false
        )
        let coast = TokenmonPopoverHeroMotionModel.motionFrame(
            fieldKind: .coast,
            sceneState: .exploring,
            fieldState: .exploring,
            phase: phase,
            itemIndex: 1,
            reduceMotion: false
        )
        let ice = TokenmonPopoverHeroMotionModel.motionFrame(
            fieldKind: .ice,
            sceneState: .exploring,
            fieldState: .exploring,
            phase: phase,
            itemIndex: 1,
            reduceMotion: false
        )
        let sky = TokenmonPopoverHeroMotionModel.motionFrame(
            fieldKind: .sky,
            sceneState: .exploring,
            fieldState: .exploring,
            phase: phase,
            itemIndex: 1,
            reduceMotion: false
        )

        #expect(abs(coast.foregroundOffset.width) > abs(grassland.foregroundOffset.width))
        #expect(abs(sky.foregroundOffset.width) > abs(ice.foregroundOffset.width))
        #expect(coast.foregroundOffset != ice.foregroundOffset)
        #expect(sky.backgroundOffset != grassland.backgroundOffset)
    }

    @Test
    func nowFieldHeroCardSupportsPopoverOnboardingAndDebuggerConstruction() {
        let context = TokenmonSceneContext(
            sceneState: .spawn,
            fieldKind: .sky,
            fieldState: .rustle,
            effectState: .alert,
            wildState: .spawning,
            wildAssetKey: "sky_012_nimbusray"
        )
        let fixedDate = Date(timeIntervalSinceReferenceDate: 20_000)

        _ = TokenmonNowFieldHeroCard(sceneContext: context)
        _ = TokenmonNowFieldHeroCard(
            sceneContext: context,
            companionAssetKeys: ["sky_012_nimbusray"]
        )
        _ = TokenmonNowFieldHeroCard(
            sceneContext: context,
            companionAssetKeys: ["sky_012_nimbusray"],
            backgroundDate: fixedDate
        )
    }

    @Test
    func explorationThresholdConfigUsesStableRangePerEncounter() {
        let config = ExplorationAccumulatorConfig()
        let first = config.tokensRequiredForEncounter(1)
        let second = config.tokensRequiredForEncounter(2)
        let firstRepeat = config.tokensRequiredForEncounter(1)
        let earlyRange = config.scaledThresholdRange(capturedSpeciesCount: 0)
        let lateRange = config.scaledThresholdRange(capturedSpeciesCount: SpeciesCatalog.expectedCount)

        #expect(earlyRange.min == 180_000)
        #expect(earlyRange.max == 260_000)
        #expect(lateRange.min == 700_000)
        #expect(lateRange.max == 900_000)
        #expect(first >= earlyRange.min)
        #expect(first <= earlyRange.max)
        #expect(second >= earlyRange.min)
        #expect(second <= earlyRange.max)
        #expect(first == firstRepeat)
        #expect(first != second)
    }

    @Test
    func explorationAccumulatorUsesEncounterSpecificThresholds() throws {
        let accumulator = ExplorationAccumulator()
        let firstThreshold = accumulator.config.tokensRequiredForEncounter(1)
        let secondThreshold = accumulator.config.tokensRequiredForEncounter(2)
        let singleEncounterTokens = firstThreshold + 200
        let doubleEncounterTokens = firstThreshold + secondThreshold + 200

        let single = try accumulator.accumulate(
            state: ExplorationAccumulatorState(),
            normalizedDeltaTokens: singleEncounterTokens,
            observedAt: "2026-04-08T00:00:00Z"
        )

        #expect(single.updatedState.totalNormalizedTokens == singleEncounterTokens)
        #expect(single.updatedState.tokensSinceLastEncounter == 200)
        #expect(single.updatedState.nextEncounterThresholdTokens == secondThreshold)
        #expect(single.updatedState.totalEncounters == 1)
        #expect(single.thresholds.count == 1)
        #expect(single.thresholds.first?.thresholdTokens == firstThreshold)

        let double = try accumulator.accumulate(
            state: ExplorationAccumulatorState(),
            normalizedDeltaTokens: doubleEncounterTokens,
            observedAt: "2026-04-08T00:01:00Z"
        )

        #expect(double.updatedState.totalNormalizedTokens == doubleEncounterTokens)
        #expect(double.updatedState.tokensSinceLastEncounter == 200)
        #expect(double.updatedState.totalEncounters == 2)
        #expect(double.thresholds.count == 2)
        #expect(double.thresholds.first?.thresholdTokens == firstThreshold)
        #expect(double.thresholds.last?.thresholdTokens == secondThreshold)
    }

    @Test
    func restingContextIgnoresRecentEncounterAnimationState() {
        let summary = makeSummary(
            totalNormalizedTokens: 80_000,
            tokensSinceLastEncounter: 200,
            tokensUntilNextEncounter: 2_600
        )
        let encounter = makeEncounter(outcome: .captured)

        let context = TokenmonSceneContextBuilder.restingContext(
            summary: summary,
            latestEncounterField: encounter.field,
            loadError: nil
        )

        #expect(
            context == TokenmonSceneContext(
                sceneState: .exploring,
                fieldKind: .sky,
                fieldState: .exploring,
                effectState: .none,
                wildState: .hidden
            )
        )
        #expect(encounter.outcome == .captured)
    }

    @Test
    func playbackControllerRunsEncounterSequenceAndReturnsToRestingState() {
        let controller = TokenmonScenePlaybackController()
        let resting = TokenmonSceneContext(
            sceneState: .exploring,
            fieldKind: .grassland,
            fieldState: .exploring,
            effectState: .none,
            wildState: .roaming
        )
        let start = Date(timeIntervalSinceReferenceDate: 1_000)

        controller.updateRestingContext(resting)
        controller.enqueue(encounters: [makeEncounter(sequence: 3, outcome: .captured)])

        #expect(controller.context(at: start).sceneState == .alert)
        #expect(controller.context(at: start.addingTimeInterval(0.30)).sceneState == .spawn)
        #expect(controller.context(at: start.addingTimeInterval(0.30)).wildAssetKey == "sky_012_nimbusray")
        #expect(controller.context(at: start.addingTimeInterval(0.75)).sceneState == .resolveSuccess)
        #expect(controller.context(at: start.addingTimeInterval(1.65)).sceneState == .exploring)
    }

    @Test
    func playbackControllerQueuesMultipleEncountersInOrder() {
        let controller = TokenmonScenePlaybackController()
        let resting = TokenmonSceneContext(
            sceneState: .exploring,
            fieldKind: .grassland,
            fieldState: .exploring,
            effectState: .none,
            wildState: .roaming
        )
        let start = Date(timeIntervalSinceReferenceDate: 2_000)

        controller.updateRestingContext(resting)
        controller.enqueue(encounters: [
            makeEncounter(sequence: 5, outcome: .escaped),
            makeEncounter(sequence: 4, outcome: .captured),
        ])

        #expect(controller.context(at: start).sceneState == .alert)
        #expect(controller.context(at: start.addingTimeInterval(0.75)).sceneState == .resolveSuccess)
        #expect(controller.context(at: start.addingTimeInterval(1.65)).sceneState == .alert)
        #expect(controller.context(at: start.addingTimeInterval(2.45)).sceneState == .resolveEscape)
    }

    @Test
    func ingestAcceptsPredatedSamplesForAccountingOnly() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let databasePath = directory.appendingPathComponent("tokenmon.sqlite").path
        let databaseManager = TokenmonDatabaseManager(path: databasePath)
        try databaseManager.bootstrap()

        let service = UsageSampleIngestionService(databasePath: databasePath)
        let result = try service.ingestProviderEvents(
            [makeUsageEvent(observedAt: "2000-01-01T00:00:00Z", fingerprint: "old-sample")],
            sourceKey: "test:predates"
        )
        let summary = try databaseManager.summary()

        #expect(result.acceptedEvents == 1)
        #expect(result.rejectedEvents == 0)
        #expect(summary.usageSamples == 1)
        #expect(summary.totalNormalizedTokens == 0)
        #expect(summary.totalEncounters == 0)
        #expect(summary.totalCaptures == 0)
        #expect(try databaseManager.tokenUsageTotals().allTimeTokens == 200)
    }

    @Test
    func resetBoundaryCountsOnlyPostResetDeltaForOngoingSession() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let databasePath = directory.appendingPathComponent("tokenmon.sqlite").path
        let databaseManager = TokenmonDatabaseManager(path: databasePath)
        try databaseManager.bootstrap()
        try databaseManager.resetProgress(startedAt: "2026-04-06T05:56:35Z")
        try databaseManager.markLiveGameplayStarted(at: "2026-04-06T05:56:34Z")

        let service = UsageSampleIngestionService(databasePath: databasePath)
        let result = try service.ingestProviderEvents(
            [
                makeUsageEvent(
                    observedAt: "2026-04-06T05:56:23Z",
                    fingerprint: "session-1-old",
                    providerSessionID: "session-1",
                    normalizedTotalTokens: 1_000,
                    totalInputTokens: 700,
                    totalOutputTokens: 300,
                    currentInputTokens: 100,
                    currentOutputTokens: 50
                ),
                makeUsageEvent(
                    observedAt: "2026-04-06T05:56:35.259Z",
                    fingerprint: "session-1-new-1",
                    providerSessionID: "session-1",
                    normalizedTotalTokens: 1_200,
                    totalInputTokens: 820,
                    totalOutputTokens: 380,
                    currentInputTokens: 120,
                    currentOutputTokens: 80
                ),
                makeUsageEvent(
                    observedAt: "2026-04-06T05:56:41.135Z",
                    fingerprint: "session-1-new-2",
                    providerSessionID: "session-1",
                    normalizedTotalTokens: 1_500,
                    totalInputTokens: 1_010,
                    totalOutputTokens: 490,
                    currentInputTokens: 130,
                    currentOutputTokens: 90
                ),
            ],
            sourceKey: "test:reset-boundary",
            sourceKind: "ndjson_file"
        )
        let summary = try databaseManager.summary()

        #expect(result.rejectedEvents == 0)
        #expect(result.acceptedEvents == 3)
        #expect(summary.usageSamples == 3)
        let gameplayDelta = try gameplayDeltaSum(databaseManager)
        #expect(gameplayDelta > 0)
        #expect(gameplayDelta < 500)
        #expect(summary.totalNormalizedTokens == gameplayDelta)
        #expect(summary.tokensSinceLastEncounter == gameplayDelta)
        #expect(try databaseManager.tokenUsageTotals().allTimeTokens == 1_500)
    }

    @Test
    func dexSidebarSelectionMatchesEntryStatuses() {
        let captured = makeDexEntry(status: .captured)
        let seen = makeDexEntry(status: .seenUncaptured, sortOrder: 2)
        let unknown = makeDexEntry(status: .unknown, sortOrder: 3)

        #expect(TokenmonDexSidebarSelection.captured.matches(captured))
        #expect(TokenmonDexSidebarSelection.seenUncaptured.matches(seen))
        #expect(TokenmonDexSidebarSelection.unknown.matches(unknown))
        #expect(TokenmonDexSidebarSelection.captured.matches(seen) == false)
    }

    @Test
    func dexSidebarSelectionPrefersMostProgressedBucket() {
        let entries = [
            makeDexEntry(status: .unknown, sortOrder: 1),
            makeDexEntry(status: .seenUncaptured, sortOrder: 2),
            makeDexEntry(status: .captured, sortOrder: 3),
        ]

        #expect(TokenmonDexSidebarSelection.preferredSelection(for: entries) == .all)
        #expect(TokenmonDexSidebarSelection.preferredSelection(for: entries.filter { $0.status != .captured }) == .all)
        #expect(TokenmonDexSidebarSelection.preferredSelection(for: entries.filter { $0.status == .unknown }) == .all)
        #expect(TokenmonDexSidebarSelection.preferredSelection(for: []) == .unknown)
    }

    @Test
    func dexBrowserFiltersBySearchFieldAndRarity() {
        let entries = [
            makeDexEntry(status: .captured, sortOrder: 1, speciesName: "Mossbun", field: .grassland, rarity: .common),
            makeDexEntry(status: .seenUncaptured, sortOrder: 2, speciesName: "Nimbusray", field: .sky, rarity: .rare),
            makeDexEntry(status: .unknown, sortOrder: 3, speciesName: "Hidden", field: .coast, rarity: .legendary),
        ]

        let filtered = TokenmonDexBrowser.filteredEntries(
            entries: entries,
            statusSelection: .all,
            fieldFilter: .sky,
            rarityFilter: .rare,
            searchQuery: "sky",
            sortMode: .number
        )

        #expect(filtered.count == 1)
        #expect(filtered.first?.speciesID == "SPC_2")
    }

    @Test
    func dexBrowserNameSearchOnlyMatchesCapturedSpecies() {
        let entries = [
            makeDexEntry(status: .captured, sortOrder: 1, speciesName: "Mossbun"),
            makeDexEntry(status: .seenUncaptured, sortOrder: 2, speciesName: "Nimbusray"),
        ]

        let capturedSearch = TokenmonDexBrowser.filteredEntries(
            entries: entries,
            statusSelection: .all,
            fieldFilter: .all,
            rarityFilter: .all,
            searchQuery: "Mossbun",
            sortMode: .number
        )
        let hiddenSearch = TokenmonDexBrowser.filteredEntries(
            entries: entries,
            statusSelection: .all,
            fieldFilter: .all,
            rarityFilter: .all,
            searchQuery: "Nimbusray",
            sortMode: .number
        )

        #expect(capturedSearch.map(\.speciesID) == ["SPC_1"])
        #expect(hiddenSearch.isEmpty)
    }

    @Test
    func dexBrowserSortsByCapturedCountDescending() {
        let entries = [
            makeDexEntry(status: .captured, sortOrder: 1, speciesName: "First", capturedCount: 1),
            makeDexEntry(status: .captured, sortOrder: 2, speciesName: "Second", capturedCount: 4),
            makeDexEntry(status: .captured, sortOrder: 3, speciesName: "Third", capturedCount: 2),
        ]

        let sorted = TokenmonDexBrowser.filteredEntries(
            entries: entries,
            statusSelection: .all,
            fieldFilter: .all,
            rarityFilter: .all,
            searchQuery: "",
            sortMode: .capturedCount
        )

        #expect(sorted.map(\.speciesID) == ["SPC_2", "SPC_3", "SPC_1"])
    }

    @Test
    func dexBrowserSortsByAffinityDescending() {
        let entries = [
            makeDexEntry(status: .captured, sortOrder: 1, speciesName: "First", capturedCount: 9, affinityLevel: 2, affinityPityCount: 1),
            makeDexEntry(status: .captured, sortOrder: 2, speciesName: "Second", capturedCount: 3, affinityLevel: 4, affinityPityCount: 0),
            makeDexEntry(status: .captured, sortOrder: 3, speciesName: "Third", capturedCount: 2, affinityLevel: 4, affinityPityCount: 2),
            makeDexEntry(status: .seenUncaptured, sortOrder: 4, speciesName: "Seen"),
        ]

        let sorted = TokenmonDexBrowser.filteredEntries(
            entries: entries,
            statusSelection: .all,
            fieldFilter: .all,
            rarityFilter: .all,
            searchQuery: "",
            sortMode: .affinity
        )

        #expect(sorted.map(\.speciesID) == ["SPC_3", "SPC_2", "SPC_1", "SPC_4"])
    }

    @Test
    func dexPresentationBuildsCollectionProgress() {
        let entries = [
            makeDexEntry(status: .captured, sortOrder: 1),
            makeDexEntry(status: .seenUncaptured, sortOrder: 2),
            makeDexEntry(status: .unknown, sortOrder: 3),
        ]

        let progress = TokenmonDexPresentation.progress(for: entries)

        #expect(progress.total == 3)
        #expect(progress.captured == 1)
        #expect(progress.seen == 2)
        #expect(progress.hidden == 1)
        #expect(progress.summaryLine == "1 captured · 2 seen · 1 hidden")
    }

    @Test
    func dexPresentationRecentFindsPreferNewestCaptureAndSeenActivity() {
        let entries = [
            DexEntrySummary(
                speciesID: "SPC_latest_seen",
                speciesName: "Latest Seen",
                field: .sky,
                rarity: .rare,
                assetKey: "sky_latest_seen",
                flavorText: "Seen most recently.",
                sortOrder: 3,
                status: .seenUncaptured,
                seenCount: 1,
                capturedCount: 0,
                firstSeenAt: "2026-04-05T00:00:00Z",
                lastSeenAt: "2026-04-07T11:00:00Z",
                firstCapturedAt: nil,
                lastCapturedAt: nil,
                stats: SpeciesStatBlock(planning: 1, design: 1, frontend: 1, backend: 1, pm: 1, infra: 1)
            ),
            DexEntrySummary(
                speciesID: "SPC_latest_capture",
                speciesName: "Latest Capture",
                field: .grassland,
                rarity: .common,
                assetKey: "grs_latest_capture",
                flavorText: "Captured second most recently.",
                sortOrder: 2,
                status: .captured,
                seenCount: 4,
                capturedCount: 2,
                firstSeenAt: "2026-04-05T00:00:00Z",
                lastSeenAt: "2026-04-07T09:00:00Z",
                firstCapturedAt: "2026-04-05T01:00:00Z",
                lastCapturedAt: "2026-04-07T10:00:00Z",
                stats: SpeciesStatBlock(planning: 1, design: 1, frontend: 1, backend: 1, pm: 1, infra: 1)
            ),
            makeDexEntry(status: .unknown, sortOrder: 1),
        ]

        let recentFinds = TokenmonDexPresentation.recentFinds(from: entries, limit: 2)

        #expect(recentFinds.map(\.speciesID) == ["SPC_latest_seen", "SPC_latest_capture"])
    }

    @Test
    func dexPresentationHiddenSlotsStayNumberSorted() {
        let entries = [
            makeDexEntry(status: .unknown, sortOrder: 12),
            makeDexEntry(status: .unknown, sortOrder: 3),
            makeDexEntry(status: .captured, sortOrder: 2),
            makeDexEntry(status: .unknown, sortOrder: 8),
        ]

        let hidden = TokenmonDexPresentation.hiddenSlots(from: entries, limit: 3)

        #expect(hidden.map(\.sortOrder) == [3, 8, 12])
    }

    @Test
    func dexPresentationNumberedEntriesStayRosterSorted() {
        let entries = [
            makeDexEntry(status: .captured, sortOrder: 44),
            makeDexEntry(status: .unknown, sortOrder: 3),
            makeDexEntry(status: .seenUncaptured, sortOrder: 17),
        ]

        let numbered = TokenmonDexPresentation.numberedEntries(from: entries)

        #expect(numbered.map(\.sortOrder) == [3, 17, 44])
    }

    @Test
    func dexActivityItemsPreferCapturedWhenSeenAndCapturedShareEncounter() throws {
        let entries = [
            makeDexEntry(status: .captured, sortOrder: 1, speciesName: "Mossbun"),
        ]

        let seenPayload = SeenDexUpdatedEventPayload(
            speciesID: "SPC_1",
            encounterID: "enc_1",
            firstSeenCreated: true,
            seenCountBefore: 0,
            seenCountAfter: 1,
            lastSeenAtAfter: "2026-04-05T01:00:00Z"
        )
        let capturedPayload = CapturedDexUpdatedEventPayload(
            speciesID: "SPC_1",
            encounterID: "enc_1",
            firstCaptureCreated: true,
            capturedCountBefore: 0,
            capturedCountAfter: 1,
            lastCapturedAtAfter: "2026-04-05T01:00:01Z"
        )

        let records = [
            try makeDomainEventRecord(type: .seenDexUpdated, occurredAt: "2026-04-05T01:00:00Z", aggregateID: "enc_1", payload: seenPayload),
            try makeDomainEventRecord(type: .capturedDexUpdated, occurredAt: "2026-04-05T01:00:01Z", aggregateID: "enc_1", payload: capturedPayload),
        ]

        let items = TokenmonDexPresentation.activityItems(from: records, entries: entries, limit: 4)

        #expect(items.count == 1)
        #expect(items.first?.kind == .captured)
        #expect(items.first?.speciesName == "Mossbun")
    }

    @Test
    func dexActivitySummaryCountsCapturedAndRevealedItems() {
        let items = [
            TokenmonDexActivityItem(
                speciesID: "SPC_1",
                encounterID: "enc_1",
                sortOrder: 1,
                speciesName: "Mossbun",
                assetKey: "grs_001_mossbun",
                field: .grassland,
                rarity: .common,
                status: .captured,
                seenCount: 2,
                capturedCount: 1,
                kind: .captured,
                occurredAt: "2026-04-05T01:00:01Z"
            ),
            TokenmonDexActivityItem(
                speciesID: "SPC_2",
                encounterID: "enc_2",
                sortOrder: 2,
                speciesName: "Pebblequail",
                assetKey: "grs_002_pebblequail",
                field: .grassland,
                rarity: .common,
                status: .seenUncaptured,
                seenCount: 2,
                capturedCount: 0,
                kind: .revealed,
                occurredAt: "2026-04-05T01:00:02Z"
            ),
        ]

        let summary = TokenmonDexPresentation.activitySummary(from: items)

        #expect(summary.capturedCount == 1)
        #expect(summary.revealedCount == 1)
        #expect(summary.headline == "1 captured · 1 revealed")
    }

    @Test
    func dexPresentationVisibleNamesRequireCapture() {
        let hidden = makeDexEntry(status: .unknown, sortOrder: 1)
        let seen = makeDexEntry(status: .seenUncaptured, sortOrder: 2, speciesName: "Nimbusray")
        let captured = makeDexEntry(status: .captured, sortOrder: 3, speciesName: "Mossbun")

        #expect(TokenmonDexPresentation.visibleSpeciesName(for: hidden) == "???")
        #expect(TokenmonDexPresentation.visibleSpeciesName(for: seen) == "???")
        #expect(TokenmonDexPresentation.visibleSpeciesName(for: seen, style: .sentence) == "Unknown species")
        #expect(TokenmonDexPresentation.visibleSpeciesName(for: captured) == "Mossbun")
    }

    @Test
    func dexPresentationRevealStageUsesSeenThresholds() {
        let firstSeen = makeDexEntry(status: .seenUncaptured, sortOrder: 1, seenCount: 1)
        let mediumReveal = makeDexEntry(status: .seenUncaptured, sortOrder: 2, seenCount: 3)
        let lightReveal = makeDexEntry(status: .seenUncaptured, sortOrder: 3, seenCount: 4)
        let captured = makeDexEntry(status: .captured, sortOrder: 4, seenCount: 4, capturedCount: 1)

        #expect(TokenmonDexPresentation.revealStage(for: firstSeen) == .heavyBlur)
        #expect(TokenmonDexPresentation.revealStage(for: mediumReveal) == .mediumBlur)
        #expect(TokenmonDexPresentation.revealStage(for: lightReveal) == .lightBlur)
        #expect(TokenmonDexPresentation.revealStage(for: captured) == .revealed)
    }

    @Test
    func dexPresentationFlavorTextUnlockRequiresCapture() {
        let seen = makeDexEntry(status: .seenUncaptured, sortOrder: 1)
        let captured = makeDexEntry(status: .captured, sortOrder: 2)

        #expect(TokenmonDexPresentation.isFlavorTextUnlocked(for: seen) == false)
        #expect(TokenmonDexPresentation.isFlavorTextUnlocked(for: captured))
    }

    @Test
    func dexNavigationRequestCanBeReissuedForSameSpecies() {
        let first = TokenmonDexNavigationRequest(speciesID: "SPC_44")
        let second = TokenmonDexNavigationRequest(speciesID: "SPC_44")

        #expect(first.speciesID == second.speciesID)
        #expect(first.requestID != second.requestID)
    }

    @Test
    func dexPresentationMetricRowsUseHumanReadableDates() {
        let entry = makeDexEntry(status: .captured, sortOrder: 7, capturedCount: 3, affinityLevel: 2)

        let rows = TokenmonDexPresentation.metricRows(
            for: entry,
            relativeTo: Date(timeIntervalSince1970: 1_775_577_600), // 2026-04-07T00:00:00Z
            calendar: Calendar(identifier: .gregorian),
            locale: Locale(identifier: "en_US_POSIX"),
            timeZone: TimeZone(secondsFromGMT: 0)!
        )

        #expect(rows.count == 6)
        #expect(rows.contains(where: { $0.title == "Bond" }) == false)
        #expect(rows.contains(where: { $0.title == "Raid bonus" }) == false)
        #expect(rows.contains(where: { $0.title == "Captured" && $0.value == "3 times" }))
        #expect(rows.contains(where: { $0.title == "Seen" && $0.value == "2 encounters" }))
        #expect(rows.filter { $0.title.contains("seen") || $0.title.contains("captured") }
            .allSatisfy { $0.value.contains("T") == false && $0.value.contains("Z") == false })
    }

    @Test
    func dexPresentationSurfacesAffinityRaidBonus() {
        let entry = makeDexEntry(status: .captured, sortOrder: 8, capturedCount: 5, affinityLevel: 4)

        #expect(TokenmonDexPresentation.metadataLine(for: entry).contains("Training Lv.1/5"))
        #expect(TokenmonDexPresentation.metadataLine(for: entry).contains("Raid +3"))
        #expect(TokenmonDexPresentation.affinityRaidBonusValueLabel(level: 4) == "+3")
        #expect(TokenmonDexPresentation.affinityRaidBonusShortLabel(level: 2) == "Raid +1")
        #expect(TokenmonDexPresentation.affinityNextTargetLabel(for: entry) == "Bond V")
    }

    @Test
    func dexPresentationSurfacesTrainingLevelAndAbility() {
        let inactive = makeDexEntry(
            status: .captured,
            sortOrder: 28,
            field: .sky,
            rarity: .rare,
            trainingTrait: .scout,
            trainingRank: .rankI,
            trainingAttemptCount: 2
        )
        let active = makeDexEntry(
            status: .captured,
            sortOrder: 29,
            field: .sky,
            rarity: .rare,
            trainingTrait: .scout,
            trainingRank: .rankIII,
            trainingAttemptCount: 5
        )

        #expect(TokenmonDexPresentation.trainingLevelLabel(for: inactive) == "Training Lv.1/5")
        #expect(TokenmonDexPresentation.trainingLevelLabel(for: inactive, compact: true) == "Lv.1/5")
        #expect(TokenmonDexPresentation.trainingAbilityTitle(for: inactive) == "Rarity Bonus")
        #expect(TokenmonDexPresentation.trainingEffectLine(for: inactive) == "Unlocks at Training Lv.2")
        #expect(TokenmonDexPresentation.trainingAttemptLabel(for: inactive) == "2")
        #expect(TokenmonDexPresentation.metadataLine(for: active).contains("Training Lv.3/5"))
        #expect(TokenmonDexPresentation.trainingEffectLine(for: active)?.contains("Sky rarity") == true)
    }

    @Test
    func dexPresentationFormatsAffinityResultLines() {
        let success = makeEncounter(
            outcome: .captured,
            capturedCount: 2,
            affinityLevel: 2,
            affinityLastOutcome: "success"
        )
        let failure = makeEncounter(
            outcome: .captured,
            capturedCount: 3,
            affinityLevel: 2,
            affinityPityCount: 1,
            affinityLastProbability: 0.2652,
            affinityLastOutcome: "failure"
        )
        let maxed = makeEncounter(
            outcome: .captured,
            capturedCount: 8,
            affinityLevel: 5,
            affinityLastOutcome: "max_level"
        )
        let escaped = makeEncounter(outcome: .escaped)
        let entry = makeDexEntry(
            status: .captured,
            sortOrder: 30,
            capturedCount: 3,
            affinityLevel: 2,
            affinityPityCount: 1,
            affinityLastProbability: 0.2652
        )

        #expect(TokenmonDexPresentation.affinityResultLine(for: success) == "Bond II reached")
        #expect(TokenmonDexPresentation.affinityResultLine(for: failure) == "Bond buffer 1/4")
        #expect(TokenmonDexPresentation.affinityResonanceLabel(for: entry) == "Bond buffer 1/4")
        #expect(TokenmonDexPresentation.affinityResultLine(for: maxed) == "Max bond")
        #expect(TokenmonDexPresentation.affinityResultLine(for: escaped) == nil)
    }

    @Test
    func dexPresentationHiddenHintIncludesFieldAndRarity() {
        let entry = makeDexEntry(status: .unknown, sortOrder: 9, field: .coast, rarity: .legendary)

        let hint = TokenmonDexPresentation.hiddenHint(for: entry)

        #expect(hint.contains("legendary"))
        #expect(hint.contains("Coast"))
    }

    @Test
    func dexPresentationStatVisibilityMatchesRevealState() {
        let hidden = makeDexEntry(status: .unknown, sortOrder: 1)
        let seen = makeDexEntry(status: .seenUncaptured, sortOrder: 2)
        let captured = makeDexEntry(status: .captured, sortOrder: 3, traits: ["Visionary"])

        #expect(TokenmonDexPresentation.showsStatTotal(for: hidden) == false)
        #expect(TokenmonDexPresentation.showsStatTotal(for: seen))
        #expect(TokenmonDexPresentation.showsStatTotal(for: captured))
        #expect(TokenmonDexPresentation.showsFullStatPlate(for: hidden) == false)
        #expect(TokenmonDexPresentation.showsFullStatPlate(for: seen) == false)
        #expect(TokenmonDexPresentation.showsFullStatPlate(for: captured))
        #expect(TokenmonDexPresentation.showsTraitTags(for: hidden) == false)
        #expect(TokenmonDexPresentation.showsTraitTags(for: seen) == false)
        #expect(TokenmonDexPresentation.showsTraitTags(for: captured))
    }

    @Test
    func dexPresentationFieldNotesPlaceholderMatchesRevealState() {
        let hidden = makeDexEntry(status: .unknown, sortOrder: 4, field: .sky, rarity: .epic)
        let seen = makeDexEntry(status: .seenUncaptured, sortOrder: 5)
        let captured = makeDexEntry(status: .captured, sortOrder: 6)

        #expect(TokenmonDexPresentation.fieldNotesPlaceholder(for: hidden)?.contains("Encounter this species once") == true)
        #expect(TokenmonDexPresentation.fieldNotesPlaceholder(for: seen)?.contains("Capture this species") == true)
        #expect(TokenmonDexPresentation.fieldNotesPlaceholder(for: captured) == nil)
        #expect(TokenmonDexPresentation.progressPanelTitle(for: hidden) == "Reveal Conditions")
        #expect(TokenmonDexPresentation.progressPanelTitle(for: seen) == "Progress")
    }

    @Test
    func dexAlbumStyleEmphasizesLegendaryCardsMoreThanCommon() {
        let common = TokenmonDexAlbumStyle.make(for: .common)
        let epic = TokenmonDexAlbumStyle.make(for: .epic)
        let legendary = TokenmonDexAlbumStyle.make(for: .legendary)

        #expect(legendary.emphasisLevel > common.emphasisLevel)
        #expect(legendary.emphasisLevel > epic.emphasisLevel)
        #expect(legendary.borderOpacity > common.borderOpacity)
        #expect(legendary.borderOpacity > epic.borderOpacity)
        #expect(legendary.glowOpacity > common.glowOpacity)
        #expect(epic.rarityFillOpacity > common.rarityFillOpacity)
        #expect(legendary.rarityFillOpacity > epic.rarityFillOpacity)
        #expect(legendary.primarySymbol == "crown.fill")
    }

    @Test
    func dexDetailCardStyleScalesEffectBudgetWithRarity() {
        let common = TokenmonDexDetailCardStyle.make(for: .common)
        let uncommon = TokenmonDexDetailCardStyle.make(for: .uncommon)
        let rare = TokenmonDexDetailCardStyle.make(for: .rare)
        let epic = TokenmonDexDetailCardStyle.make(for: .epic)
        let legendary = TokenmonDexDetailCardStyle.make(for: .legendary)

        #expect(legendary.glareOpacity > common.glareOpacity)
        #expect(rare.glareOpacity > uncommon.glareOpacity)
        #expect(legendary.frameHighlight > common.frameHighlight)
        #expect(legendary.shadowOpacity > common.shadowOpacity)
        #expect(legendary.hoverShadowBoost > common.hoverShadowBoost)
        #expect(legendary.holoOpacity > common.holoOpacity)
        #expect(legendary.holoGlareIntensity > common.holoGlareIntensity)
        #expect(legendary.sparkleCount > epic.sparkleCount)
        #expect(legendary.tiltStrength > common.tiltStrength)
        #expect(common.shimmerOpacity == 0)
        #expect(rare.shimmerOpacity == 0)
        #expect(epic.shimmerOpacity == 0)
        #expect(legendary.shimmerOpacity == 0)
        #expect(uncommon.shellCenterProtection < 0.025)
        #expect(legendary.shellCenterProtection > common.shellCenterProtection)
        #expect(legendary.artBackplateOpacity > common.artBackplateOpacity)
        #expect(legendary.artGlareOpacity > uncommon.artGlareOpacity)
        #expect(legendary.artGlareWidth > uncommon.artGlareWidth)
        #expect(common.shimmerAllowed == false)
        #expect(uncommon.shimmerAllowed == false)
        #expect(rare.shimmerAllowed)
        #expect(rare.shimmerZone == .perimeter)
        #expect(epic.shimmerZone == .perimeter)
        #expect(legendary.shimmerZone == .perimeter)
        #expect(rare.pulseAllowed == false)
        #expect(epic.pulseAllowed)
        #expect(legendary.pulseAllowed)
    }

    @Test
    func dexDetailCardPremiumEffectsRequireCapture() {
        #expect(DexEntryStatus.unknown.allowsPremiumDexDetailCardEffects == false)
        #expect(DexEntryStatus.seenUncaptured.allowsPremiumDexDetailCardEffects == false)
        #expect(DexEntryStatus.captured.allowsPremiumDexDetailCardEffects)
    }

    @Test
    func unknownDexSpriteUsesSpeciesSilhouetteWhenPortraitExists() {
        #expect(TokenmonDexSpriteContent.resolve(revealStage: .silhouette, portraitAvailable: false) == .mystery)
        #expect(TokenmonDexSpriteContent.resolve(revealStage: .silhouette, portraitAvailable: true) == .speciesPortrait)
        #expect(TokenmonDexSpriteContent.resolve(revealStage: .revealed, portraitAvailable: true) == .speciesPortrait)
        #expect(TokenmonDexSpriteContent.resolve(revealStage: .mediumBlur, portraitAvailable: false) == .fallback)
    }

    @Test
    func recentEncounterSummariesIncludeSeenAndCapturedDexCounts() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let databasePath = directory.appendingPathComponent("tokenmon.sqlite").path
        let manager = TokenmonDatabaseManager(path: databasePath)
        try manager.bootstrap()

        _ = try manager.forgeEncounter(
            TokenmonDeveloperEncounterForgeRequest(
                provider: .codex,
                field: .sky,
                rarity: .uncommon,
                speciesID: "SKY_012",
                outcome: .captured,
                occurredAt: "2026-04-05T00:00:00Z"
            )
        )
        _ = try manager.forgeEncounter(
            TokenmonDeveloperEncounterForgeRequest(
                provider: .codex,
                field: .sky,
                rarity: .uncommon,
                speciesID: "SKY_012",
                outcome: .escaped,
                occurredAt: "2026-04-05T00:05:00Z"
            )
        )

        let latestEncounter = try #require(manager.recentEncounterSummaries(limit: 1).first)

        #expect(latestEncounter.speciesID == "SKY_012")
        #expect(latestEncounter.outcome == .escaped)
        #expect(latestEncounter.seenCount == 2)
        #expect(latestEncounter.capturedCount == 1)
    }

    @Test
    func speciesSpriteLoaderReportsFullVariantCoverageForCatalog() {
        let missingExports = SpeciesCatalog.all.flatMap { species in
            TokenmonSpeciesSpriteVariant.allCases.compactMap { variant in
                TokenmonSpeciesSpriteLoader.hasImage(assetKey: species.assetKey, variant: variant)
                    ? nil
                    : "\(species.id):\(variant.rawValue)"
            }
        }

        #expect(missingExports.isEmpty)
    }

    @Test
    func unknownDexStatusUsesHiddenCopy() {
        #expect(DexEntryStatus.unknown.detailTitle == "Hidden")
    }

    @Test
    func buildInfoFormatsVersionAndRevisionForLocalWorkspace() {
        let info = TokenmonBuildInfo(
            marketingVersion: nil,
            buildNumber: nil,
            branch: "codex/dex-unknown-mystery-state",
            commitShortHash: "fa7a55e",
            hasLocalModifications: true,
            buildConfiguration: .debug
        )

        #expect(info.versionSummary == "Workspace build")
        #expect(info.revisionSummary == "codex/dex-unknown-mystery-state @ fa7a55e + local edits")
        #expect(info.toolbarLabel == "dev · fa7a55e+")
    }

    @Test
    func buildInfoFormatsReleaseMetadataWhenAvailable() {
        let info = TokenmonBuildInfo(
            marketingVersion: "0.1.0",
            buildNumber: "1",
            branch: "main",
            commitShortHash: "fa7a55e",
            hasLocalModifications: false,
            buildConfiguration: .release
        )

        #expect(info.versionSummary == "v0.1.0 (1)")
        #expect(info.revisionSummary == "main @ fa7a55e")
        #expect(info.toolbarLabel == "v0.1.0 · fa7a55e")
    }

    @Test
    func buildInfoFormatsBuildTimestampFromExecutableDate() throws {
        let buildDate = try #require(
            ISO8601DateFormatter().date(from: "2026-04-12T08:15:30Z")
        )
        let info = TokenmonBuildInfo(
            marketingVersion: "0.1.0",
            buildNumber: "1",
            branch: "main",
            commitShortHash: "fa7a55e",
            hasLocalModifications: false,
            buildConfiguration: .release,
            buildDate: buildDate
        )

        #expect(info.formattedBuildTimestamp(timeZone: TimeZone(secondsFromGMT: 0)!) == "2026-04-12 08:15:30 GMT")
        #expect(info.toolbarBadgeLabel(timeZone: TimeZone(secondsFromGMT: 0)!) == "v0.1.0 · fa7a55e · 04-12 08:15")
        #expect(info.accessibilityLabel.contains("built "))
    }

    @Test
    func buildInfoShowsDeveloperToolsOnlyForDebugBuilds() {
        let debug = TokenmonBuildInfo(
            marketingVersion: "0.1.0",
            buildNumber: "1",
            branch: "main",
            commitShortHash: "fa7a55e",
            hasLocalModifications: false,
            buildConfiguration: .debug
        )
        let release = TokenmonBuildInfo(
            marketingVersion: "0.1.0",
            buildNumber: "1",
            branch: "main",
            commitShortHash: "fa7a55e",
            hasLocalModifications: false,
            buildConfiguration: .release
        )

        #expect(debug.developerToolsVisible == true)
        #expect(release.developerToolsVisible == false)
    }

    @Test
    func codexProviderInstallIsAutomaticAndLeavesConfigUntouched() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let home = directory.appendingPathComponent("home", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let codexDirectory = home.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: codexDirectory, withIntermediateDirectories: true)

        let configPath = codexDirectory.appendingPathComponent("config.toml")
        try "[features]\nmulti_agent = true\n".write(to: configPath, atomically: true, encoding: .utf8)

        let databasePath = directory.appendingPathComponent("tokenmon.sqlite").path
        try TokenmonDatabaseManager(path: databasePath).bootstrap()

        let originalOverride = ProcessInfo.processInfo.environment["TOKENMON_HOME_OVERRIDE"]
        setenv("TOKENMON_HOME_OVERRIDE", home.path, 1)
        defer {
            if let originalOverride {
                setenv("TOKENMON_HOME_OVERRIDE", originalOverride, 1)
            } else {
                unsetenv("TOKENMON_HOME_OVERRIDE")
            }
        }

        let result = try TokenmonProviderOnboarding.install(
            provider: .codex,
            databasePath: databasePath,
            executablePath: "/tmp/TokenmonApp",
            preferences: ProviderInstallationPreferences()
        )

        let configContents = try String(contentsOf: configPath, encoding: .utf8)

        #expect(result.message.contains("automatic"))
        #expect(configContents.contains("multi_agent = true"))
        #expect(configContents.contains("codex_hooks = true") == false)
        #expect(FileManager.default.fileExists(atPath: codexDirectory.appendingPathComponent("hooks.json").path) == false)
    }

    @Test
    func codexOnboardingTreatsLegacyHooksAsOptional() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let home = directory.appendingPathComponent("home", isDirectory: true)
        let codexDirectory = home.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: codexDirectory, withIntermediateDirectories: true)
        try "[features]\ncodex_hooks = true\n".write(
            to: codexDirectory.appendingPathComponent("config.toml"),
            atomically: true,
            encoding: .utf8
        )
        try """
        {
          "hooks": {
            "SessionStart": [
              {
                "hooks": [
                  {
                    "type": "command",
                    "command": "tokenmon --tokenmon-provider-codex-hook-import --db /tmp/tokenmon.sqlite"
                  }
                ]
              }
            ]
          }
        }
        """.write(
            to: codexDirectory.appendingPathComponent("hooks.json"),
            atomically: true,
            encoding: .utf8
        )

        let databasePath = directory.appendingPathComponent("tokenmon.sqlite").path
        try TokenmonDatabaseManager(path: databasePath).bootstrap()

        let originalOverride = ProcessInfo.processInfo.environment["TOKENMON_HOME_OVERRIDE"]
        let originalPath = ProcessInfo.processInfo.environment["PATH"]
        let fakeBinDirectory = directory.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: fakeBinDirectory, withIntermediateDirectories: true)
        let fakeCodexPath = fakeBinDirectory.appendingPathComponent("codex")
        try "#!/bin/sh\nexit 0\n".write(to: fakeCodexPath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: fakeCodexPath.path
        )

        setenv("TOKENMON_HOME_OVERRIDE", home.path, 1)
        if let originalPath {
            setenv("PATH", "\(fakeBinDirectory.path):\(originalPath)", 1)
        } else {
            setenv("PATH", fakeBinDirectory.path, 1)
        }
        defer {
            if let originalOverride {
                setenv("TOKENMON_HOME_OVERRIDE", originalOverride, 1)
            } else {
                unsetenv("TOKENMON_HOME_OVERRIDE")
            }
            if let originalPath {
                setenv("PATH", originalPath, 1)
            } else {
                unsetenv("PATH")
            }
        }

        let statuses = TokenmonProviderOnboarding.inspectAll(
            databasePath: databasePath,
            executablePath: "/tmp/TokenmonApp",
            preferences: ProviderInstallationPreferences()
        )
        let codexStatus = try #require(statuses.first(where: { $0.provider == .codex }))

        #expect(codexStatus.isConnected)
        #expect(codexStatus.isPartial == false)
        #expect(codexStatus.title == "Codex ready")
        #expect(codexStatus.actionTitle == nil)
    }

    @Test
    func autoConfigureDetectedProvidersLeavesClaudeSettingsUntouchedAndSetsUpGemini() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let home = directory.appendingPathComponent("home", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let claudeDirectory = home.appendingPathComponent(".claude", isDirectory: true)
        let geminiDirectory = home.appendingPathComponent(".gemini", isDirectory: true)
        try FileManager.default.createDirectory(at: claudeDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: geminiDirectory, withIntermediateDirectories: true)

        try """
        {
          "telemetry": {
            "enabled": true,
            "target": "gcp",
            "otlpEndpoint": "honeycomb.io:4317"
          }
        }
        """.write(
            to: geminiDirectory.appendingPathComponent("settings.json"),
            atomically: true,
            encoding: .utf8
        )

        let fakeBinDirectory = directory.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: fakeBinDirectory, withIntermediateDirectories: true)
        let fakeClaudePath = fakeBinDirectory.appendingPathComponent("claude")
        let fakeGeminiPath = fakeBinDirectory.appendingPathComponent("gemini")
        try "#!/bin/sh\nexit 0\n".write(to: fakeClaudePath, atomically: true, encoding: .utf8)
        try "#!/bin/sh\nexit 0\n".write(to: fakeGeminiPath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeClaudePath.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeGeminiPath.path)

        let databasePath = directory.appendingPathComponent("tokenmon.sqlite").path
        try TokenmonDatabaseManager(path: databasePath).bootstrap()

        let originalOverride = ProcessInfo.processInfo.environment["TOKENMON_HOME_OVERRIDE"]
        let originalPath = ProcessInfo.processInfo.environment["PATH"]
        setenv("TOKENMON_HOME_OVERRIDE", home.path, 1)
        if let originalPath {
            setenv("PATH", "\(fakeBinDirectory.path):\(originalPath)", 1)
        } else {
            setenv("PATH", fakeBinDirectory.path, 1)
        }
        defer {
            if let originalOverride {
                setenv("TOKENMON_HOME_OVERRIDE", originalOverride, 1)
            } else {
                unsetenv("TOKENMON_HOME_OVERRIDE")
            }
            if let originalPath {
                setenv("PATH", originalPath, 1)
            } else {
                unsetenv("PATH")
            }
        }

        let results = TokenmonProviderOnboarding.autoConfigureDetectedProviders(
            databasePath: databasePath,
            executablePath: "/tmp/TokenmonApp",
            preferences: ProviderInstallationPreferences()
        )

        let claudeResult = try #require(results.first(where: { $0.provider == .claude }))
        let geminiResult = try #require(results.first(where: { $0.provider == .gemini }))
        let geminiSettings = try String(contentsOf: geminiDirectory.appendingPathComponent("settings.json"), encoding: .utf8)

        #expect(claudeResult.configured)
        #expect(geminiResult.configured)
        #expect(FileManager.default.fileExists(atPath: claudeDirectory.appendingPathComponent("settings.json").path) == false)
        #expect(FileManager.default.fileExists(atPath: claudeDirectory.appendingPathComponent("tokenmon-statusline.sh").path) == false)
        #expect(geminiSettings.contains("\"otlpEndpoint\""))
        #expect(geminiSettings.contains("127.0.0.1:4317"))
        #expect(geminiSettings.contains("honeycomb.io:4317") == false)
    }

    @Test
    func autoConfigureDetectedProvidersPreservesUserClaudeStatusLine() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let home = directory.appendingPathComponent("home", isDirectory: true)
        let claudeDirectory = home.appendingPathComponent(".claude", isDirectory: true)
        try FileManager.default.createDirectory(at: claudeDirectory, withIntermediateDirectories: true)

        let originalSettings = """
        {
          "statusLine": {
            "type": "command",
            "command": "~/.claude/user-hud.sh",
            "padding": 2,
            "refreshInterval": 5
          }
        }
        """
        let settingsPath = claudeDirectory.appendingPathComponent("settings.json")
        try originalSettings.write(to: settingsPath, atomically: true, encoding: .utf8)

        let fakeBinDirectory = directory.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: fakeBinDirectory, withIntermediateDirectories: true)
        let fakeClaudePath = fakeBinDirectory.appendingPathComponent("claude")
        try "#!/bin/sh\nexit 0\n".write(to: fakeClaudePath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeClaudePath.path)

        let databasePath = directory.appendingPathComponent("tokenmon.sqlite").path
        try TokenmonDatabaseManager(path: databasePath).bootstrap()

        let originalOverride = ProcessInfo.processInfo.environment["TOKENMON_HOME_OVERRIDE"]
        let originalPath = ProcessInfo.processInfo.environment["PATH"]
        setenv("TOKENMON_HOME_OVERRIDE", home.path, 1)
        if let originalPath {
            setenv("PATH", "\(fakeBinDirectory.path):\(originalPath)", 1)
        } else {
            setenv("PATH", fakeBinDirectory.path, 1)
        }
        defer {
            if let originalOverride {
                setenv("TOKENMON_HOME_OVERRIDE", originalOverride, 1)
            } else {
                unsetenv("TOKENMON_HOME_OVERRIDE")
            }
            if let originalPath {
                setenv("PATH", originalPath, 1)
            } else {
                unsetenv("PATH")
            }
        }

        let results = TokenmonProviderOnboarding.autoConfigureDetectedProviders(
            databasePath: databasePath,
            executablePath: "/tmp/TokenmonApp",
            preferences: ProviderInstallationPreferences()
        )

        let claudeResult = try #require(results.first(where: { $0.provider == .claude }))
        let updatedSettings = try String(contentsOf: settingsPath, encoding: .utf8)

        #expect(claudeResult.configured)
        #expect(updatedSettings == originalSettings)
        #expect(FileManager.default.fileExists(atPath: claudeDirectory.appendingPathComponent("tokenmon-statusline.sh").path) == false)
    }

    @Test
    func claudeInstallLeavesExistingStatusLineSettingsUntouched() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let claudeDirectory = directory.appendingPathComponent(".claude", isDirectory: true)
        try FileManager.default.createDirectory(at: claudeDirectory, withIntermediateDirectories: true)

        let settingsPath = claudeDirectory.appendingPathComponent("settings.json")
        let originalSettings = """
        {
          "statusLine": {
            "type": "command",
            "command": "~/.claude/user-statusline.sh",
            "padding": 2,
            "refreshInterval": 5
          }
        }
        """
        try originalSettings.write(to: settingsPath, atomically: true, encoding: .utf8)

        var preferences = ProviderInstallationPreferences()
        preferences.setConfigurationPath(claudeDirectory.path, for: .claude)

        let databasePath = directory.appendingPathComponent("tokenmon.sqlite").path
        try TokenmonDatabaseManager(path: databasePath).bootstrap()
        _ = try TokenmonProviderOnboarding.install(
            provider: .claude,
            databasePath: databasePath,
            executablePath: "/tmp/TokenmonApp",
            preferences: preferences
        )

        let updatedSettings = try String(contentsOf: settingsPath, encoding: .utf8)
        #expect(updatedSettings == originalSettings)
        #expect(FileManager.default.fileExists(atPath: claudeDirectory.appendingPathComponent("tokenmon-statusline.sh").path) == false)
    }

    @Test
    func claudeInstallPreservesExternalOtelWithoutAddingStatusLine() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let claudeDirectory = directory.appendingPathComponent(".claude", isDirectory: true)
        try FileManager.default.createDirectory(at: claudeDirectory, withIntermediateDirectories: true)

        let settingsPath = claudeDirectory.appendingPathComponent("settings.json")
        let originalSettings = """
        {
          "env": {
            "CLAUDE_CODE_ENABLE_TELEMETRY": "1",
            "OTEL_LOGS_EXPORTER": "otlp",
            "OTEL_EXPORTER_OTLP_ENDPOINT": "https://observability.example.com:4317",
            "OTEL_EXPORTER_OTLP_HEADERS": "authorization=Bearer secret"
          }
        }
        """
        try originalSettings.write(to: settingsPath, atomically: true, encoding: .utf8)

        var preferences = ProviderInstallationPreferences()
        preferences.setConfigurationPath(claudeDirectory.path, for: .claude)

        let databasePath = directory.appendingPathComponent("tokenmon.sqlite").path
        try TokenmonDatabaseManager(path: databasePath).bootstrap()
        let result = try TokenmonProviderOnboarding.install(
            provider: .claude,
            databasePath: databasePath,
            executablePath: "/tmp/TokenmonApp",
            preferences: preferences
        )

        let updatedSettings = try String(contentsOf: settingsPath, encoding: .utf8)
        #expect(result.message.contains("transcript"))
        #expect(updatedSettings == originalSettings)
        #expect(FileManager.default.fileExists(atPath: claudeDirectory.appendingPathComponent("tokenmon-statusline.sh").path) == false)
    }

    @Test
    func claudeInstallPreservesTokenmonOwnedOtelInsteadOfRepairingAutomatically() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let claudeDirectory = directory.appendingPathComponent(".claude", isDirectory: true)
        try FileManager.default.createDirectory(at: claudeDirectory, withIntermediateDirectories: true)

        let fakeClaudeExecutable = directory.appendingPathComponent("claude")
        try "#!/bin/sh\nexit 0\n".write(to: fakeClaudeExecutable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeClaudeExecutable.path)

        let settingsPath = claudeDirectory.appendingPathComponent("settings.json")
        try """
        {
          "env": {
            "CLAUDE_CODE_ENABLE_TELEMETRY": "1",
            "OTEL_LOGS_EXPORTER": "otlp",
            "OTEL_METRICS_EXPORTER": "none",
            "OTEL_TRACES_EXPORTER": "none",
            "OTEL_EXPORTER_OTLP_PROTOCOL": "grpc",
            "OTEL_EXPORTER_OTLP_ENDPOINT": "http://127.0.0.1:4317",
            "EXAMPLE_ENV": "preserve-me"
          },
          "statusLine": {
            "type": "command",
            "command": "'/tmp/TokenmonApp' --tokenmon-provider-claude-statusline-import --db '/tmp/tokenmon.sqlite' --metadata-only",
            "padding": 0
          }
        }
        """.write(to: settingsPath, atomically: true, encoding: .utf8)

        var preferences = ProviderInstallationPreferences()
        preferences.setExecutablePath(fakeClaudeExecutable.path, for: .claude)
        preferences.setConfigurationPath(claudeDirectory.path, for: .claude)

        let databasePath = directory.appendingPathComponent("tokenmon.sqlite").path
        try TokenmonDatabaseManager(path: databasePath).bootstrap()

        let statuses = TokenmonProviderOnboarding.inspectAll(
            databasePath: databasePath,
            executablePath: "/tmp/TokenmonApp",
            preferences: preferences
        )
        let claudeStatus = try #require(statuses.first(where: { $0.provider == .claude }))
        #expect(claudeStatus.isConnected)
        #expect(claudeStatus.isPartial == false)
        #expect(claudeStatus.actionTitle == nil)

        _ = try TokenmonProviderOnboarding.install(
            provider: .claude,
            databasePath: databasePath,
            executablePath: "/tmp/TokenmonApp",
            preferences: preferences
        )

        let settingsData = try Data(contentsOf: settingsPath)
        let settings = try #require(try JSONSerialization.jsonObject(with: settingsData) as? [String: Any])
        let env = try #require(settings["env"] as? [String: Any])
        let statusLine = try #require(settings["statusLine"] as? [String: Any])
        let wrapperCommand = try #require(statusLine["command"] as? String)

        #expect(env["EXAMPLE_ENV"] as? String == "preserve-me")
        #expect(env["CLAUDE_CODE_ENABLE_TELEMETRY"] as? String == "1")
        #expect(env["OTEL_LOGS_EXPORTER"] as? String == "otlp")
        #expect(env["OTEL_EXPORTER_OTLP_ENDPOINT"] as? String == "http://127.0.0.1:4317")
        #expect(statusLine["padding"] as? Int == 0)
        #expect(wrapperCommand.contains("--metadata-only"))
        #expect(FileManager.default.fileExists(atPath: claudeDirectory.appendingPathComponent("tokenmon-statusline.sh").path) == false)
    }

    @Test
    func claudeInstallDoesNotRecoverOrRewriteStatusLineBackup() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let claudeDirectory = directory.appendingPathComponent(".claude", isDirectory: true)
        try FileManager.default.createDirectory(at: claudeDirectory, withIntermediateDirectories: true)

        let previousStatusLine = claudeDirectory.appendingPathComponent("statusline.sh")
        try """
        #!/bin/sh
        cat >/dev/null
        printf 'BACKUP USER STATUS\\n'
        """.write(to: previousStatusLine, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: previousStatusLine.path)

        let previousCommand = "'\(previousStatusLine.path)'"
        let settingsPath = claudeDirectory.appendingPathComponent("settings.json")
        try """
        {
          "statusLine": {
            "type": "command",
            "command": "'/tmp/TokenmonApp' --tokenmon-provider-claude-statusline-import --db '/tmp/tokenmon.sqlite'",
            "padding": 0
          }
        }
        """.write(to: settingsPath, atomically: true, encoding: .utf8)
        try """
        {
          "statusLine": {
            "type": "command",
            "command": "\(previousCommand)",
            "padding": 2
          }
        }
        """.write(
            to: claudeDirectory.appendingPathComponent("settings.json.tokenmon-backup"),
            atomically: true,
            encoding: .utf8
        )

        var preferences = ProviderInstallationPreferences()
        preferences.setConfigurationPath(claudeDirectory.path, for: .claude)

        let databasePath = directory.appendingPathComponent("tokenmon.sqlite").path
        try TokenmonDatabaseManager(path: databasePath).bootstrap()
        _ = try TokenmonProviderOnboarding.install(
            provider: .claude,
            databasePath: databasePath,
            executablePath: "/tmp/TokenmonApp",
            preferences: preferences
        )

        let claudeSettings = try String(contentsOf: settingsPath, encoding: .utf8)
        let rawSettings = try JSONSerialization.jsonObject(with: Data(claudeSettings.utf8))
        let settings = try #require(rawSettings as? [String: Any])
        let statusLine = try #require(settings["statusLine"] as? [String: Any])
        let wrapperCommand = try #require(statusLine["command"] as? String)

        #expect(wrapperCommand == "'/tmp/TokenmonApp' --tokenmon-provider-claude-statusline-import --db '/tmp/tokenmon.sqlite'")
        #expect(FileManager.default.fileExists(atPath: claudeDirectory.appendingPathComponent("tokenmon-statusline.sh").path) == false)
    }

    @Test
    func providerOnboardingUsesCustomPathOverrides() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let customClaudeDirectory = directory.appendingPathComponent("custom-claude", isDirectory: true)
        let customCodexDirectory = directory.appendingPathComponent("custom-codex", isDirectory: true)
        try FileManager.default.createDirectory(at: customClaudeDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: customCodexDirectory, withIntermediateDirectories: true)

        let fakeClaudeExecutable = directory.appendingPathComponent("claude")
        let fakeCodexExecutable = directory.appendingPathComponent("codex")
        try "#!/bin/sh\nexit 0\n".write(to: fakeClaudeExecutable, atomically: true, encoding: .utf8)
        try "#!/bin/sh\nexit 0\n".write(to: fakeCodexExecutable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeClaudeExecutable.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeCodexExecutable.path)

        var preferences = ProviderInstallationPreferences()
        preferences.setExecutablePath(fakeClaudeExecutable.path, for: .claude)
        preferences.setConfigurationPath(customClaudeDirectory.path, for: .claude)
        preferences.setExecutablePath(fakeCodexExecutable.path, for: .codex)
        preferences.setConfigurationPath(customCodexDirectory.path, for: .codex)

        let databasePath = directory.appendingPathComponent("tokenmon.sqlite").path
        try TokenmonDatabaseManager(path: databasePath).bootstrap()

        let statuses = TokenmonProviderOnboarding.inspectAll(
            databasePath: databasePath,
            executablePath: "/tmp/TokenmonApp",
            preferences: preferences
        )
        let claudeStatus = try #require(statuses.first(where: { $0.provider == .claude }))
        let codexStatus = try #require(statuses.first(where: { $0.provider == .codex }))

        #expect(claudeStatus.executablePath == fakeClaudeExecutable.path)
        #expect(claudeStatus.usesCustomExecutablePath)
        #expect(claudeStatus.configurationPath == customClaudeDirectory.path)
        #expect(codexStatus.executablePath == fakeCodexExecutable.path)
        #expect(codexStatus.usesCustomConfigurationPath)
        #expect(codexStatus.configurationPath == customCodexDirectory.path)
    }

    @Test
    func codexStopHookQueuesBackfillUntilAppScanProcessesIt() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let databasePath = directory.appendingPathComponent("tokenmon.sqlite").path
        let manager = TokenmonDatabaseManager(path: databasePath)
        try manager.bootstrap()
        try manager.resetProgress(startedAt: "2000-01-01T00:00:00Z")
        _ = try SpeciesSeeder.seed(databasePath: databasePath)

        let stopPayload = CodexHookPayload(
            sessionID: "codex_transcript_fixture",
            transcriptPath: "Fixtures/CodexTranscript/token-counts.jsonl",
            cwd: "/tmp/tokenmon-fixture",
            hookEventName: "Stop",
            model: "gpt-5.4",
            message: nil
        )

        let result = try CodexHookEnrichmentStore.apply(
            databasePath: databasePath,
            payload: stopPayload
        )

        #expect(result.transcriptBackfillStatus == "queued")
        #expect(try manager.summary().usageSamples == 0)
        #expect(try ProviderBackfillRequestQueue.pendingRequests(databasePath: databasePath).count == 1)

        TokenmonInboxMonitor(databasePath: databasePath).performInitialScan()

        #expect(try manager.summary().usageSamples == 2)
        #expect(try ProviderBackfillRequestQueue.pendingRequests(databasePath: databasePath).isEmpty)
    }

    @Test
    func codexSessionStartResolvesTranscriptPathFromSessionStorage() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let databasePath = directory.appendingPathComponent("tokenmon.sqlite").path
        let manager = TokenmonDatabaseManager(path: databasePath)
        try manager.bootstrap()

        let codexHome = directory.appendingPathComponent("codex-home", isDirectory: true)
        let transcriptPath = codexHome
            .appendingPathComponent("sessions/2026/04/10", isDirectory: true)
            .appendingPathComponent("rollout-2026-04-10T10-27-42-session-storage-match.jsonl")
            .resolvingSymlinksInPath()
            .path
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: transcriptPath).deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try writeTranscriptLines(
            [codexSessionMetaLine(sessionID: "session-storage-match")],
            to: transcriptPath
        )

        let originalCodexHome = ProcessInfo.processInfo.environment["CODEX_HOME"]
        setenv("CODEX_HOME", codexHome.path, 1)
        defer {
            if let originalCodexHome {
                setenv("CODEX_HOME", originalCodexHome, 1)
            } else {
                unsetenv("CODEX_HOME")
            }
        }

        let payload = CodexHookPayload(
            sessionID: "session-storage-match",
            transcriptPath: nil,
            cwd: "/tmp/tokenmon-fixture",
            hookEventName: "SessionStart",
            model: "gpt-5.4",
            message: nil
        )

        _ = try CodexHookEnrichmentStore.apply(
            databasePath: databasePath,
            payload: payload
        )

        let database = try manager.open()
        let storedTranscriptPath = try database.fetchOne(
            """
            SELECT transcript_path
            FROM provider_sessions
            WHERE provider_code = ? AND provider_session_id = ?
            LIMIT 1;
            """,
            bindings: [.text(ProviderCode.codex.rawValue), .text("session-storage-match")]
        ) { statement in
            SQLiteDatabase.columnOptionalText(statement, index: 0)
        } ?? nil

        #expect(
            URL(fileURLWithPath: storedTranscriptPath ?? "").resolvingSymlinksInPath().path ==
                URL(fileURLWithPath: transcriptPath).resolvingSymlinksInPath().path
        )
    }

    @Test
    func codexSessionStoreRecoveryRecoversExistingSessionForDashboardOnly() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let databasePath = directory.appendingPathComponent("tokenmon.sqlite").path
        let manager = TokenmonDatabaseManager(path: databasePath)
        try manager.bootstrap()
        try manager.resetProgress(startedAt: "2000-01-01T00:00:00Z")
        try manager.markLiveGameplayStarted(at: "2026-04-10T10:29:00Z")
        _ = try SpeciesSeeder.seed(databasePath: databasePath)

        let sessionsRootPath = directory.appendingPathComponent("codex-home/sessions", isDirectory: true)
        let transcriptPath = sessionsRootPath
            .appendingPathComponent("2026/04/10", isDirectory: true)
            .appendingPathComponent("rollout-2026-04-10T10-20-00-recovery-session.jsonl")
            .path
        try FileManager.default.createDirectory(
            at: transcriptPath.deletingLastPathComponentURL,
            withIntermediateDirectories: true
        )
        try writeTranscriptLines(
            [
                codexSessionMetaLine(sessionID: "recovery-session"),
                codexTokenCountLine(
                    timestamp: "2026-04-10T10:25:00Z",
                    inputTokens: 1_000,
                    cachedInputTokens: 100,
                    outputTokens: 400,
                    lastInputTokens: 1_000,
                    lastOutputTokens: 400
                ),
            ],
            to: transcriptPath
        )

        let result = try CodexSessionStoreRecoveryService.run(
            databasePath: databasePath,
            sessionsRootPath: sessionsRootPath.path
        )

        let summary = try manager.summary()
        let currentRun = try manager.currentRunSummary()
        let database = try manager.open()
        let checkpointOffset = try database.fetchOne(
            """
            SELECT last_offset
            FROM ingest_sources
            WHERE source_key LIKE ?
            LIMIT 1;
            """,
            bindings: [.text("%recovery-session.jsonl")]
        ) { statement in
            SQLiteDatabase.columnInt64(statement, index: 0)
        }

        #expect(result.filesScanned == 1)
        #expect(result.filesRecovered == 1)
        #expect(result.samplesCreated == 1)
        #expect(result.errorsCount == 0)
        #expect(summary.usageSamples == 1)
        #expect(summary.totalNormalizedTokens == 0)
        #expect(summary.tokensSinceLastEncounter == 0)
        #expect(currentRun.usageSamples == 0)
        #expect(try manager.tokenUsageTotals().allTimeTokens == 1_400)
        #expect(checkpointOffset != nil)
        #expect(FileManager.default.fileExists(atPath: TokenmonDatabaseManager.inboxPath(provider: .codex, databasePath: databasePath)) == false)
    }

    @Test
    func recentProviderSessionsExcludeHookOnlyMetadataRows() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let databasePath = directory.appendingPathComponent("tokenmon.sqlite").path
        let manager = TokenmonDatabaseManager(path: databasePath)
        try manager.bootstrap()
        try manager.resetProgress(startedAt: "2000-01-01T00:00:00Z")

        let service = UsageSampleIngestionService(databasePath: databasePath)
        let ingestResult = try service.ingestProviderEvents(
            [
                makeUsageEvent(
                    observedAt: "2026-04-10T10:11:00Z",
                    fingerprint: "dashboard-session-usage",
                    providerSessionID: "dashboard-session",
                    normalizedTotalTokens: 1_500,
                    totalInputTokens: 1_000,
                    totalOutputTokens: 400,
                    totalCachedInputTokens: 100,
                    currentInputTokens: 1_000,
                    currentOutputTokens: 400
                ),
            ],
            sourceKey: "test:dashboard-sessions"
        )
        #expect(ingestResult.acceptedEvents == 1)

        _ = try CodexHookEnrichmentStore.apply(
            databasePath: databasePath,
            payload: CodexHookPayload(
                sessionID: "hook-only-session",
                transcriptPath: nil,
                cwd: "/tmp/tokenmon-fixture",
                hookEventName: "SessionStart",
                model: "gpt-5.4",
                message: nil
            ),
            observedAt: "2026-04-10T10:12:00Z"
        )

        let recentSessions = try manager.recentProviderSessions(limit: 10)
        let session = try #require(recentSessions.first)

        #expect(recentSessions.count == 1)
        #expect(session.providerSessionID == "dashboard-session")
        #expect(session.totalTokens == 1_500)
    }

    @Test
    func codexSessionStoreRecoveryUsesCheckpointForAppendedContent() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let databasePath = directory.appendingPathComponent("tokenmon.sqlite").path
        let manager = TokenmonDatabaseManager(path: databasePath)
        try manager.bootstrap()
        try manager.resetProgress(startedAt: "2000-01-01T00:00:00Z")
        try manager.markLiveGameplayStarted(at: "2026-04-10T10:29:00Z")
        _ = try SpeciesSeeder.seed(databasePath: databasePath)

        let sessionsRootPath = directory.appendingPathComponent("codex-home/sessions", isDirectory: true)
        let transcriptPath = sessionsRootPath
            .appendingPathComponent("2026/04/10", isDirectory: true)
            .appendingPathComponent("rollout-2026-04-10T10-20-00-recovery-append.jsonl")
            .path
        try FileManager.default.createDirectory(
            at: transcriptPath.deletingLastPathComponentURL,
            withIntermediateDirectories: true
        )
        try writeTranscriptLines(
            [
                codexSessionMetaLine(sessionID: "recovery-append"),
                codexTokenCountLine(
                    timestamp: "2026-04-10T10:25:00Z",
                    inputTokens: 1_000,
                    cachedInputTokens: 100,
                    outputTokens: 400,
                    lastInputTokens: 1_000,
                    lastOutputTokens: 400
                ),
            ],
            to: transcriptPath
        )

        let first = try CodexSessionStoreRecoveryService.run(
            databasePath: databasePath,
            sessionsRootPath: sessionsRootPath.path
        )
        try appendTranscriptLines(
            [
                codexTokenCountLine(
                    timestamp: "2026-04-10T10:28:00Z",
                    inputTokens: 2_000,
                    cachedInputTokens: 200,
                    outputTokens: 800,
                    lastInputTokens: 1_000,
                    lastOutputTokens: 400
                ),
            ],
            to: transcriptPath
        )
        let second = try CodexSessionStoreRecoveryService.run(
            databasePath: databasePath,
            sessionsRootPath: sessionsRootPath.path
        )

        let summary = try manager.summary()
        #expect(first.samplesCreated == 1)
        #expect(second.samplesCreated == 1)
        #expect(summary.usageSamples == 2)
        #expect(summary.totalNormalizedTokens == 0)
        #expect(try manager.tokenUsageTotals().allTimeTokens == 2_800)
    }

    @Test
    func codexSessionStoreStartupRecoverySkipsUnsettledSessionFiles() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let databasePath = directory.appendingPathComponent("tokenmon.sqlite").path
        let manager = TokenmonDatabaseManager(path: databasePath)
        try manager.bootstrap()
        try manager.resetProgress(startedAt: "2000-01-01T00:00:00Z")
        try manager.markLiveGameplayStarted(at: "2026-04-10T10:29:00Z")

        let sessionsRootPath = directory.appendingPathComponent("codex-home/sessions", isDirectory: true)
        let settledTranscriptPath = sessionsRootPath
            .appendingPathComponent("2026/04/10", isDirectory: true)
            .appendingPathComponent("rollout-2026-04-10T10-20-00-settled-session.jsonl")
            .path
        let activeTranscriptPath = sessionsRootPath
            .appendingPathComponent("2026/04/10", isDirectory: true)
            .appendingPathComponent("rollout-2026-04-10T10-21-00-active-session.jsonl")
            .path
        try FileManager.default.createDirectory(
            at: settledTranscriptPath.deletingLastPathComponentURL,
            withIntermediateDirectories: true
        )
        try writeTranscriptLines(
            [
                codexSessionMetaLine(sessionID: "settled-session"),
                codexTokenCountLine(
                    timestamp: "2026-04-10T10:25:00Z",
                    inputTokens: 1_000,
                    cachedInputTokens: 100,
                    outputTokens: 400,
                    lastInputTokens: 1_000,
                    lastOutputTokens: 400
                ),
            ],
            to: settledTranscriptPath
        )
        try writeTranscriptLines(
            [
                codexSessionMetaLine(sessionID: "active-session"),
                codexTokenCountLine(
                    timestamp: "2026-04-10T10:26:00Z",
                    inputTokens: 2_000,
                    cachedInputTokens: 200,
                    outputTokens: 800,
                    lastInputTokens: 2_000,
                    lastOutputTokens: 800
                ),
            ],
            to: activeTranscriptPath
        )
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -600)],
            ofItemAtPath: settledTranscriptPath
        )

        let result = try CodexSessionStoreRecoveryService.run(
            databasePath: databasePath,
            sessionsRootPath: sessionsRootPath.path,
            config: CodexSessionStoreRecoveryConfig(minimumFileAgeSeconds: 120)
        )

        let summary = try manager.summary()
        #expect(result.filesScanned == 1)
        #expect(result.filesRecovered == 1)
        #expect(result.samplesCreated == 1)
        #expect(summary.usageSamples == 1)
        #expect(try manager.tokenUsageTotals().allTimeTokens == 1_400)
    }

    @Test
    func codexSessionStoreObserverTreatsExistingSessionAsGameplayBaseline() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let databasePath = directory.appendingPathComponent("tokenmon.sqlite").path
        let manager = TokenmonDatabaseManager(path: databasePath)
        try manager.bootstrap()
        try manager.resetProgress(startedAt: "2000-01-01T00:00:00Z")
        try manager.markLiveGameplayStarted(at: "2026-04-10T10:29:00Z")
        _ = try SpeciesSeeder.seed(databasePath: databasePath)

        let codexHome = directory.appendingPathComponent("codex-home", isDirectory: true)
        let sessionsRootPath = codexHome
            .appendingPathComponent("sessions", isDirectory: true)
            .path
        let transcriptPath = codexHome
            .appendingPathComponent("sessions/2026/04/10", isDirectory: true)
            .appendingPathComponent("rollout-2026-04-10T10-27-42-live-hook-session.jsonl")
            .resolvingSymlinksInPath()
            .path
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: transcriptPath).deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try writeTranscriptLines(
            [codexSessionMetaLine(sessionID: "live-hook-session")],
            to: transcriptPath
        )

        let inboxPath = TokenmonDatabaseManager.inboxPath(provider: .codex, databasePath: databasePath)
        let liveMonitor = TokenmonInboxMonitor(
            databasePath: databasePath,
            scanDebounceDelay: .milliseconds(25)
        )
        defer { liveMonitor.stop() }
        liveMonitor.start {}

        let observer = CodexSessionStoreObserver(
            config: CodexSessionStoreObserverConfig(
                sessionsRootPath: sessionsRootPath,
                outputPath: inboxPath,
                rescanDebounceDelay: .milliseconds(25),
                fileProcessDebounceDelay: .milliseconds(25)
            )
        )
        defer { observer.stop() }
        observer.start()
        try await Task.sleep(for: .milliseconds(150))

        try appendTranscriptLines(
            [
                codexTokenCountLine(
                    timestamp: "2026-04-10T10:30:00Z",
                    inputTokens: 1_000,
                    cachedInputTokens: 100,
                    outputTokens: 400,
                    lastInputTokens: 1_000,
                    lastOutputTokens: 400
                ),
            ],
            to: transcriptPath
        )

        let ingestedAppend = await waitUntil(timeout: .seconds(8)) {
            try manager.summary().usageSamples == 1
        }

        #expect(ingestedAppend)
        #expect(try manager.summary().totalNormalizedTokens == 0)
        #expect(try manager.tokenUsageTotals().allTimeTokens == 1_400)
    }

    @Test
    func codexSessionStoreObserverCountsNewRuntimeSessionForGameplay() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let databasePath = directory.appendingPathComponent("tokenmon.sqlite").path
        let manager = TokenmonDatabaseManager(path: databasePath)
        try manager.bootstrap()
        try manager.resetProgress(startedAt: "2000-01-01T00:00:00Z")
        try manager.markLiveGameplayStarted(at: "2026-04-10T10:29:00Z")
        _ = try SpeciesSeeder.seed(databasePath: databasePath)

        let codexHome = directory.appendingPathComponent("codex-home", isDirectory: true)
        let sessionsRootPath = codexHome
            .appendingPathComponent("sessions", isDirectory: true)
            .path
        let liveSessionDirectory = URL(fileURLWithPath: sessionsRootPath, isDirectory: true)
            .appendingPathComponent("2026/04/10", isDirectory: true)
        try FileManager.default.createDirectory(
            at: liveSessionDirectory,
            withIntermediateDirectories: true
        )

        let inboxPath = TokenmonDatabaseManager.inboxPath(provider: .codex, databasePath: databasePath)
        let liveMonitor = TokenmonInboxMonitor(
            databasePath: databasePath,
            scanDebounceDelay: .milliseconds(25)
        )
        defer { liveMonitor.stop() }
        liveMonitor.start {}

        let observer = CodexSessionStoreObserver(
            config: CodexSessionStoreObserverConfig(
                sessionsRootPath: sessionsRootPath,
                outputPath: inboxPath,
                rescanDebounceDelay: .milliseconds(25),
                fileProcessDebounceDelay: .milliseconds(25)
            )
        )
        defer { observer.stop() }
        observer.start()
        try await Task.sleep(for: .milliseconds(150))

        let transcriptPath = liveSessionDirectory
            .appendingPathComponent("rollout-2026-04-10T10-30-00-runtime-session.jsonl")
            .path
        try writeTranscriptLines(
            [
                codexSessionMetaLine(sessionID: "runtime-session"),
                codexTokenCountLine(
                    timestamp: "2026-04-10T10:30:05Z",
                    inputTokens: 1_000,
                    cachedInputTokens: 100,
                    outputTokens: 400,
                    lastInputTokens: 1_000,
                    lastOutputTokens: 400
                ),
            ],
            to: transcriptPath
        )

        let ingestedEvent = await waitUntil(timeout: .seconds(8)) {
            try manager.summary().usageSamples == 1
        }

        #expect(ingestedEvent)
        let gameplayDelta = try gameplayDeltaSum(manager)
        #expect(gameplayDelta > 0)
        #expect(gameplayDelta < 1_400)
        #expect(try manager.summary().totalNormalizedTokens == gameplayDelta)
        #expect(try manager.summary().tokensSinceLastEncounter == gameplayDelta)
        #expect(try manager.tokenUsageTotals().allTimeTokens == 1_400)
    }

    @Test
    func claudeTranscriptLiveObserverFollowsExistingSessionWithoutSettingsMutation() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let databasePath = directory.appendingPathComponent("tokenmon.sqlite").path
        let manager = TokenmonDatabaseManager(path: databasePath)
        try manager.bootstrap()
        try manager.resetProgress(startedAt: "2000-01-01T00:00:00Z")
        try manager.markLiveGameplayStarted(at: "2026-04-10T10:29:00Z")
        _ = try SpeciesSeeder.seed(databasePath: databasePath)

        let claudeRoot = directory.appendingPathComponent(".claude", isDirectory: true)
        let projectsRootPath = claudeRoot.appendingPathComponent("projects", isDirectory: true).path
        let transcriptDirectory = URL(fileURLWithPath: projectsRootPath, isDirectory: true)
            .appendingPathComponent("-tmp-tokenmon-tests", isDirectory: true)
        let transcriptPath = transcriptDirectory
            .appendingPathComponent("existing-session.jsonl")
            .path
        try FileManager.default.createDirectory(at: transcriptDirectory, withIntermediateDirectories: true)
        try writeTranscriptLines(
            [
                claudeTranscriptLine(
                    sessionID: "claude-existing-session",
                    messageID: "msg-before-live",
                    timestamp: "2026-04-10T10:28:00Z",
                    inputTokens: 800,
                    outputTokens: 300,
                    cacheCreationInputTokens: 0,
                    cacheReadInputTokens: 0
                ),
            ],
            to: transcriptPath
        )

        let inboxPath = TokenmonDatabaseManager.inboxPath(provider: .claude, databasePath: databasePath)
        let liveMonitor = TokenmonInboxMonitor(
            databasePath: databasePath,
            scanDebounceDelay: .milliseconds(25)
        )
        defer { liveMonitor.stop() }
        liveMonitor.start {}

        let observer = ClaudeTranscriptLiveObserver(
            config: ClaudeTranscriptLiveObserverConfig(
                projectsRootPath: projectsRootPath,
                outputPath: inboxPath,
                rescanDebounceDelay: .milliseconds(25),
                fileProcessDebounceDelay: .milliseconds(25)
            )
        )
        defer { observer.stop() }
        observer.start()
        try await Task.sleep(for: .milliseconds(150))

        try appendTranscriptLines(
            [
                claudeTranscriptLine(
                    sessionID: "claude-existing-session",
                    messageID: "msg-after-live",
                    timestamp: "2026-04-10T10:30:00Z",
                    inputTokens: 1_000,
                    outputTokens: 400,
                    cacheCreationInputTokens: 0,
                    cacheReadInputTokens: 0
                ),
            ],
            to: transcriptPath
        )

        let ingestedAppend = await waitUntil(timeout: .seconds(8)) {
            try manager.summary().usageSamples == 2
        }

        #expect(ingestedAppend)
        #expect(FileManager.default.fileExists(atPath: claudeRoot.appendingPathComponent("settings.json").path) == false)
        #expect(FileManager.default.fileExists(atPath: claudeRoot.appendingPathComponent("tokenmon-statusline.sh").path) == false)
        let gameplayDelta = try gameplayDeltaSum(manager)
        #expect(gameplayDelta > 0)
        #expect(try manager.tokenUsageTotals().allTimeTokens == 2_500)
    }

    @Test
    func claudeTranscriptLiveObserverCountsNewRuntimeSessionForGameplay() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let databasePath = directory.appendingPathComponent("tokenmon.sqlite").path
        let manager = TokenmonDatabaseManager(path: databasePath)
        try manager.bootstrap()
        try manager.resetProgress(startedAt: "2000-01-01T00:00:00Z")
        try manager.markLiveGameplayStarted(at: "2026-04-10T10:29:00Z")
        _ = try SpeciesSeeder.seed(databasePath: databasePath)

        let projectsRootPath = directory
            .appendingPathComponent(".claude/projects", isDirectory: true)
            .path
        let transcriptDirectory = URL(fileURLWithPath: projectsRootPath, isDirectory: true)
            .appendingPathComponent("-tmp-tokenmon-tests", isDirectory: true)
        try FileManager.default.createDirectory(at: transcriptDirectory, withIntermediateDirectories: true)

        let inboxPath = TokenmonDatabaseManager.inboxPath(provider: .claude, databasePath: databasePath)
        let liveMonitor = TokenmonInboxMonitor(
            databasePath: databasePath,
            scanDebounceDelay: .milliseconds(25)
        )
        defer { liveMonitor.stop() }
        liveMonitor.start {}

        let observer = ClaudeTranscriptLiveObserver(
            config: ClaudeTranscriptLiveObserverConfig(
                projectsRootPath: projectsRootPath,
                outputPath: inboxPath,
                rescanDebounceDelay: .milliseconds(25),
                fileProcessDebounceDelay: .milliseconds(25)
            )
        )
        defer { observer.stop() }
        observer.start()
        try await Task.sleep(for: .milliseconds(150))

        let transcriptPath = transcriptDirectory
            .appendingPathComponent("runtime-session.jsonl")
            .path
        try writeTranscriptLines(
            [
                claudeTranscriptLine(
                    sessionID: "claude-runtime-session",
                    messageID: "msg-runtime",
                    timestamp: "2026-04-10T10:30:05Z",
                    inputTokens: 1_000,
                    outputTokens: 400,
                    cacheCreationInputTokens: 0,
                    cacheReadInputTokens: 0
                ),
            ],
            to: transcriptPath
        )

        let ingestedEvent = await waitUntil(timeout: .seconds(8)) {
            try manager.summary().usageSamples == 1
        }

        #expect(ingestedEvent)
        let gameplayDelta = try gameplayDeltaSum(manager)
        #expect(gameplayDelta > 0)
        #expect(try manager.tokenUsageTotals().allTimeTokens == 1_400)
    }

    @Test
    func claudeTranscriptLiveObserverDetectsProjectsDirectoryCreatedAfterStart() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let databasePath = directory.appendingPathComponent("tokenmon.sqlite").path
        let manager = TokenmonDatabaseManager(path: databasePath)
        try manager.bootstrap()
        try manager.resetProgress(startedAt: "2000-01-01T00:00:00Z")
        try manager.markLiveGameplayStarted(at: "2026-04-10T10:29:00Z")
        _ = try SpeciesSeeder.seed(databasePath: databasePath)

        let claudeRoot = directory.appendingPathComponent(".claude", isDirectory: true)
        let projectsRootPath = claudeRoot.appendingPathComponent("projects", isDirectory: true).path
        let inboxPath = TokenmonDatabaseManager.inboxPath(provider: .claude, databasePath: databasePath)
        let liveMonitor = TokenmonInboxMonitor(
            databasePath: databasePath,
            scanDebounceDelay: .milliseconds(25)
        )
        defer { liveMonitor.stop() }
        liveMonitor.start {}

        let observer = ClaudeTranscriptLiveObserver(
            config: ClaudeTranscriptLiveObserverConfig(
                projectsRootPath: projectsRootPath,
                outputPath: inboxPath,
                rescanDebounceDelay: .milliseconds(25),
                fileProcessDebounceDelay: .milliseconds(25)
            )
        )
        defer { observer.stop() }
        observer.start()
        try await Task.sleep(for: .milliseconds(150))

        let transcriptDirectory = URL(fileURLWithPath: projectsRootPath, isDirectory: true)
            .appendingPathComponent("-tmp-tokenmon-tests", isDirectory: true)
        try FileManager.default.createDirectory(at: transcriptDirectory, withIntermediateDirectories: true)
        try writeTranscriptLines(
            [
                claudeTranscriptLine(
                    sessionID: "claude-created-after-start",
                    messageID: "msg-runtime",
                    timestamp: "2026-04-10T10:30:05Z",
                    inputTokens: 1_000,
                    outputTokens: 400,
                    cacheCreationInputTokens: 0,
                    cacheReadInputTokens: 0
                ),
            ],
            to: transcriptDirectory.appendingPathComponent("created-after-start.jsonl").path
        )

        let ingestedEvent = await waitUntil(timeout: .seconds(8)) {
            try manager.summary().usageSamples == 1
        }

        #expect(ingestedEvent)
        #expect(FileManager.default.fileExists(atPath: claudeRoot.appendingPathComponent("settings.json").path) == false)
        #expect(try manager.tokenUsageTotals().allTimeTokens == 1_400)
    }

    @Test
    func encounterGeneratorPenalizesRecentSpeciesRepeats() throws {
        let catalog = [
            SpeciesDefinition(id: "GRS_001", name: "First", field: .grassland, rarity: .common, assetKey: "grs_001_first", sortOrder: 1, trainingTrait: .trail),
            SpeciesDefinition(id: "GRS_002", name: "Second", field: .grassland, rarity: .common, assetKey: "grs_002_second", sortOrder: 2, trainingTrait: .scout),
            SpeciesDefinition(id: "GRS_003", name: "Third", field: .grassland, rarity: .common, assetKey: "grs_003_third", sortOrder: 3, trainingTrait: .capture),
        ]

        let generator = EncounterGenerator(
            config: EncounterGenerationConfig(speciesCatalog: catalog)
        )

        var rng = FixedEncounterRNG(rolls: [0.0, 0.0, 0.25])
        let generated = try generator.generateEncounter(
            context: EncounterGenerationContext(
                threshold: EncounterThresholdCrossedSnapshot(
                    thresholdIndexGlobal: 1,
                    totalNormalizedTokensAtThreshold: 6_000_000,
                    thresholdTokens: 5_800_000,
                    remainingTokensAfter: 0,
                    nextEncounterThresholdTokens: 6_200_000
                ),
                usageSampleID: 1,
                occurredAt: "2026-04-05T00:00:00Z",
                burstIntensityBand: 1,
                priorEncounterFields: [.grassland, .sky],
                priorEncounterSpeciesIDs: ["GRS_001", "GRS_002"],
                capturedSpeciesCounts: ["GRS_002": 3]
            ),
            using: &rng
        )

        #expect(generated.species.id == "GRS_003")
    }

    @Test
    func codexExecJSONRunStreamsEventsBeforeProcessExit() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let fakeCodexPath = directory.appendingPathComponent("fake-codex")
        let outputPath = directory.appendingPathComponent("codex.ndjson").path

        try """
        #!/bin/sh
        printf '%s\\n' '{"type":"thread.started","thread_id":"thread_streaming","cwd":"/tmp/tokenmon-stream","model":"gpt-5.4"}'
        sleep 1
        printf '%s\\n' '{"type":"turn.completed","thread_id":"thread_streaming","turn_id":"turn_001","timestamp":"2026-04-06T00:00:00Z","cwd":"/tmp/tokenmon-stream","model":"gpt-5.4","usage":{"input_tokens":1000,"cached_input_tokens":100,"output_tokens":400}}'
        sleep 2
        printf '%s\\n' '{"type":"turn.completed","thread_id":"thread_streaming","turn_id":"turn_002","timestamp":"2026-04-06T00:00:03Z","cwd":"/tmp/tokenmon-stream","model":"gpt-5.4","usage":{"input_tokens":1200,"cached_input_tokens":0,"output_tokens":500}}'
        """.write(to: fakeCodexPath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeCodexPath.path)

        let runTask = Task.detached {
            try CodexExecJSONAdapter.runCodexExecJSON(
                prompt: "stream please",
                outputPath: outputPath,
                codexBin: fakeCodexPath.path
            )
        }

        let firstEventWritten = await waitUntil(timeout: .seconds(4)) {
            guard FileManager.default.fileExists(atPath: outputPath) else {
                return false
            }

            let contents = try String(contentsOfFile: outputPath, encoding: .utf8)
            return contents.contains("turn_001") && contents.contains("turn_002") == false
        }
        #expect(firstEventWritten)

        let result = try await runTask.value
        let finalContents = try String(contentsOfFile: outputPath, encoding: .utf8)

        #expect(result.threadID == "thread_streaming")
        #expect(result.eventsWritten == 2)
        #expect(finalContents.contains("turn_001"))
        #expect(finalContents.contains("turn_002"))
    }

    @Test
    func ingestResetsCheckpointWhenInboxFileIsReplaced() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let databasePath = directory.appendingPathComponent("tokenmon.sqlite").path
        let inboxPath = directory.appendingPathComponent("codex.ndjson").path
        let databaseManager = TokenmonDatabaseManager(path: databasePath)
        try databaseManager.bootstrap()

        let service = UsageSampleIngestionService(databasePath: databasePath)
        let baseDate = Date().addingTimeInterval(2)
        let firstObservedAt = ISO8601DateFormatter().string(from: baseDate)
        let firstEvent = makeUsageEvent(
            observedAt: firstObservedAt,
            fingerprint: "replace-turn-001",
            providerSessionID: "replace-a",
            normalizedTotalTokens: 200,
            totalInputTokens: 120,
            totalOutputTokens: 80,
            currentInputTokens: 120,
            currentOutputTokens: 80
        )
        try writeInboxEvents([firstEvent], to: inboxPath)

        let firstResult = try service.ingestInboxFile(at: inboxPath, sourceKey: "replace-test")
        #expect(firstResult.acceptedEvents == 1)

        let secondObservedAt = ISO8601DateFormatter().string(from: baseDate.addingTimeInterval(1))
        let secondEvent = makeUsageEvent(
            observedAt: secondObservedAt,
            fingerprint: "replace-turn-002",
            providerSessionID: "replace-b",
            normalizedTotalTokens: 400,
            totalInputTokens: 220,
            totalOutputTokens: 180,
            currentInputTokens: 220,
            currentOutputTokens: 180
        )
        try writeInboxEvents([secondEvent], to: inboxPath)

        let secondResult = try service.ingestInboxFile(at: inboxPath, sourceKey: "replace-test")
        let summary = try databaseManager.summary()

        #expect(secondResult.acceptedEvents == 1)
        #expect(secondResult.lastLineNumber == 1)
        #expect(summary.usageSamples == 2)
    }

    @Test
    func inboxMonitorDetectsAppendOnExistingInboxFile() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let databasePath = directory.appendingPathComponent("tokenmon.sqlite").path
        let databaseManager = TokenmonDatabaseManager(path: databasePath)
        try databaseManager.bootstrap()

        let inboxPath = TokenmonDatabaseManager.inboxPath(provider: .codex, databasePath: databasePath)
        let inboxDirectory = URL(fileURLWithPath: inboxPath).deletingLastPathComponent()
        try FileManager.default.createDirectory(at: inboxDirectory, withIntermediateDirectories: true)

        let firstEvent = makeUsageEvent(
            observedAt: ISO8601DateFormatter().string(from: Date().addingTimeInterval(2)),
            fingerprint: "monitor-turn-001",
            providerSessionID: "monitor-session",
            normalizedTotalTokens: 200,
            totalInputTokens: 120,
            totalOutputTokens: 80,
            currentInputTokens: 120,
            currentOutputTokens: 80
        )
        let secondEvent = makeUsageEvent(
            observedAt: ISO8601DateFormatter().string(from: Date().addingTimeInterval(4)),
            fingerprint: "monitor-turn-002",
            providerSessionID: "monitor-session",
            normalizedTotalTokens: 400,
            totalInputTokens: 240,
            totalOutputTokens: 160,
            currentInputTokens: 120,
            currentOutputTokens: 80
        )

        try writeInboxEvents([firstEvent], to: inboxPath)
        TokenmonInboxMonitor(databasePath: databasePath).performInitialScan()
        #expect(try databaseManager.summary().usageSamples == 1)

        let liveMonitor = TokenmonInboxMonitor(
            databasePath: databasePath,
            scanDebounceDelay: .milliseconds(25)
        )
        defer { liveMonitor.stop() }
        liveMonitor.start {}

        try await Task.sleep(for: .milliseconds(2000))
        try appendInboxEvents([secondEvent], to: inboxPath)

        let ingestedAppend = await waitUntil(timeout: .seconds(15)) {
            try databaseManager.summary().usageSamples == 2
        }

        #expect(ingestedAppend)
    }

    @Test
    func codexHookSignalTouchCreatesInboxSignalFile() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let databasePath = directory.appendingPathComponent("tokenmon.sqlite").path
        let databaseManager = TokenmonDatabaseManager(path: databasePath)
        try databaseManager.bootstrap()
        try TokenmonInboxActivitySignal.touchCodexHookSignal(databasePath: databasePath)
        let signalPath = URL(
            fileURLWithPath: TokenmonDatabaseManager.inboxDirectory(forDatabasePath: databasePath),
            isDirectory: true
        )
        .appendingPathComponent("codex-hook.signal")

        let signalContents = try String(contentsOf: signalPath, encoding: .utf8)
        #expect(signalContents.isEmpty == false)
    }

    @Test
    func statusItemRendererCachesIdenticalFrames() {
        let context = TokenmonSceneContext(
            sceneState: .exploring,
            fieldKind: .grassland,
            fieldState: .exploring,
            effectState: .none,
            wildState: .hidden
        )
        let timestamp = Date(timeIntervalSinceReferenceDate: 42_000)

        let firstImage = TokenmonStatusItemImageRenderer.render(
            context: context,
            at: timestamp,
            buttonBounds: NSRect(x: 0, y: 0, width: 56, height: 22)
        )
        let secondImage = TokenmonStatusItemImageRenderer.render(
            context: context,
            at: timestamp,
            buttonBounds: NSRect(x: 0, y: 0, width: 56, height: 22)
        )

        #expect(firstImage != nil)
        #expect(firstImage === secondImage)
    }

    @Test
    func statusItemRenderGateSkipsUnchangedContextTickAndTooltip() {
        let context = TokenmonSceneContext(
            sceneState: .exploring,
            fieldKind: .grassland,
            fieldState: .exploring,
            effectState: .none,
            wildState: .hidden
        )
        let key = TokenmonStatusItemRenderUpdateKey(
            context: context,
            tick: 12,
            tooltip: "Exploring",
            buttonBounds: NSRect(x: 0, y: 0, width: 56, height: 22),
            scaleFactor: 2,
            debugOffset: .zero
        )
        var gate = TokenmonStatusItemRenderUpdateGate()

        let firstApply = gate.shouldApply(key)
        let secondApply = gate.shouldApply(key)
        #expect(firstApply)
        #expect(secondApply == false)

        let changedTooltip = TokenmonStatusItemRenderUpdateKey(
            context: context,
            tick: 12,
            tooltip: "Captured Mossbun",
            buttonBounds: NSRect(x: 0, y: 0, width: 56, height: 22),
            scaleFactor: 2,
            debugOffset: .zero
        )
        let tooltipApply = gate.shouldApply(changedTooltip)
        #expect(tooltipApply)
    }

    @Test
    func asyncProcessRunnerDrainsLargeStdoutAndStderr() async throws {
        let script = """
        python3 - <<'PY'
        import sys
        sys.stdout.write("o" * 200000)
        sys.stderr.write("e" * 200000)
        PY
        """

        let result = try await TokenmonAsyncProcessRunner.run(
            TokenmonAsyncProcessRequest(
                executableURL: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", script],
                timeout: 5
            )
        )

        #expect(result.terminationStatus == 0)
        #expect(result.stdout.count == 200_000)
        #expect(result.stderr.count == 200_000)
    }

    @Test
    func launchAtLoginFallbackSupportsInstalledUserApplicationsBundle() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let fakeHome = directory.appendingPathComponent("fake-home", isDirectory: true)
        try FileManager.default.createDirectory(at: fakeHome, withIntermediateDirectories: true)
        let bundle = try makeFakeAppBundle(
            appURL: fakeHome.appendingPathComponent("Applications/Tokenmon.app", isDirectory: true)
        )

        let state = TokenmonLaunchAtLoginController.snapshot(
            using: TokenmonLaunchAtLoginDependencies(
                bundle: bundle,
                fileManager: .default,
                homeDirectory: fakeHome,
                nativeStatusProvider: { .notFound },
                nativeSetter: { _ in }
            )
        )

        #expect(state.isSupported)
        #expect(state.isEnabled == false)
        #expect(state.reason == TokenmonL10n.string("settings.launch_at_login.reason.disabled"))
    }

    @Test
    func launchAtLoginFallbackWritesAndRemovesUserLaunchAgent() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let fakeHome = directory.appendingPathComponent("fake-home", isDirectory: true)
        try FileManager.default.createDirectory(at: fakeHome, withIntermediateDirectories: true)
        let bundle = try makeFakeAppBundle(
            appURL: fakeHome.appendingPathComponent("Applications/Tokenmon.app", isDirectory: true)
        )
        let dependencies = TokenmonLaunchAtLoginDependencies(
            bundle: bundle,
            fileManager: .default,
            homeDirectory: fakeHome,
            nativeStatusProvider: { .notFound },
            nativeSetter: { _ in }
        )
        let plistURL = fakeHome
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent("com.aroido.tokenmon.launch-at-login.plist", isDirectory: false)

        let enabledState = try TokenmonLaunchAtLoginController.setEnabled(true, using: dependencies)
        #expect(enabledState.isSupported)
        #expect(enabledState.isEnabled)
        #expect(FileManager.default.fileExists(atPath: plistURL.path))

        let payload = try PropertyListSerialization.propertyList(
            from: Data(contentsOf: plistURL),
            format: nil
        ) as? [String: Any]
        let arguments = payload?["ProgramArguments"] as? [String]
        let associatedBundleIdentifiers = payload?["AssociatedBundleIdentifiers"] as? [String]
        let expectedExecutablePath = try #require(bundle.executableURL?.standardizedFileURL.path)
        #expect(arguments == [expectedExecutablePath])
        #expect(associatedBundleIdentifiers == ["com.aroido.tokenmon"])

        let disabledState = try TokenmonLaunchAtLoginController.setEnabled(false, using: dependencies)
        #expect(disabledState.isSupported)
        #expect(disabledState.isEnabled == false)
        #expect(FileManager.default.fileExists(atPath: plistURL.path) == false)
    }

    @Test
    func launchAtLoginFallbackMigratesLegacyOpenLaunchAgent() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let fakeHome = directory.appendingPathComponent("fake-home", isDirectory: true)
        try FileManager.default.createDirectory(at: fakeHome, withIntermediateDirectories: true)
        let bundle = try makeFakeAppBundle(
            appURL: fakeHome.appendingPathComponent("Applications/Tokenmon.app", isDirectory: true)
        )
        let dependencies = TokenmonLaunchAtLoginDependencies(
            bundle: bundle,
            fileManager: .default,
            homeDirectory: fakeHome,
            nativeStatusProvider: { .notFound },
            nativeSetter: { _ in }
        )
        let plistURL = fakeHome
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent("com.aroido.tokenmon.launch-at-login.plist", isDirectory: false)

        try FileManager.default.createDirectory(
            at: plistURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let legacyPayload: [String: Any] = [
            "Label": "com.aroido.tokenmon.launch-at-login",
            "LimitLoadToSessionType": ["Aqua"],
            "ProcessType": "Interactive",
            "ProgramArguments": ["/usr/bin/open", "-g", bundle.bundleURL.standardizedFileURL.path],
            "RunAtLoad": true,
        ]
        let legacyData = try PropertyListSerialization.data(
            fromPropertyList: legacyPayload,
            format: .xml,
            options: 0
        )
        try legacyData.write(to: plistURL, options: .atomic)

        let state = TokenmonLaunchAtLoginController.snapshot(using: dependencies)
        #expect(state.isSupported)
        #expect(state.isEnabled)

        let payload = try PropertyListSerialization.propertyList(
            from: Data(contentsOf: plistURL),
            format: nil
        ) as? [String: Any]
        let arguments = payload?["ProgramArguments"] as? [String]
        let associatedBundleIdentifiers = payload?["AssociatedBundleIdentifiers"] as? [String]
        let expectedExecutablePath = try #require(bundle.executableURL?.standardizedFileURL.path)
        #expect(arguments == [expectedExecutablePath])
        #expect(associatedBundleIdentifiers == ["com.aroido.tokenmon"])
    }

    @Test
    func launchAtLoginFallbackRejectsTemporaryBundleLocations() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let fakeHome = directory.appendingPathComponent("fake-home", isDirectory: true)
        try FileManager.default.createDirectory(at: fakeHome, withIntermediateDirectories: true)
        let bundle = try makeFakeAppBundle(
            appURL: directory.appendingPathComponent("build/Tokenmon.app", isDirectory: true)
        )

        let state = TokenmonLaunchAtLoginController.snapshot(
            using: TokenmonLaunchAtLoginDependencies(
                bundle: bundle,
                fileManager: .default,
                homeDirectory: fakeHome,
                nativeStatusProvider: { .notFound },
                nativeSetter: { _ in }
            )
        )

        #expect(state.isSupported == false)
        #expect(state.reason == TokenmonL10n.string("settings.launch_at_login.reason.installed_only"))
    }

    @Test
    func installedAppBundleSupportAcceptsApplicationsLocations() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let fakeHome = directory.appendingPathComponent("fake-home", isDirectory: true)
        try FileManager.default.createDirectory(at: fakeHome, withIntermediateDirectories: true)
        let bundle = try makeFakeAppBundle(
            appURL: fakeHome.appendingPathComponent("Applications/Tokenmon.app", isDirectory: true)
        )

        #expect(
            TokenmonInstalledAppBundleSupport.isInstalledAppBundle(
                bundle: bundle,
                homeDirectory: fakeHome
            )
        )
    }

    @Test
    func installedAppBundleSupportRejectsTemporaryLocations() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let fakeHome = directory.appendingPathComponent("fake-home", isDirectory: true)
        try FileManager.default.createDirectory(at: fakeHome, withIntermediateDirectories: true)
        let bundle = try makeFakeAppBundle(
            appURL: directory.appendingPathComponent("build/Tokenmon.app", isDirectory: true)
        )

        #expect(
            TokenmonInstalledAppBundleSupport.isInstalledAppBundle(
                bundle: bundle,
                homeDirectory: fakeHome
            ) == false
        )
    }

    @Test
    func launchAtLoginReleasePathDoesNotWriteFallbackLaunchAgent() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let fakeHome = directory.appendingPathComponent("fake-home", isDirectory: true)
        try FileManager.default.createDirectory(at: fakeHome, withIntermediateDirectories: true)
        let bundle = try makeFakeAppBundle(
            appURL: fakeHome.appendingPathComponent("Applications/Tokenmon.app", isDirectory: true)
        )
        let dependencies = TokenmonLaunchAtLoginDependencies(
            bundle: bundle,
            fileManager: .default,
            homeDirectory: fakeHome,
            nativeStatusProvider: { .notFound },
            nativeSetter: { _ in },
            fallbackPolicy: .nativeOnly,
            supportDirectoryPath: directory.path
        )
        let plistURL = fakeHome
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent("com.aroido.tokenmon.launch-at-login.plist", isDirectory: false)

        let state = try TokenmonLaunchAtLoginController.setEnabled(true, using: dependencies)
        #expect(state.isSupported)
        #expect(state.isEnabled == false)
        #expect(state.reason == TokenmonL10n.string("settings.launch_at_login.reason.disabled"))
        #expect(FileManager.default.fileExists(atPath: plistURL.path) == false)
    }

    @Test
    func launchAtLoginReleaseSnapshotTreatsNotFoundAsDisabledState() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let fakeHome = directory.appendingPathComponent("fake-home", isDirectory: true)
        try FileManager.default.createDirectory(at: fakeHome, withIntermediateDirectories: true)
        let bundle = try makeFakeAppBundle(
            appURL: fakeHome.appendingPathComponent("Applications/Tokenmon.app", isDirectory: true)
        )

        let state = TokenmonLaunchAtLoginController.snapshot(
            using: TokenmonLaunchAtLoginDependencies(
                bundle: bundle,
                fileManager: .default,
                homeDirectory: fakeHome,
                nativeStatusProvider: { .notFound },
                nativeSetter: { _ in },
                fallbackPolicy: .nativeOnly,
                supportDirectoryPath: directory.path
            )
        )

        #expect(state.isSupported)
        #expect(state.isEnabled == false)
        #expect(state.reason == TokenmonL10n.string("settings.launch_at_login.reason.disabled"))
        #expect(state.showsOpenSystemSettingsAction == false)
    }

    @Test
    func launchAtLoginReleasePathAttemptsNativeRegistrationWhenStatusIsNotFound() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let fakeHome = directory.appendingPathComponent("fake-home", isDirectory: true)
        try FileManager.default.createDirectory(at: fakeHome, withIntermediateDirectories: true)
        let bundle = try makeFakeAppBundle(
            appURL: fakeHome.appendingPathComponent("Applications/Tokenmon.app", isDirectory: true)
        )

        final class Box: @unchecked Sendable {
            var values: [Bool] = []
        }
        let box = Box()

        _ = try TokenmonLaunchAtLoginController.setEnabled(
            true,
            using: TokenmonLaunchAtLoginDependencies(
                bundle: bundle,
                fileManager: .default,
                homeDirectory: fakeHome,
                nativeStatusProvider: { .notFound },
                nativeSetter: { enabled in
                    box.values.append(enabled)
                },
                fallbackPolicy: .nativeOnly,
                supportDirectoryPath: directory.path
            )
        )

        #expect(box.values == [true])
    }

    @Test
    func launchAtLoginReleaseSnapshotRemovesLegacyLaunchAgent() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let fakeHome = directory.appendingPathComponent("fake-home", isDirectory: true)
        try FileManager.default.createDirectory(at: fakeHome, withIntermediateDirectories: true)
        let bundle = try makeFakeAppBundle(
            appURL: fakeHome.appendingPathComponent("Applications/Tokenmon.app", isDirectory: true)
        )
        let dependencies = TokenmonLaunchAtLoginDependencies(
            bundle: bundle,
            fileManager: .default,
            homeDirectory: fakeHome,
            nativeStatusProvider: { .statusUnavailable },
            nativeSetter: { _ in },
            fallbackPolicy: .nativeOnly,
            supportDirectoryPath: directory.path
        )
        let plistURL = fakeHome
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent("com.aroido.tokenmon.launch-at-login.plist", isDirectory: false)

        try FileManager.default.createDirectory(
            at: plistURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let legacyPayload: [String: Any] = [
            "Label": "com.aroido.tokenmon.launch-at-login",
            "LimitLoadToSessionType": ["Aqua"],
            "ProcessType": "Interactive",
            "ProgramArguments": ["/usr/bin/open", "-g", bundle.bundleURL.standardizedFileURL.path],
            "RunAtLoad": true,
        ]
        let legacyData = try PropertyListSerialization.data(
            fromPropertyList: legacyPayload,
            format: .xml,
            options: 0
        )
        try legacyData.write(to: plistURL, options: .atomic)

        let state = TokenmonLaunchAtLoginController.snapshot(using: dependencies)
        #expect(state.isSupported == false)
        #expect(state.reason == TokenmonL10n.string("settings.launch_at_login.reason.status_unavailable"))
        #expect(FileManager.default.fileExists(atPath: plistURL.path) == false)
    }

    @Test
    func launchAtLoginRequiresApprovalShowsSystemSettingsAction() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let fakeHome = directory.appendingPathComponent("fake-home", isDirectory: true)
        try FileManager.default.createDirectory(at: fakeHome, withIntermediateDirectories: true)
        let bundle = try makeFakeAppBundle(
            appURL: fakeHome.appendingPathComponent("Applications/Tokenmon.app", isDirectory: true)
        )
        let state = TokenmonLaunchAtLoginController.snapshot(
            using: TokenmonLaunchAtLoginDependencies(
                bundle: bundle,
                fileManager: .default,
                homeDirectory: fakeHome,
                nativeStatusProvider: { .requiresApproval },
                nativeSetter: { _ in }
            )
        )

        #expect(state.showsOpenSystemSettingsAction)
    }

    @Test
    func hotPathRefreshSkipsProviderInspectionUntilSettingsSurfaceOpens() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let databasePath = directory.appendingPathComponent("tokenmon.sqlite").path
        let manager = TokenmonDatabaseManager(path: databasePath)
        try manager.bootstrap()
        try manager.resetProgress(startedAt: "2000-01-01T00:00:00Z")

        let counter = ProviderInspectionCounter()
        let model = TokenmonMenuModel(
            databasePath: databasePath,
            providerInspector: { _, _, _ in
                counter.increment()
                return []
            },
            launchAtLoginStateProvider: {
                .unsupported(reason: "tests")
            }
        )

        await model.waitForRefreshToFinish()
        let initialCount = counter.snapshot()

        model.refresh(reason: .hotPath)
        await model.waitForRefreshToFinish()
        #expect(counter.snapshot() == initialCount)

        model.surfaceOpened(.settings)
        await model.waitForRefreshToFinish()
        #expect(counter.snapshot() == initialCount + 1)
    }

    @Test
    func popoverActivationRefreshesInsightsTabsEvenAfterInitialLoad() {
        #expect(
            TokenmonPopoverContainer.refreshSurfaceForActivation(
                activeTab: .tokens,
                runtimeLoaded: true
            ) == .tokens
        )
        #expect(
            TokenmonPopoverContainer.refreshSurfaceForActivation(
                activeTab: .stats,
                runtimeLoaded: true
            ) == .stats
        )
        #expect(
            TokenmonPopoverContainer.refreshSurfaceForActivation(
                activeTab: .dex,
                runtimeLoaded: true
            ) == .dex
        )
    }

    @Test
    func popoverActivationKeepsNowTabColdAfterRuntimeLoads() {
        #expect(
            TokenmonPopoverContainer.refreshSurfaceForActivation(
                activeTab: .now,
                runtimeLoaded: false
            ) == .now
        )
        #expect(
            TokenmonPopoverContainer.refreshSurfaceForActivation(
                activeTab: .now,
                runtimeLoaded: true
            ) == nil
        )
    }

    @Test
    func inboxRefreshUpgradesToInsightsAfterInsightsHaveLoaded() {
        #expect(TokenmonRefreshReason.inboxEvent.resolvedScopes(insightsLoaded: false) == .runtime)
        #expect(
            TokenmonRefreshReason.inboxEvent.resolvedScopes(insightsLoaded: true)
                == [.runtime, .insights]
        )
        #expect(TokenmonRefreshReason.hotPath.resolvedScopes(insightsLoaded: true) == .runtime)
    }

    @Test
    func menuModelLoadsNotificationAuthorizationStateFromCoordinator() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let databasePath = directory.appendingPathComponent("tokenmon.sqlite").path
        let manager = TokenmonDatabaseManager(path: databasePath)
        try manager.bootstrap()

        let coordinator = CaptureNotificationCoordinatorSpy()
        coordinator.authorizationState = .denied

        let model = TokenmonMenuModel(
            databasePath: databasePath,
            providerInspector: { _, _, _ in [] },
            launchAtLoginStateProvider: { .unsupported(reason: "tests") },
            notificationCoordinator: coordinator
        )

        await model.waitForRefreshToFinish()
        #expect(model.notificationAuthorizationState == .denied)
    }

    @Test
    func freshInstallsDefaultCaptureNotificationsToOff() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let databasePath = directory.appendingPathComponent("tokenmon.sqlite").path
        let manager = TokenmonDatabaseManager(path: databasePath)
        try manager.bootstrap()

        #expect(try manager.appSettings().notificationsEnabled == false)
    }

    @Test
    func firstRunSetupPromptAutoPresentationPersistsOnceShown() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let databasePath = directory.appendingPathComponent("tokenmon.sqlite").path
        let manager = TokenmonDatabaseManager(path: databasePath)
        try manager.bootstrap()

        let coordinator = CaptureNotificationCoordinatorSpy()
        coordinator.authorizationState = .notDetermined

        let model = TokenmonMenuModel(
            databasePath: databasePath,
            providerInspector: { _, _, _ in [] },
            launchAtLoginStateProvider: {
                TokenmonLaunchAtLoginState(
                    isSupported: true,
                    isEnabled: false,
                    reason: TokenmonL10n.string("settings.launch_at_login.reason.disabled")
                )
            },
            notificationCoordinator: coordinator
        )

        await model.waitForRefreshToFinish()
        #expect(model.shouldShowSetupRecommendations)
        #expect(model.shouldAutoPresentOnboarding)

        model.markFirstRunOnboardingShown()

        #expect(!model.shouldAutoPresentOnboarding)
        #expect(try manager.appSettings().firstRunSetupPromptShown)
    }

    @Test
    func onboardingStepSequenceMatchesTwoStepFlow() {
        #expect(TokenmonFirstRunOnboardingStep.allCases == [.welcome, .setup])
        #expect(TokenmonFirstRunOnboardingStep.welcome.next == .setup)
        #expect(TokenmonFirstRunOnboardingStep.setup.previous == .welcome)
        #expect(TokenmonFirstRunOnboardingStep.setup.next == nil)
    }

    @Test
    func setupRecommendationsPreferExplicitEnableActions() {
        let items = TokenmonSetupRecommendationsBuilder.items(
            appSettings: AppSettings(notificationsEnabled: false),
            launchAtLoginState: TokenmonLaunchAtLoginState(
                isSupported: true,
                isEnabled: false,
                reason: TokenmonL10n.string("settings.launch_at_login.reason.disabled")
            ),
            notificationAuthorizationState: .notDetermined
        )

        #expect(items.map(\.action) == [.enableLaunchAtLogin, .enableCaptureNotifications])
    }

    @Test
    func setupRecommendationsUseRequestPermissionWhenNotificationsAreEnabledButUndetermined() {
        let items = TokenmonSetupRecommendationsBuilder.items(
            appSettings: AppSettings(notificationsEnabled: true),
            launchAtLoginState: TokenmonLaunchAtLoginState(
                isSupported: true,
                isEnabled: true,
                reason: TokenmonL10n.string("settings.launch_at_login.reason.enabled")
            ),
            notificationAuthorizationState: .notDetermined
        )

        #expect(items.map(\.action) == [.requestCaptureNotificationPermission])
    }

    @Test
    func setupRecommendationsRouteDeniedNotificationsToSystemSettings() {
        let items = TokenmonSetupRecommendationsBuilder.items(
            appSettings: AppSettings(notificationsEnabled: true),
            launchAtLoginState: TokenmonLaunchAtLoginState(
                isSupported: true,
                isEnabled: true,
                reason: TokenmonL10n.string("settings.launch_at_login.reason.enabled")
            ),
            notificationAuthorizationState: .denied
        )

        #expect(items.map(\.action) == [.openNotificationSettings])
    }

    @Test
    func setupRecommendationsAreEmptyWhenLaunchAndNotificationsAlreadyLookGood() {
        let items = TokenmonSetupRecommendationsBuilder.items(
            appSettings: AppSettings(notificationsEnabled: true),
            launchAtLoginState: TokenmonLaunchAtLoginState(
                isSupported: true,
                isEnabled: true,
                reason: TokenmonL10n.string("settings.launch_at_login.reason.enabled")
            ),
            notificationAuthorizationState: .authorized(alertsEnabled: true, soundsEnabled: true, alertStyle: 1)
        )

        #expect(items.isEmpty)
    }

    @Test
    func firstRunOnboardingStillAutoPresentsWhenSetupAlreadyLooksConfigured() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let databasePath = directory.appendingPathComponent("tokenmon.sqlite").path
        let manager = TokenmonDatabaseManager(path: databasePath)
        try manager.bootstrap()

        var settings = try manager.appSettings()
        settings.notificationsEnabled = true
        try manager.saveAppSettings(settings)

        let coordinator = CaptureNotificationCoordinatorSpy()
        coordinator.authorizationState = .authorized(alertsEnabled: true, soundsEnabled: true, alertStyle: 1)

        let model = TokenmonMenuModel(
            databasePath: databasePath,
            providerInspector: { _, _, _ in [] },
            launchAtLoginStateProvider: {
                .unsupported(reason: TokenmonL10n.string("settings.launch_at_login.reason.installed_only"))
            },
            notificationCoordinator: coordinator
        )

        await model.waitForRefreshToFinish()
        #expect(!model.shouldShowSetupRecommendations)
        #expect(model.shouldAutoPresentOnboarding)
    }

    @Test
    func firstRunSetupPromptDoesNotAutoPresentOnceGameplayHistoryExists() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let databasePath = directory.appendingPathComponent("tokenmon.sqlite").path
        let manager = TokenmonDatabaseManager(path: databasePath)
        try manager.bootstrap()

        _ = try manager.forgeEncounter(
            TokenmonDeveloperEncounterForgeRequest(
                provider: .codex,
                field: .sky,
                rarity: .uncommon,
                speciesID: "SKY_012",
                outcome: .captured,
                occurredAt: "2026-04-05T00:00:00Z"
            )
        )

        let coordinator = CaptureNotificationCoordinatorSpy()
        coordinator.authorizationState = .notDetermined

        let model = TokenmonMenuModel(
            databasePath: databasePath,
            providerInspector: { _, _, _ in [] },
            launchAtLoginStateProvider: {
                TokenmonLaunchAtLoginState(
                    isSupported: true,
                    isEnabled: false,
                    reason: TokenmonL10n.string("settings.launch_at_login.reason.disabled")
                )
            },
            notificationCoordinator: coordinator
        )

        await model.waitForRefreshToFinish()
        #expect(model.shouldShowSetupRecommendations)
        #expect(!model.shouldAutoPresentOnboarding)
    }

    @Test
    func usageAnalyticsPromptIsVisibleByDefaultAndDismissable() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let databasePath = directory.appendingPathComponent("tokenmon.sqlite").path
        let manager = TokenmonDatabaseManager(path: databasePath)
        try manager.bootstrap()

        let tracker = TokenmonAnalyticsTrackerSpy()
        let model = TokenmonMenuModel(
            databasePath: databasePath,
            providerInspector: { _, _, _ in [] },
            launchAtLoginStateProvider: { .unsupported(reason: "tests") },
            analyticsTracker: tracker
        )

        await model.waitForRefreshToFinish()
        #expect(model.shouldShowUsageAnalyticsPrompt)

        model.dismissUsageAnalyticsPrompt()
        #expect(!model.shouldShowUsageAnalyticsPrompt)
        #expect(try manager.appSettings().usageAnalyticsPromptDismissed)
        #expect(tracker.latestConsentSettings.usageAnalyticsPromptDismissed)
    }

    @Test
    func enablingUsageAnalyticsEmitsCatchUpAppOpenedOnce() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let databasePath = directory.appendingPathComponent("tokenmon.sqlite").path
        let manager = TokenmonDatabaseManager(path: databasePath)
        try manager.bootstrap()

        let database = try manager.open()
        try database.execute(
            """
            INSERT INTO provider_health (
                provider_code,
                source_mode,
                health_state,
                message,
                last_success_at,
                last_error_at,
                last_error_code,
                last_error_summary,
                updated_at
            ) VALUES (
                'claude',
                'claude_statusline_live',
                'active',
                'Claude ingest active via status line',
                '2026-04-10T10:12:00Z',
                NULL,
                NULL,
                NULL,
                '2026-04-10T10:12:00Z'
            )
            ON CONFLICT(provider_code, source_mode) DO UPDATE SET
                health_state = excluded.health_state,
                message = excluded.message,
                last_success_at = excluded.last_success_at,
                updated_at = excluded.updated_at;
            """
        )

        let tracker = TokenmonAnalyticsTrackerSpy()
        let model = TokenmonMenuModel(
            databasePath: databasePath,
            providerInspector: { _, _, _ in [] },
            launchAtLoginStateProvider: { .unsupported(reason: "tests") },
            analyticsTracker: tracker
        )

        await model.waitForRefreshToFinish()
        model.refresh(reason: .surfaceOpened(.settings))
        await model.waitForRefreshToFinish()
        #expect(tracker.events(named: "tokenmon_app_opened").isEmpty)

        model.updateUsageAnalyticsEnabled(true)
        model.emitAppOpenedAnalyticsIfNeeded()

        let appOpenedEvents = tracker.events(named: "tokenmon_app_opened")
        #expect(appOpenedEvents.count == 1)
        #expect(appOpenedEvents.first?.properties["has_latest_encounter"] == "false")
        #expect(appOpenedEvents.first?.properties["claude_connected"] == "true")
        #expect(appOpenedEvents.first?.properties["claude_live_gameplay_armed"] == "false")
        #expect(appOpenedEvents.first?.properties["codex_connected"] == "false")
        #expect(try manager.appSettings().usageAnalyticsEnabled)
    }

    @Test
    func menuModelSkipsInitialEncounterLoadForMenuBarPlayback() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let databasePath = directory.appendingPathComponent("tokenmon.sqlite").path
        let manager = TokenmonDatabaseManager(path: databasePath)
        try manager.bootstrap()

        _ = try manager.forgeEncounter(
            TokenmonDeveloperEncounterForgeRequest(
                provider: .codex,
                field: .sky,
                rarity: .uncommon,
                speciesID: "SKY_012",
                outcome: .captured,
                occurredAt: "2026-04-05T00:00:00Z"
            )
        )

        let model = TokenmonMenuModel(
            databasePath: databasePath,
            providerInspector: { _, _, _ in [] },
            launchAtLoginStateProvider: { .unsupported(reason: "tests") }
        )

        await model.waitForRefreshToFinish()

        #expect(model.consumePendingMenuBarEncounterAnimations().isEmpty)
    }

    @Test
    func menuModelAccumulatesNewMenuBarEncounterAnimationsUntilConsumed() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let databasePath = directory.appendingPathComponent("tokenmon.sqlite").path
        let manager = TokenmonDatabaseManager(path: databasePath)
        try manager.bootstrap()

        let model = TokenmonMenuModel(
            databasePath: databasePath,
            providerInspector: { _, _, _ in [] },
            launchAtLoginStateProvider: { .unsupported(reason: "tests") }
        )

        await model.waitForRefreshToFinish()
        #expect(model.consumePendingMenuBarEncounterAnimations().isEmpty)

        _ = try manager.forgeEncounter(
            TokenmonDeveloperEncounterForgeRequest(
                provider: .codex,
                field: .sky,
                rarity: .uncommon,
                speciesID: "SKY_012",
                outcome: .captured,
                occurredAt: "2026-04-05T00:00:00Z"
            )
        )
        model.refresh(reason: .hotPath)
        await model.waitForRefreshToFinish()

        _ = try manager.forgeEncounter(
            TokenmonDeveloperEncounterForgeRequest(
                provider: .codex,
                field: .sky,
                rarity: .uncommon,
                speciesID: "SKY_012",
                outcome: .escaped,
                occurredAt: "2026-04-05T00:05:00Z"
            )
        )
        model.refresh(reason: .hotPath)
        await model.waitForRefreshToFinish()

        let pendingAnimations = model.consumePendingMenuBarEncounterAnimations()
        #expect(pendingAnimations.map(\.encounterSequence) == [1, 2])
        #expect(model.consumePendingMenuBarEncounterAnimations().isEmpty)
    }

    @Test
    func encounterResolutionAnalyticsTracksFirstSeenAndFirstCapture() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let databasePath = directory.appendingPathComponent("tokenmon.sqlite").path
        let manager = TokenmonDatabaseManager(path: databasePath)
        try manager.bootstrap()

        var settings = try manager.appSettings()
        settings.usageAnalyticsEnabled = true
        settings.usageAnalyticsPromptDismissed = true
        try manager.saveAppSettings(settings)

        let tracker = TokenmonAnalyticsTrackerSpy()
        let model = TokenmonMenuModel(
            databasePath: databasePath,
            providerInspector: { _, _, _ in [] },
            launchAtLoginStateProvider: { .unsupported(reason: "tests") },
            analyticsTracker: tracker
        )

        await model.waitForRefreshToFinish()

        _ = try manager.forgeEncounter(
            TokenmonDeveloperEncounterForgeRequest(
                provider: .codex,
                field: .sky,
                rarity: .uncommon,
                speciesID: "SKY_012",
                outcome: .captured,
                occurredAt: "2026-04-05T00:00:00Z"
            )
        )

        model.refresh(reason: .hotPath)
        await model.waitForRefreshToFinish()

        let encounterEvents = tracker.events(named: "tokenmon_encounter_resolved")
        #expect(encounterEvents.count == 1)
        #expect(encounterEvents.first?.properties["provider"] == "codex")
        #expect(encounterEvents.first?.properties["is_first_seen"] == "true")
        #expect(encounterEvents.first?.properties["is_first_capture"] == "true")
    }

    @Test
    func providerHealthTransitionEmitsAnalyticsOnce() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let databasePath = directory.appendingPathComponent("tokenmon.sqlite").path
        let manager = TokenmonDatabaseManager(path: databasePath)
        try manager.bootstrap()

        var settings = try manager.appSettings()
        settings.usageAnalyticsEnabled = true
        settings.usageAnalyticsPromptDismissed = true
        try manager.saveAppSettings(settings)

        let tracker = TokenmonAnalyticsTrackerSpy()
        let model = TokenmonMenuModel(
            databasePath: databasePath,
            providerInspector: { _, _, _ in [] },
            launchAtLoginStateProvider: { .unsupported(reason: "tests") },
            analyticsTracker: tracker
        )

        await model.waitForRefreshToFinish()

        let database = try manager.open()
        try database.execute(
            """
            INSERT INTO provider_health (
                provider_code,
                source_mode,
                health_state,
                message,
                last_success_at,
                last_error_at,
                last_error_code,
                last_error_summary,
                updated_at
            ) VALUES (
                'claude',
                'claude_statusline_live',
                'active',
                'Claude ingest active via status line',
                '2026-04-10T10:12:00Z',
                NULL,
                NULL,
                NULL,
                '2026-04-10T10:12:00Z'
            )
            ON CONFLICT(provider_code, source_mode) DO UPDATE SET
                health_state = excluded.health_state,
                message = excluded.message,
                last_success_at = excluded.last_success_at,
                updated_at = excluded.updated_at;
            """
        )

        model.refresh(reason: .surfaceOpened(.settings))
        await model.waitForRefreshToFinish()

        let healthEvents = tracker.events(named: "tokenmon_provider_health_changed")
        #expect(healthEvents.count == 1)
        #expect(healthEvents.first?.properties["provider"] == "claude")
        #expect(healthEvents.first?.properties["health_state"] == "active")
    }

    @Test
    func analyticsTrackerCapturesNotificationOpenContext() {
        let tracker = TokenmonAnalyticsTrackerSpy()

        tracker.captureCaptureNotificationOpened(
            speciesID: "SKY_012",
            provider: .codex,
            field: .sky,
            rarity: .rare
        )

        let notificationEvents = tracker.events(named: "tokenmon_capture_notification_opened")
        #expect(notificationEvents.count == 1)
        #expect(notificationEvents.first?.properties["species_id"] == "SKY_012")
        #expect(notificationEvents.first?.properties["provider"] == "codex")
        #expect(notificationEvents.first?.properties["field"] == "sky")
        #expect(notificationEvents.first?.properties["rarity"] == "rare")
    }

    @Test
    func appBehaviorLoggerRoundTripsRecentEntries() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let supportDirectoryPath = directory.path
        TokenmonAppBehaviorLogger.notice(
            category: "tests",
            event: "roundtrip_event",
            metadata: ["source": "unit"],
            supportDirectoryPath: supportDirectoryPath
        )

        let deadline = Date().addingTimeInterval(2)
        var entries: [TokenmonAppLogEntry] = []
        repeat {
            entries = TokenmonAppBehaviorLogger.recentEntries(supportDirectoryPath: supportDirectoryPath, limit: 10)
            if entries.contains(where: { $0.event == "roundtrip_event" }) {
                break
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        } while Date() < deadline

        let matchingEntry = entries.first(where: { $0.event == "roundtrip_event" })
        #expect(matchingEntry?.category == "tests")
        #expect(matchingEntry?.metadata["source"] == "unit")
    }

    @Test
    func developerSurfaceLoadsRecentAppBehaviorLogs() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let databasePath = directory.appendingPathComponent("tokenmon.sqlite").path
        let manager = TokenmonDatabaseManager(path: databasePath)
        try manager.bootstrap()
        TokenmonAppBehaviorLogger.info(
            category: "tests",
            event: "developer_surface_log",
            metadata: ["path": "developer"],
            supportDirectoryPath: directory.path
        )

        let model = TokenmonMenuModel(
            databasePath: databasePath,
            providerInspector: { _, _, _ in [] },
            launchAtLoginStateProvider: { .unsupported(reason: "tests") }
        )

        await model.waitForRefreshToFinish()
        model.surfaceOpened(.developer)
        await model.waitForRefreshToFinish()

        #expect(model.recentAppLogEntries.contains(where: {
            $0.category == "tests" && $0.event == "developer_surface_log"
        }))
    }

    @Test
    func refreshLogsIncludeTimingMetadata() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let databasePath = directory.appendingPathComponent("tokenmon.sqlite").path
        let manager = TokenmonDatabaseManager(path: databasePath)
        try manager.bootstrap()

        let model = TokenmonMenuModel(
            databasePath: databasePath,
            providerInspector: { _, _, _ in [] },
            launchAtLoginStateProvider: { .unsupported(reason: "tests") }
        )

        await model.waitForRefreshToFinish()

        let entries = TokenmonAppBehaviorLogger.recentEntries(
            supportDirectoryPath: directory.path,
            limit: 20
        )

        let refreshCompleted = entries.first(where: { $0.event == "refresh_completed" })
        let snapshotCompleted = entries.first(where: { $0.event == "snapshot_load_completed" })

        #expect(refreshCompleted?.metadata["duration_ms"] != nil)
        #expect(refreshCompleted?.metadata["scopes"] == "runtime")
        #expect(snapshotCompleted?.metadata["duration_ms"] != nil)
        #expect(snapshotCompleted?.metadata["scopes"] == "runtime")
    }

    @Test
    func developerPreviewCaptureNotificationUsesCoordinatorWithoutMutatingDex() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let databasePath = directory.appendingPathComponent("tokenmon.sqlite").path
        let manager = TokenmonDatabaseManager(path: databasePath)
        try manager.bootstrap()

        let coordinator = CaptureNotificationCoordinatorSpy()
        let model = TokenmonMenuModel(
            databasePath: databasePath,
            providerInspector: { _, _, _ in [] },
            launchAtLoginStateProvider: { .unsupported(reason: "tests") },
            notificationCoordinator: coordinator
        )

        await model.waitForRefreshToFinish()
        model.sendCaptureNotificationPreview(speciesID: "SKY_012")

        #expect(coordinator.previewRequests.count == 1)
        #expect(coordinator.previewRequests.first?.speciesID == "SKY_012")
        #expect(coordinator.previewRequests.first?.assetKey == "sky_012_nimbusray")
        #expect(model.settingsMessage == "Preview scheduled")
        #expect(model.settingsError == nil)
        #expect(try manager.currentRunSummary().totalCaptures == 0)
        #expect(try manager.recentEncounterSummaries(limit: 1).isEmpty)
    }

    @Test
    func notificationAttachmentURLPrefersApprovedPortraitSource() {
        let url = TokenmonSpeciesSpriteLoader.notificationAttachmentURL(assetKey: "sky_012_nimbusray")

        #expect(url?.path.contains("/approved-portraits/sky_012_nimbusray.png") == true)
    }

    @Test
    func notificationAttachmentURLReturnsNilForMissingSpeciesArt() {
        #expect(TokenmonSpeciesSpriteLoader.notificationAttachmentURL(assetKey: "missing_species") == nil)
    }

    @Test
    func notificationSettingsURLsPreferAppSpecificTargetBeforeFallbacks() {
        let urls = TokenmonSystemSettingsOpener.notificationSettingsURLs(bundleIdentifier: "com.aroido.tokenmon")

        #expect(
            urls.map(\.absoluteString) == [
                "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=com.aroido.tokenmon",
                "x-apple.systempreferences:com.apple.preference.notifications?id=com.aroido.tokenmon",
                "x-apple.systempreferences:com.apple.Notifications-Settings.extension",
                "x-apple.systempreferences:com.apple.preference.notifications",
                "x-apple.systempreferences:",
            ]
        )
    }

    @Test
    func notificationSettingsDestinationsCarryStructuredResults() {
        let destinations = TokenmonSystemSettingsOpener.notificationSettingsDestinations(
            bundleIdentifier: "com.aroido.tokenmon"
        )

        #expect(
            destinations.map(\.result) == [
                .openedAppSpecific,
                .openedAppSpecific,
                .openedGenericNotifications,
                .openedGenericNotifications,
                .openedSystemSettingsRoot,
            ]
        )
    }

    @Test
    func notificationSettingsOpenerReturnsMatchingResult() {
        let result = TokenmonSystemSettingsOpener.openNotificationSettings(
            bundleIdentifier: "com.aroido.tokenmon",
            openURL: { url in
                url.absoluteString == "x-apple.systempreferences:com.apple.preference.notifications"
            }
        )

        #expect(result == .openedGenericNotifications)
    }

    @Test
    func notificationSettingsOpenerReturnsAppSpecificResult() {
        let result = TokenmonSystemSettingsOpener.openNotificationSettings(
            bundleIdentifier: "com.aroido.tokenmon",
            openURL: { url in
                url.absoluteString == "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=com.aroido.tokenmon"
            }
        )

        #expect(result == .openedAppSpecific)
    }

    @Test
    func notificationSettingsOpenerReturnsFailureWhenNoDestinationOpens() {
        let result = TokenmonSystemSettingsOpener.openNotificationSettings(
            bundleIdentifier: "com.aroido.tokenmon",
            openURL: { _ in false }
        )

        #expect(result == .failed)
    }

    @Test
    func openSystemNotificationSettingsUsesStructuredSuccessMessages() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let databasePath = directory.appendingPathComponent("tokenmon.sqlite").path
        let manager = TokenmonDatabaseManager(path: databasePath)
        try manager.bootstrap()

        let model = TokenmonMenuModel(
            databasePath: databasePath,
            providerInspector: { _, _, _ in [] },
            launchAtLoginStateProvider: { .unsupported(reason: "tests") },
            notificationSettingsOpener: { .openedGenericNotifications }
        )

        await model.waitForRefreshToFinish()
        model.openSystemNotificationSettings()

        #expect(
            model.settingsMessage == TokenmonL10n.string("settings.feedback.opened_notification_settings_generic")
        )
        #expect(model.settingsError == nil)
    }

    @Test
    func openSystemNotificationSettingsUsesFailureMessageWhenOpenFails() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let databasePath = directory.appendingPathComponent("tokenmon.sqlite").path
        let manager = TokenmonDatabaseManager(path: databasePath)
        try manager.bootstrap()

        let model = TokenmonMenuModel(
            databasePath: databasePath,
            providerInspector: { _, _, _ in [] },
            launchAtLoginStateProvider: { .unsupported(reason: "tests") },
            notificationSettingsOpener: { .failed }
        )

        await model.waitForRefreshToFinish()
        model.openSystemNotificationSettings()

        #expect(model.settingsMessage == nil)
        #expect(model.settingsError == TokenmonL10n.string("settings.feedback.failed_notification_settings"))
    }

    @Test
    func openLoginItemsSettingsUsesInjectedOpenerAndSetsFeedback() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let databasePath = directory.appendingPathComponent("tokenmon.sqlite").path
        let manager = TokenmonDatabaseManager(path: databasePath)
        try manager.bootstrap()

        final class Box: @unchecked Sendable {
            var count = 0
        }
        let box = Box()

        let model = TokenmonMenuModel(
            databasePath: databasePath,
            providerInspector: { _, _, _ in [] },
            launchAtLoginStateProvider: {
                TokenmonLaunchAtLoginState(
                    isSupported: true,
                    isEnabled: false,
                    reason: TokenmonL10n.string("settings.launch_at_login.reason.requires_approval"),
                    showsOpenSystemSettingsAction: true
                )
            },
            loginItemsSettingsOpener: {
                box.count += 1
            }
        )

        await model.waitForRefreshToFinish()
        model.openLoginItemsSettings()

        #expect(box.count == 1)
        #expect(model.settingsMessage == TokenmonL10n.string("settings.feedback.opened_login_items_settings"))
        #expect(model.settingsError == nil)
    }

    @Test
    func notificationSettingsURLsFallbackWithoutBundleIdentifier() {
        let urls = TokenmonSystemSettingsOpener.notificationSettingsURLs(bundleIdentifier: nil)

        #expect(
            urls.map(\.absoluteString) == [
                "x-apple.systempreferences:com.apple.Notifications-Settings.extension",
                "x-apple.systempreferences:com.apple.preference.notifications",
                "x-apple.systempreferences:",
            ]
        )
    }

    @Test
    func brandLinksStayOrderedAndPointToPublicDestinations() {
        #expect(TokenmonBrandLink.allCases == [.website, .github])
        #expect(TokenmonBrandLink.website.destination.absoluteString == "https://aroido.com/")
        #expect(TokenmonBrandLink.github.destination.absoluteString == "https://github.com/aroido/tokenmon")
        #expect(TokenmonBrandLink.website.displayValue == "aroido.com")
        #expect(TokenmonBrandLink.github.displayValue == "github.com/aroido/tokenmon")
        #expect(TokenmonBrandLink.github.brandMarkImage(forDarkAppearance: false) != nil)
        #expect(TokenmonBrandLink.github.brandMarkImage(forDarkAppearance: true) != nil)
    }

    @Test
    func codexTranscriptBackfillSkipsRunRecordsForNoopAndDuplicateOnlyDeltas() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let databasePath = directory.appendingPathComponent("tokenmon.sqlite").path
        let transcriptPath = directory.appendingPathComponent("codex-transcript.jsonl").path
        let manager = TokenmonDatabaseManager(path: databasePath)
        try manager.bootstrap()
        try manager.resetProgress(startedAt: "2000-01-01T00:00:00Z")
        _ = try SpeciesSeeder.seed(databasePath: databasePath)

        try writeTranscriptLines(
            [
                codexSessionMetaLine(sessionID: "session-backfill"),
                codexTokenCountLine(
                    timestamp: "2026-04-09T00:00:00Z",
                    inputTokens: 120,
                    cachedInputTokens: 0,
                    outputTokens: 80,
                    lastInputTokens: 120,
                    lastOutputTokens: 80
                ),
            ],
            to: transcriptPath
        )

        let firstResult = try CodexTranscriptBackfillService.run(
            databasePath: databasePath,
            providerSessionID: nil,
            transcriptPath: transcriptPath
        )

        #expect(firstResult.status == "completed")
        #expect(firstResult.samplesCreated == 1)
        #expect(try manager.summary().usageSamples == 1)
        #expect(try rowCount(in: "backfill_runs", databasePath: databasePath) == 1)
        #expect(try backfillDomainEventCount(databasePath: databasePath) == 2)

        let secondResult = try CodexTranscriptBackfillService.run(
            databasePath: databasePath,
            providerSessionID: nil,
            transcriptPath: transcriptPath
        )

        #expect(secondResult.status == "noop")
        #expect(secondResult.backfillRunID == 0)
        #expect(try rowCount(in: "backfill_runs", databasePath: databasePath) == 1)
        #expect(try backfillDomainEventCount(databasePath: databasePath) == 2)

        try appendTranscriptLines(
            [
                """
                {"type":"event_msg","timestamp":"2026-04-09T00:01:00Z","payload":{"type":"turn_completed","id":"turn-002"}}
                """,
            ],
            to: transcriptPath
        )

        let thirdResult = try CodexTranscriptBackfillService.run(
            databasePath: databasePath,
            providerSessionID: nil,
            transcriptPath: transcriptPath
        )

        #expect(thirdResult.status == "noop")
        #expect(try rowCount(in: "backfill_runs", databasePath: databasePath) == 1)
        #expect(try backfillDomainEventCount(databasePath: databasePath) == 2)

        try appendTranscriptLines(
            [
                codexTokenCountLine(
                    timestamp: "2026-04-09T00:02:00Z",
                    inputTokens: 240,
                    cachedInputTokens: 0,
                    outputTokens: 140,
                    lastInputTokens: 120,
                    lastOutputTokens: 60
                ),
            ],
            to: transcriptPath
        )

        let fourthResult = try CodexTranscriptBackfillService.run(
            databasePath: databasePath,
            providerSessionID: nil,
            transcriptPath: transcriptPath
        )

        #expect(fourthResult.status == "completed")
        #expect(fourthResult.samplesCreated == 1)
        #expect(try manager.summary().usageSamples == 2)
        #expect(try rowCount(in: "backfill_runs", databasePath: databasePath) == 2)
        #expect(try backfillDomainEventCount(databasePath: databasePath) == 4)
    }

    private func makeSummary(
        totalNormalizedTokens: Int64 = 0,
        tokensSinceLastEncounter: Int64 = 0,
        tokensUntilNextEncounter: Int64 = 3_000,
        nextEncounterThresholdTokens: Int64? = nil,
        totalEncounters: Int64 = 0,
        totalCaptures: Int64 = 0,
        seenSpeciesCount: Int = 0,
        capturedSpeciesCount: Int = 0
    ) -> CurrentRunSummary {
        let requiredTokens = nextEncounterThresholdTokens ?? max(tokensSinceLastEncounter + tokensUntilNextEncounter, 1)
        return CurrentRunSummary(
            providerSessions: 1,
            usageSamples: 1,
            totalNormalizedTokens: totalNormalizedTokens,
            tokensSinceLastEncounter: tokensSinceLastEncounter,
            nextEncounterThresholdTokens: requiredTokens,
            tokensUntilNextEncounter: tokensUntilNextEncounter,
            totalEncounters: totalEncounters,
            totalCaptures: totalCaptures,
            seenSpeciesCount: seenSpeciesCount,
            capturedSpeciesCount: capturedSpeciesCount,
            latestUsageSampleObservedAt: "2026-04-05T00:00:00Z",
            latestEncounterOccurredAt: "2026-04-05T00:01:00Z"
        )
    }

    private func makeEncounter(
        sequence: Int64 = 1,
        outcome: EncounterOutcome,
        seenCount: Int64 = 1,
        capturedCount: Int64? = nil,
        affinityLevel: Int64 = 0,
        affinityPityCount: Int64 = 0,
        affinityLastProbability: Double? = nil,
        affinityLastOutcome: String? = nil
    ) -> RecentEncounterSummary {
        let resolvedCapturedCount = capturedCount ?? (outcome == .captured ? 1 : 0)
        return RecentEncounterSummary(
            encounterID: "enc_\(sequence)",
            encounterSequence: sequence,
            occurredAt: "2026-04-05T00:01:00Z",
            provider: .codex,
            field: .sky,
            rarity: .rare,
            speciesID: "SKY_012",
            speciesName: "Nimbusray",
            assetKey: "sky_012_nimbusray",
            seenCount: seenCount,
            capturedCount: resolvedCapturedCount,
            affinityLevel: affinityLevel,
            affinityPityCount: affinityPityCount,
            affinityLastProbability: affinityLastProbability,
            affinityLastOutcome: affinityLastOutcome,
            burstIntensityBand: 2,
            captureProbability: 0.6,
            captureRoll: 0.2,
            outcome: outcome
        )
    }

    private func makeRuntimeSnapshot(
        latestEncounter: RecentEncounterSummary?,
        recentEncounterFeed: [RecentEncounterSummary],
        isLoaded: Bool = true
    ) -> TokenmonRuntimeSnapshot {
        TokenmonRuntimeSnapshot(
            isLoaded: isLoaded,
            summary: makeSummary(
                totalEncounters: Int64(recentEncounterFeed.count),
                totalCaptures: Int64(recentEncounterFeed.filter { $0.outcome == .captured }.count)
            ),
            latestEncounter: latestEncounter,
            recentEncounterFeed: recentEncounterFeed,
            todayActivity: nil,
            providerHealthSummaries: [],
            ambientCompanionRoster: .byField([:])
        )
    }

    private func makeProviderHealth(
        provider: ProviderCode,
        healthState: String,
        message: String
    ) -> ProviderHealthSummary {
        ProviderHealthSummary(
            provider: provider,
            sourceMode: provider == .claude ? "claude_statusline_live" : "codex_exec_json",
            healthState: healthState,
            supportLevel: provider.defaultSupportLevel,
            reliabilityLabel: provider == .codex ? "managed_first_class" : "first_class",
            message: message,
            offlineDashboardRecovery: provider == .codex ? "automatic_supported" : provider == .claude ? "known_transcript_only" : "unavailable",
            liveGameplayArmed: provider != .gemini,
            diagnosticFacts: [:],
            lastSuccessAt: nil,
            lastErrorAt: nil,
            lastErrorSummary: nil,
            lastObservedAt: nil,
            lastBackfillMode: nil,
            lastBackfillStatus: nil,
            lastBackfillCompletedAt: nil,
            lastBackfillSummary: nil
        )
    }

    @Test
    func speciesSpriteLoaderLoadsGrasslandStarterPortraits() {
        let assetKeys = [
            "grs_001_mossbun",
            "grs_002_pebblequail",
            "grs_003_seedkit",
            "grs_004_fernfawn",
            "grs_005_sprigmouse",
            "grs_006_pollenpup",
            "grs_007_twiglet",
            "grs_008_acornip",
            "grs_009_clovercub",
            "grs_010_bramblefinch",
        ]

        for assetKey in assetKeys {
            let image = TokenmonSpeciesSpriteLoader.image(assetKey: assetKey, variant: .portrait32)
            #expect(image != nil)
            #expect((image?.size.width ?? 0) > 0)
            #expect((image?.size.height ?? 0) > 0)
            #expect((image?.size.width ?? 0) <= 64)
            #expect((image?.size.height ?? 0) <= 64)
        }
    }

    private func makeDexEntry(
        status: DexEntryStatus,
        sortOrder: Int = 1,
        speciesName: String? = nil,
        field: FieldType = .grassland,
        rarity: RarityTier = .rare,
        seenCount: Int64? = nil,
        capturedCount: Int64? = nil,
        affinityLevel: Int64 = 0,
        affinityPityCount: Int64 = 0,
        affinityLastProbability: Double? = nil,
        affinityLastOutcome: String? = nil,
        trainingTrait: TrainingTrait = .trail,
        trainingRank: TrainingRank = .rankI,
        trainingAttemptCount: Int = 0,
        traits: [String] = []
    ) -> DexEntrySummary {
        let resolvedSeenCount = seenCount ?? (status == .unknown ? 0 : 2)
        let resolvedCapturedCount = capturedCount ?? (status == .captured ? 1 : 0)
        return DexEntrySummary(
            speciesID: "SPC_\(sortOrder)",
            speciesName: speciesName ?? "Specimon \(sortOrder)",
            field: field,
            rarity: rarity,
            assetKey: "spc_\(sortOrder)",
            flavorText: resolvedCapturedCount > 0 ? "A placeholder field note for Specimon \(sortOrder)." : nil,
            sortOrder: sortOrder,
            status: status,
            seenCount: resolvedSeenCount,
            capturedCount: resolvedCapturedCount,
            firstSeenAt: resolvedSeenCount > 0 ? "2026-04-05T00:00:00Z" : nil,
            lastSeenAt: resolvedSeenCount > 0 ? "2026-04-05T01:00:00Z" : nil,
            firstCapturedAt: resolvedCapturedCount > 0 ? "2026-04-05T00:30:00Z" : nil,
            lastCapturedAt: resolvedCapturedCount > 0 ? "2026-04-05T01:30:00Z" : nil,
            affinityLevel: affinityLevel,
            affinityPityCount: affinityPityCount,
            affinityLastProbability: affinityLastProbability,
            affinityLastOutcome: affinityLastOutcome,
            trainingTrait: trainingTrait,
            trainingRank: trainingRank,
            trainingAttemptCount: trainingAttemptCount,
            stats: SpeciesStatBlock(
                planning: 1,
                design: 1,
                frontend: 1,
                backend: 1,
                pm: 1,
                infra: 1,
                traits: traits
            )
        )
    }

    private func makeUsageEvent(
        observedAt: String,
        fingerprint: String,
        providerSessionID: String = "session-1",
        normalizedTotalTokens: Int64 = 200,
        totalInputTokens: Int64 = 120,
        totalOutputTokens: Int64 = 80,
        totalCachedInputTokens: Int64 = 0,
        currentInputTokens: Int64? = 120,
        currentOutputTokens: Int64? = 80
    ) -> ProviderUsageSampleEvent {
        ProviderUsageSampleEvent(
            eventType: "provider_usage_sample",
            provider: .codex,
            sourceMode: "codex_exec_json",
            providerSessionID: providerSessionID,
            observedAt: observedAt,
            workspaceDir: "/tmp/tokenmon-tests",
            modelSlug: "gpt-test",
            transcriptPath: nil,
            totalInputTokens: totalInputTokens,
            totalOutputTokens: totalOutputTokens,
            totalCachedInputTokens: totalCachedInputTokens,
            normalizedTotalTokens: normalizedTotalTokens,
            providerEventFingerprint: fingerprint,
            rawReference: ProviderRawReference(kind: "test", offset: "1", eventName: "turn.completed"),
            currentInputTokens: currentInputTokens,
            currentOutputTokens: currentOutputTokens
        )
    }

    private func makeDomainEventRecord<Payload: Encodable>(
        type: TokenmonDomainEventType,
        occurredAt: String,
        aggregateID: String,
        payload: Payload
    ) throws -> PersistedDomainEventRecord {
        let payloadJSON = try String(decoding: JSONEncoder().encode(payload), as: UTF8.self)
        return PersistedDomainEventRecord(
            eventID: "\(type.rawValue):\(aggregateID)",
            eventType: type.rawValue,
            occurredAt: occurredAt,
            producer: "tests",
            correlationID: nil,
            causationID: nil,
            aggregateType: "encounter",
            aggregateID: aggregateID,
            payloadJSON: payloadJSON,
            createdAt: occurredAt
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func runShellCommand(command: String, stdin: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]

        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = Pipe()

        try process.run()
        try input.fileHandleForWriting.write(contentsOf: Data(stdin.utf8))
        try input.fileHandleForWriting.close()
        process.waitUntilExit()

        let data = output.fileHandleForReading.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self)
    }

    private func makeFakeAppBundle(appURL: URL) throws -> Bundle {
        let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)
        let macOSURL = contentsURL.appendingPathComponent("MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: macOSURL, withIntermediateDirectories: true)

        let infoPlistURL = contentsURL.appendingPathComponent("Info.plist", isDirectory: false)
        let payload: [String: Any] = [
            "CFBundleExecutable": "TokenmonApp",
            "CFBundleIdentifier": "com.aroido.tokenmon",
            "CFBundleName": "Tokenmon",
            "CFBundlePackageType": "APPL",
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: payload,
            format: .xml,
            options: 0
        )
        try data.write(to: infoPlistURL, options: .atomic)
        let executableURL = macOSURL.appendingPathComponent("TokenmonApp", isDirectory: false)
        FileManager.default.createFile(atPath: executableURL.path, contents: Data())
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executableURL.path
        )

        guard let bundle = Bundle(url: appURL) else {
            throw NSError(domain: "TokenmonPresentationTests", code: 1)
        }

        return bundle
    }

    private func writeInboxEvents(_ events: [ProviderUsageSampleEvent], to path: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let payload = try events
            .map { String(decoding: try encoder.encode($0), as: UTF8.self) }
            .joined(separator: "\n") + "\n"
        try payload.write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
    }

    private func appendInboxEvents(_ events: [ProviderUsageSampleEvent], to path: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let payload = try events
            .map { String(decoding: try encoder.encode($0), as: UTF8.self) }
            .joined(separator: "\n") + "\n"

        let fileHandle = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
        defer { try? fileHandle.close() }
        try fileHandle.seekToEnd()
        try fileHandle.write(contentsOf: Data(payload.utf8))
    }

    private func writeTranscriptLines(_ lines: [String], to path: String) throws {
        let payload = lines.joined(separator: "\n") + "\n"
        try payload.write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
    }

    private func appendTranscriptLines(_ lines: [String], to path: String) throws {
        let payload = lines.joined(separator: "\n") + "\n"
        let fileHandle = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
        defer { try? fileHandle.close() }
        try fileHandle.seekToEnd()
        try fileHandle.write(contentsOf: Data(payload.utf8))
    }

    private func codexSessionMetaLine(sessionID: String) -> String {
        """
        {"type":"session_meta","payload":{"id":"\(sessionID)","cwd":"/tmp/tokenmon-tests","model":"gpt-5.4"}}
        """
    }

    private func codexTokenCountLine(
        timestamp: String,
        inputTokens: Int64,
        cachedInputTokens: Int64,
        outputTokens: Int64,
        lastInputTokens: Int64,
        lastOutputTokens: Int64
    ) -> String {
        """
        {"type":"event_msg","timestamp":"\(timestamp)","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":\(inputTokens),"cached_input_tokens":\(cachedInputTokens),"output_tokens":\(outputTokens),"total_tokens":\(inputTokens + outputTokens)},"last_token_usage":{"input_tokens":\(lastInputTokens),"output_tokens":\(lastOutputTokens)}}}}
        """
    }

    private func claudeTranscriptLine(
        sessionID: String,
        messageID: String,
        timestamp: String,
        inputTokens: Int64,
        outputTokens: Int64,
        cacheCreationInputTokens: Int64,
        cacheReadInputTokens: Int64
    ) -> String {
        """
        {"session_id":"\(sessionID)","cwd":"/tmp/tokenmon-tests","type":"assistant","message":{"id":"\(messageID)","model":{"id":"claude-opus-4-1"},"usage":{"input_tokens":\(inputTokens),"output_tokens":\(outputTokens),"cache_creation_input_tokens":\(cacheCreationInputTokens),"cache_read_input_tokens":\(cacheReadInputTokens)}},"timestamp":"\(timestamp)"}
        """
    }

    private func rowCount(in table: String, databasePath: String) throws -> Int64 {
        let database = try TokenmonDatabaseManager(path: databasePath).open()
        return try database.fetchOne("SELECT COUNT(*) FROM \(table);") { statement in
            SQLiteDatabase.columnInt64(statement, index: 0)
        } ?? 0
    }

    private func backfillDomainEventCount(databasePath: String) throws -> Int64 {
        let database = try TokenmonDatabaseManager(path: databasePath).open()
        return try database.fetchOne(
            """
            SELECT COUNT(*)
            FROM domain_events
            WHERE event_type IN ('backfill_started', 'backfill_completed');
            """
        ) { statement in
            SQLiteDatabase.columnInt64(statement, index: 0)
        } ?? 0
    }

    private func waitUntil(
        timeout: Duration,
        pollInterval: Duration = .milliseconds(25),
        condition: () throws -> Bool
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)

        while clock.now < deadline {
            if (try? condition()) == true {
                return true
            }

            try? await Task.sleep(for: pollInterval)
        }

        return (try? condition()) == true
    }

    private func dominantCueToken(_ cue: TokenmonFieldDominantCue) -> String {
        switch cue {
        case .meadowStage:
            return "meadow"
        case .iceFlurry:
            return "ice"
        case .cloudShelf:
            return "cloud"
        case .shoreline:
            return "shore"
        case .neutral:
            return "neutral"
        }
    }

    private func sceneState(for effectState: TokenmonEffectState) -> TokenmonSceneState {
        switch effectState {
        case .none:
            return .idle
        case .alert:
            return .alert
        case .captureSnap:
            return .resolveSuccess
        case .escapeDash:
            return .resolveEscape
        }
    }

    private func fieldState(for effectState: TokenmonEffectState) -> TokenmonFieldState {
        switch effectState {
        case .none:
            return .calm
        case .alert:
            return .rustle
        case .captureSnap, .escapeDash:
            return .settle
        }
    }

    private func makeOnboardingStatus(
        provider: ProviderCode,
        cliInstalled: Bool,
        isConnected: Bool,
        isPartial: Bool,
        title: String,
        codexMode: CodexConnectionMode? = nil
    ) -> TokenmonProviderOnboardingStatus {
        TokenmonProviderOnboardingStatus(
            provider: provider,
            cliInstalled: cliInstalled,
            isConnected: isConnected,
            isPartial: isPartial,
            title: title,
            detail: "\(provider.displayName) status detail",
            actionTitle: isConnected ? nil : "Connect",
            executablePath: cliInstalled ? "/usr/local/bin/\(provider.rawValue)" : nil,
            executableSource: cliInstalled ? .shellLookup : .unavailable,
            configurationPath: "/tmp/\(provider.rawValue)",
            configurationSource: .commonLocation,
            usesCustomExecutablePath: false,
            usesCustomConfigurationPath: false,
            codexMode: codexMode
        )
    }

    private func makeHealthSummary(
        provider: ProviderCode,
        sourceMode: String?,
        healthState: String,
        supportLevel: String
    ) -> ProviderHealthSummary {
        ProviderHealthSummary(
            provider: provider,
            sourceMode: sourceMode,
            healthState: healthState,
            supportLevel: supportLevel,
            reliabilityLabel: healthState == "degraded" ? "degraded" : provider == .cursor ? "stats_only" : provider == .codex && sourceMode == "codex_exec_json" ? "managed_first_class" : supportLevel,
            message: "\(provider.displayName) health message",
            offlineDashboardRecovery: provider == .codex ? "automatic_supported" : provider == .claude ? "known_transcript_only" : "unavailable",
            liveGameplayArmed: provider == .codex,
            diagnosticFacts: [:],
            lastSuccessAt: nil,
            lastErrorAt: nil,
            lastErrorSummary: nil,
            lastObservedAt: nil,
            lastBackfillMode: nil,
            lastBackfillStatus: nil,
            lastBackfillCompletedAt: nil,
            lastBackfillSummary: nil
        )
    }

    private final class CaptureNotificationCoordinatorSpy: TokenmonCaptureNotificationCoordinating {
        struct PreviewRequest {
            let speciesID: String
            let assetKey: String
            let speciesName: String
            let subtitle: String
        }

        private(set) var previewRequests: [PreviewRequest] = []
        private(set) var capturePreferenceChanges: [Bool] = []
        private(set) var updatePreferenceChanges: [Bool] = []
        var authorizationState: TokenmonNotificationAuthorizationState = .unknown

        func start() {}

        func fetchAuthorizationState(
            completion: @escaping @MainActor (TokenmonNotificationAuthorizationState) -> Void
        ) {
            completion(authorizationState)
        }

        func runtimeDidRefresh(
            from _: TokenmonRuntimeSnapshot,
            to _: TokenmonRuntimeSnapshot,
            settings _: AppSettings
        ) {}

        func sendPreviewCaptureNotification(
            speciesID: String,
            assetKey: String,
            speciesName: String,
            subtitle: String,
            completion: @escaping @MainActor (String?, String?) -> Void
        ) {
            previewRequests.append(
                PreviewRequest(
                    speciesID: speciesID,
                    assetKey: assetKey,
                    speciesName: speciesName,
                    subtitle: subtitle
                )
            )
            completion("Preview scheduled", nil)
        }

        func notificationsPreferenceDidChange(
            isEnabled: Bool,
            completion: @escaping @MainActor (String?, String?) -> Void
        ) {
            capturePreferenceChanges.append(isEnabled)
            completion(nil, nil)
        }

        func updateNotificationsPreferenceDidChange(
            isEnabled: Bool,
            completion: @escaping @MainActor (String?, String?) -> Void
        ) {
            updatePreferenceChanges.append(isEnabled)
            completion(nil, nil)
        }

        func sendUpdateAvailableNotification(
            version _: String,
            completion: (@MainActor @Sendable (Bool) -> Void)?
        ) {
            completion?(false)
        }
    }

    @Test
    func updateReadyAlertsDefaultToOffInSettingsPersistence() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let databasePath = directory.appendingPathComponent("tokenmon.sqlite").path
        let manager = TokenmonDatabaseManager(path: databasePath)
        try manager.bootstrap()

        let model = TokenmonMenuModel(
            databasePath: databasePath,
            providerInspector: { _, _, _ in [] },
            launchAtLoginStateProvider: { .unsupported(reason: "tests") }
        )

        await model.waitForRefreshToFinish()

        #expect(model.appSettings.updateNotificationsEnabled == false)
        #expect(try manager.appSettings().updateNotificationsEnabled == false)
    }

    @Test
    func enablingUpdateReadyAlertsPersistsPreferenceAndRequestsAuthorization() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let databasePath = directory.appendingPathComponent("tokenmon.sqlite").path
        let manager = TokenmonDatabaseManager(path: databasePath)
        try manager.bootstrap()

        let coordinator = CaptureNotificationCoordinatorSpy()
        coordinator.authorizationState = .authorized(alertsEnabled: true, soundsEnabled: true, alertStyle: 1)

        let model = TokenmonMenuModel(
            databasePath: databasePath,
            providerInspector: { _, _, _ in [] },
            launchAtLoginStateProvider: { .unsupported(reason: "tests") },
            notificationCoordinator: coordinator
        )

        await model.waitForRefreshToFinish()
        model.updateUpdateNotificationsEnabled(true)

        #expect(model.appSettings.updateNotificationsEnabled)
        #expect(try manager.appSettings().updateNotificationsEnabled)
        #expect(coordinator.updatePreferenceChanges == [true])
    }

    @Test
    func disablingUpdateReadyAlertsPersistsWithoutPrompting() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let databasePath = directory.appendingPathComponent("tokenmon.sqlite").path
        let manager = TokenmonDatabaseManager(path: databasePath)
        try manager.bootstrap()

        var settings = try manager.appSettings()
        settings.updateNotificationsEnabled = true
        try manager.saveAppSettings(settings)

        let coordinator = CaptureNotificationCoordinatorSpy()
        let model = TokenmonMenuModel(
            databasePath: databasePath,
            providerInspector: { _, _, _ in [] },
            launchAtLoginStateProvider: { .unsupported(reason: "tests") },
            notificationCoordinator: coordinator
        )

        await model.waitForRefreshToFinish()
        model.updateUpdateNotificationsEnabled(false)

        #expect(model.appSettings.updateNotificationsEnabled == false)
        #expect(try manager.appSettings().updateNotificationsEnabled == false)
        #expect(coordinator.updatePreferenceChanges == [false])
    }

    @Test
    func statusItemShortcutMenuUsesCompactQuickActionsByDefault() {
        #expect(
            TokenmonStatusItemShortcutMenuItem.defaultItems(developerToolsVisible: false) == [
                .popover(.now),
                .popover(.raid),
                .popover(.tokens),
                .popover(.stats),
                .separator,
                .dexWindow,
                .settingsWindow,
                .separator,
                .quit,
            ]
        )
    }

    @Test
    func statusItemShortcutMenuAddsDeveloperToolsOnlyWhenEnabled() {
        #expect(
            TokenmonStatusItemShortcutMenuItem.defaultItems(developerToolsVisible: true) == [
                .popover(.now),
                .popover(.raid),
                .popover(.tokens),
                .popover(.stats),
                .separator,
                .dexWindow,
                .settingsWindow,
                .developerTools,
                .separator,
                .quit,
            ]
        )
    }

    @Test
    func raidArtLoaderLoadsSeededRaidAssets() {
        #expect(TokenmonRaidArtLoader.image(artKey: "raid_backdrop_treasure_vault") != nil)
        #expect(TokenmonRaidArtLoader.image(artKey: "raid_backdrop_token_vault_chamber") != nil)
        #expect(TokenmonRaidArtLoader.image(artKey: "raid_backdrop_grassland_vault") != nil)
        #expect(TokenmonRaidArtLoader.image(artKey: "raid_backdrop_sky_beacon") != nil)
        #expect(TokenmonRaidArtLoader.image(artKey: "raid_backdrop_coast_tideglass") != nil)
        #expect(TokenmonRaidArtLoader.image(artKey: "raid_backdrop_ice_aurora_archive") != nil)
        #expect(TokenmonRaidArtLoader.image(artKey: "raid_target_training_trophy_cache") != nil)
        #expect(TokenmonRaidArtLoader.image(artKey: "raid_target_logo_vault") != nil)
        #expect(TokenmonRaidArtLoader.image(artKey: "raid_target_token_vault_sentinel") != nil)
        for raid in RaidCatalog.allRaids {
            #expect(TokenmonRaidArtLoader.image(artKey: raid.targetArtKey) != nil)
        }
        #expect(TokenmonRaidArtLoader.image(artKey: "reward_first_spark_trophy") != nil)
        #expect(TokenmonRaidArtLoader.image(artKey: "reward_2026_04_april_relic") != nil)
        #expect(TokenmonRaidArtLoader.image(artKey: "reward_2026_05_may_relic") != nil)
        #expect(TokenmonRaidArtLoader.image(artKey: "reward_tokenmon_logo_relic") != nil)
        #expect(TokenmonRaidArtLoader.image(artKey: "reward_2026_07_july_relic") != nil)
        #expect(TokenmonRaidArtLoader.image(artKey: "reward_2026_08_august_relic") != nil)
        #expect(TokenmonRaidArtLoader.image(artKey: "reward_2026_09_september_relic") != nil)
        #expect(TokenmonRaidArtLoader.image(artKey: "reward_2026_10_october_relic") != nil)
        #expect(TokenmonRaidArtLoader.image(artKey: "reward_2026_11_november_relic") != nil)
        #expect(TokenmonRaidArtLoader.image(artKey: "reward_2026_12_december_relic") != nil)
    }

    @Test
    func achievementBadgeArtLoaderLoadsCatalogAssets() {
        #expect(AchievementCatalog.allBadges.count == 36)
        for badge in AchievementCatalog.allBadges {
            #expect(TokenmonBadgeArtLoader.image(artKey: badge.artKey) != nil)
        }
    }

    @Test
    func achievementBadgeCatalogHasLocalizedCopy() {
        TokenmonL10n.setLocaleOverride("en")
        for badge in AchievementCatalog.allBadges {
            #expect(TokenmonL10n.string(forKey: badge.titleKey) != badge.titleKey)
            #expect(TokenmonL10n.string(forKey: badge.descriptionKey) != badge.descriptionKey)
        }
    }

    private func sampleSpecies(field: FieldType, offset: Int) -> SpeciesDefinition {
        let species = SpeciesCatalog.all.filter { $0.isActive && $0.field == field }
        guard offset < species.count else {
            preconditionFailure("missing sample species for \(field)")
        }
        return species[offset]
    }

    private func sampleSpecies(trait: TrainingTrait) -> SpeciesDefinition {
        guard let species = SpeciesCatalog.all.first(where: { $0.isActive && $0.trainingTrait == trait }) else {
            preconditionFailure("missing sample species for \(trait)")
        }
        return species
    }

    private func expectedNowCampRewardName(for trait: TrainingTrait) -> String {
        switch trait {
        case .trail:
            return TokenmonL10n.string("now.camp.train.reward.trail")
        case .scout:
            return TokenmonL10n.string("now.camp.train.reward.scout")
        case .capture:
            return TokenmonL10n.string("now.camp.train.reward.capture")
        case .raider:
            return TokenmonL10n.string("now.camp.train.reward.raider")
        }
    }

    private func expectedNowCampRewardShortName(for trait: TrainingTrait) -> String {
        switch trait {
        case .trail:
            return TokenmonL10n.string("now.camp.train.reward.trail.short")
        case .scout:
            return TokenmonL10n.string("now.camp.train.reward.scout.short")
        case .capture:
            return TokenmonL10n.string("now.camp.train.reward.capture.short")
        case .raider:
            return TokenmonL10n.string("now.camp.train.reward.raider.short")
        }
    }

    private func expectedNowCampRewardSystemImage(for trait: TrainingTrait) -> String {
        switch trait {
        case .trail:
            return "map.fill"
        case .scout:
            return "star.fill"
        case .capture:
            return "scope"
        case .raider:
            return "shield.fill"
        }
    }

    private func expectedNowCampV2PracticeChance(
        rarity: RarityTier,
        trainingRank: TrainingRank
    ) -> String {
        guard let targetRank = trainingRank.next else {
            return TokenmonL10n.string("now.camp.v2.max")
        }
        let probability = try! LeaderTrainingResolver().successProbability(
            rarity: rarity,
            targetRank: targetRank
        )
        return TokenmonL10n.format(
            "now.camp.v2.percent",
            Int64((probability * 100).rounded())
        )
    }

    private func expectedNowCampV2Resonance(
        rarity: RarityTier,
        trainingRank: TrainingRank,
        resonance: Int = 2
    ) -> String {
        guard let targetRank = trainingRank.next else {
            return TokenmonL10n.string("now.camp.v2.max")
        }
        let resolver = LeaderTrainingResolver()
        let probability = try! resolver.successProbability(
            rarity: rarity,
            targetRank: targetRank
        )
        let ceiling = try! resolver.ceilingFailures(probability: probability)
        return TokenmonL10n.format(
            "now.camp.v2.resonance.value",
            Int64(min(max(resonance, 0), ceiling)),
            Int64(ceiling)
        )
    }

    private func expectedNowCampV2RewardValue(for preview: LeaderTraitBonusPreview) -> String {
        guard preview.isActive, preview.bonusAmount > 0 else {
            return TokenmonL10n.string("now.camp.v2.unavailable")
        }
        switch preview.unit {
        case .fieldWeight, .rarityWeightShift, .raidPower:
            return TokenmonL10n.format("now.camp.v2.signed_integer", Int64(preview.bonusAmount.rounded()))
        case .probabilityPoints:
            return TokenmonL10n.format("now.camp.v2.points", Int64((preview.bonusAmount * 100).rounded()))
        }
    }

    private func expectedNowCampV2CompactRewardValue(for preview: LeaderTraitBonusPreview) -> String {
        let value = expectedNowCampV2RewardValue(for: preview)
        guard preview.isActive else {
            return value
        }
        switch preview.kind {
        case .trail:
            return TokenmonL10n.format("now.camp.v2.reward.trail.compact_value", preview.field.displayName)
        case .scout:
            return TokenmonL10n.format("now.camp.v2.reward.scout.compact_value", preview.field.displayName)
        case .capture:
            return TokenmonL10n.format("now.camp.v2.reward.capture.compact_value", preview.field.displayName)
        case .raider:
            return TokenmonL10n.format("now.camp.v2.reward.raider.compact_value", preview.field.displayName)
        }
    }

    private func expectedNowCampV2CompactRewardDetail(for preview: LeaderTraitBonusPreview) -> String {
        guard preview.isActive else {
            return TokenmonL10n.string("now.camp.v2.reward.inactive")
        }
        let value = expectedNowCampV2RewardValue(for: preview)
        switch preview.kind {
        case .trail:
            return TokenmonL10n.format("now.camp.v2.reward.trail.compact_detail", value)
        case .scout:
            return TokenmonL10n.format("now.camp.v2.reward.scout.compact_detail", value)
        case .capture:
            return TokenmonL10n.format("now.camp.v2.reward.capture.compact_detail", value)
        case .raider:
            return TokenmonL10n.format("now.camp.v2.reward.raider.compact_detail", value)
        }
    }

    private func expectedNowCampV2LeadEffectValue(current: LeaderTraitBonusPreview) -> String {
        if current.isActive {
            return expectedNowCampV2RewardValue(for: current)
        }
        return TokenmonL10n.string("now.camp.v2.unavailable")
    }

    private func expectedNowCampV2LeadEffectDetail(
        current: LeaderTraitBonusPreview,
        next: LeaderTraitBonusPreview?,
        nextRank: TrainingRank?,
        nextIsBlocked: Bool = false,
        blockedCurrent: Int64? = nil,
        blockedRequired: Int64? = nil
    ) -> String {
        let currentLine = current.isActive
            ? expectedNowCampV2EffectLineText(for: current)
            : TokenmonL10n.string("now.camp.v2.reward.current.none")
        let successLine: String
        if nextIsBlocked {
            if let blockedCurrent, let blockedRequired {
                successLine = TokenmonL10n.format(
                    "now.camp.action.rank_gate.short",
                    blockedCurrent,
                    blockedRequired
                )
            } else {
                successLine = TokenmonL10n.string("now.camp.v2.bond_gate")
            }
        } else if nextRank == nil {
            successLine = TokenmonL10n.string("now.camp.v2.max")
        } else if let next, next.isActive {
            successLine = expectedNowCampV2EffectLineText(for: next)
        } else {
            successLine = TokenmonL10n.string("now.camp.v2.reward.success.none")
        }
        return TokenmonL10n.format(
            "now.camp.v2.reward.current_success.detail",
            currentLine,
            successLine
        )
    }

    private func expectedNowCampV2LeadEffectCompactValue(
        current: LeaderTraitBonusPreview,
        next: LeaderTraitBonusPreview?,
        nextIsBlocked: Bool = false
    ) -> String {
        if current.isActive {
            return expectedNowCampV2CompactRewardValue(for: current)
        }
        guard let next,
              next.isActive,
              !nextIsBlocked else {
            if nextIsBlocked {
                return TokenmonL10n.string("now.camp.v2.bond_gate")
            }
            return TokenmonL10n.string("now.camp.v2.reward.inactive")
        }
        return expectedNowCampV2CompactRewardValue(for: next)
    }

    private func expectedNowCampV2LeadEffectCompactDetail(
        current: LeaderTraitBonusPreview,
        next: LeaderTraitBonusPreview?,
        nextIsBlocked: Bool = false
    ) -> String {
        if current.isActive {
            let currentDetail = expectedNowCampV2CompactRewardDetail(for: current)
            guard let next,
                  next.isActive,
                  !nextIsBlocked else {
                return currentDetail
            }
            let currentValue = expectedNowCampV2RewardValue(for: current)
            let nextValue = expectedNowCampV2RewardValue(for: next)
            guard currentValue != nextValue else {
                return currentDetail
            }
            return TokenmonL10n.format(
                "now.camp.v2.reward.current_to_next",
                currentDetail,
                nextValue
            )
        }
        guard let next,
              next.isActive,
              !nextIsBlocked else {
            if nextIsBlocked {
                return TokenmonL10n.string("now.camp.v2.bond_gate")
            }
            return TokenmonL10n.string("now.camp.v2.reward.inactive")
        }
        return TokenmonL10n.string("now.camp.v2.reward.unlock_first_success")
    }

    private func expectedNowCampV2EffectLineText(for preview: LeaderTraitBonusPreview) -> String {
        let value = expectedNowCampV2RewardValue(for: preview)
        switch preview.kind {
        case .trail:
            return TokenmonL10n.format("now.camp.v2.reward.trail.effect_line", preview.field.displayName, value)
        case .scout:
            return TokenmonL10n.format("now.camp.v2.reward.scout.effect_line", preview.field.displayName, value)
        case .capture:
            return TokenmonL10n.format("now.camp.v2.reward.capture.effect_line", preview.field.displayName, value)
        case .raider:
            return TokenmonL10n.format("now.camp.v2.reward.raider.effect_line", preview.field.displayName, value)
        }
    }

    private func expectedNowCampBenefitText(for species: SpeciesDefinition) -> String {
        switch species.trainingTrait {
        case .trail:
            return TokenmonL10n.format("now.camp.practice.benefit.trail", species.field.displayName)
        case .scout:
            return TokenmonL10n.string("now.camp.practice.benefit.scout")
        case .capture:
            return TokenmonL10n.format("now.camp.practice.benefit.capture", species.field.displayName)
        case .raider:
            return TokenmonL10n.string("now.camp.practice.benefit.raider")
        }
    }

    private func makeNowCampSceneContext(field: FieldType) -> TokenmonSceneContext {
        TokenmonSceneContext(
            sceneState: .exploring,
            fieldKind: sceneFieldKind(for: field),
            fieldState: .exploring,
            effectState: .none,
            wildState: .hidden
        )
    }

    private func sceneFieldKind(for field: FieldType) -> TokenmonSceneFieldKind {
        switch field {
        case .grassland:
            return .grassland
        case .ice:
            return .ice
        case .coast:
            return .coast
        case .sky:
            return .sky
        }
    }

    private func makeNowCampSummary(
        lead: SpeciesDefinition?,
        supports: [SpeciesDefinition],
        focusEnergy: Int,
        affinityLevel: Int64,
        trainingRank: TrainingRank,
        careReady: Bool = false,
        careElapsedSeconds: Int = 0,
        careFocusEarnedLocalDate: String = "2026-04-24",
        careFocusEarnedToday: Int = 0
    ) -> NowCampSummary {
        NowCampSummary(
            leadSpeciesID: lead?.id,
            focusEnergy: focusEnergy,
            focusRemainderTokens: 12_000,
            focusEarnedLocalDate: "2026-04-24",
            focusEarnedToday: 24,
            careReady: careReady,
            careElapsedSeconds: careElapsedSeconds,
            careFocusEarnedLocalDate: careFocusEarnedLocalDate,
            careFocusEarnedToday: careFocusEarnedToday,
            lead: lead.map {
                makeLeadSummary(
                    from: $0,
                    affinityLevel: affinityLevel,
                    trainingRank: trainingRank
                )
            },
            supports: supports.enumerated().map { index, species in
                makePartyMember(from: species, slotOrder: index + 2)
            }
        )
    }

    private func makeLeadSummary(
        from species: SpeciesDefinition,
        affinityLevel: Int64,
        trainingRank: TrainingRank
    ) -> NowCampLeadSummary {
        NowCampLeadSummary(
            speciesID: species.id,
            displayName: species.name,
            assetKey: species.assetKey,
            field: species.field,
            rarity: species.rarity,
            trainingTrait: species.trainingTrait,
            affinityLevel: affinityLevel,
            slotOrder: 1,
            training: NowCampTrainingSummary(
                trainingRank: trainingRank,
                trainingResonance: 2,
                trainingAttemptCount: 4
            )
        )
    }

    private func makePartyMember(
        from species: SpeciesDefinition,
        slotOrder: Int = 1,
        affinityLevel: Int64 = 1,
        trainingRank: TrainingRank = .rankI
    ) -> PartyMemberSummary {
        PartyMemberSummary(
            speciesID: species.id,
            assetKey: species.assetKey,
            field: species.field,
            rarity: species.rarity,
            displayName: species.name,
            addedAt: "2026-04-24T00:00:00Z",
            slotOrder: slotOrder,
            capturedCount: 1,
            affinityLevel: affinityLevel,
            trainingTrait: species.trainingTrait,
            trainingRank: trainingRank,
            stats: species.stats
        )
    }

    private func gameplayDeltaSum(_ manager: TokenmonDatabaseManager) throws -> Int64 {
        let database = try manager.open()
        return try database.fetchOne(
            "SELECT COALESCE(SUM(gameplay_delta_tokens), 0) FROM usage_samples;"
        ) { statement in
            SQLiteDatabase.columnInt64(statement, index: 0)
        } ?? 0
    }

    private func date(hour: Int, calendar: Calendar) -> Date {
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = 2026
        components.month = 4
        components.day = 24
        components.hour = hour
        components.minute = 0
        components.second = 0
        return calendar.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }
}

private extension String {
    var deletingLastPathComponentURL: URL {
        URL(fileURLWithPath: self).deletingLastPathComponent()
    }
}

private final class ProviderInspectionCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func increment() {
        lock.lock()
        value += 1
        lock.unlock()
    }

    func snapshot() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

private struct FixedEncounterRNG: EncounterRandomNumberGenerator {
    var rolls: [Double]
    private var index = 0

    init(rolls: [Double]) {
        self.rolls = rolls
    }

    mutating func nextUnitInterval() -> Double {
        defer { index += 1 }
        return rolls[min(index, rolls.count - 1)]
    }
}
