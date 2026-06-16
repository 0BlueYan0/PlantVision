import RealityKit
import simd
import UIKit
import PlantAnchor

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

}

extension SpatialLabelBuilder {

    /// 載入並取出兩個 marker 模板；失敗回 (nil, nil)，由 makeCallout 走 fallback。
    @MainActor
    static func loadMarkerTemplates() async -> (flower: Entity?, leaf: Entity?) {
        guard let root = try? await Entity(named: "MarkerTemplate", in: plantAnchorBundle) else {
            return (nil, nil)
        }
        return (root.findEntity(named: "FlowerMarker"), root.findEntity(named: "LeafMarker"))
    }

    /// 組一個部位 callout：clone 模板（發光球+光暈+脈動）+ 長引線 + SwiftUI 標籤。
    /// `template` 為 nil 時退回程式化發光球。group.position 由選取層每幀更新。
    @MainActor
    static func makeCallout(part: PlantPart,
                            template: Entity?,
                            label: Entity?,
                            labelOffset: SIMD3<Float>) -> Entity {
        let group = Entity()
        group.name = "callout-\(part.rawValue)"
        group.isEnabled = false   // 選取層選到候選前先隱藏

        let marker: Entity
        if let template {
            let clone = template.clone(recursive: true)
            clone.position = .zero
            // 剝除模板自帶的短引線/標籤底板，改用我們自己的長引線+SwiftUI標籤（避免花葉標籤重疊）
            clone.findEntity(named: "LeaderLine")?.removeFromParent()
            clone.findEntity(named: "LabelBacking")?.removeFromParent()
            playAllAnimations(on: clone)   // 脈動 + Halo 旋轉，循環
            marker = clone
        } else {
            marker = makeMarker(radius: 0.02, color: UIColor(part.markerColor))
        }
        group.addChild(marker)

        group.addChild(makeLeader(from: .zero, to: labelOffset, color: UIColor(part.markerColor)))

        if let label {
            label.position = labelOffset
            label.components.set(BillboardComponent())
            group.addChild(label)
        }
        return group
    }

    /// 遞迴播放整個子樹上所有 USD 烘焙動畫，循環。
    @MainActor
    static func playAllAnimations(on entity: Entity) {
        for anim in entity.availableAnimations {
            entity.playAnimation(anim.repeat(), transitionDuration: 0, startsPaused: false)
        }
        for child in entity.children { playAllAnimations(on: child) }
    }
}
