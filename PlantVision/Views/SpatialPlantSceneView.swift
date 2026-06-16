import ARKit
import RealityKit
import SwiftUI

/// Immersive 場景的入口。實機(支援 Object Tracking)走「真實植物追蹤」;
/// 模擬器/不支援的裝置 fallback 到原本的合成植物示意場景,讓 app 仍可操作。
struct SpatialPlantSceneView: View {
    var body: some View {
        if ObjectTrackingProvider.isSupported {
            RealPlantTrackingView()
        } else {
            SyntheticPlantSceneView()
        }
    }
}

// MARK: - 真實植物追蹤(部位級空間標籤)

/// 用 ObjectTracking 對齊真實盆栽,並把花/葉標籤錨在對應部位。需實機 Vision Pro。
struct RealPlantTrackingView: View {
    @EnvironmentObject private var appModel: PlantVisionModel
    @StateObject private var controller = ObjectTrackingController()

    /// 攤平成「每株 × 每部位」一個標籤格,給 attachments 用。id 跨植物唯一。
    private struct LabelSlot: Identifiable {
        let id: String
        let part: PlantPart
        let plant: Plant
    }

    private var labelSlots: [LabelSlot] {
        SpatialLabelCatalog.profiles.flatMap { profile -> [LabelSlot] in
            let plant = PlantDatabase.plant(id: profile.plantID) ?? PlantDatabase.primaryPlant
            return profile.parts.map { anchor in
                LabelSlot(id: "label-\(profile.referenceObjectID)-\(anchor.part.rawValue)", part: anchor.part, plant: plant)
            }
        }
    }

    var body: some View {
        RealityView { content, attachments in
            // 載入 marker 模板(一次);每株建花/葉兩個 callout group,掛在 frameCorrection 下。
            let templates = await SpatialLabelBuilder.loadMarkerTemplates()
            var roots: [String: Entity] = [:]
            var bindings: [String: ObjectTrackingController.PlantCalloutBinding] = [:]

            for profile in SpatialLabelCatalog.profiles {
                let root = Entity()
                root.name = "tracked-\(profile.referenceObjectID)"

                let correction = Entity()
                correction.position = profile.frameCorrection
                root.addChild(correction)

                var flowerCallout: Entity?
                var leafCallout: Entity?
                var flowerPoints: [SIMD3<Float>] = []
                var leafPoints: [SIMD3<Float>] = []

                for anchor in profile.parts {
                    let label = attachments.entity(for: "label-\(profile.referenceObjectID)-\(anchor.part.rawValue)")
                    let callout = SpatialLabelBuilder.makeCallout(
                        part: anchor.part,
                        template: anchor.part == .flower ? templates.flower : templates.leaf,
                        label: label,
                        labelOffset: anchor.labelOffset)
                    correction.addChild(callout)
                    switch anchor.part {
                    case .flower: flowerCallout = callout; flowerPoints = anchor.points
                    case .leaf:   leafCallout = callout;   leafPoints = anchor.points
                    }
                }

                content.add(root)
                roots[profile.referenceObjectID] = root
                if let f = flowerCallout, let l = leafCallout {
                    bindings[profile.referenceObjectID] = .init(
                        flowerPoints: flowerPoints, leafPoints: leafPoints,
                        flowerCallout: f, leafCallout: l)
                }
            }
            controller.bind(roots: roots)
            controller.bindCallouts(bindings)

            // 每幀依頭部位置重選最近花/葉 callout。
            controller.updateSubscription = content.subscribe(to: SceneEvents.Update.self) { _ in
                controller.refreshCallouts()
            }

            if let status = attachments.entity(for: "tracking-status") {
                status.name = "tracking-status"
                status.position = [0, 1.4, -1.2]
                content.add(status)
            }
        } update: { content, _ in
            // 追蹤穩定後就把狀態提示收起來。
            if let status = content.entities.first(where: { $0.name == "tracking-status" }) {
                status.isEnabled = (controller.phase != .tracking)
            }
        } attachments: {
            ForEach(labelSlots) { slot in
                Attachment(id: slot.id) {
                    SpatialPartLabel(part: slot.part, plant: slot.plant)
                }
            }
            Attachment(id: "tracking-status") {
                SpatialTrackingStatusLabel(phase: controller.phase)
            }
        }
        .task {
            await controller.start(holdProvider: { appModel.isHolding })
        }
        .onDisappear {
            controller.stop()
        }
    }
}

// MARK: - 合成植物示意場景(fallback / 模擬器)

struct SyntheticPlantSceneView: View {
    @EnvironmentObject private var appModel: PlantVisionModel

