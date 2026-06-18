import Foundation

@MainActor
final class PlantVisionModel: ObservableObject {
    static let immersiveSpaceID = "PlantVisionImmersiveSpace"
    static let placementImmersiveSpaceID = "PlantVisionPlacementImmersiveSpace"
    static let growthImmersiveSpaceID = "PlantVisionGrowthImmersiveSpace"
    static let plantDetailWindowID = "PlantVisionPlantDetailWindow"

    @Published var recognitionState: RecognitionProviderState = .idle
    @Published var currentResult: RecognitionResult?
    /// 鎖定後完全凍結目前顯示:即使收到 background 或不同植物也不更動,讓使用者能安心看資訊卡 / App 視窗。
    @Published private(set) var isHolding: Bool = false
    @Published var selectedStage: GrowthStage = .sprout
    @Published var isGrowthPlaying = false
    /// 「重播」訊號:遞增即要求生長動畫場景瞬間歸零到發芽後重新播放(比照 placementResetToken 慣例)。
    @Published private(set) var growthReplayToken: Int = 0
    /// 空間資訊卡「觀看生長動畫」訊號:遞增即要求主視窗層切換到生長動畫 immersive space。
    @Published private(set) var growthModeRequestToken: Int = 0
    /// 「擺放」面板 → 場景的重置訊號;遞增即要求把植物拉回使用者面前的地板。
    @Published private(set) var placementResetToken: Int = 0
    @Published var relayURLText: String {
        didSet { relaySettingsStore.relayURL = relayURLText }
    }
    @Published var relayPairingCode: String {
        didSet { relaySettingsStore.pairingCode = relayPairingCode }
    }
    @Published var relayStatus: RelayClientStatus = .disconnected
    @Published private(set) var history: [PlantHistoryRecord] = []
    /// 最新的綜合植物健康（枯萎＋黃化＋趨勢，來自 Mac relay，與植物辨識獨立）。
    /// nil 代表本幀沒有任何健康訊號,2D 視窗即不顯示。
    @Published private(set) var plantHealth: PlantHealthStatus?

    private let demoProvider = DemoRecognitionProvider()
    private let relayClient = SocketIORelayClient()
    private let historyStore = HistoryStore()
    private let relaySettingsStore: RelaySettingsStore
    private var playbackTask: Task<Void, Never>?

    init(relaySettingsStore: RelaySettingsStore = RelaySettingsStore()) {
        self.relaySettingsStore = relaySettingsStore
        relayURLText = relaySettingsStore.relayURL
        relayPairingCode = relaySettingsStore.pairingCode
        history = historyStore.load()
        relayClient.onStatusChange = { [weak self] status in
            Task { @MainActor in
                self?.handleRelayStatus(status)
            }
        }
        relayClient.onFramePayload = { [weak self] payload in
            Task { @MainActor in
                self?.handleRelayFramePayload(payload)
            }
        }
    }

    func runDemoRecognition() async {
        let attempt = await demoProvider.recognize()
        if case .recognized(let result, let state) = attempt {
            apply(result: result, state: state)
        }
    }

    func connectRelay() {
        guard let url = URL(string: relayURLText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            relayStatus = .failed("Relay URL 無效")
            recognitionState = .failed("Relay URL 無效")
            return
        }

        do {
            try relayClient.connect(relayURL: url, pairingCode: relayPairingCode)
        } catch {
            relayStatus = .failed(error.localizedDescription)
            recognitionState = .failed(error.localizedDescription)
        }
    }

    func disconnectRelay() {
        relayClient.disconnect()
    }

    func addCurrentResultToHistory() {
        guard let result = currentResult else { return }
        addToHistory(plant: result.plant, confidence: result.confidence, source: result.source)
    }

    /// 直接把某株植物寫進歷史(供空間資訊卡使用:身分來自追蹤到的 reference object,
    /// 不一定有 relay 的 currentResult)。
    func addToHistory(plant: Plant, confidence: Double, source: RecognitionSource) {
        let record = PlantHistoryRecord(
            id: UUID(),
            plantID: plant.id,
            chineseName: plant.chineseName,
            scientificName: plant.scientificName,
            confidence: confidence,
            source: source.rawValue,
            createdAt: Date()
        )
        history.insert(record, at: 0)
        historyStore.save(history)
    }

    func clearHistory() {
        history.removeAll()
        historyStore.save(history)
    }

