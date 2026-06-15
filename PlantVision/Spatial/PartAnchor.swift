import simd
import SwiftUI

/// 要在空間中標註的植物部位。目前只支援花與葉(對齊使用者選定的範圍)。
enum PlantPart: String, CaseIterable, Hashable, Sendable {
    case flower
    case leaf

    var displayName: String {
        switch self {
        case .flower: "花"
        case .leaf: "葉"
        }
    }

    /// 標記球的顏色,用來在實機校正時一眼分辨花/葉錨點。
    var markerColor: Color {
        switch self {
        case .flower: .yellow
        case .leaf: .green
        }
    }
}

/// 把某個部位「烘焙」進被追蹤物件的座標系。
///
/// 因為 ObjectTracking 只給整株剛體的 pose、一般 App 又不能讀鏡頭即時偵測部位,
/// 所以花/葉的位置是事先相對追蹤框定義好的。這裡用「bounding box 正規化座標」表示,
/// 好處是不必手動量公分、會自動依掃描出的尺寸縮放;實機看到偏掉時再微調這些數字即可。
struct PartAnchor: Sendable {
    let part: PlantPart
    /// 部位在追蹤物件 axis-aligned bounding box 內的位置,每軸 0...1
    /// (0 = bbox 最小角,1 = 最大角)。例:花約 [0.5, 0.9, 0.5] = 頂部中央。
    let normalizedPosition: SIMD3<Float>
    /// 標籤相對部位點要浮出的位移(公尺,物件 local 座標)。
    let labelOffset: SIMD3<Float>
    /// 此錨點代表該部位的「寬鬆程度」:葉是一片區域(較大),花較精準(較小)。
    /// 同時當作校正用標記球的半徑。
    let zoneRadius: Float
}

/// 一個 `.referenceobject` 對應的設定:檔名、是哪種植物、各部位錨點。
struct ReferenceObjectProfile: Sendable {
    /// 穩定識別字(內部用)。
    let referenceObjectID: String
    /// app bundle 內 `.referenceobject` 的檔名(不含副檔名)。
    let referenceFileName: String
    /// 對應 `PlantDatabase` 的 plant id,決定標籤顯示哪種植物的文字。
    let plantID: String
    let parts: [PartAnchor]
}

/// 已掃描 reference object 的設定清單。新增掃描後在這裡加一筆即可。
enum SpatialLabelCatalog {
    /// ⚠️ 初始值是「對盆栽合理的預設」,實機上若花/葉標籤位置偏掉,
    /// 直接調 `normalizedPosition` / `labelOffset` 這些常數即可(不需重新訓練)。
    /// `plantID` 請改成你實際掃描的那一株植物。
    static let profiles: [ReferenceObjectProfile] = [
        ReferenceObjectProfile(
            referenceObjectID: "plantpot",
            referenceFileName: "PlantPot",
            plantID: "lobelia-erinus",
            parts: [
                PartAnchor(
                    part: .flower,
                    normalizedPosition: [0.5, 0.88, 0.5],
                    labelOffset: [0.16, 0.06, 0.02],
                    zoneRadius: 0.02
                ),
                PartAnchor(
                    part: .leaf,
                    normalizedPosition: [0.36, 0.5, 0.5],
                    labelOffset: [-0.18, 0.0, 0.02],
                    zoneRadius: 0.05
                )
            ]
        )
    ]

    static func profile(forFileNamed name: String) -> ReferenceObjectProfile? {
        profiles.first { $0.referenceFileName == name }
    }
}
