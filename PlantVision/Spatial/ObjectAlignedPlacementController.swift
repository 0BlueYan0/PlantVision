import ARKit
import Foundation
import RealityKit
import QuartzCore
import simd

/// 「放置虛擬模型」場景的位置邏輯:先做最多 5 秒的 ObjectTracking 抓到真實植物 pose,
/// 把虛擬模型放到真實植物「面向使用者那一側」、貼在地板上,且 yaw 朝向與真實植物一致;
/// 抓到一次就定格(capture-once)、停止追蹤,模型維持可沿地板拖曳。
///
/// 若 5 秒內沒追到(或裝置/資產不支援 ObjectTracking),就不管朝向,直接放在使用者面前的地板
/// (沿用 `ManualPlacementController` 的 `placeInFront` 行為)。
///
/// 設計上比照 `ManualPlacementController`(floor 偵測、貼地、花/葉 callout 全部相同),
/// 額外多跑一個 `ObjectTrackingProvider` 做一次性的朝向對齊。刻意不引用其他 controller 的同名型別,保持解耦。
@MainActor
final class ObjectAlignedPlacementController: ObservableObject {

    enum Phase: Equatable {
        case idle
        case aligning             // 5 秒視窗內,跑物件追蹤等待鎖定真實植物
        case placedAligned        // 已依真實植物朝向放在旁邊
        case placedFallback       // 沒追到(逾時/不支援/權限),直接放在面前(無朝向)
        case needsAuthorization
        case failed(String)
    }

    /// 一株植物的候選點與對應 callout 實體(與 ManualPlacement 同構,刻意各自宣告以保持解耦)。
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
    /// 對齊用的物件追蹤 provider;載入 reference object 後才建立(無資產則為 nil)。
    private var objectTracking: ObjectTrackingProvider?

    private var root: Entity?
    private var binding: CalloutBinding?
    /// 模型底部相對 root 原點的 Y(由場景算 visualBounds 提供),用來讓底部剛好踩地。
    private var baseOffset: Float = 0
    /// 模型水平半寬(由場景算 visualBounds 提供),用來決定「放在旁邊」要離真實植物多遠。
    private var modelHalfWidth: Float = 0.2
    /// 偵測到的地板世界 Y;nil = 尚未取得,用 fallback。
    private var floorHeight: Float?
    private var floorLocked = false
    private let fallbackFloor: Float = 0
    /// fallback 起始放置時,植物離使用者前方距離(公尺)。
    private let spawnDistance: Float = 1.0
    /// 對齊視窗:超過就放棄朝向直接擺放。
    private let alignTimeout: Duration = .seconds(5)
    /// 旁邊擺放時兩株之間額外的安全間距(公尺)。
    private let sideMargin: Float = 0.12

    /// 是否已完成擺放(對齊或 fallback),避免重複擺放、並讓物件追蹤迴圈一次性收掉。
    private var placed = false

    // 最近選取狀態(帶遲滯)。
    private var selectionFlower: Int?
    private var selectionLeaf: Int?
    private let switchMargin: Float = 0.05

    /// 保留 RealityView scene-update 訂閱,避免被釋放。
    var updateSubscription: EventSubscription?

    /// View 在建好場景後注入 draggable root、callout binding、貼地偏移與模型半寬。
    /// 對齊完成前先把 root 藏起來(只顯示狀態提示),避免「先出現在面前再瞬移到植物旁」的跳動。
    func bind(root: Entity, binding: CalloutBinding, baseOffset: Float, modelHalfWidth: Float) {
        self.root = root
        self.binding = binding
        self.baseOffset = baseOffset
        self.modelHalfWidth = modelHalfWidth
        root.isEnabled = false
    }

    /// 拖曳手勢用:植物 root 應鎖定的世界 Y(地板高度扣掉貼地偏移)。
    func floorLockedY() -> Float {
        (floorHeight ?? fallbackFloor) - baseOffset
    }

