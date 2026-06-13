import Foundation
import Testing
@testable import MacFrameRelayCore

private let bg = PlantImageClassifier.backgroundLabel

private func plant(_ label: String, _ conf: Double = 1.0) -> PlantClassificationResult {
    PlantClassificationResult(label: label, confidence: conf)
}

/// 以固定起點 + 0.1 秒間隔模擬自動擷取的時間戳
private func tick(_ base: Date, _ index: Int) -> Date {
    base.addingTimeInterval(0.1 * Double(index))
}

@Test
func smootherReturnsSingleManualCaptureImmediately() {
    var smoother = TemporalLabelSmoother()
    let base = Date(timeIntervalSince1970: 1_000)
    // 單張手動擷取只有一幀，門檻取 min(minimumVotes, 幀數)=1 → 直接回該幀
    let result = smoother.record(plant("catharanthus-roseus"), at: base)
    #expect(result?.label == "catharanthus-roseus")
}

@Test
func smootherStabilizesToMajorityInStream() {
    var smoother = TemporalLabelSmoother()
    let base = Date(timeIntervalSince1970: 2_000)
    let seq = ["catharanthus-roseus", "catharanthus-roseus", "lobelia-erinus",
               "catharanthus-roseus", "catharanthus-roseus"]
    var last: PlantClassificationResult?
    for (i, label) in seq.enumerated() {
        last = smoother.record(plant(label), at: tick(base, i))
    }
    // 窗內 cath×4 lob×1 → 穩定輸出 catharanthus，單幀 lobelia 雜訊被濾掉
    #expect(last?.label == "catharanthus-roseus")
}

@Test
func smootherReportsUncertainOnFiftyFiftyFlicker() {
    var smoother = TemporalLabelSmoother()
    let base = Date(timeIntervalSince1970: 3_000)
    // 兩類交替抖動 → 窗內打平 → 回 nil（不確定），不在兩類間跳
    let seq = ["catharanthus-roseus", "lobelia-erinus", "catharanthus-roseus",
               "lobelia-erinus", "catharanthus-roseus", "lobelia-erinus"]
    var last: PlantClassificationResult?
    for (i, label) in seq.enumerated() {
        last = smoother.record(plant(label), at: tick(base, i))
    }
    #expect(last == nil)
}

@Test
func smootherIgnoresSingleFrameBlip() {
    var smoother = TemporalLabelSmoother()
    let base = Date(timeIntervalSince1970: 4_000)
    _ = smoother.record(plant("lobelia-erinus"), at: tick(base, 0))
    _ = smoother.record(plant("lobelia-erinus"), at: tick(base, 1))
    _ = smoother.record(plant("catharanthus-roseus"), at: tick(base, 2)) // blip
    let last = smoother.record(plant("lobelia-erinus"), at: tick(base, 3))
    // lob×3 cath×1 → lobelia 維持穩定，單幀 catharanthus blip 不翻面
    #expect(last?.label == "lobelia-erinus")
}

@Test
func smootherPrunesFramesOutsideWindow() {
    var smoother = TemporalLabelSmoother(windowSeconds: 0.7, minimumVotes: 3)
    let base = Date(timeIntervalSince1970: 5_000)
    // 舊的 catharanthus 幀
    _ = smoother.record(plant("catharanthus-roseus"), at: base)
    _ = smoother.record(plant("catharanthus-roseus"), at: base.addingTimeInterval(0.1))
    // 1 秒後（超出 0.7 秒窗）連續 lobelia → 舊 cath 已被丟棄
    var last: PlantClassificationResult?
    for i in 0..<3 {
        last = smoother.record(plant("lobelia-erinus"), at: base.addingTimeInterval(1.0 + 0.1 * Double(i)))
    }
    #expect(last?.label == "lobelia-erinus")
}

@Test
func smootherTreatsNilAsBackgroundVote() {
    var smoother = TemporalLabelSmoother()
    let base = Date(timeIntervalSince1970: 6_000)
    // 連續不確定（nil）→ 視同 background 多數 → 回 background 結果
    var last: PlantClassificationResult?
    for i in 0..<3 {
        last = smoother.record(nil, at: tick(base, i))
    }
    #expect(last?.label == bg)
}
