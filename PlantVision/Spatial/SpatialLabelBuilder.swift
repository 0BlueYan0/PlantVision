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

    /// 從部位點 `a` 指到標籤點 `b` 的指引線。
    /// 結構:核心細圓柱 +(可選)同軸半透明光暈圓柱 +(可選)卡側銜接小球;
    /// 圓柱預設沿 +Y 軸,整個 leader 父節點旋轉對齊 a→b 方向。外觀參數見「引線外觀(可調)」。
    static func makeLeader(from a: SIMD3<Float>,
                           to b: SIMD3<Float>,
                           radius: Float = leaderRadius,
                           color: UIColor = .white) -> Entity {
        let direction = b - a
        let length = simd_length(direction)
        let h = max(length, 0.0001)

        // 父節點:承載核心線 / 光暈 / 端點,統一定位與旋轉。
        let leader = Entity()
        leader.name = "part-leader"

        // 核心細發光線(unlit,從各角度等亮)。
        let core = ModelEntity(
            mesh: .generateCylinder(height: h, radius: radius),
            materials: [UnlitMaterial(color: color)]
        )
        leader.addChild(core)

        // 同軸半透明光暈:略大半徑、低 alpha,讓引線在葉叢前更易辨識(對比 / 可讀)。
        if leaderHaloEnabled {
            var haloMaterial = UnlitMaterial(color: color)
            haloMaterial.blending = .transparent(opacity: .init(floatLiteral: leaderHaloOpacity))
            let halo = ModelEntity(
                mesh: .generateCylinder(height: h, radius: radius * leaderHaloRadiusMultiple),
                materials: [haloMaterial]
            )
            leader.addChild(halo)
        }

        // 卡側銜接小球:把線「接」進標籤卡那一端(local +Y 的 b 端 = world b)。
        // 只在卡側,不在植物部位端重加圓點(尊重 commit 2c6ee92「移除部位圓點」)。
        if leaderCardNodeEnabled {
            let node = ModelEntity(
                mesh: .generateSphere(radius: radius * leaderCardNodeRadiusMultiple),
                materials: [UnlitMaterial(color: color)]
            )
            node.position = SIMD3<Float>(0, h / 2, 0)
            leader.addChild(node)
        }

        leader.position = (a + b) / 2

        if length > 1e-5 {
            let up = SIMD3<Float>(0, 1, 0)
            let n = direction / length
            let dot = simd_dot(up, n)
            if dot < 0.9999 && dot > -0.9999 {
                let axis = simd_normalize(simd_cross(up, n))
                leader.orientation = simd_quatf(angle: acos(dot), axis: axis)
            } else if dot <= -0.9999 {
                // 反向:繞任一水平軸轉 180°
                leader.orientation = simd_quatf(angle: .pi, axis: [1, 0, 0])
            }
        }
        return leader
    }

}

extension SpatialLabelBuilder {

    // MARK: - 引線外觀(可調)

    /// 核心引線半徑(公尺)。原 0.0015;略加粗讓 1–2m 下更清楚,仍維持細緻。
    static let leaderRadius: Float = 0.0022

    /// 是否畫同軸半透明光暈(讓引線在葉叢前更顯眼)。
    static let leaderHaloEnabled = true
    /// 光暈半徑相對核心的倍數。
    static let leaderHaloRadiusMultiple: Float = 2.6
    /// 光暈不透明度(0...1)。
    static let leaderHaloOpacity: Float = 0.22

    /// 是否在「卡片那一端」加同色銜接小球,把線接進卡片(不在植物部位端加,尊重移除圓點的設計)。
    static let leaderCardNodeEnabled = true
    /// 卡側小球半徑相對核心的倍數。
    static let leaderCardNodeRadiusMultiple: Float = 3.0

    /// 引線終點停在標籤近緣前的間隙(公尺)。標籤約 240pt 寬的玻璃卡,半徑 ≈ 0.08m;
    /// 引線縮短到「標籤中心前 gap」結束,避免線段穿過/超出卡片(見實機回報)。可調。
    static let leaderCardGap: Float = 0.08

    /// 組一個部位 callout:依設計只有「同色發光引線(核心線 + 光暈 + 卡側銜接小球)+ SwiftUI 標籤」,
    /// 不在植物部位端加圓點/發光球。引線從部位點(group 原點)指向標籤,但停在卡片近緣前(縮短 leaderCardGap);
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
