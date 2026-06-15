import RealityKit
import simd
import UIKit

/// 組裝空間標籤所需的 RealityKit 物件,以及純數學的平滑/座標換算。
/// 數學部分刻意抽成 static 純函式,方便日後加單元測試。
enum SpatialLabelBuilder {

    // MARK: - 純數學(可獨立測試)

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

    /// 組好「一個部位」的子樹,並把 group 放到點群重心:
    /// 每個標註點一顆小圓點(實機核對用)+ 從重心指到標籤的指引線 + 面向使用者的標籤。
    /// group 已是 trackedRoot 的子節點,因此整株被追到後這些內容會一起跟著動。
    static func makePartGroup(_ anchor: PartAnchor, label: Entity?) -> Entity {
        let group = Entity()
        group.name = "part-group-\(anchor.part.rawValue)"
        group.position = anchor.centroid

        let color = UIColor(anchor.part.markerColor)

        // 每個 RCP 標註點 → 一顆小圓點(相對重心擺放)
        for point in anchor.points {
            let dot = makeMarker(radius: anchor.dotRadius, color: color)
            dot.position = point - anchor.centroid
            group.addChild(dot)
        }

        // 指引線:重心(group 原點)→ 標籤位置
        group.addChild(makeLeader(from: .zero, to: anchor.labelOffset, color: color))

        if let label {
            label.position = anchor.labelOffset
            label.components.set(BillboardComponent())
            group.addChild(label)
        }
        return group
    }
}
