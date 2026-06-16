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

}

extension SpatialLabelBuilder {

    /// 組一個部位 callout:依設計只有「同色細發光引線 + SwiftUI 標籤」,不含部位圓點/發光球。
    /// 引線從部位點(group 原點)指向標籤位置;group.position 由選取層每幀更新。
    @MainActor
    static func makeCallout(part: PlantPart,
                            label: Entity?,
                            labelOffset: SIMD3<Float>) -> Entity {
        let group = Entity()
        group.name = "callout-\(part.rawValue)"
        group.isEnabled = false   // 選取層選到候選前先隱藏

        // 部位色(花黃/葉綠)細發光引線,從部位點(.zero)指到標籤。
        group.addChild(makeLeader(from: .zero, to: labelOffset, color: UIColor(part.markerColor)))

        if let label {
            label.position = labelOffset
            label.components.set(BillboardComponent())
            group.addChild(label)
        }
        return group
    }
}