    /// 捏合手勢切換鎖定:鎖定時暫停自動切換與背景判定,維持目前資訊卡;解鎖後恢復即時辨識。
    func toggleHold() {
        isHolding.toggle()
        if isHolding {
            if let name = currentResult?.plant.chineseName {
                recognitionState = .relayResult("🔒 已鎖定「\(name)」，暫停自動切換。再捏合一次可解鎖。")
            } else {
                recognitionState = .relayResult("🔒 已鎖定，暫停自動切換。再捏合一次可解鎖。")
            }
        } else {
            recognitionState = .relayResult("🔓 已解鎖，恢復即時辨識與自動切換。")
        }
    }

    /// 「擺放」分頁按「拉回面前」時呼叫;場景以 onChange 觀察 token 變化後重新放置。
    func requestPlacementReset() {
        placementResetToken += 1
    }

    func toggleGrowthPlayback() {
        isGrowthPlaying.toggle()
        if isGrowthPlaying {
            startGrowthPlayback()
        } else {
            playbackTask?.cancel()
        }
    }

    /// 「切換」:跳到指定階段並停止自動播放(場景會平滑轉場到該階段)。
    func setStage(_ stage: GrowthStage) {
        selectedStage = stage
        isGrowthPlaying = false
        playbackTask?.cancel()
    }

    /// 「重播」:瞬間歸零到發芽(bump token 讓場景 snap),再從頭自動播放。
    func replayGrowth() {
        growthReplayToken += 1
        selectedStage = .sprout
        isGrowthPlaying = true
        startGrowthPlayback()
    }

    /// 空間資訊卡「觀看生長動畫」CTA:由主視窗層觀察 token 後切換 immersive space。
    func requestGrowthMode() {
        growthModeRequestToken += 1
    }

    private func apply(result: RecognitionResult, state: RecognitionProviderState) {
        currentResult = result
        recognitionState = state
        selectedStage = .sprout
    }

    private func handleRelayStatus(_ status: RelayClientStatus) {
        relayStatus = status
        switch status {
        case .disconnected:
            break
        case .connecting:
            recognitionState = .relayConnecting(status.message)
        case .connected, .joined:
            recognitionState = .relayConnected(status.message)
        case .failed(let reason):
            recognitionState = .failed(reason)
        }
    }

    /// 收到一幀 relay 結果後該怎麼處理顯示。抽成純函式方便單元測試(對齊 Mac 端 resolveScene 慣例)。
    enum DisplayDecision: Equatable {
        case ignore                    // 已鎖定:維持目前顯示
        case keep                      // 背景 / 未知:不清除,維持上次辨識
        case refresh                   // 同一株植物:維持穩定顯示,不重設生長階段
        case switchTo(plantID: String) // 換成不同的、已知的植物
    }

    static func decideDisplay(incomingKnownPlantID: String?,
                              currentPlantID: String?,
                              isHolding: Bool) -> DisplayDecision {
        if isHolding { return .ignore }
        guard let incomingKnownPlantID else { return .keep }
        if incomingKnownPlantID == currentPlantID { return .refresh }
        return .switchTo(plantID: incomingKnownPlantID)
    }

    /// 由一幀 payload 組出綜合健康狀態。子訊號缺欄位則為 nil;枯萎缺值回 nil(整體不顯示)。
    /// 缺 level 但有 ratio 時用鏡像閾值後備推等級(對齊 Mac 端)。
    static func makePlantHealth(from payload: RelayFramePayload) -> PlantHealthStatus? {
        let wither = payload.witherRatio.map { ratio in
            WitherStatus(ratio: ratio, level: payload.witherLevel ?? WitherLevel.level(forRatio: ratio))
        }
        let trend = payload.witherTrend.flatMap { WitherTrend(rawValue: $0) }
        let status = PlantHealthStatus(wither: wither, trend: trend)
        return status.hasAnySignal ? status : nil
    }

