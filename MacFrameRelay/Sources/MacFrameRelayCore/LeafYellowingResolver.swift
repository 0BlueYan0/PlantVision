import Foundation

/// 單一像素的顏色歸類。`background` 代表低飽和／低亮度（陰影、土壤、牆面等）或色相落在
/// 綠黃帶之外，不計入黃化比例的分母——黃化是「葉片裡黃掉的比例」，只看綠＋黃的植物像素。
public enum LeafPixelClass: Equatable, Sendable {
    case green
    case yellow
    case background
}

/// 由逐像素的綠／黃／背景判定，彙整出整幅畫面的「葉片黃化比例」。抽成純函式以便用具體像素值測試。
///
/// 與枯萎（`WitherScoreResolver`）互補但獨立：枯萎來自二元模型對整塊葉片的判定，黃化純粹看顏色，
/// 不需 ML。比例 = 黃化像素 ÷（綠＋黃像素），`background` 不計入分母；植物像素太少回 `nil`（不確定）。
public enum LeafYellowingResolver {
    /// 至少要有幾個「植物像素（綠或黃）」才回報比例，否則視為樣本不足 → 不確定。
    public static let minimumPlantPixels = 200

    // 色相以度（0–360）表示。綠帶與黃帶相接於 80°，避免中間出現判不出的死區。
    static let yellowHueRange: ClosedRange<Double> = 40 ... 80
    static let greenHueLowerBound: Double = 80
    static let greenHueUpperBound: Double = 170
    // 飽和度或亮度低於此值視為背景（灰、暗、近白都不是飽和的葉色）。
    static let minimumSaturation: Double = 0.20
    static let minimumValue: Double = 0.20

    public static func resolve(
        _ pixels: [LeafPixelClass],
        minimumPlantPixels: Int = LeafYellowingResolver.minimumPlantPixels
    ) -> Double? {
        let yellowCount = pixels.lazy.filter { $0 == .yellow }.count
        let greenCount = pixels.lazy.filter { $0 == .green }.count
        let plantPixels = yellowCount + greenCount

        guard plantPixels >= minimumPlantPixels else { return nil }
        return Double(yellowCount) / Double(plantPixels)
    }

    /// 純函式：把單一像素的 HSV（hue 0–360、saturation/value 0–1）映射成綠／黃／背景。
    /// 飽和度或亮度過低 → 背景；色相落在黃帶 → 黃；綠帶 → 綠；其餘（橘、紅、藍等）→ 背景。
    /// 抽出以便用具體 HSV 值單元測試。
    public static func classifyPixel(
        hue: Double,
        saturation: Double,
        value: Double
    ) -> LeafPixelClass {
        guard saturation >= minimumSaturation, value >= minimumValue else { return .background }
        if yellowHueRange.contains(hue) { return .yellow }
        if hue > greenHueLowerBound, hue <= greenHueUpperBound { return .green }
        return .background
    }
}