    var body: some View {
        RealityView { content, attachments in
            let root = PlantEntityFactory.makeScene(stage: appModel.selectedStage)
            content.add(root)

            if let label = attachments.entity(for: "plant-label") {
                label.position = [0.34, 0.54, 0]
                content.add(label)
            }
        } update: { content, attachments in
            content.entities.removeAll()
            let root = PlantEntityFactory.makeScene(stage: appModel.selectedStage)
            content.add(root)

            if let label = attachments.entity(for: "plant-label") {
                label.position = [0.34, 0.54, 0]
                content.add(label)
            }
        } attachments: {
            Attachment(id: "plant-label") {
                SpatialPlantLabel(
                    result: appModel.currentResult,
                    isHolding: appModel.isHolding,
                    onToggleHold: { appModel.toggleHold() }
                )
            }
        }
        // 捏合 3D 植物模型 → 播放/暫停生長動畫(維持原有行為)。捏合資訊標籤 → 鎖定/解鎖(見 SpatialPlantLabel)。
        .gesture(TapGesture().targetedToAnyEntity().onEnded { _ in
            appModel.toggleGrowthPlayback()
        })
    }
}

struct SpatialPlantLabel: View {
    let result: RecognitionResult?
    var isHolding: Bool = false
    var onToggleHold: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let result {
                HStack(spacing: 8) {
                    Text(result.plant.chineseName)
                        .font(.title3.weight(.bold))
                    if isHolding {
                        Image(systemName: "lock.fill")
                            .font(.callout)
                            .foregroundStyle(.orange)
                            .accessibilityLabel("已鎖定")
                    }
                }
                Text(result.plant.scientificName)
                    .font(.callout)
                    .italic()
                Text("信心 \(Int(result.confidence * 100))% · \(result.source.rawValue)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(isHolding ? "已鎖定，捏合解鎖" : "捏合鎖定，看資訊時不消失")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("PlantVision")
                    .font(.title3.weight(.bold))
                Text("先執行 Scan 取得植物資訊")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(width: 260, alignment: .leading)
        .glassBackgroundEffect()
        .contentShape(Rectangle())
        .onTapGesture { onToggleHold() }
    }
}

enum PlantEntityFactory {
    @MainActor
    static func makeScene(stage: GrowthStage) -> Entity {
        let root = Entity()
        root.name = "PlantVisionSpatialRoot"
        root.position = [0, 0, -1.0]

        root.addChild(makePot())
        root.addChild(makeStem(height: Float(0.2 + 0.42 * stage.progress)))
        root.addChild(makeLeaves(stage: stage))

        if stage == .flowering || stage == .mature {
            root.addChild(makeFlower())
        }

        let floor = ModelEntity(
            mesh: .generateBox(size: [0.62, 0.012, 0.42]),
            materials: [SimpleMaterial(color: .init(white: 0.9, alpha: 0.32), roughness: 0.8, isMetallic: false)]
        )
        floor.position = [0, -0.18, 0]
        root.addChild(floor)

        return root
    }

    @MainActor
    private static func makePot() -> Entity {
        let pot = ModelEntity(
            mesh: .generateBox(size: [0.28, 0.2, 0.22]),
            materials: [SimpleMaterial(color: .init(red: 0.58, green: 0.42, blue: 0.28, alpha: 1), roughness: 0.7, isMetallic: false)]
        )
        pot.position = [0, -0.08, 0]
        return pot
    }

    @MainActor
    private static func makeStem(height: Float) -> Entity {
        let stem = ModelEntity(
            mesh: .generateBox(size: [0.035, height, 0.035]),
            materials: [SimpleMaterial(color: .init(red: 0.16, green: 0.52, blue: 0.21, alpha: 1), roughness: 0.55, isMetallic: false)]
        )
        stem.position = [0, height / 2, 0]
        return stem
    }

    @MainActor
    private static func makeLeaves(stage: GrowthStage) -> Entity {
        let group = Entity()
        let count = max(2, Int(round(stage.progress * 7)))
        for index in 0..<count {
            let side: Float = index.isMultiple(of: 2) ? -1 : 1
            let height = Float(index) * 0.055 + 0.14
            let size = Float(0.08 + stage.progress * 0.09)
            let leaf = ModelEntity(
                mesh: .generateSphere(radius: size),
                materials: [SimpleMaterial(color: .init(red: 0.08, green: 0.48, blue: 0.18, alpha: 1), roughness: 0.62, isMetallic: false)]
            )
            leaf.scale = [1.5, 0.22, 0.72]
            leaf.position = [side * (0.08 + Float(index) * 0.012), height, 0]
            leaf.orientation = simd_quatf(angle: side * .pi / 7, axis: [0, 0, 1])
            group.addChild(leaf)
        }
        return group
    }

    @MainActor
    private static func makeFlower() -> Entity {
        let flower = ModelEntity(
            mesh: .generateSphere(radius: 0.065),
            materials: [SimpleMaterial(color: .init(red: 1, green: 0.86, blue: 0.22, alpha: 1), roughness: 0.45, isMetallic: false)]
        )
        flower.position = [0, 0.58, 0]
        return flower
    }
}
