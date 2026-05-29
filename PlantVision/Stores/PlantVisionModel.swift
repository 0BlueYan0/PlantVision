import Foundation

@MainActor
final class PlantVisionModel: ObservableObject {
    static let immersiveSpaceID = "PlantVisionImmersiveSpace"

    @Published var recognitionState: RecognitionProviderState = .idle
    @Published var currentResult: RecognitionResult?
    @Published var selectedStage: GrowthStage = .sprout
    @Published var isGrowthPlaying = false
    @Published var relayURLText = "http://127.0.0.1:8080"
    @Published var relayPairingCode = "482913"
    @Published var relayStatus: RelayClientStatus = .disconnected
    @Published private(set) var history: [PlantHistoryRecord] = []

    private let demoProvider = DemoRecognitionProvider()
    private let cameraProvider = CameraRecognitionProvider()
    private let relayClient = SocketIORelayClient()
    private let historyStore = HistoryStore()
    private var playbackTask: Task<Void, Never>?

    init() {
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

    func scanWithCameraFirst() {
        recognitionState = .requestingCamera
        Task {
            let attempt = await cameraProvider.recognize()
            switch attempt {
            case .recognized(let result, let state):
                apply(result: result, state: state)
            case .fallbackRequired(let state):
                recognitionState = state
                await runDemoRecognition()
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
        let record = PlantHistoryRecord(
            id: UUID(),
            plantID: result.plant.id,
            chineseName: result.plant.chineseName,
            scientificName: result.plant.scientificName,
            confidence: result.confidence,
            source: result.source.rawValue,
            createdAt: Date()
        )
        history.insert(record, at: 0)
        historyStore.save(history)
    }

    func clearHistory() {
        history.removeAll()
        historyStore.save(history)
    }

    func toggleGrowthPlayback() {
        isGrowthPlaying.toggle()
        if isGrowthPlaying {
            startGrowthPlayback()
        } else {
            playbackTask?.cancel()
        }
    }

    func setStage(_ stage: GrowthStage) {
        selectedStage = stage
        isGrowthPlaying = false
        playbackTask?.cancel()
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

    private func handleRelayFramePayload(_ payload: RelayFramePayload) {
        guard payload.message == "成功抽幀" else {
            recognitionState = .relayResult("收到 Relay 訊息：\(payload.message)")
            return
        }

        let plant = PlantDatabase.primaryPlant
        let sizeDescription: String
        if let width = payload.frameWidth, let height = payload.frameHeight {
            sizeDescription = "frame 尺寸 \(width) x \(height)"
        } else {
            sizeDescription = "未提供 frame 尺寸"
        }

        let result = RecognitionResult(
            plant: plant,
            confidence: plant.demoConfidence,
            source: .relay,
            detectedAt: Date(),
            note: "已從 Mac relay 收到「成功抽幀」；\(sizeDescription)。目前先沿用本地植物資料顯示辨識結果。"
        )
        apply(result: result, state: .relayResult("Mac 已成功抽幀並回傳 Vision Pro"))
    }

    private func startGrowthPlayback() {
        playbackTask?.cancel()
        playbackTask = Task { [weak self] in
            let stages = GrowthStage.allCases
            while !Task.isCancelled {
                for stage in stages {
                    guard !Task.isCancelled else { return }
                    try? await Task.sleep(nanoseconds: 900_000_000)
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
