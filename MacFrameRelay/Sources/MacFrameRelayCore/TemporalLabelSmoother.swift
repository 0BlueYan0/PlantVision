import Foundation

/// 跨幀穩定器：自動擷取每 0.1 秒一幀，單幀判定會在決策邊界附近抖動（同一株植物
/// 在 catharanthus / lobelia 之間跳）。這個結構在一個時間窗內對最近的逐幀判定做
/// 多數決，濾掉單幀雜訊；真正拉鋸（兩類票數打平）時誠實回報不確定，而非硬選一個。
///
/// 取代原本「保留上一個非背景結果 1 秒」的 hold——那個作法會延續錯誤標籤，
/// 多數決則需要近期多幀一致才改變輸出，既穩定又不會卡在舊的錯標。
///
/// 輸入語意：逐幀 `result == nil`（模型沒回傳結果）正規化成 background 一票。
/// 輸出語意：回傳 nil 代表窗內沒有足夠一致的多數（含兩類打平）→ 呼叫端視為不確定；
/// 回傳 background 結果代表穩定判定為背景；回傳植物結果代表穩定判定為該植物。
public struct TemporalLabelSmoother {
    /// 參與多數決的時間窗（秒）。0.7 秒在 0.1 秒抽幀下約 7 幀。
    public let windowSeconds: TimeInterval
    /// 勝出標籤至少要在窗內出現幾次，避免只憑一兩幀就輸出。
    /// 窗內幀數不足（手動單張或剛開始擷取）時，門檻自動降為現有幀數。
    public let minimumVotes: Int

    private var history: [(result: PlantClassificationResult, at: Date)] = []

    public init(windowSeconds: TimeInterval = 0.7, minimumVotes: Int = 3) {
        self.windowSeconds = windowSeconds
        self.minimumVotes = minimumVotes
    }

    public mutating func record(_ result: PlantClassificationResult?, at: Date) -> PlantClassificationResult? {
        let normalized = result ?? PlantClassificationResult(label: PlantImageClassifier.backgroundLabel, confidence: 0)
        history.append((normalized, at))
        // 丟掉超出時間窗、或時間戳比當前還新的（防亂序）
        history.removeAll { at.timeIntervalSince($0.at) > windowSeconds || $0.at > at }

        var counts: [String: Int] = [:]
        for entry in history {
            counts[entry.result.label, default: 0] += 1
        }

        let ranked = counts.sorted { $0.value > $1.value }
        // 門檻取 min(minimumVotes, 窗內幀數)：自動串流滿窗時要求多數一致才輸出（穩定）；
        // 手動單張或剛開始擷取（幀數不足）時用現有幀數當門檻，避免卡住。
        let needed = min(minimumVotes, history.count)
        guard let winner = ranked.first, winner.value >= needed else { return nil }
        // 嚴格多數：與亞軍打平則視為拉鋸 → 不確定
        if ranked.count >= 2, ranked[1].value == winner.value { return nil }

        // 回傳窗內最近一個帶有勝出標籤的實際結果，保留真實信心值
        for entry in history.reversed() where entry.result.label == winner.key {
            return entry.result
        }
        return nil
    }
}
