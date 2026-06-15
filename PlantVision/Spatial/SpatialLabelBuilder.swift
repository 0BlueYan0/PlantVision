import RealityKit
import simd
import UIKit

/// 組裝空間標籤所需的 RealityKit 物件,以及純數學的平滑/座標換算。
/// 數學部分刻意抽成 static 純函式,方便日後加單元測試。
enum SpatialLabelBuilder {

    // MARK: - 純數學(可獨立測試)

    /// 由 bounding box 的最小角 + 範圍,換算正規化座標(0...1)對應的 local 座標點。
    static func localPoint(boundingBoxMin min: SIMD3<Float>,
                           extent: SIMD3<Float>,
                           normalized: SIMD3<Float>) -> SIMD3<Float> {
        min + normalized * extent
    }

    /// 對剛體 transform 做指數平滑(translation 線性內插、rotation 球面內插),降低追蹤抖動。
    /// `alpha` 0...1,越大越跟手、越小越穩。ObjectTracking 回傳的是剛體 pose,這裡固定 scale = 1。
    static func smoothed(current: Transform, target: Transform, alpha: Float) -> Transform {
        var result = current
        result.translation = simd_mix(current.translation, target.translation, SIMD3<Float>(repeating: alpha))
        result.rotation = simd_slerp(current.rotation, target.rotation, alpha)
        result.scale = .one
        return result
    }

    // MARK: - RealityKit 物件

    /// 部位標記球(實機校正時用來確認錨點落在真實花/葉上)。
    static func makeMarker(radius: Float, color: UIColor) -> ModelEntity {
        let marker = ModelEntity(
            mesh: .generateSphere(radius: max(0.004, radius)),
            materials: [UnlitMaterial(color: color.withAlphaComponent(0.6))]
        )
        marker.name = "part-marker"
        return marker
    }

    /// 從部位點 `a` 指到標籤點 `b` 的指引線(細圓柱)。
    /// 圓柱預設沿 +Y 軸,需把它旋轉對齊 a→b 方向。
    static func makeLeader(from a: SIMD3<Float>,
                           to b: SIMD3<Float>,
                           radius: Float = 0.0015,
                           color: UIColor = .white) -> ModelEntity {
        let direction = b - a
        let length = simd_length(direction)
        let cylinder = ModelEntity(
            mesh: .generateCylinder(height: max(length, 0.0001), radius: radius),
            materials: [UnlitMaterial(color: color)]
        )
        cylinder.name = "part-leader"
        cylinder.position = (a + b) / 2

        if length > 1e-5 {
            let up = SIMD3<Float>(0, 1, 0)
            let n = direction / length
            let dot = simd_dot(up, n)
            if dot < 0.9999 && dot > -0.9999 {
                let axis = simd_normalize(simd_cross(up, n))
                cylinder.orientation = simd_quatf(angle: acos(dot), axis: axis)
            } else if dot <= -0.9999 {
                // 反向:繞任一水平軸轉 180°
                cylinder.orientation = simd_quatf(angle: .pi, axis: [1, 0, 0])
            }
        }
        return cylinder
    }

    /// 組好「一個部位」的子樹:標記球(在 group 原點)+ 指引線 + 標籤(在 labelOffset,面向使用者)。
    /// group 本身的位置之後由 `ObjectTrackingController` 依 bounding box 設定。
    static func makePartGroup(_ anchor: PartAnchor, label: Entity?) -> Entity {
        let group = Entity()
        group.name = "part-group-\(anchor.part.rawValue)"

        group.addChild(makeMarker(radius: anchor.zoneRadius, color: UIColor(anchor.part.markerColor)))
        group.addChild(makeLeader(from: .zero, to: anchor.labelOffset))

        if let label {
            label.position = anchor.labelOffset
            label.components.set(BillboardComponent())
            group.addChild(label)
        }
        return group
    }
}
