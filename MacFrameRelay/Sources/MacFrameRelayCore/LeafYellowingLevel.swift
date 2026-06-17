import Foundation

/// 把連續的葉片黃化比例（0–1）分成幾個等級。結構鏡像 `WitherLevel`，但**閾值獨立**——
/// 黃化與枯萎是兩種不同的劣化訊號，不共用同一組界線。Mac 端用它把 `yellowLevel` 填進 payload，
/// visionOS 端有一份相同閾值的鏡像（見 `PlantVision/.../LeafYellowingLevel.swift`），改閾值要同步兩邊。
///
/// 等級：0 正常 / 1 輕微 / 2 中度 / 3 嚴重。閾值為展示用預設值，可依實機觀察調整。
public enum LeafYellowingLevel {
    public static let none = 0
    public static let mild = 1
    public static let moderate = 2
    public static let severe = 3

    public static func level(forRatio ratio: Double) -> Int {
        switch ratio {
        case ..<0.15: none
        case ..<0.35: mild
        case ..<0.60: moderate
        default: severe
        }
    }
}