    private func handleRelayFramePayload(_ payload: RelayFramePayload) {
        guard payload.message == "成功抽幀" else {
            updateState(.relayResult("收到 Relay 訊息：\(payload.message)"))
            return
        }

        // 健康訊號（枯萎＋趨勢）與植物辨識是獨立的兩條線:直接依當前幀更新
        // (缺欄位則該子訊號隱藏,全缺則整體不顯示,向後相容)。鎖定時凍結,與資訊卡一致;
        // 不耦合到 decideDisplay 的辨識決策。
        if !isHolding {
            plantHealth = Self.makePlantHealth(from: payload)
        }

        // 僅當 plantID 對應到資料庫中的植物時才視為「已知植物」;background / 未知 / nil 一律視為非植物。
        let knownPlantID: String? = {
            guard let plantID = payload.plantID, PlantDatabase.plant(id: plantID) != nil else { return nil }
            return plantID
        }()

        switch Self.decideDisplay(incomingKnownPlantID: knownPlantID,
                                  currentPlantID: currentResult?.plant.id,
                                  isHolding: isHolding) {
        case .ignore:
            break // 已鎖定,維持目前顯示
        case .keep:
            updateBackgroundStatus(rawPlantID: payload.plantID)
        case .refresh:
            break // 同一株植物,維持穩定顯示,不重設生長階段
        case .switchTo(let plantID):
            applyRelayPlant(plantID: plantID, payload: payload)
        }
    }

    /// 背景 / 未知幀:不清除 currentResult,只更新狀態文字。原本就沒有結果時維持空狀態。
    private func updateBackgroundStatus(rawPlantID: String?) {
        let detail: String
        if let current = currentResult {
            let reason = rawPlantID.map { "模型分類：\($0)" } ?? "未收到模型分類"
            detail = "畫面為背景（\(reason)），維持顯示上次辨識的「\(current.plant.chineseName)」。"
        } else if let rawPlantID {
            detail = "Mac 已抽幀，畫面中未偵測到植物（模型分類：\(rawPlantID)）"
        } else {
            detail = "Mac 已抽幀，但未收到模型分類結果"
        }
        updateState(.relayResult(detail))
    }

    private func applyRelayPlant(plantID: String, payload: RelayFramePayload) {
        guard let plant = PlantDatabase.plant(id: plantID) else { return }

        let confidence = payload.confidence ?? plant.demoConfidence
        let sizeDescription: String
        if let width = payload.frameWidth, let height = payload.frameHeight {
            sizeDescription = "frame 尺寸 \(width) x \(height)"
        } else {
            sizeDescription = "未提供 frame 尺寸"
        }

        let result = RecognitionResult(
            plant: plant,
            confidence: confidence,
            source: .relay,
            detectedAt: Date(),
            note: "已從 Mac relay 收到「成功抽幀」；\(sizeDescription)。模型回傳 \(plantID)。"
        )
        apply(result: result, state: .relayResult("Mac 已成功抽幀並回傳 Vision Pro"))
    }

    /// 避免 10 FPS relay 串流對同一狀態反覆賦值造成不必要的重繪。
    private func updateState(_ state: RecognitionProviderState) {
        guard recognitionState != state else { return }
        recognitionState = state
    }

    private func startGrowthPlayback() {
        playbackTask?.cancel()
        playbackTask = Task { [weak self] in
            let stages = GrowthStage.allCases
            // 停留 ~1.2s,讓場景每次階段切換的 ~0.8s 平滑轉場走完後再進下一階段。
            while !Task.isCancelled {
                for stage in stages {
                    guard !Task.isCancelled else { return }
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
                    await MainActor.run {
                        self?.selectedStage = stage
                    }
                }
            }
        }
    }
}

private struct HistoryStore {
    private var url: URL {
        URL.documentsDirectory.appending(path: "PlantVisionHistory.json")
    }

    func load() -> [PlantHistoryRecord] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([PlantHistoryRecord].self, from: data)) ?? []
    }

    func save(_ records: [PlantHistoryRecord]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: url, options: [.atomic])
    }
}

final class RelaySettingsStore {
    static let defaultRelayURL = "http://127.0.0.1:8080"
    static let defaultPairingCode = "482913"

    private enum Key {
        static let relayURL = "PlantVision.relayURL"
        static let pairingCode = "PlantVision.relayPairingCode"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var relayURL: String {
        get {
            defaults.string(forKey: Key.relayURL) ?? Self.defaultRelayURL
        }
        set {
            defaults.set(newValue, forKey: Key.relayURL)
        }
    }

    var pairingCode: String {
        get {
            defaults.string(forKey: Key.pairingCode) ?? Self.defaultPairingCode
        }
        set {
            defaults.set(newValue, forKey: Key.pairingCode)
        }
    }
}
