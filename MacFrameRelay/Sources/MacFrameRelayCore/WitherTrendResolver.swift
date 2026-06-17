import Foundation

/// 一段時間內枯萎程度的變化趨勢。與「當下枯萎比例」是兩條不同的訊號：
/// 比例回答「現在多枯」，趨勢回答「正在變好還是變壞」。
public enum WitherTrend: String, Equatable, Sendable {
    case worsening   // 惡化（枯萎比例隨時間上升）
    case improving   // 改善（枯萎比例隨時間下降）
    case stable      // 穩定（變化在雜訊門檻內）
}

/// 由一段時間內平滑後的枯萎比例序列，判定趨勢（惡化／改善／穩定）。抽成純函式以便用樣本序列測試。
///
/// 做法：把序列切成「前半窗」與「後半窗」，比較兩段的平均值之差。差值超過門檻才判定
/// 惡化／改善，否則視為穩定——刻意用「兩段平均之差」而非線性斜率，較抗單幀雜訊、也好測，
/// 與專案其他地方「取平均壓抖動」的風格一致（見 `TemporalWitherSmoother`）。
///
/// 樣本太少時回 `nil`（不確定，不硬猜趨勢），交由呼叫端忽略；比例上升＝惡化。
public enum WitherTrendResolver {
    /// 至少要有幾個樣本才判定趨勢，否則視為樣本不足 → 不確定。
    public static let minimumSamples = 6
    /// 後半窗平均與前半窗平均之差，絕對值要達到此門檻才算惡化／改善，否則穩定（濾掉小幅雜訊）。
    public static let changeThreshold = 0.08

    public static func resolve(
        _ samples: [Double],
        minimumSamples: Int = WitherTrendResolver.minimumSamples,
        changeThreshold: Double = WitherTrendResolver.changeThreshold
    ) -> WitherTrend? {
        guard samples.count >= minimumSamples else { return nil }

        // 奇數個樣本時，捨去正中央那一個，前後各取 count/2 個，維持兩段對稱。
        let half = samples.count / 2
        let earlyAverage = mean(of: Array(samples.prefix(half)))
        let recentAverage = mean(of: Array(samples.suffix(half)))
        let delta = recentAverage - earlyAverage

        if delta >= changeThreshold { return .worsening }
        if delta <= -changeThreshold { return .improving }
        return .stable
    }

    private static func mean(of values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }
}
