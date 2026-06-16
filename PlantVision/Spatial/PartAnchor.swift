import simd
import SwiftUI

/// 要在空間中標註的植物部位。目前支援花與葉。
enum PlantPart: String, CaseIterable, Hashable, Sendable {
    case flower
    case leaf

    var displayName: String {
        switch self {
        case .flower: "花"
        case .leaf: "葉"
        }
    }

    /// 標註點/指引線的顏色,用來分辨花(黃)與葉(綠)。
    var markerColor: Color {
        switch self {
        case .flower: .yellow
        case .leaf: .green
        }
    }

    /// 部位圖示(SF Symbol),用在空間標籤上。
    var symbolName: String {
        switch self {
        case .flower: "camera.macro"
        case .leaf: "leaf.fill"
        }
    }
}

/// 某個部位「烘焙」進被追蹤物件座標系的所有標註點。
///
/// 座標來自在 Reality Composer Pro 對著掃描模型標的 `anchor_flower` / `anchor_leaf` 節點
/// (公尺、物件 local frame,與 `.referenceobject` 同一個座標系)。runtime 時整株被 ObjectTracking
/// 追到後,這些點就是相對追蹤框的固定位移。
struct PartAnchor: Sendable {
    let part: PlantPart
    /// 該部位的候選點:每個點 = 一朵花/一片葉的獨立位置(物件 local 座標,公尺)。
    /// runtime 只顯示離使用者最近的一個(見 NearestPartSelector)。
    let points: [SIMD3<Float>]
    /// 標籤相對「選中候選點」浮出的位移(公尺,物件 local)。
    /// 花/葉可能相鄰,靠這個位移把兩張標籤分開、各自拉指引線。
    let labelOffset: SIMD3<Float>
}

/// 一個 `.referenceobject` 對應的設定。新增一株植物 = 在 `SpatialLabelCatalog.profiles` 加一筆,
/// 並把對應的 `<referenceFileName>.referenceobject` 放進 app bundle(其他程式不用動)。
struct ReferenceObjectProfile: Sendable {
    let referenceObjectID: String
    /// app bundle 內 `.referenceobject` 的檔名(不含副檔名)。
    let referenceFileName: String
    /// 對應 `PlantDatabase` 的 plant id,決定標籤文字。
    let plantID: String
    let parts: [PartAnchor]
    /// 整株標籤的座標微調(公尺,物件 local)。若實機上整片一致偏移一個常數,在這裡補;預設 `.zero`。
    /// 注意:只能修正「常數平移」;植物變形(如枯萎)造成的飄移無法靠這個修。
    let frameCorrection: SIMD3<Float>
}

/// 已掃描 reference object 的設定清單。
enum SpatialLabelCatalog {
    /// 花/葉的座標由 RCP 的 Scene.usda 解析而來(花 22 點、葉 14 點)。
    /// `plantID` = lantana-camara(馬纓丹,使用者掃描的植物)。
    /// 若實機上整片標籤位置一致地偏移,通常是追蹤框與模型框差一個常數,調 `labelOffset` 或回報我即可。
    static let profiles: [ReferenceObjectProfile] = [
        ReferenceObjectProfile(
            referenceObjectID: "lantana-camara",
            referenceFileName: "PlantTracker",
            plantID: "lantana-camara",
            parts: [
                PartAnchor(
                    part: .flower,
                    points: [
                        SIMD3<Float>(-0.05678, 0.32874, 0.08402),
                        SIMD3<Float>(0.00603, 0.31891, -0.11940),
                        SIMD3<Float>(-0.10362, 0.31044, -0.05745),
                        SIMD3<Float>(-0.09382, 0.30899, 0.07372),
                        SIMD3<Float>(-0.13492, 0.29778, -0.00455),
                        SIMD3<Float>(-0.06215, 0.28653, -0.10640),
                        SIMD3<Float>(-0.08530, 0.28519, 0.09251),
                        SIMD3<Float>(-0.09563, 0.28500, -0.09317),
                        SIMD3<Float>(0.04164, 0.28155, -0.12079),
                        SIMD3<Float>(0.09654, 0.27870, 0.08967),
                        SIMD3<Float>(0.11902, 0.27804, -0.02468),
                        SIMD3<Float>(0.10851, 0.27731, -0.05893),
                        SIMD3<Float>(0.01081, 0.27343, 0.12502),
                        SIMD3<Float>(-0.12629, 0.26518, -0.04543),
                        SIMD3<Float>(0.03867, 0.25935, 0.13598),
                        SIMD3<Float>(0.09001, 0.25067, -0.09510),
                        SIMD3<Float>(-0.07776, 0.24942, -0.11063),
                        SIMD3<Float>(-0.14075, 0.24115, 0.01490),
                        SIMD3<Float>(0.10864, 0.24114, -0.05589),
                        SIMD3<Float>(-0.08707, 0.22602, -0.08843),
                        SIMD3<Float>(-0.07059, 0.22352, 0.09933),
                        SIMD3<Float>(0.08901, 0.21733, 0.10670)
                    ],
                    labelOffset: SIMD3<Float>(0.24, 0.17, 0.0)
                ),
                PartAnchor(
                    part: .leaf,
                    points: [
                        SIMD3<Float>(-0.11319, 0.32005, 0.01936),
                        SIMD3<Float>(0.12673, 0.31914, 0.01825),
                        SIMD3<Float>(0.03898, 0.31772, -0.12937),
                        SIMD3<Float>(0.09326, 0.30633, 0.06462),
                        SIMD3<Float>(0.11794, 0.30407, -0.03262),
                        SIMD3<Float>(-0.11726, 0.30163, -0.03222),
                        SIMD3<Float>(-0.02674, 0.30147, 0.11859),
                        SIMD3<Float>(-0.12388, 0.28383, 0.06157),
                        SIMD3<Float>(-0.03196, 0.28359, -0.12418),
                        SIMD3<Float>(0.05729, 0.28217, 0.11648),
                        SIMD3<Float>(0.03092, 0.26490, -0.13251),
                        SIMD3<Float>(0.12776, 0.26036, 0.01941),
                        SIMD3<Float>(0.11177, 0.25822, 0.07998),
                        SIMD3<Float>(-0.13179, 0.24958, -0.01490)
                    ],
                    labelOffset: SIMD3<Float>(-0.26, -0.12, 0.0)
                )
            ],
            frameCorrection: .zero
        )
    ]

    static func profile(forFileNamed name: String) -> ReferenceObjectProfile? {
        profiles.first { $0.referenceFileName == name }
    }
}
