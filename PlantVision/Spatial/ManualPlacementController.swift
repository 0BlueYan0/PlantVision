import ARKit
import RealityKit
import QuartzCore

/// 「手動擺放」場景的位置邏輯:用 PlaneDetection 找地板、把模型貼地放在使用者面前,
/// 並用 WorldTracking 的頭部位置每幀重選最近花/葉 callout。完全不依賴 ObjectTracking。
@MainActor
final class ManualPlacementController: ObservableObject {

    enum Phase: Equatable {
        case idle
        case needsAuthorization   // 世界感測權限被拒(改用 fallback 地板)
        case locatingFloor        // 已啟動平面偵測,尚未找到地板
        case ready                // 地板就緒(或模擬器 fallback),可操作
        case failed(String)
    }

    /// 一株植物的候選點與對應 callout 實體(刻意不引用 ObjectTrackingController 的同名型別,保持解耦)。
    struct CalloutBinding {
        let flowerPoints: [SIMD3<Float>]
        let leafPoints: [SIMD3<Float>]
        let flowerCallout: Entity
        let leafCallout: Entity
    }

    @Published private(set) var phase: Phase = .idle

    private let session = ARKitSession()
    private let worldTracking = WorldTrackingProvider()
    private let planeDetection = PlaneDetectionProvider(alignments: [.horizontal])

    private var root: Entity?
    private var binding: CalloutBinding?
    /// 模型底部相對 root 原點的 Y(由場景算 visualBounds 提供),用來讓底部剛好踩地。
    private var baseOffset: Float = 0
    /// 偵測到的地板世界 Y;nil = 尚未取得,用 fallback。
    private var floorHeight: Float?
    /// 已鎖定 .floor 分類的平面後,只有 .floor 平面能再更新地板高度。
    private var floorLocked = false
    private let fallbackFloor: Float = 0
    /// 起始放置時,植物離使用者前方距離(公尺)。
    private let spawnDistance: Float = 1.0

    // 最近選取狀態(帶遲滯)。
    private var selectionFlower: Int?
    private var selectionLeaf: Int?
    private let switchMargin: Float = 0.05

    /// 保留 RealityView scene-update 訂閱,避免被釋放。
    var updateSubscription: EventSubscription?

    /// View 在建好場景後注入 draggable root、callout binding、貼地偏移。
    /// 注意契約:`binding` 的 flowerCallout / leafCallout 必須是 `root` 的子節點
    /// (候選點與 callout 位置都是 root-local 座標),否則 refreshCallouts 會把標籤定位到錯的地方。
    func bind(root: Entity, binding: CalloutBinding, baseOffset: Float) {
        self.root = root
        self.binding = binding
        self.baseOffset = baseOffset
        // 立刻以目前已知(可能是 fallback)地板高度放好,確保不論 bind()/start() 誰先呼叫植物都會出現;
        // start() 取得頭部位置、setFloor() 取得真實地板後會再校正。
        placeInFront()
    }

    /// 拖曳手勢用:植物 root 應鎖定的世界 Y(地板高度扣掉貼地偏移)。
    func floorLockedY() -> Float {
        (floorHeight ?? fallbackFloor) - baseOffset
    }

    /// 啟動世界/平面追蹤並開始放置。**呼叫契約**:必須由 View 的結構化 `.task { await start() }`
    /// 驅動(View 消失時會自動取消,結束 anchorUpdates 迴圈),並在 `.onDisappear` 呼叫 `stop()`。
    /// 不要用 fire-and-forget 的 `Task {}`,否則重新進場時可能重複 run session。
    func start() async {
        let auths = WorldTrackingProvider.requiredAuthorizations + PlaneDetectionProvider.requiredAuthorizations
        let status = await session.requestAuthorization(for: auths)
        guard status.values.allSatisfy({ $0 == .allowed }) else {
            phase = .needsAuthorization
            floorHeight = fallbackFloor
            placeInFront()
            return
        }

        if PlaneDetectionProvider.isSupported {
            do {
                try await session.run([worldTracking, planeDetection])
            } catch {
                phase = .failed("啟動 ARKit session 失敗:\(error.localizedDescription)")
                floorHeight = fallbackFloor
                placeInFront()
                return
            }
            phase = .locatingFloor
            placeInFront()   // 先用 fallback 高度放,偵測到地板再校正 Y
            for await update in planeDetection.anchorUpdates {
                handlePlane(update)
            }
        } else {
            // 模擬器:無平面偵測,只跑頭部追蹤 + fallback 地板。
            try? await session.run([worldTracking])
            floorHeight = fallbackFloor
            phase = .ready
            placeInFront()
        }
    }

