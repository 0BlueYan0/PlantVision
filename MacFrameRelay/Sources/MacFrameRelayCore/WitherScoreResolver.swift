import Foundation

/// 單一區塊的枯萎判定結果。`noPlant` 代表該區塊沒有足夠信心判定為植物葉片
/// （背景或兩類都不確定），不計入枯萎比例的分母。
public enum WitherTileClassification: String, Equatable, Sendable {
    case healthy
    case withered
    case noPlant
}

/// 由各區塊的枯萎/健康判定彙整出整幅畫面的「枯萎面積比例」。抽成純函式以便用真實票數做單元測試。
///
/// 重點：枯萎程度是**面積比例**問題，不是「數幾塊枯掉」。比例 = 枯萎區塊 ÷（健康＋枯萎區塊），
/// `noPlant` 區塊不計入分母。有植物的區塊太少時回 `nil`（不確定，不硬猜），交給呼叫端忽略該幀。
public enum WitherScoreResolver {
    /// 至少要有幾個「有植物」的區塊才回報比例，否則視為樣本不足 → 不確定。
    public static let minimumPlantTiles = 2

    public static func resolve(
        _ tiles: [WitherTileClassification],
        minimumPlantTiles: Int = WitherScoreResolver.minimumPlantTiles
    ) -> Double? {
        let witheredCount = tiles.lazy.filter { $0 == .withered }.count
        let healthyCount = tiles.lazy.filter { $0 == .healthy }.count
        let plantTiles = witheredCount + healthyCount

        guard plantTiles >= minimumPlantTiles else { return nil }
        return Double(witheredCount) / Double(plantTiles)
    }
}
