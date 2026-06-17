import ARKit
import RealityKit
import SwiftUI

/// Immersive 場景的入口。實機(支援 Object Tracking)走「真實植物追蹤」;
/// 模擬器/不支援的裝置 fallback 到生長動畫示意場景,讓 app 仍可操作。
struct SpatialPlantSceneView: View {
    var body: some View {
        if ObjectTrackingProvider.isSupported {
            RealPlantTrackingView()
        } else {
            GrowthAnimationSceneView()
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

    /// 每株一張整株資訊卡(對齊 p.5),id 跨植物唯一。
    private struct InfoCardSlot: Identifiable {
        let id: String
        let plant: Plant
    }

    private var infoCardSlots: [InfoCardSlot] {
        SpatialLabelCatalog.profiles.map { profile in
            let plant = PlantDatabase.plant(id: profile.plantID) ?? PlantDatabase.primaryPlant
            return InfoCardSlot(id: "info-card-\(profile.referenceObjectID)", plant: plant)
        }
    }

    var body: some View {
        RealityView { content, attachments in
            // 每株建花/葉兩個 callout group,掛在 frameCorrection 下。
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
                        label: label,
                        labelOffset: anchor.labelOffset)
                    correction.addChild(callout)
                    switch anchor.part {
                    case .flower: flowerCallout = callout; flowerPoints = anchor.points
                    case .leaf:   leafCallout = callout;   leafPoints = anchor.points
                    }
                }

                // 整株資訊卡:掛在 correction 下、植物側邊,面向使用者(隨 root.isEnabled 連動顯示)。
                if let card = attachments.entity(for: "info-card-\(profile.referenceObjectID)") {
                    card.position = [0.45, 0.95, 0]
                    card.components.set(BillboardComponent())
                    correction.addChild(card)
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
            ForEach(infoCardSlots) { slot in
                Attachment(id: slot.id) {
                    SpatialInfoCard(plant: slot.plant)
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

// MARK: - 生長動畫示意場景(可於實機/模擬器顯示;由 Growth 分頁開啟,亦為追蹤不支援時的 fallback)

/// 程式生成的植物從發芽→長葉→開花→成熟,各階段以平滑補間(scale/opacity/position)轉場。
/// 階層只建一次,動畫由 `GrowthAnimationController` 驅動;時間軸(自動推進)由 `PlantVisionModel` 持有。
struct GrowthAnimationSceneView: View {
    @EnvironmentObject private var appModel: PlantVisionModel
    @StateObject private var controller = GrowthAnimationController()

    var body: some View {
        RealityView { content, attachments in
            let root = controller.build(initialStage: appModel.selectedStage)
            content.add(root)

            if let badge = attachments.entity(for: "growth-stage-badge") {
                badge.position = [0, 0.95, -0.82]
                badge.components.set(BillboardComponent())
                content.add(badge)
            }
        } attachments: {
            Attachment(id: "growth-stage-badge") {
                GrowthStageBadge(stage: appModel.selectedStage, isPlaying: appModel.isGrowthPlaying)
            }
        }
        // 階段變更 → 平滑轉場;重播 token → 瞬間歸零到發芽。
        .onChange(of: appModel.selectedStage) { _, stage in
            controller.animate(to: stage)
        }
        .onChange(of: appModel.growthReplayToken) { _, _ in
            controller.animate(to: .sprout, duration: 0)
        }
        // 捏合 3D 植物模型 → 播放/暫停生長動畫(維持原有捏合行為)。
        .gesture(TapGesture().targetedToAnyEntity().onEnded { _ in
            appModel.toggleGrowthPlayback()
        })
    }
}

/// 浮在生長植物上方的階段提示(目前階段名稱 + 說明 + 播放狀態)。
struct GrowthStageBadge: View {
    let stage: GrowthStage
    let isPlaying: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: isPlaying ? "play.circle.fill" : "pause.circle")
                    .font(.callout)
                    .foregroundStyle(.green)
                Text(stage.title)
                    .font(.title3.weight(.bold))
            }
            Text(stage.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(width: 240, alignment: .leading)
        .glassBackgroundEffect()
    }
}
