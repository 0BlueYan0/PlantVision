import Foundation

/// 把連續的枯萎面積比例（0–1）分成幾個等級。Mac 端用它把 `witherLevel` 填進 payload，
/// visionOS 端有一份相同閾值的鏡像（見 `PlantVision/.../WitherLevel.swift`）。
///
/// 等級：0 健康 / 1 輕微 / 2 中度 / 3 嚴重。閾值為展示用預設值，可依實機觀察調整；
/// 與 `PlantClassifier` 那些用 held-out 校過的投票閾值不同，這裡尚未做資料校準。
public enum WitherLevel {
    public static let healthy = 0
    public static let mild = 1
    public static let moderate = 2
    public static let severe = 3

    public static func level(forRatio ratio: Double) -> Int {
        switch ratio {
        case ..<0.10: healthy
        case ..<0.35: mild
        case ..<0.65: moderate
        default: severe
        }
    }
}
