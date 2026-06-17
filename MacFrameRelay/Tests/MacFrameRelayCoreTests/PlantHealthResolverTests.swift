import Foundation
import Testing
@testable import MacFrameRelayCore

// MARK: - overallLevel

@Test
func overallLevelTakesMoreSevereOfTwoSignals() {
    // 枯萎 1（輕微）+ 黃化 3（嚴重）→ 整體取較嚴重者 3
    #expect(PlantHealthResolver.overallLevel(witherLevel: 1, yellowLevel: 3) == 3)
    #expect(PlantHealthResolver.overallLevel(witherLevel: 2, yellowLevel: 0) == 2)
}

@Test
func overallLevelFallsBackToSingleSignalWhenOtherIsNil() {
    #expect(PlantHealthResolver.overallLevel(witherLevel: 2, yellowLevel: nil) == 2)
    #expect(PlantHealthResolver.overallLevel(witherLevel: nil, yellowLevel: 1) == 1)
}

@Test
func overallLevelIsNilWhenBothSignalsMissing() {
    // 兩條訊號都缺 → 不顯示（向後相容：舊 Mac 不送新欄位）
    #expect(PlantHealthResolver.overallLevel(witherLevel: nil, yellowLevel: nil) == nil)
}

// MARK: - trendModifier

@Test
func trendModifierMapsEachTrendToText() {
    #expect(PlantHealthResolver.trendModifier(.worsening) == "狀況似乎正在惡化")
    #expect(PlantHealthResolver.trendModifier(.improving) == "狀況似乎正在好轉")
    #expect(PlantHealthResolver.trendModifier(.stable) == "近期狀況穩定")
}

@Test
func trendModifierIsNilWhenNoTrend() {
    #expect(PlantHealthResolver.trendModifier(nil) == nil)
}
