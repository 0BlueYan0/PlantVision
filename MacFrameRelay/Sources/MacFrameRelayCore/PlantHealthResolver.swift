import Foundation

/// 把三條獨立的健康訊號（枯萎等級、黃化等級、趨勢）收斂成顯示用的結果。抽成純函式以便測試，
/// visionOS 端有一份相同邏輯的鏡像（見 `PlantVision/.../PlantHealth.swift`）。
///
/// 設計：整體健康等級取「枯萎與黃化的較嚴重者（max）」——整體健康看最差的指標，
/// 兩種劣化途徑不相加（避免比例虛高）。趨勢是時間維度，化為使用者可見的修飾語，
/// 不混進嚴重度數字。任一子訊號缺值（nil）就只看另一個；全缺則整體 nil（不顯示）。
public enum PlantHealthResolver {
    /// 整體健康等級＝枯萎等級與黃化等級的較嚴重者。一者為 nil 取另一者，皆 nil 回 nil。
    public static func overallLevel(witherLevel: Int?, yellowLevel: Int?) -> Int? {
        switch (witherLevel, yellowLevel) {
        case let (wither?, yellow?): return max(wither, yellow)
        case let (wither?, nil): return wither
        case let (nil, yellow?): return yellow
        case (nil, nil): return nil
        }
    }

    /// 趨勢化為使用者可見的繁中修飾語；無趨勢資料回 nil（該行不顯示）。
    public static func trendModifier(_ trend: WitherTrend?) -> String? {
        switch trend {
        case .worsening: "狀況似乎正在惡化"
        case .improving: "狀況似乎正在好轉"
        case .stable: "近期狀況穩定"
        case nil: nil
        }
    }
}
