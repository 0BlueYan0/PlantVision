import ARKit
import RealityKit
import SwiftUI
import PlantAnchor

/// 「手動擺放」immersive 場景:載入植物 USDZ、貼地放在面前、可沿地板拖曳,
/// 花/葉空間標籤用頭部位置動態指向最近的一個。不需物件追蹤。
struct ManualPlacementSceneView: View {
    @EnvironmentObject private var appModel: PlantVisionModel
    @StateObject private var controller = ManualPlacementController()

    private struct LabelSlot: Identifiable {
        let id: String
        let part: PlantPart
        let plant: Plant
    }

    private var profile: ReferenceObjectProfile? { SpatialLabelCatalog.profiles.first }

    private var plant: Plant {
        guard let id = profile?.plantID, let p = PlantDatabase.plant(id: id) else {
            return PlantDatabase.primaryPlant
        }
        return p
    }

    private var labelSlots: [LabelSlot] {
        (profile?.parts ?? []).map { anchor in
            LabelSlot(id: "place-label-\(anchor.part.rawValue)", part: anchor.part, plant: plant)
        }
    }

    var body: some View {
        RealityView { content, attachments in
            let root = Entity()
            root.name = "placement-root"

            // 載入植物模型,加為 root 子節點,並算出底部偏移(讓底部踩地)。
            // TODO: 模型檔名目前硬編碼,與 catalog 的單一 profile 隱性耦合;
            // 若日後 catalog 換成別的植物,應改由 profile 提供模型資產名(新增欄位),讓模型與花/葉錨點一致。
            var baseOffset: Float = 0
            if let model = try? await Entity(named: "馬纓丹", in: plantAnchorBundle) {
                root.addChild(model)
                baseOffset = model.visualBounds(relativeTo: root).min.y
            }

            var flowerCallout: Entity?
            var leafCallout: Entity?
            var flowerPoints: [SIMD3<Float>] = []
            var leafPoints: [SIMD3<Float>] = []

            for anchor in profile?.parts ?? [] {
                let label = attachments.entity(for: "place-label-\(anchor.part.rawValue)")
                let callout = SpatialLabelBuilder.makeCallout(
                    part: anchor.part,
                    label: label,
                    labelOffset: anchor.labelOffset)
                root.addChild(callout)
                switch anchor.part {
                case .flower: flowerCallout = callout; flowerPoints = anchor.points
                case .leaf:   leafCallout = callout;   leafPoints = anchor.points
                }
            }

            // 整株資訊卡:植物側邊,面向使用者(對齊 p.5)。
            if let card = attachments.entity(for: "place-info-card") {
                card.position = [0.5, 1.0, 0]
                card.components.set(BillboardComponent())
                root.addChild(card)
            }

            // 讓 root 可被拖曳:加碰撞形狀 + 輸入目標。
            // visualBounds(relativeTo: root) 以 root-local 空間計算,只依賴已加入的子節點,
            // 不需要 root 先進入場景,因此在 content.add(root) 之前算是安全的。
            let bounds = root.visualBounds(relativeTo: root)
            let shape = ShapeResource.generateBox(size: bounds.extents).offsetBy(translation: bounds.center)
            root.components.set(CollisionComponent(shapes: [shape]))
            root.components.set(InputTargetComponent())

            content.add(root)

            if let f = flowerCallout, let l = leafCallout {
                controller.bind(
                    root: root,
                    binding: .init(flowerPoints: flowerPoints, leafPoints: leafPoints,
                                   flowerCallout: f, leafCallout: l),
                    baseOffset: baseOffset)
            } else {
                // profile 必須同時含 flower 與 leaf 部位;否則 bind 不會發生、植物不會被放置/可拖曳。
                // 目前 catalog 固定兩者皆有;此斷言只在 debug 觸發,提醒未來改 catalog 的人。
                assertionFailure("ManualPlacement: profile 缺少 flower 或 leaf 部位,callout 無法綁定")
            }

            controller.updateSubscription = content.subscribe(to: SceneEvents.Update.self) { _ in
                controller.refreshCallouts()
            }

            if let status = attachments.entity(for: "placement-status") {
                status.name = "placement-status"
                status.position = [0, 1.4, -1.2]
                content.add(status)
            }
        } update: { content, _ in
            // 就緒後把狀態提示收起來。
            if let status = content.entities.first(where: { $0.name == "placement-status" }) {
                status.isEnabled = (controller.phase != .ready)
            }
        } attachments: {
            ForEach(labelSlots) { slot in
                Attachment(id: slot.id) {
                    SpatialPartLabel(part: slot.part, plant: slot.plant)
                }
            }
            Attachment(id: "place-info-card") {
                SpatialInfoCard(plant: plant)
            }
            Attachment(id: "placement-status") {
                ManualPlacementStatusLabel(phase: controller.phase)
            }
        }
        // 沿地板拖曳:把拖曳點轉到場景座標,只取水平 X/Z,Y 永遠鎖在地面。
        .gesture(
            DragGesture()
                .targetedToAnyEntity()
                .onChanged { value in
                    guard value.entity.name == "placement-root" else { return }
                    let p = value.convert(value.location3D, from: .local, to: .scene)
                    value.entity.position = [p.x, controller.floorLockedY(), p.z]
                }
        )
        .task { await controller.start() }
        .onDisappear { controller.stop() }
        .onChange(of: appModel.placementResetToken) { _, _ in
            controller.resetPosition()
        }
    }
}

/// 擺放場景的狀態提示,固定浮在使用者前方。
struct ManualPlacementStatusLabel: View {
    let phase: ManualPlacementController.Phase

    private var text: String {
        switch phase {
        case .idle: "準備中…"
        case .needsAuthorization: "需要「世界感測」權限才能偵測地板,目前用預設地板高度。可到設定開啟。"
        case .locatingFloor: "正在尋找地板…請看向地面一兩秒。"
        case .ready: "已就緒。捏住植物可沿地板拖曳移動。"
        case .failed(let reason): "啟動失敗:\(reason)"
        }
    }

    var body: some View {
        Text(text)
            .font(.callout)
            .multilineTextAlignment(.center)
            .padding(16)
            .frame(maxWidth: 360)
            .glassBackgroundEffect()
    }
}