    /// 啟動追蹤與放置。**呼叫契約**:由 View 的結構化 `.task { await start() }` 驅動(View 消失時自動取消,
    /// 結束 anchorUpdates 迴圈),並在 `.onDisappear` 呼叫 `stop()`。
    func start() async {
        // 1) 決定能否做朝向對齊:裝置支援 ObjectTracking 且至少載入一個 reference object。
        var references: [ReferenceObject] = []
        if ObjectTrackingProvider.isSupported {
            for profile in SpatialLabelCatalog.profiles {
                guard let url = Bundle.main.url(forResource: profile.referenceFileName, withExtension: "referenceobject") else {
                    continue
                }
                if let reference = try? await ReferenceObject(from: url) {
                    references.append(reference)
                }
            }
        }
        let canTrack = !references.isEmpty

        // 2) 權限:聯集要跑的 provider 所需授權。
        var auths = WorldTrackingProvider.requiredAuthorizations + PlaneDetectionProvider.requiredAuthorizations
        if canTrack { auths += ObjectTrackingProvider.requiredAuthorizations }
        let status = await session.requestAuthorization(for: auths)
        guard status.values.allSatisfy({ $0 == .allowed }) else {
            phase = .needsAuthorization
            floorHeight = fallbackFloor
            placeInFront()                              // 無權限:直接放面前(fallback 地板)
            return
        }

        // 3) 組 provider 清單並啟動 session。
        let planeSupported = PlaneDetectionProvider.isSupported
        var providers: [any DataProvider] = [worldTracking]
        if planeSupported { providers.append(planeDetection) }
        if canTrack {
            let provider = ObjectTrackingProvider(referenceObjects: references)
            objectTracking = provider
            providers.append(provider)
        }
        do {
            try await session.run(providers)
        } catch {
            phase = .failed("啟動 ARKit session 失敗:\(error.localizedDescription)")
            floorHeight = fallbackFloor
            placeInFront()
            return
        }

        if !planeSupported { floorHeight = fallbackFloor }   // 模擬器:無平面偵測,用預設地板

        // 4) 有追蹤能力 → 進入對齊視窗;否則直接 fallback 面前擺放(行為同 ManualPlacement)。
        // 閉包只捕捉 self(@MainActor 類別,隱含 Sendable),provider 一律經由 self 取用,避免捕捉非 Sendable 區域變數。
        if canTrack {
            phase = .aligning
            await withTaskGroup(of: Void.self) { group in
                if planeSupported {
                    group.addTask { @MainActor in
                        for await update in self.planeDetection.anchorUpdates { self.handlePlane(update) }
                    }
                }
                group.addTask { @MainActor in
                    guard let provider = self.objectTracking else { return }
                    for await update in provider.anchorUpdates {
                        if self.placed { break }           // capture-once:擺好後就停止消費物件更新
                        self.handleObject(update)
                    }
                }
                group.addTask { @MainActor in
                    try? await Task.sleep(for: self.alignTimeout)
                    guard !self.placed else { return }     // 逾時但已對齊成功:不動作
                    self.placeInFront()
                    self.phase = .placedFallback
                }
            }
        } else {
            placeInFront()
            phase = .placedFallback
            if planeSupported {
                for await update in planeDetection.anchorUpdates { handlePlane(update) }
            }
        }
    }

    func stop() {
        session.stop()
    }

