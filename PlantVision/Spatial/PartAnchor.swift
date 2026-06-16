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
}

/// 某個部位「烘焙」進被追蹤物件座標系的所有標註點。
///
/// 座標來自在 Reality Composer Pro 對著掃描模型標的 `anchor_flower` / `anchor_leaf` 節點
/// (公尺、物件 local frame,與 `.referenceobject` 同一個座標系)。runtime 時整株被 ObjectTracking
/// 追到後,這些點就是相對追蹤框的固定位移。
struct PartAnchor: Sendable {
    let part: PlantPart
    /// 該部位所有標註點(物件 local 座標,公尺)。會各畫一顆小圓點,方便實機核對。
    let points: [SIMD3<Float>]
    /// 標籤相對「點群重心」浮出的位移(公尺,物件 local)。
    /// 花/葉重心很近(本例僅約 2.3cm),靠這個位移把兩張標籤分開、各自拉指引線。
    let labelOffset: SIMD3<Float>
    /// 每個標註點顯示的小圓點半徑(公尺)。
    let dotRadius: Float

    /// 點群重心 = 指引線指向的目標點。
    var centroid: SIMD3<Float> {
        guard !points.isEmpty else { return .zero }
        return points.reduce(.zero, +) / Float(points.count)
    }
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
    /// 花/葉的座標由 RCP 的 Scene.usda 解析而來(花 25 點、葉 10 點)。
    /// `plantID` = catharanthus-roseus(日日春,使用者掃描的植物)。
    /// 若實機上整片標籤位置一致地偏移,通常是追蹤框與模型框差一個常數,調 `labelOffset` 或回報我即可。
    static let profiles: [ReferenceObjectProfile] = [
        ReferenceObjectProfile(
            referenceObjectID: "plantpot",
            referenceFileName: "PlantPot",
            plantID: "lantana-camara",
            parts: [
                PartAnchor(
                    part: .flower,
                    points: [
                        SIMD3<Float>(0.11748, 1.18959, 0.01660),
                        SIMD3<Float>(0.17539, 1.18959, 0.04901),
                        SIMD3<Float>(0.19339, 1.18959, -0.02994),
                        SIMD3<Float>(0.12786, 1.23882, -0.01699),
                        SIMD3<Float>(0.28400, 1.15560, -0.09822),
                        SIMD3<Float>(0.27609, 1.12322, -0.07126),
                        SIMD3<Float>(-0.03100, 1.27400, -0.15630),
                        SIMD3<Float>(0.04770, 1.26540, -0.10500),
                        SIMD3<Float>(-0.08710, 1.25000, -0.16500),
                        SIMD3<Float>(-0.02090, 1.23940, -0.02440),
                        SIMD3<Float>(0.21880, 1.23100, -0.16150),
                        SIMD3<Float>(0.06350, 1.21340, -0.09660),
                        SIMD3<Float>(0.12810, 1.20060, -0.16130),
                        SIMD3<Float>(0.04920, 1.17920, -0.13000),
                        SIMD3<Float>(-0.08500, 1.17530, -0.14350),
                        SIMD3<Float>(0.01630, 1.14880, 0.06630),
                        SIMD3<Float>(0.20490, 1.14370, -0.14930),
                        SIMD3<Float>(-0.05730, 1.13120, -0.14590),
                        SIMD3<Float>(0.06770, 1.12870, 0.01150),
                        SIMD3<Float>(-0.01340, 1.12860, -0.08020),
                        SIMD3<Float>(0.17810, 1.11300, -0.09420),
                        SIMD3<Float>(0.07020, 1.10570, -0.11140),
                        SIMD3<Float>(0.23510, 1.09370, -0.16130),
                        SIMD3<Float>(0.14580, 1.08450, -0.04310),
                        SIMD3<Float>(-0.09630, 1.07350, -0.09270)
                    ],
                    labelOffset: SIMD3<Float>(0.24, 0.17, 0.0),
                    dotRadius: 0.008
                ),
                PartAnchor(
                    part: .leaf,
                    points: [
                        SIMD3<Float>(-0.11400, 1.16150, -0.11990),
                        SIMD3<Float>(0.05830, 1.12680, -0.17670),
                        SIMD3<Float>(0.26180, 1.18670, -0.15900),
                        SIMD3<Float>(0.23450, 1.13430, -0.02550),
                        SIMD3<Float>(0.00170, 1.14560, 0.07890),
                        SIMD3<Float>(-0.09680, 1.12320, -0.16140),
                        SIMD3<Float>(0.17630, 1.17540, -0.17650),
                        SIMD3<Float>(0.16230, 1.15600, 0.03420),
                        SIMD3<Float>(-0.05830, 1.17060, -0.00590),
                        SIMD3<Float>(0.10700, 1.16380, -0.17840)
                    ],
                    labelOffset: SIMD3<Float>(-0.26, -0.12, 0.0),
                    dotRadius: 0.008
                )
            ],
            frameCorrection: .zero
        )
    ]

    static func profile(forFileNamed name: String) -> ReferenceObjectProfile? {
        profiles.first { $0.referenceFileName == name }
    }
}
