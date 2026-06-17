import Foundation

/// 枯萎程度的時間變化趨勢。**這是 `MacFrameRelayCore.WitherTrend` 的鏡像**：Mac 端算出後
/// 以 rawValue 放進 payload（`witherTrend`），這裡用相同的 case 解析並補上繁中修飾語與圖示。
enum WitherTrend: String, Equatable {
    case worsening   // 惡化（枯萎比例隨時間上升）
    case improving   // 改善（枯萎比例隨時間下降）
    case stable      // 穩定（變化在雜訊門檻內）

    /// 使用者可見的繁中修飾語（與 `PlantHealthResolver.trendModifier` 一致）。
    var modifier: String {
        switch self {
        case .worsening: "狀況似乎正在惡化"
        case .improving: "狀況似乎正在好轉"
        case .stable: "近期狀況穩定"
        }
    }

    /// 趨勢圖示。文字＋圖示並存，不單靠顏色／方向傳達（無障礙）。
    var systemImage: String {
        switch self {
        case .worsening: "arrow.up.right"
        case .improving: "arrow.down.right"
        case .stable: "arrow.right"
        }
    }
}

/// 把三條獨立的健康訊號（枯萎等級、黃化等級、趨勢）收斂成顯示用結果。
/// **這是 `MacFrameRelayCore.PlantHealthResolver` 的鏡像**（visionOS app target 無法跑測試，
/// 真正的單元測試在 MacFrameRelayCore）。整體等級取枯萎與黃化的較嚴重者；趨勢化為修飾語。
enum PlantHealthResolver {
    static func overallLevel(witherLevel: Int?, yellowLevel: Int?) -> Int? {
        switch (witherLevel, yellowLevel) {
        case let (wither?, yellow?): return max(wither, yellow)
        case let (wither?, nil): return wither
        case let (nil, yellow?): return yellow
        case (nil, nil): return nil
        }
    }

    static func trendModifier(_ trend: WitherTrend?) -> String? {
        trend?.modifier
    }
}

/// 整體健康等級對應的徽章文字。與枯萎／黃化的措辭分開——這是「整體」的判斷，
/// 不寫成枯萎或黃化特定字眼。等級：0 健康 / 1 輕微 / 2 中度 / 3 嚴重。
enum PlantHealthLevel {
    static func label(forLevel level: Int) -> String {
        switch min(max(level, 0), 3) {
        case 0: "健康"
        case 1: "輕微"
        case 2: "中度"
        default: "嚴重"
        }
    }
}

/// 顯示用的綜合健康狀態：彙整枯萎、黃化、趨勢三條訊號。任一子訊號可缺（nil），
/// 缺的就不在卡片上渲染——向後相容：舊 Mac 不送新欄位時，卡片只顯示有的訊號、不崩潰。
struct PlantHealthStatus: Equatable {
    let wither: WitherStatus?
    let yellowing: YellowingStatus?
    let trend: WitherTrend?

    /// 整體健康等級（枯萎與黃化的較嚴重者）；兩者皆無時為 nil。
    var overallLevel: Int? {
        PlantHealthResolver.overallLevel(witherLevel: wither?.level, yellowLevel: yellowing?.level)
    }

    /// 是否有任一可顯示的健康訊號。皆無則整個卡片不顯示。
    var hasAnySignal: Bool { wither != nil || yellowing != nil }

    /// 整體等級的徽章文字；無整體等級時為 nil。
    var overallLabel: String? { overallLevel.map(PlantHealthLevel.label(forLevel:)) }

    /// 趨勢修飾語（副標）；無趨勢資料時為 nil。
    var trendModifier: String? { PlantHealthResolver.trendModifier(trend) }

    /// 黃化偏高（達輕微以上）時的補充提示；否則 nil。
    var yellowingHint: String? {
        guard let yellowing, yellowing.level >= LeafYellowingLevel.mild else { return nil }
        return "葉片偏黃常與澆水過量或缺氮、缺鐵有關，可一併留意。"
    }
}
