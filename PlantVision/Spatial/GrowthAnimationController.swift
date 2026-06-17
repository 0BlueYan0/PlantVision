import Foundation
import RealityKit

/// 負責生長動畫的「呈現與平滑轉場」這一半:建立一次穩定的植物階層(盆/莖/葉/花),
/// 之後每次階段變更只用 RealityKit 動畫補間 transform 與 opacity,不再整棵重建。
///
/// 時間軸(自動播放推進到下一階段)由 `PlantVisionModel` 持有;controller 只負責把
/// 「目前是哪個階段」平滑地畫出來。比照 `ObjectTrackingController` / `ManualPlacementController`
/// 的 `@StateObject` 控制器慣例。
@MainActor
final class GrowthAnimationController: ObservableObject {

    // 造型常數(沿用原 PlantEntityFactory 的比例)。
    private let maxStemHeight: Float = 0.62
    private let maxLeafCount = 8

    // 穩定階層:建一次後只改 transform / opacity。
    private var root: Entity?
    private var stemPivot: Entity?          // 縮放 y 讓莖由底部往上長(底部固定踩在盆口)
    private var leafGroup: Entity?          // 整體隨生長抬升/放大
    private var leaves: [ModelEntity] = []  // 預建滿數量,靠 opacity 呈現多寡
    private var flower: ModelEntity?

    /// 建立一次性穩定階層,回傳場景 root。之後請呼叫 `animate(to:)` 驅動。
    func build(initialStage: GrowthStage = .sprout) -> Entity {
        let root = Entity()
        root.name = "PlantVisionGrowthRoot"
        root.position = [0, 0, -1.0]

        root.addChild(makePot())
        root.addChild(makeFloor())

        // 莖:pivot 在盆口,box 子節點下緣對齊 pivot,縮放 pivot.y 即由底部向上長。
        let stemPivot = Entity()
        stemPivot.name = "stem-pivot"
        let stemModel = ModelEntity(
            mesh: .generateBox(size: [0.035, maxStemHeight, 0.035]),
            materials: [SimpleMaterial(color: .init(red: 0.16, green: 0.52, blue: 0.21, alpha: 1), roughness: 0.55, isMetallic: false)]
        )
        stemModel.position = [0, maxStemHeight / 2, 0]
        stemPivot.addChild(stemModel)
        root.addChild(stemPivot)
        self.stemPivot = stemPivot

        // 葉:預建滿 maxLeafCount 片,左右交錯沿莖排列;以 opacity 控制「長出幾片」。
        let leafGroup = Entity()
        leafGroup.name = "leaf-group"
        for index in 0..<maxLeafCount {
            let side: Float = index.isMultiple(of: 2) ? -1 : 1
            let height = Float(index) * 0.055 + 0.14
            let size = Float(0.13)
            let leaf = ModelEntity(
                mesh: .generateSphere(radius: size),
                materials: [SimpleMaterial(color: .init(red: 0.08, green: 0.48, blue: 0.18, alpha: 1), roughness: 0.62, isMetallic: false)]
            )
            leaf.scale = [1.5, 0.22, 0.72]
            leaf.position = [side * (0.08 + Float(index) * 0.012), height, 0]
            leaf.orientation = simd_quatf(angle: side * .pi / 7, axis: [0, 0, 1])
            leaf.components.set(OpacityComponent(opacity: 0))
            leafGroup.addChild(leaf)
            leaves.append(leaf)
        }
        root.addChild(leafGroup)
        self.leafGroup = leafGroup

        // 花:固定在莖頂,以 opacity 淡入(只在開花/成熟出現)。
        let flower = ModelEntity(
            mesh: .generateSphere(radius: 0.065),
            materials: [SimpleMaterial(color: .init(red: 1, green: 0.86, blue: 0.22, alpha: 1), roughness: 0.45, isMetallic: false)]
        )
        flower.position = [0, 0.58, 0]
        flower.components.set(OpacityComponent(opacity: 0))
        root.addChild(flower)
        self.flower = flower

        self.root = root

        // 初始狀態瞬間套用(duration 0),避免從預設值跳動。
        apply(stage: initialStage, duration: 0)
        return root
    }

    /// 平滑轉場到指定階段。`duration == 0` 代表瞬間套用(用於重播歸零或初始化)。
    func animate(to stage: GrowthStage, duration: TimeInterval = 0.8) {
        apply(stage: stage, duration: duration)
    }

    // MARK: - Private

    private func apply(stage: GrowthStage, duration: TimeInterval) {
        let p = Float(stage.progress)

        // 莖:由 ~0.32 長到 1.0(縮放 pivot.y,底部固定)。
        if let stemPivot {
            var t = stemPivot.transform
            t.scale = [1, 0.25 + 0.75 * p, 1]
            move(stemPivot, to: t, duration: duration)
        }

        // 葉群:整體隨生長抬升並略放大。
        if let leafGroup {
            var t = leafGroup.transform
            t.scale = SIMD3<Float>(repeating: 0.45 + 0.55 * p)
            t.translation = [0, 0.02 * p, 0]
            move(leafGroup, to: t, duration: duration)
        }

        // 葉片數量:用 opacity 淡入,前 visibleCount 片可見。
        let visibleCount = max(1, Int((stage.progress * Double(maxLeafCount)).rounded()))
        for (index, leaf) in leaves.enumerated() {
            setOpacity(leaf, to: index < visibleCount ? 1 : 0, duration: duration)
        }

        // 花:開花/成熟才淡入。
        let flowerOpacity: Float = (stage == .flowering || stage == .mature) ? 1 : 0
        if let flower {
            setOpacity(flower, to: flowerOpacity, duration: duration)
        }
    }

    private func move(_ entity: Entity, to transform: Transform, duration: TimeInterval) {
        if duration <= 0 {
            entity.transform = transform
        } else {
            entity.move(to: transform, relativeTo: entity.parent, duration: duration, timingFunction: .easeInOut)
        }
    }

    /// 淡入/淡出 entity 的 hierarchy opacity。duration 0 直接設定;否則用 .opacity 綁定動畫。
    private func setOpacity(_ entity: Entity, to target: Float, duration: TimeInterval) {
        let from = entity.components[OpacityComponent.self]?.opacity ?? 1
        if duration <= 0 || abs(from - target) < 0.001 {
            entity.components.set(OpacityComponent(opacity: target))
            return
        }
        let fade = FromToByAnimation<Float>(
            name: "fade",
            from: from,
            to: target,
            duration: duration,
            timing: .easeInOut,
            bindTarget: .opacity
        )
        if let resource = try? AnimationResource.generate(with: fade) {
            entity.components.set(OpacityComponent(opacity: target))
            entity.playAnimation(resource)
        } else {
            entity.components.set(OpacityComponent(opacity: target))
        }
    }

    private func makePot() -> Entity {
        let pot = ModelEntity(
            mesh: .generateBox(size: [0.28, 0.2, 0.22]),
            materials: [SimpleMaterial(color: .init(red: 0.58, green: 0.42, blue: 0.28, alpha: 1), roughness: 0.7, isMetallic: false)]
        )
        pot.position = [0, -0.08, 0]
        return pot
    }

    private func makeFloor() -> Entity {
        let floor = ModelEntity(
            mesh: .generateBox(size: [0.62, 0.012, 0.42]),
            materials: [SimpleMaterial(color: .init(white: 0.9, alpha: 0.32), roughness: 0.8, isMetallic: false)]
        )
        floor.position = [0, -0.18, 0]
        return floor
    }
}
