import Foundation

/// 跨幀平滑枯萎比例。枯萎比例是**連續值**，單幀會在邊界附近抖動，
/// 因此在一個時間窗內對最近幾幀的比例**取算術平均**壓抖動——
/// 刻意不沿用 `TemporalLabelSmoother` 的多數決（多數決適用離散標籤，不適用連續比例）。
///
/// 輸入語意：逐幀 `ratio == nil`（該幀有植物的區塊不足、不確定）視為「沒有可用樣本」，
/// 不計入平均；窗內完全沒有有效樣本時回 `nil`（不確定），交由呼叫端忽略。
public struct TemporalWitherSmoother {
    /// 參與平均的時間窗（秒）。0.7 秒在 0.1 秒抽幀下約 7 幀，與 `TemporalLabelSmoother` 對齊。
    public let windowSeconds: TimeInterval
    /// 窗內至少要有幾個有效樣本才回報平均，否則回 nil。
    public let minimumSamples: Int

    private var history: [(ratio: Double, at: Date)] = []

    public init(windowSeconds: TimeInterval = 0.7, minimumSamples: Int = 1) {
        self.windowSeconds = windowSeconds
        self.minimumSamples = minimumSamples
    }

    public mutating func record(_ ratio: Double?, at: Date) -> Double? {
        // nil（不確定）不入窗：沒有可用比例，不能當成 0 拉低平均。
        if let ratio {
            history.append((ratio, at))
        }
        // 丟掉超出時間窗、或時間戳比當前還新的（防亂序），與 TemporalLabelSmoother 對齊。
        history.removeAll { at.timeIntervalSince($0.at) > windowSeconds || $0.at > at }
        return Self.average(of: history.map(\.ratio), minimumSamples: minimumSamples)
    }

    /// 純函式：對窗內各幀的枯萎比例取算術平均。樣本數低於門檻（或為空）回 nil。
    public static func average(of ratios: [Double], minimumSamples: Int = 1) -> Double? {
        guard ratios.count >= minimumSamples, !ratios.isEmpty else { return nil }
        return ratios.reduce(0, +) / Double(ratios.count)
    }
}