    func stop() {
        session.stop()
    }

    /// 重置:把植物重新放回使用者面前的地板。
    func resetPosition() {
        placeInFront()
    }

    /// 依當下頭部位置,把花/葉 callout 移到最近候選(帶遲滯)。由 SceneEvents.Update 每幀呼叫。
    func refreshCallouts() {
        guard let root, root.isEnabled, let b = binding,
              let device = worldTracking.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()) else { return }
        let h = device.originFromAnchorTransform.columns.3
        let headWorld = SIMD3<Float>(h.x, h.y, h.z)
        let m = root.transform.matrix
        func world(_ pts: [SIMD3<Float>]) -> [SIMD3<Float>] {
            pts.map { p in
                let w = m * SIMD4<Float>(p.x, p.y, p.z, 1)
                return SIMD3<Float>(w.x, w.y, w.z)
            }
        }
        let f = NearestPartSelector.select(candidatesWorld: world(b.flowerPoints),
                                           headWorld: headWorld, current: selectionFlower, switchMargin: switchMargin)
        let l = NearestPartSelector.select(candidatesWorld: world(b.leafPoints),
                                           headWorld: headWorld, current: selectionLeaf, switchMargin: switchMargin)
        selectionFlower = f
        selectionLeaf = l
        if let f { b.flowerCallout.position = b.flowerPoints[f]; b.flowerCallout.isEnabled = true }
        else { b.flowerCallout.isEnabled = false }
        if let l { b.leafCallout.position = b.leafPoints[l]; b.leafCallout.isEnabled = true }
        else { b.leafCallout.isEnabled = false }
    }

    // MARK: - Private

    private func handlePlane(_ update: AnchorUpdate<PlaneAnchor>) {
        // 已知限制:若鎖定的地板平面之後被 .removed(換房間/追蹤丟失),這裡不會解除 floorLocked,
        // 會沿用最後的地板高度。對「站在原地擺放」的使用情境可接受,暫不處理。
        guard update.event != .removed else { return }
        let anchor = update.anchor
        guard anchor.alignment == .horizontal else { return }
        let y = anchor.originFromAnchorTransform.columns.3.y
        if anchor.classification == .floor {
            floorLocked = true
            setFloor(y)                                   // 地板分類最權威
        } else if !floorLocked, floorHeight == nil || y < floorHeight! {
            setFloor(y)                                   // 尚無地板時,取目前最低的水平面當估計
        }
    }

    private func setFloor(_ y: Float) {
        floorHeight = y
        phase = .ready
        if let root { root.position.y = floorLockedY() } // 只校正高度,X/Z 維持
    }

    /// 把 root 放到使用者面前的地板:頭部水平位置 + 朝向前方 spawnDistance,Y = 地板高度 − 貼地偏移。
    private func placeInFront() {
        guard let root else { return }
        var x: Float = 0
        var z: Float = -spawnDistance
        if let device = worldTracking.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()) {
            let m = device.originFromAnchorTransform
            let pos = m.columns.3
            var fwd = SIMD3<Float>(-m.columns.2.x, 0, -m.columns.2.z)   // 頭部前方投影到水平面
            fwd = simd_length(fwd) > 1e-4 ? simd_normalize(fwd) : SIMD3<Float>(0, 0, -1)
            x = pos.x + fwd.x * spawnDistance
            z = pos.z + fwd.z * spawnDistance
        }
        root.position = SIMD3<Float>(x, floorLockedY(), z)
        root.isEnabled = true
    }
}
