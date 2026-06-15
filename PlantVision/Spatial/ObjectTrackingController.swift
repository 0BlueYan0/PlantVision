import ARKit
import Foundation
import RealityKit

/// 負責「位置」這一半:用 ARKit ObjectTracking 同時載入多株植物的 reference object,
/// 找到哪一株就把那株的標籤子樹 root 對齊到它的 pose(部位錨點已由 builder 依 RCP 座標擺好)。
///
/// 「身分」由當下追到的 reference object 直接決定(對應 `ReferenceObjectProfile.plantID`),
/// 不依賴 Mac relay。對齊 roadmap Phase 6:tracking 管位置、recognition 管身分。
/// 新增植物 = 丟一個 `.referenceobject` + 在 `SpatialLabelCatalog` 加一筆 profile,程式不用改。
@MainActor
final class ObjectTrackingController: ObservableObject {

    enum Phase: Equatable {
        case idle
        case unsupported          // 模擬器或不支援 ObjectTracking 的裝置
        case needsAuthorization   // 使用者拒絕世界感測
        case missingAsset         // 找不到 .referenceobject
        case searching            // 已啟動,尚未找到/暫時 lost
        case tracking             // 正在穩定追蹤
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    /// 目前追蹤到的植物 id(供標籤顯示對應文字)。
    @Published private(set) var activePlantID: String?

    private let session = ARKitSession()
    private var holdProvider: @MainActor () -> Bool = { false }

    // 每株植物各一個 root(key = referenceObjectID),由 View 在建立場景時注入。
    // 部位錨點已由 builder 依各自 RCP 座標擺好,controller 只負責驅動被追到那株的整體 pose。
    private var roots: [String: Entity] = [:]

    // 平滑狀態(per reference object)
    private var smoothed: [String: Transform] = [:]
    private var loggedBoxes: Set<String> = []
    private let smoothingAlpha: Float = 0.25

    /// View 把每株的 root 交給 controller(key = referenceObjectID)。
    func bind(roots: [String: Entity]) {
        self.roots = roots
        roots.values.forEach { $0.isEnabled = false } // 找到目標前先隱藏
    }

    /// 啟動追蹤。`holdProvider` 讓 controller 即時讀取鎖定狀態(鎖定時凍結 pose)。
    func start(holdProvider: @escaping @MainActor () -> Bool) async {
        self.holdProvider = holdProvider

        guard ObjectTrackingProvider.isSupported else {
            phase = .unsupported
            return
        }

        // 載入所有 catalog 中的 reference object,並記住每個對應的 profile。
        var loaded: [(reference: ReferenceObject, profile: ReferenceObjectProfile)] = []
        for profile in SpatialLabelCatalog.profiles {
            guard let url = Bundle.main.url(forResource: profile.referenceFileName, withExtension: "referenceobject") else {
                continue
            }
            do {
                let reference = try await ReferenceObject(from: url)
                loaded.append((reference, profile))
            } catch {
                phase = .failed("載入 \(profile.referenceFileName).referenceobject 失敗:\(error.localizedDescription)")
                return
            }
        }

        guard !loaded.isEmpty else {
            phase = .missingAsset
            return
        }

        let status = await session.requestAuthorization(for: ObjectTrackingProvider.requiredAuthorizations)
        guard status.values.allSatisfy({ $0 == .allowed }) else {
            phase = .needsAuthorization
            return
        }

        let provider = ObjectTrackingProvider(referenceObjects: loaded.map(\.reference))
        do {
            try await session.run([provider])
        } catch {
            phase = .failed("啟動 ARKit session 失敗:\(error.localizedDescription)")
            return
        }

        phase = .searching
        for await update in provider.anchorUpdates {
            handle(update, loaded: loaded)
        }
    }

    func stop() {
        session.stop()
    }

    // MARK: - Private

    private func handle(_ update: AnchorUpdate<ObjectAnchor>,
                        loaded: [(reference: ReferenceObject, profile: ReferenceObjectProfile)]) {
        let anchor = update.anchor
        // 用「當下追到的是哪個 reference object」決定身分與要驅動的那株 root。
        guard let profile = (loaded.first { $0.reference == anchor.referenceObject }?.profile) ?? loaded.first?.profile else {
            return
        }
        let root = roots[profile.referenceObjectID]

        switch update.event {
        case .added, .updated:
            if anchor.isTracked {
                activePlantID = profile.plantID
                phase = .tracking
                logBoxOnce(anchor, id: profile.referenceObjectID)
                drive(root: root, id: profile.referenceObjectID, anchor: anchor)
                root?.isEnabled = true
            } else {
                // 暫時 lost:先隱藏這株的標籤(避免漂在錯的地方)。
                root?.isEnabled = false
            }
        case .removed:
            root?.isEnabled = false
            smoothed[profile.referenceObjectID] = nil
        }

        // 沒有任何一株仍在顯示時,把狀態退回 searching。
        if !roots.values.contains(where: { $0.isEnabled }) {
            phase = .searching
        }
    }

    /// 第一次追到某株時印出追蹤框,用來核對「追蹤框」與 RCP「模型框」是否同一個座標系。
    /// 若整片標籤一致地偏移,通常是差一個常數,可在該 profile 的 `frameCorrection` 補。
    private func logBoxOnce(_ anchor: ObjectAnchor, id: String) {
        guard loggedBoxes.insert(id).inserted else { return }
        let box = anchor.boundingBox
        print("[PlantVision] \(id) boundingBox min=\(box.min) max=\(box.max) center=\(box.center) extent=\(box.extent)")
    }

    /// 把某株的 root 對齊到(平滑後的)物件 pose。鎖定時凍結,不更新位置。
    private func drive(root: Entity?, id: String, anchor: ObjectAnchor) {
        guard let root, !holdProvider() else { return }
        let target = Transform(matrix: anchor.originFromAnchorTransform)
        let next = smoothed[id].map {
            SpatialLabelBuilder.smoothed(current: $0, target: target, alpha: smoothingAlpha)
        } ?? target
        smoothed[id] = next
        root.transform = next
    }
}
