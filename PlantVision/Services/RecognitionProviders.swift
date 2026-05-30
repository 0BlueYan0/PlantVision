import Foundation

enum RecognitionProviderState: Equatable {
    case idle
    case relayConnecting(String)
    case relayConnected(String)
    case relayResult(String)
    case demoMode(String)
    case failed(String)

    var message: String {
        switch self {
        case .idle:
            "尚未開始辨識"
        case .relayConnecting(let detail):
            "Relay 連線中：\(detail)"
        case .relayConnected(let detail):
            "Relay 已連線：\(detail)"
        case .relayResult(let detail):
            detail
        case .demoMode(let reason):
            "Demo Mode：\(reason)"
        case .failed(let reason):
            "無法啟動：\(reason)"
        }
    }
}

protocol RecognitionProviding {
    func recognize() async -> RecognitionAttempt
}

enum RecognitionAttempt {
    case recognized(RecognitionResult, RecognitionProviderState)
    case fallbackRequired(RecognitionProviderState)
}

struct DemoRecognitionProvider: RecognitionProviding {
    func recognize() async -> RecognitionAttempt {
        try? await Task.sleep(nanoseconds: 450_000_000)
        let plant = PlantDatabase.primaryPlant
        let result = RecognitionResult(
            plant: plant,
            confidence: plant.demoConfidence,
            source: .demo,
            detectedAt: Date(),
            note: "使用內建植物樣本回傳穩定辨識結果，保留與 Relay 相同的結果資料流。"
        )
        return .recognized(result, .demoMode("使用內建植物樣本"))
    }
}
