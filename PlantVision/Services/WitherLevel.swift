import Foundation

/// 枯萎程度等級。**這是 `MacFrameRelayCore.WitherLevel` 的鏡像**：Mac 端用同一套閾值
/// 把 `witherLevel` 填進 payload，這裡保留一份相同實作，供 payload 缺 `witherLevel`
/// 卻有 `witherRatio` 時的後備換算，以及徽章文字。兩端共用相同閾值——
/// 真正的單元測試在 MacFrameRelayCore（visionOS app target 沒有可跑的測試 target），
/// 修改閾值時請同步兩邊。
///
/// 等級：0 健康 / 1 輕微 / 2 中度 / 3 嚴重。
enum WitherLevel {
    static let healthy = 0
    static let mild = 1
    static let moderate = 2
    static let severe = 3

    static func level(forRatio ratio: Double) -> Int {
        switch ratio {
        case ..<0.10: healthy
        case ..<0.35: mild
        case ..<0.65: moderate
        default: severe
        }
    }

    /// 等級對應的徽章短文字（繁中）。
    static func label(forLevel level: Int) -> String {
        switch level {
        case healthy: "健康"
        case mild: "輕微枯萎"
        case moderate: "中度枯萎"
        default: "嚴重枯萎"
        }
    }

    /// 徽章顏色提示用的等級嚴重度（0–3），方便 UI 上色。
    static func clampedLevel(_ level: Int) -> Int {
        min(max(level, healthy), severe)
    }
}

/// 一幀的枯萎狀態：連續比例（0–1）＋等級。供 2D 視窗顯示百分比與徽章。
struct WitherStatus: Equatable {
    let ratio: Double
    let level: Int

    init(ratio: Double, level: Int) {
        self.ratio = ratio
        self.level = level
    }

    /// 只有比例時，等級用 `WitherLevel` 的閾值推出（payload 缺 witherLevel 時的後備）。
    init(ratio: Double) {
        self.init(ratio: ratio, level: WitherLevel.level(forRatio: ratio))
    }

    /// 0–100 的整數百分比，用於顯示。
    var percentText: String { "\(Int((ratio * 100).rounded()))%" }
    var levelLabel: String { WitherLevel.label(forLevel: level) }
}
