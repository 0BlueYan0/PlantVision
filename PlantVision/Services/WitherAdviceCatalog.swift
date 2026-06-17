import Foundation

/// 一則枯萎照護建議：一句狀態摘要 + 幾條一般性參考做法。
struct WitherAdvice: Equatable {
    let summary: String
    let actions: [String]
}

/// 本地、硬編的枯萎照護建議對照表（做法比照 `PlantDatabase`，純繁中、不連網）。
/// 以 `(plantID, level)` 為 key：找得到植物專屬條目就用專屬，否則退回泛用建議。
///
/// 文字一律為「一般性參考」語氣（可考慮／建議／留意／檢查），不寫成絕對的醫療式指示。
enum WitherAdviceCatalog {
    /// 顯示在建議區塊頂端的免責語。
    static let generalNote = "以下為一般性照護參考，實際養護請依現場狀況與植物種類自行斟酌。"

    static func advice(plantID: String?, level: Int) -> WitherAdvice {
        let level = WitherLevel.clampedLevel(level)
        if let plantID, let specific = plantSpecific[plantID]?[level] {
            return specific
        }
        // 泛用 fallback 一定備齊 0–3 級，clampedLevel 已保證 index 合法。
        return generic[level] ?? generic[WitherLevel.severe]!
    }

    // MARK: - 馬纓丹（Lantana camara）專屬

    private static let plantSpecific: [String: [Int: WitherAdvice]] = [
        "lantana-camara": [
            WitherLevel.healthy: WitherAdvice(
                summary: "馬纓丹葉片翠綠、生長狀態正常。",
                actions: [
                    "馬纓丹喜全日照，建議維持充足光照",
                    "本種耐旱，可待介質表面乾燥再澆水",
                    "花後可適度修剪，通常有助分枝與開花"
                ]
            ),
            WitherLevel.mild: WitherAdvice(
                summary: "馬纓丹出現少量枯黃葉片。",
                actions: [
                    "可先確認是否澆水過於頻繁——馬纓丹耐旱、忌積水",
                    "建議移除明顯枯黃的葉片，保持通風",
                    "留意葉背是否有軍配蟲（網椿）或粉蝨等跡象"
                ]
            ),
            WitherLevel.moderate: WitherAdvice(
                summary: "馬纓丹枯萎面積已達中等程度。",
                actions: [
                    "建議檢查盆底排水，避免根部長期潮濕",
                    "可確認日照是否足夠，光線不足較易黃化徒長",
                    "可適度修剪枯枝、加強通風後持續觀察"
                ]
            ),
            WitherLevel.severe: WitherAdvice(
                summary: "馬纓丹出現大面積枯萎。",
                actions: [
                    "可檢查根系是否因積水腐爛，必要時考慮換土修根",
                    "可保留健康主枝強剪，減少蒸散負擔",
                    "建議先穩定水分與光照，待新芽長出再恢復施肥"
                ]
            )
        ]
    ]

    // MARK: - 泛用 fallback（任何植物）

    private static let generic: [Int: WitherAdvice] = [
        WitherLevel.healthy: WitherAdvice(
            summary: "葉片整體狀態良好。",
            actions: [
                "可維持目前的日照與澆水節奏",
                "建議定期移除少量老葉、保持通風",
                "可持續觀察是否有新葉與花芽"
            ]
        ),
        WitherLevel.mild: WitherAdvice(
            summary: "出現少量枯黃葉片。",
            actions: [
                "建議檢查近期澆水是否過多或過少",
                "可移除明顯枯黃的葉片以利通風",
                "留意葉背是否有蟲害跡象"
            ]
        ),
        WitherLevel.moderate: WitherAdvice(
            summary: "枯萎面積已達中等程度。",
            actions: [
                "建議檢視根部與介質排水是否良好",
                "可調整擺放位置，避免長時間強光直曬或過度陰暗",
                "可適度修剪枯枝枯葉，集中養分"
            ]
        ),
        WitherLevel.severe: WitherAdvice(
            summary: "大面積枯萎，植株壓力較大。",
            actions: [
                "可檢查根系是否腐爛或乾枯，必要時考慮換盆換土",
                "建議暫停施肥，先穩定水分與環境",
                "可保留健康枝條、大幅修剪枯萎部位後持續觀察"
            ]
        )
    ]
}
