import Foundation
import Testing
@testable import MacFrameRelayCore

@Test
func witherTrendIsNilBelowMinimumSamples() {
    // 樣本不足（< 6）→ 不確定，回 nil，不硬猜趨勢
    #expect(WitherTrendResolver.resolve([0.1, 0.2, 0.3, 0.4, 0.5]) == nil)
    #expect(WitherTrendResolver.resolve([]) == nil)
}

@Test
func witherTrendWorseningWhenRecentHalfRises() {
    // 前半 ~0.1，後半 ~0.5，差遠超門檻 → 惡化
    let samples = [0.10, 0.10, 0.12, 0.48, 0.50, 0.52]
    #expect(WitherTrendResolver.resolve(samples) == .worsening)
}

@Test
func witherTrendImprovingWhenRecentHalfFalls() {
    // 前半 ~0.6，後半 ~0.1，比例下降 → 改善
    let samples = [0.60, 0.58, 0.62, 0.12, 0.10, 0.08]
    #expect(WitherTrendResolver.resolve(samples) == .improving)
}

@Test
func witherTrendStableWhenFlat() {
    let samples = [0.40, 0.40, 0.40, 0.40, 0.40, 0.40]
    #expect(WitherTrendResolver.resolve(samples) == .stable)
}

@Test
func witherTrendStableWhenChangeWithinThreshold() {
    // 前半 0.40，後半 0.44，差 0.04 < 門檻 0.08，且含小幅抖動 → 穩定（不被雜訊誤判）
    let samples = [0.39, 0.41, 0.40, 0.45, 0.43, 0.44]
    #expect(WitherTrendResolver.resolve(samples) == .stable)
}

@Test
func witherTrendUsesChangeThresholdBoundaryInclusively() {
    // 前半平均 0.10、後半平均 0.18，差恰為 0.08（門檻）→ 達標即惡化
    let samples = [0.10, 0.10, 0.10, 0.18, 0.18, 0.18]
    #expect(WitherTrendResolver.resolve(samples) == .worsening)
    // 自訂較大的門檻（0.20）後，同一序列的 0.08 差不足 → 穩定
    #expect(WitherTrendResolver.resolve(samples, changeThreshold: 0.20) == .stable)
}

@Test
func witherTrendDropsMiddleSampleForOddCounts() {
    // 7 個樣本：捨去正中央（index 3）的離群值 0.99，前半[0.1,0.1,0.1]、後半[0.5,0.5,0.5]→惡化
    let samples = [0.10, 0.10, 0.10, 0.99, 0.50, 0.50, 0.50]
    #expect(WitherTrendResolver.resolve(samples) == .worsening)
}
