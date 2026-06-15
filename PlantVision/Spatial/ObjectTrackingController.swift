import ARKit
import Foundation
import RealityKit

/// 負責「位置」這一半:用 ARKit ObjectTracking 找到真實植物,把標籤子樹的 root
/// 對齊到它的 pose,並依 bounding box 把花/葉錨點放到對的 local 位置。
///
/// 「身分」由被追蹤的 reference object 直接決定(對應 `ReferenceObjectProfile.plantID`),
/// 不依賴 Mac relay。對齊 roadmap Phase 6:tracking 管位置、recognition 管身分。
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

    // 由 View 在建立場景時注入的實體
    private weak var trackedRoot: Entity?
    private var partGroups: [PlantPart: Entity] = [:]

    // 狀態
    private var smoothedTransform: Transform?
    private var didLayoutParts = false
    private let smoothingAlpha: Float = 0.25

    /// View 把要驅動的 root 與各部位 group 交給 controller。
    func bind(trackedRoot: Entity, partGroups: [PlantPart: Entity]) {
        self.trackedRoot = trackedRoot
        self.partGroups = partGroups
        trackedRoot.isEnabled = false // 找到目標前先隱藏
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
        let profile = loaded.first { $0.reference == anchor.referenceObject }?.profile ?? loaded.first?.profile
        activePlantID = profile?.plantID

        switch update.event {
        case .added, .updated:
            if anchor.isTracked {
                phase = .tracking
                layoutPartsIfNeeded(anchor: anchor, profile: profile)
                drive(anchor: anchor)
                trackedRoot?.isEnabled = true
            } else {
                // 暫時 lost:保留最後位置,先隱藏標籤(避免漂在錯的地方)。
                phase = .searching
                trackedRoot?.isEnabled = false
            }
        case .removed:
            phase = .searching
            trackedRoot?.isEnabled = false
        }
    }

    /// 第一次穩定追蹤到時,依 bounding box 把各部位 group 放到對的 local 位置(只做一次)。
    private func layoutPartsIfNeeded(anchor: ObjectAnchor, profile: ReferenceObjectProfile?) {
        guard !didLayoutParts, let profile else { return }
        let box = anchor.boundingBox
        for part in profile.parts {
            guard let group = partGroups[part.part] else { continue }
            group.position = SpatialLabelBuilder.localPoint(
                boundingBoxMin: box.min,
                extent: box.extent,
                normalized: part.normalizedPosition
            )
        }
        didLayoutParts = true
    }

    /// 把 root 對齊到(平滑後的)物件 pose。鎖定時凍結,不更新位置。
    private func drive(anchor: ObjectAnchor) {
        guard !holdProvider() else { return }
        let target = Transform(matrix: anchor.originFromAnchorTransform)
        let next: Transform
        if let current = smoothedTransform {
            next = SpatialLabelBuilder.smoothed(current: current, target: target, alpha: smoothingAlpha)
        } else {
            next = target
        }
        smoothedTransform = next
        trackedRoot?.transform = next
    }
}
