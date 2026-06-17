import Foundation
import Testing
@testable import MacFrameRelayCore

private let green = LeafPixelClass.green
private let yellow = LeafPixelClass.yellow
private let background = LeafPixelClass.background

// MARK: - classifyPixel

@Test
func classifyPixelTreatsLowSaturationAsBackground() {
    // 灰（飽和度低）不論色相都是背景
    #expect(LeafYellowingResolver.classifyPixel(hue: 120, saturation: 0.05, value: 0.6) == .background)
}

@Test
func classifyPixelTreatsDarkAsBackground() {
    // 太暗（亮度低）視為背景
    #expect(LeafYellowingResolver.classifyPixel(hue: 60, saturation: 0.8, value: 0.05) == .background)
}

@Test
func classifyPixelDetectsTypicalGreenAndYellow() {
    #expect(LeafYellowingResolver.classifyPixel(hue: 120, saturation: 0.7, value: 0.6) == .green)
    #expect(LeafYellowingResolver.classifyPixel(hue: 55, saturation: 0.7, value: 0.8) == .yellow)
}

@Test
func classifyPixelTreatsOrangeAndRedAsBackground() {
    // 橘（30°）與紅（5°）不算黃化葉色，落在綠黃帶外 → 背景，不入分母
    #expect(LeafYellowingResolver.classifyPixel(hue: 30, saturation: 0.8, value: 0.8) == .background)
    #expect(LeafYellowingResolver.classifyPixel(hue: 5, saturation: 0.8, value: 0.8) == .background)
}

@Test
func classifyPixelGreenYellowBoundaryGoesToYellow() {
    // 80° 為兩帶交界：歸黃（黃帶含 80，綠帶從 >80 起），確保無死區、判定確定
    #expect(LeafYellowingResolver.classifyPixel(hue: 80, saturation: 0.7, value: 0.7) == .yellow)
    #expect(LeafYellowingResolver.classifyPixel(hue: 81, saturation: 0.7, value: 0.7) == .green)
}

// MARK: - resolve（用小門檻測比例聚合）

@Test
func yellowingRatioIsYellowOverPlantPixels() {
    // 2 黃 + 2 綠 → 0.5
    let ratio = LeafYellowingResolver.resolve([yellow, yellow, green, green], minimumPlantPixels: 1)
    #expect(ratio == 0.5)
}

@Test
func yellowingRatioIsZeroWhenAllGreen() {
    #expect(LeafYellowingResolver.resolve([green, green, green], minimumPlantPixels: 1) == 0.0)
}

@Test
func yellowingRatioIsOneWhenAllYellow() {
    #expect(LeafYellowingResolver.resolve([yellow, yellow], minimumPlantPixels: 1) == 1.0)
}

@Test
func yellowingRatioExcludesBackgroundFromDenominator() {
    // 1 黃 + 3 綠 + 一堆背景 → 1 / (1+3) = 0.25，背景不算分母
    let ratio = LeafYellowingResolver.resolve(
        [yellow, green, green, green, background, background, background],
        minimumPlantPixels: 1
    )
    #expect(ratio == 0.25)
}

@Test
func yellowingRatioIsNilWhenTooFewPlantPixels() {
    // 植物像素 < 門檻 → 不確定
    let ratio = LeafYellowingResolver.resolve([yellow, background, background], minimumPlantPixels: 2)
    #expect(ratio == nil)
}

@Test
func yellowingRatioIsNilWhenEmpty() {
    #expect(LeafYellowingResolver.resolve([], minimumPlantPixels: 1) == nil)
}
