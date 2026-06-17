import ARKit
import RealityKit
import SwiftUI
import PlantAnchor

/// 「放置虛擬模型」immersive 場景:載入植物 USDZ,先做短暫物件追蹤對齊真實植物朝向,
/// 把模型放到真實植物旁邊、貼地;5 秒沒追到就直接放在面前。對齊後可沿地板拖曳。
/// 結構比照 `ManualPlacementSceneView`,差別在改用 `ObjectAlignedPlacementController` 並多傳模型半寬。
struct ObjectAlignedPlacementSceneView: View {
    @EnvironmentObject private var appModel: PlantVisionModel
    @StateObject private var controller = ObjectAlignedPlacementController()
    /// 拖曳起手時記住「觸點 → 模型原點」的水平位移:讓捏取當下不瞬移、拖曳期間維持相對抓點。
    @State private var dragGrabOffset: SIMD3<Float>?

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
            LabelSlot(id: "aligned-label-\(anchor.part.rawValue)", part: anchor.part, plant: plant)
        }
    }

    var body: some View {
        RealityView { content, attachments in
            let root = Entity()
            root.name = "aligned-placement-root"

            // 載入植物模型,加為 root 子節點,並算出底部偏移(讓底部踩地)與水平半寬(決定旁邊距離)。
            // TODO: 模型檔名硬編碼,與 catalog 單一 profile 隱性耦合;日後換植物應由 profile 提供模型資產名。
            var baseOffset: Float = 0
            var modelHalfWidth: Float = 0.2
            if let model = try? await Entity(named: "馬纓丹", in: plantAnchorBundle) {
                root.addChild(model)
                let bounds = model.visualBounds(relativeTo: root)
                baseOffset = bounds.min.y
                modelHalfWidth = max(bounds.extents.x, bounds.extents.z) * 0.5
            }

            var flowerCallout: Entity?
            var leafCallout: Entity?
            var flowerPoints: [SIMD3<Float>] = []
            var leafPoints: [SIMD3<Float>] = []

            for anchor in profile?.parts ?? [] {
                let label = attachments.entity(for: "aligned-label-\(anchor.part.rawValue)")
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

            // 讓 root 可被拖曳:加碰撞形狀 + 輸入目標。visualBounds 以 root-local 計算,進場景前算是安全的。
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
                    baseOffset: baseOffset,
                    modelHalfWidth: modelHalfWidth)
            } else {
                assertionFailure("ObjectAlignedPlacement: profile 缺少 flower 或 leaf 部位,callout 無法綁定")
            }

            controller.updateSubscription = content.subscribe(to: SceneEvents.Update.self) { _ in
                controller.refreshCallouts()
            }

            if let status = attachments.entity(for: "aligned-status") {
                status.name = "aligned-status"
                status.position = [0, 1.4, -1.2]
                content.add(status)
            }
        } update: { content, _ in
            // 擺放完成(對齊或 fallback)後把狀態提示收起來。
            if let status = content.entities.first(where: { $0.name == "aligned-status" }) {
                switch controller.phase {
                case .placedAligned, .placedFallback: status.isEnabled = false
                default: status.isEnabled = true
                }
            }
        } attachments: {
            ForEach(labelSlots) { slot in
                Attachment(id: slot.id) {
                    SpatialPartLabel(part: slot.part, plant: slot.plant)
                }
            }
            Attachment(id: "aligned-status") {
                ObjectAlignedPlacementStatusLabel(phase: controller.phase)
            }
        }
        // 沿地板拖曳:把拖曳點轉到場景座標,只取水平 X/Z,Y 永遠鎖在地面;捏取當下記住相對抓點避免瞬移。
        .gesture(
            DragGesture()
                .targetedToAnyEntity()
                .onChanged { value in
                    guard value.entity.name == "aligned-placement-root" else { return }
                    let p = value.convert(value.location3D, from: .local, to: .scene)
                    if dragGrabOffset == nil {
                        dragGrabOffset = SIMD3<Float>(value.entity.position.x - p.x, 0, value.entity.position.z - p.z)
                    }
                    let offset = dragGrabOffset ?? .zero
                    value.entity.position = [p.x + offset.x, controller.floorLockedY(), p.z + offset.z]
                }
                .onEnded { _ in dragGrabOffset = nil }
        )
        .task { await controller.start() }
        .onDisappear { controller.stop() }
    }
}

/// 對齊擺放場景的狀態提示,固定浮在使用者前方。
struct ObjectAlignedPlacementStatusLabel: View {
    let phase: ObjectAlignedPlacementController.Phase

    private var text: String {
        switch phase {
        case .idle: "準備中…"
        case .aligning: "正在確認植物朝向…請看向真實植物一兩秒。"
        case .placedAligned: "已依真實植物朝向放在旁邊。捏住植物可沿地板拖曳移動。"
        case .placedFallback: "未在 5 秒內偵測到植物,已直接放在你面前的地板。捏住可拖曳。"
        case .needsAuthorization: "需要「世界感測」權限才能對齊與偵測地板,目前用預設地板高度。可到設定開啟。"
        case .failed(let reason): "啟動失敗:\(reason)"
        }
    }

    var body: some View {
        Text(text)
            .font(.callout)
            .multilineTextAlignment(.center)
            .padding(16)
            .frame(maxWidth: 360)
            .glassPanel(cornerRadius: Theme.cardCorner)
    }
}
