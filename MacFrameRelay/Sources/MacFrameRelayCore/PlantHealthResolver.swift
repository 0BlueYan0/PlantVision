import Foundation

/// 把獨立的健康訊號（枯萎等級、趨勢）收斂成顯示用的結果。抽成純函式以便測試，
/// visionOS 端有一份相同邏輯的鏡像（見 `PlantVision/.../PlantHealth.swift`）。
///
/// 設計：整體健康等級即枯萎等級。趨勢是時間維度，化為使用者可見的修飾語，
/// 不混進嚴重度數字。枯萎缺值（nil）則整體 nil（不顯示）。
public enum PlantHealthResolver {
    /// 整體健康等級＝枯萎等級。枯萎缺值時回 nil。
    public static func overallLevel(witherLevel: Int?) -> Int? {
        witherLevel
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
