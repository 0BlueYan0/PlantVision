import Foundation
import Testing
@testable import MacFrameRelayCore

private let healthy = WitherTileClassification.healthy
private let withered = WitherTileClassification.withered
private let noPlant = WitherTileClassification.noPlant

@Test
func witherRatioIsWitheredOverPlantTiles() {
    // 2 枯 + 2 健 → 枯萎比例 0.5
    let ratio = WitherScoreResolver.resolve([withered, withered, healthy, healthy])
    #expect(ratio == 0.5)
}

@Test
func witherRatioExcludesNoPlantTilesFromDenominator() {
    // 3 健 + 1 枯，外加 4 塊背景（noPlant）→ 比例 = 1 / (3+1) = 0.25，背景不算分母
    let ratio = WitherScoreResolver.resolve(
        [withered, healthy, healthy, healthy, noPlant, noPlant, noPlant, noPlant]
    )
    #expect(ratio == 0.25)
}

@Test
func witherRatioIsZeroWhenAllPlantTilesHealthy() {
    let ratio = WitherScoreResolver.resolve([healthy, healthy, healthy])
    #expect(ratio == 0.0)
}

@Test
func witherRatioIsOneWhenAllPlantTilesWithered() {
    let ratio = WitherScoreResolver.resolve([withered, withered])
    #expect(ratio == 1.0)
}

@Test
func witherRatioIsNilWhenTooFewPlantTiles() {
    // 只有 1 塊有植物（門檻 2）→ 不確定，回 nil，不硬猜
    let ratio = WitherScoreResolver.resolve([withered, noPlant, noPlant])
    #expect(ratio == nil)
}

@Test
func witherRatioIsNilWhenNoPlantTilesAtAll() {
    let ratio = WitherScoreResolver.resolve([noPlant, noPlant, noPlant])
    #expect(ratio == nil)
}

@Test
func witherRatioHonoursCustomMinimumPlantTiles() {
    // 把門檻降到 1：單一有植物的區塊也回報比例
    let ratio = WitherScoreResolver.resolve([withered, noPlant], minimumPlantTiles: 1)
    #expect(ratio == 1.0)
}
