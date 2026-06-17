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

    /// 引線終點停在標籤近緣前的間隙(公尺)。標籤約 210pt 寬的玻璃卡,半徑 ≈ 0.08m;
    /// 引線縮短到「標籤中心前 gap」結束,避免線段穿過/超出卡片(見實機回報)。可調。
    static let leaderCardGap: Float = 0.08

    /// 組一個部位 callout:依設計只有「同色細發光引線 + SwiftUI 標籤」,不含部位圓點/發光球。
    /// 引線從部位點(group 原點)指向標籤,但停在卡片近緣前(縮短 leaderCardGap);
    /// group 的 position / orientation 由選取層每幀以 `place(_:at:)` 更新(位置 + 朝樹叢外側 yaw)。
    @MainActor
    static func makeCallout(part: PlantPart,
                            label: Entity?,
                            labelOffset: SIMD3<Float>) -> Entity {
        let group = Entity()
        group.name = "callout-\(part.rawValue)"
        group.isEnabled = false   // 選取層選到候選前先隱藏

        // 部位色(花黃/葉綠)細發光引線:從部位點(.zero)指向標籤近緣(縮短 gap,避免戳出卡片)。
        let dist = simd_length(labelOffset)
        let leaderEnd = dist > leaderCardGap ? labelOffset * ((dist - leaderCardGap) / dist) : labelOffset
        group.addChild(makeLeader(from: .zero, to: leaderEnd, color: UIColor(part.markerColor)))

        if let label {
            label.position = labelOffset
            label.components.set(BillboardComponent())
            group.addChild(label)
        }
        return group
    }

    /// 把 callout 放到部位點,並繞 +Y 轉向,使其 local +X 指向「植物中軸 → 該點」的水平方向(朝樹叢外側)。
    /// 如此 labelOffset 的 +X 分量永遠把標籤往樹叢外推(不再因固定 model 方向而把半邊標籤埋進葉子被遮擋),
    /// +Y 分量(花正/上、葉負/下)維持垂直分離。標籤本身有 BillboardComponent,仍面向使用者,只有位置受影響。
    /// 由兩個場景(手動擺放 / 物件追蹤)的 refreshCallouts 每幀呼叫。
    static func place(_ callout: Entity, at point: SIMD3<Float>) {
        callout.position = point
        let horizontal = SIMD3<Float>(point.x, 0, point.z)
        let len = simd_length(horizontal)
        guard len > 1e-4 else {
            // 點幾乎在中軸上,沒有明確外側方向,保持不旋轉。
            callout.orientation = simd_quatf(angle: 0, axis: [0, 1, 0])
            return
        }
        let d = horizontal / len
        // 繞 +Y 轉 θ 使 (1,0,0) → (d.x, 0, d.z):θ = atan2(-d.z, d.x)。
        callout.orientation = simd_quatf(angle: atan2(-d.z, d.x), axis: [0, 1, 0])
    }
}
