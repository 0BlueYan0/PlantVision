import RealityKit
import SwiftUI

struct SpatialPlantSceneView: View {
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
