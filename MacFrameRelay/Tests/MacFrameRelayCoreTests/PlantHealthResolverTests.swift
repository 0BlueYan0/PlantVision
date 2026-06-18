import Foundation
import Testing
@testable import MacFrameRelayCore

// MARK: - overallLevel

@Test
func overallLevelReflectsWitherLevel() {
    #expect(PlantHealthResolver.overallLevel(witherLevel: 3) == 3)
    #expect(PlantHealthResolver.overallLevel(witherLevel: 0) == 0)
}

@Test
func overallLevelIsNilWhenWitherMissing() {
    // 枯萎缺值 → 不顯示（向後相容：舊 Mac 不送新欄位）
    #expect(PlantHealthResolver.overallLevel(witherLevel: nil) == nil)
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