    /// 依當下頭部位置,把花/葉 callout 移到最近候選(帶遲滯)。由 SceneEvents.Update 每幀呼叫。
    func refreshCallouts() {
        guard let root, root.isEnabled, let b = binding,
              let device = worldTracking.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()) else { return }
        let h = device.originFromAnchorTransform.columns.3
        let headWorld = SIMD3<Float>(h.x, h.y, h.z)
        // 不變式:root 直接掛在場景 content 下(無被變換的父節點),故 root.transform.matrix 即 root→world。
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
        if let f { SpatialLabelBuilder.place(b.flowerCallout, at: b.flowerPoints[f]); b.flowerCallout.isEnabled = true }
        else { b.flowerCallout.isEnabled = false }
        if let l { SpatialLabelBuilder.place(b.leafCallout, at: b.leafPoints[l]); b.leafCallout.isEnabled = true }
        else { b.leafCallout.isEnabled = false }
    }

    // MARK: - Private

    /// 首次追到真實植物:算出「旁邊 + 朝向一致」的擺放並定格。
    private func handleObject(_ update: AnchorUpdate<ObjectAnchor>) {
        guard !placed, let root else { return }
        let anchor = update.anchor
        guard update.event != .removed, anchor.isTracked else { return }
        placed = true

        let t = anchor.originFromAnchorTransform
        let plant = SIMD3<Float>(t.columns.3.x, 0, t.columns.3.z)   // 真實植物水平位置

        // 與視線垂直的方向 = 「面向使用者那一側」。退化(看不到頭部/正上方)時用世界 +Z。
        var toHead = SIMD3<Float>(0, 0, 1)
        if let device = worldTracking.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()) {
            let hp = device.originFromAnchorTransform.columns.3
            let v = SIMD3<Float>(hp.x - plant.x, 0, hp.z - plant.z)
            if simd_length(v) > 1e-4 { toHead = simd_normalize(v) }
        }
        let lateral = SIMD3<Float>(toHead.z, 0, -toHead.x)          // 繞 Y 轉 90°

        // 旁邊距離:真實植物半寬 + 模型半寬 + 安全間距,確保兩株不重疊。
        let box = anchor.boundingBox
        let plantHalf = max(box.extent.x, box.extent.z) * 0.5
        let dist = plantHalf + modelHalfWidth + sideMargin

        root.position = SIMD3<Float>(plant.x + lateral.x * dist, floorLockedY(), plant.z + lateral.z * dist)

        // 朝向:只取 yaw,讓模型直立貼地且面向與真實植物一致(物件 local +Z 投影到水平)。
        var fwd = SIMD3<Float>(t.columns.2.x, 0, t.columns.2.z)
        fwd = simd_length(fwd) > 1e-4 ? simd_normalize(fwd) : SIMD3<Float>(0, 0, 1)
        root.orientation = simd_quatf(angle: atan2(fwd.x, fwd.z), axis: SIMD3<Float>(0, 1, 0))
        root.isEnabled = true

        phase = .placedAligned
    }

    private func handlePlane(_ update: AnchorUpdate<PlaneAnchor>) {
        guard update.event != .removed else { return }
        let anchor = update.anchor
        guard anchor.alignment == .horizontal else { return }
        let y = anchor.originFromAnchorTransform.columns.3.y
        if anchor.classification == .floor {
            floorLocked = true
            setFloor(y)
        } else if !floorLocked, floorHeight == nil || y < floorHeight! {
            setFloor(y)
        }
    }

    private func setFloor(_ y: Float) {
        floorHeight = y
        if let root, placed { root.position.y = floorLockedY() }   // 已擺放才校正高度,X/Z 維持
    }

    /// fallback:把 root 放到使用者面前的地板,朝向用預設(不管朝向)。
    private func placeInFront() {
        guard let root else { return }
        placed = true
        var x: Float = 0
        var z: Float = -spawnDistance
        if let device = worldTracking.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()) {
            let m = device.originFromAnchorTransform
            let pos = m.columns.3
            var fwd = SIMD3<Float>(-m.columns.2.x, 0, -m.columns.2.z)
            fwd = simd_length(fwd) > 1e-4 ? simd_normalize(fwd) : SIMD3<Float>(0, 0, -1)
            x = pos.x + fwd.x * spawnDistance
            z = pos.z + fwd.z * spawnDistance
        }
        root.orientation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
        root.position = SIMD3<Float>(x, floorLockedY(), z)
        root.isEnabled = true
    }
}
