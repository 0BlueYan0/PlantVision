import Foundation

/// 葉片黃化等級。**這是 `MacFrameRelayCore.LeafYellowingLevel` 的鏡像**：Mac 端用同一套閾值
/// 把 `yellowLevel` 填進 payload，這裡保留一份相同實作，供 payload 缺 `yellowLevel`
/// 卻有 `yellowRatio` 時的後備換算，以及徽章文字。兩端共用相同閾值——
/// 真正的單元測試在 MacFrameRelayCore，修改閾值時請同步兩邊。
///
/// 等級：0 正常 / 1 輕微 / 2 中度 / 3 嚴重。閾值獨立於枯萎（`WitherLevel`）。
enum LeafYellowingLevel {
    static let none = 0
    static let mild = 1
    static let moderate = 2
    static let severe = 3

    static func level(forRatio ratio: Double) -> Int {
        switch ratio {
        case ..<0.15: none
        case ..<0.35: mild
        case ..<0.60: moderate
        default: severe
        }
    }

    /// 等級對應的徽章短文字（繁中）。
    static func label(forLevel level: Int) -> String {
        switch level {
        case none: "正常"
        case mild: "輕微黃化"
        case moderate: "中度黃化"
        default: "嚴重黃化"
        }
    }

    static func clampedLevel(_ level: Int) -> Int {
        min(max(level, none), severe)
    }
}

/// 一幀的葉片黃化狀態：連續比例（0–1）＋等級。供 2D 視窗顯示百分比與徽章。
struct YellowingStatus: Equatable {
    let ratio: Double
    let level: Int

    init(ratio: Double, level: Int) {
        self.ratio = ratio
        self.level = level
    }

    /// 只有比例時，等級用 `LeafYellowingLevel` 的閾值推出（payload 缺 yellowLevel 時的後備）。
    init(ratio: Double) {
        self.init(ratio: ratio, level: LeafYellowingLevel.level(forRatio: ratio))
    }

    var percentText: String { "\(Int((ratio * 100).rounded()))%" }
    var levelLabel: String { LeafYellowingLevel.label(forLevel: level) }
}
