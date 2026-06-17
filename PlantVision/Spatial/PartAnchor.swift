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
    /// 標籤相對「選中候選點」浮出的位移(公尺)。X = 朝樹叢外側(由 `SpatialLabelBuilder.place(_:at:)`
    /// 每幀繞 Y 對齊到該點的徑向方向),Y = 垂直分離(花正/上、葉負/下,避免兩標籤重疊),Z 一般為 0。
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
    /// 花/葉的座標由 RCP 的 Scene.usda 解析而來(花 25 點、葉 14 點)。
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
                        SIMD3<Float>(-0.15742, 0.92919, 0.23854),
                        SIMD3<Float>(0.02897, 0.89350, -0.37253),
                        SIMD3<Float>(-0.29759, 0.86381, -0.18524),
                        SIMD3<Float>(-0.26982, 0.86285, 0.21237),
                        SIMD3<Float>(-0.39305, 0.82758, -0.02550),
                        SIMD3<Float>(-0.20655, 0.91396, -0.07479),
                        SIMD3<Float>(0.13907, 0.89498, -0.26731),
                        SIMD3<Float>(0.29322, 0.88850, -0.11601),
                        SIMD3<Float>(-0.17485, 0.79425, -0.32891),
                        SIMD3<Float>(-0.24481, 0.78658, 0.26194),
                        SIMD3<Float>(-0.27710, 0.78951, -0.29228),
                        SIMD3<Float>(0.13740, 0.77860, -0.37758),
                        SIMD3<Float>(0.30057, 0.77090, 0.25703),
                        SIMD3<Float>(0.36843, 0.76815, -0.08324),
                        SIMD3<Float>(0.33988, 0.76587, -0.19490),
                        SIMD3<Float>(0.04433, 0.75602, 0.36510),
                        SIMD3<Float>(-0.37299, 0.73039, -0.15136),
                        SIMD3<Float>(0.12600, 0.71160, 0.39519),
                        SIMD3<Float>(0.28140, 0.68834, -0.30190),
                        SIMD3<Float>(-0.22312, 0.68374, -0.34550),
                        SIMD3<Float>(-0.41573, 0.65487, 0.03360),
                        SIMD3<Float>(0.33157, 0.66170, -0.17417),
                        SIMD3<Float>(-0.24952, 0.61211, -0.27676),
                        SIMD3<Float>(-0.20231, 0.60781, 0.28902),
                        SIMD3<Float>(0.28203, 0.58838, 0.31129)
                    ],
                    labelOffset: SIMD3<Float>(0.24, 0.17, 0.0)
                ),
                PartAnchor(
                    part: .leaf,
                    points: [
                        SIMD3<Float>(-0.32401, 0.90436, 0.04814),
                        SIMD3<Float>(0.39155, 0.89193, 0.04282),
                        SIMD3<Float>(0.12782, 0.88730, -0.39988),
                        SIMD3<Float>(0.28622, 0.84956, 0.17431),
                        SIMD3<Float>(0.36491, 0.84676, -0.10949),
                        SIMD3<Float>(-0.33963, 0.83151, -0.10868),
                        SIMD3<Float>(-0.06868, 0.83678, 0.34324),
                        SIMD3<Float>(-0.35800, 0.78394, 0.17314),
                        SIMD3<Float>(-0.08375, 0.78398, -0.38389),
                        SIMD3<Float>(0.18499, 0.77833, 0.33537),
                        SIMD3<Float>(0.09035, 0.72955, -0.41535),
                        SIMD3<Float>(0.39609, 0.71898, 0.04524),
                        SIMD3<Float>(0.35195, 0.71095, 0.23149),
                        SIMD3<Float>(-0.38023, 0.67984, -0.05579)
                    ],
                    labelOffset: SIMD3<Float>(0.26, -0.12, 0.0)
                )
            ],
            frameCorrection: .zero
        )
    ]

    static func profile(forFileNamed name: String) -> ReferenceObjectProfile? {
        profiles.first { $0.referenceFileName == name }
    }
}
