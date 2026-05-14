import Foundation

@MainActor
final class PlantVisionModel: ObservableObject {
    static let immersiveSpaceID = "PlantVisionImmersiveSpace"

    @Published var recognitionState: RecognitionProviderState = .idle
    @Published var currentResult: RecognitionResult?
    @Published var selectedStage: GrowthStage = .sprout
    @Published var isGrowthPlaying = false
    @Published private(set) var history: [PlantHistoryRecord] = []

    private let demoProvider = DemoRecognitionProvider()
    private let cameraProvider = CameraRecognitionProvider()
    private let historyStore = HistoryStore()
    private var playbackTask: Task<Void, Never>?

    init() {
        history = historyStore.load()
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
