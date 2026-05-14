import Foundation
import Vision

#if !targetEnvironment(simulator) && canImport(ARKit)
import ARKit
import CoreVideo
#endif

enum RecognitionProviderState: Equatable {
    case idle
    case requestingCamera
    case cameraRunning
    case demoMode(String)
    case failed(String)

    var message: String {
        switch self {
        case .idle:
            "尚未開始辨識"
        case .requestingCamera:
            "正在請求主鏡頭權限"
        case .cameraRunning:
            "主鏡頭 Demo 辨識中"
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
            note: "使用內建植物樣本回傳穩定辨識結果，保留與主鏡頭相同的結果資料流。"
        )
        return .recognized(result, .demoMode("主鏡頭不可用時使用內建植物樣本"))
    }
}

struct CameraRecognitionProvider: RecognitionProviding {
    func recognize() async -> RecognitionAttempt {
        #if targetEnvironment(simulator)
        return .fallbackRequired(.demoMode("visionOS Simulator 無法提供 Vision Pro 主鏡頭影像"))
        #else
        return await CameraFrameExperiment().recognize()
        #endif
    }
}

#if !targetEnvironment(simulator) && canImport(ARKit)
@available(visionOS 2.0, *)
private final class CameraFrameExperiment {
    func recognize() async -> RecognitionAttempt {
        guard CameraFrameProvider.isSupported else {
            return .fallbackRequired(.demoMode("此裝置不支援 CameraFrameProvider"))
        }

        let session = ARKitSession()
        let provider = CameraFrameProvider()

        do {
            let authorization = await session.requestAuthorization(for: [.cameraAccess])
            guard authorization[.cameraAccess] == .allowed else {
                return .fallbackRequired(.demoMode("主鏡頭權限未授權或 entitlement 不可用"))
            }

            guard let format = CameraVideoFormat.supportedVideoFormats(for: .main, cameraPositions: [.left]).first,
                  let updates = provider.cameraFrameUpdates(for: format) else {
                return .fallbackRequired(.demoMode("找不到可用的主鏡頭影像格式"))
            }

            try await session.run([provider])

            for await frame in updates {
                _ = frame
                let plant = PlantDatabase.primaryPlant
                let result = RecognitionResult(
                    plant: plant,
                    confidence: 0.82,
                    source: .camera,
                    detectedAt: Date(),
                    note: "已取得主鏡頭 frame；Demo 版以本地植物類別模擬 Vision/Core ML 分類結果。"
                )
                return .recognized(result, .cameraRunning)
            }

            return .fallbackRequired(.demoMode("CameraFrameProvider 沒有產生 frame"))
        } catch {
            return .fallbackRequired(.demoMode("主鏡頭啟動失敗：\(error.localizedDescription)"))
        }
    }
}
#endif
