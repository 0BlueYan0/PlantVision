import Foundation
import Testing
@testable import MacFrameRelayCore

/// 以固定起點 + 0.1 秒間隔模擬自動擷取的時間戳
private func tick(_ base: Date, _ index: Int) -> Date {
    base.addingTimeInterval(0.1 * Double(index))
}

/// 連續比例取平均會有浮點誤差，用容差比較。
private func isClose(_ actual: Double?, _ expected: Double, tolerance: Double = 1e-9) -> Bool {
    guard let actual else { return false }
    return abs(actual - expected) < tolerance
}

// MARK: - average 純函式

@Test
func averageReturnsNilForEmptySamples() {
    #expect(TemporalWitherSmoother.average(of: []) == nil)
}

@Test
func averageOfSingleSampleIsThatSample() {
    #expect(TemporalWitherSmoother.average(of: [0.4]) == 0.4)
}

@Test
func averageIsArithmeticMean() {
    // (0.2 + 0.4 + 0.6) / 3 = 0.4
    let mean = TemporalWitherSmoother.average(of: [0.2, 0.4, 0.6])
    #expect(isClose(mean, 0.4))
}

@Test
func averageReturnsNilBelowMinimumSamples() {
    #expect(TemporalWitherSmoother.average(of: [0.5], minimumSamples: 3) == nil)
    #expect(TemporalWitherSmoother.average(of: [0.5, 0.5, 0.5], minimumSamples: 3) == 0.5)
}

// MARK: - record 時間窗行為

@Test
func smootherReturnsSingleSampleImmediately() {
    var smoother = TemporalWitherSmoother()
    let base = Date(timeIntervalSince1970: 1_000)
    #expect(smoother.record(0.3, at: base) == 0.3)
}

@Test
func smootherAveragesAcrossWindow() {
    var smoother = TemporalWitherSmoother()
    let base = Date(timeIntervalSince1970: 2_000)
    _ = smoother.record(0.2, at: tick(base, 0))
    _ = smoother.record(0.4, at: tick(base, 1))
    let smoothed = smoother.record(0.6, at: tick(base, 2))
    // (0.2 + 0.4 + 0.6) / 3 = 0.4，連續比例被平滑
    #expect(isClose(smoothed, 0.4))
}

@Test
func smootherIgnoresNilUncertainFrames() {
    var smoother = TemporalWitherSmoother()
    let base = Date(timeIntervalSince1970: 3_000)
    _ = smoother.record(0.8, at: tick(base, 0))
    // nil（該幀有植物的區塊不足）不計入平均：平均仍只有 0.8 一個樣本
    let smoothed = smoother.record(nil, at: tick(base, 1))
    #expect(smoothed == 0.8)
}

@Test
func smootherReturnsNilWhenOnlyUncertainFrames() {
    var smoother = TemporalWitherSmoother()
    let base = Date(timeIntervalSince1970: 4_000)
    _ = smoother.record(nil, at: tick(base, 0))
    let smoothed = smoother.record(nil, at: tick(base, 1))
    #expect(smoothed == nil)
}

@Test
func smootherPrunesSamplesOutsideWindow() {
    var smoother = TemporalWitherSmoother(windowSeconds: 0.7, minimumSamples: 1)
    let base = Date(timeIntervalSince1970: 5_000)
    // 舊的高比例樣本
    _ = smoother.record(1.0, at: base)
    // 1 秒後（超出 0.7 秒窗）的新樣本 → 舊的 1.0 已被丟棄，平均只剩新值
    let smoothed = smoother.record(0.2, at: base.addingTimeInterval(1.0))
    #expect(smoothed == 0.2)
}
