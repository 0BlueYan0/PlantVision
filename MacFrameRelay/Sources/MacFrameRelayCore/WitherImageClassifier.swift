import CoreGraphics
import CoreML
import Foundation
import Vision

public enum WitherImageClassifierError: LocalizedError, Equatable {
    case modelNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .modelNotFound(let modelName):
            "找不到 Core ML 模型：\(modelName).mlmodel、\(modelName).mlpackage 或 \(modelName).mlmodelc"
        }
    }
}

/// 用獨立的 `WitherClassifier` 模型，對每個區塊判定健康/枯萎。與 `PlantImageClassifier`
/// 完全分離——兩個模型各跑各的，但共用 `PlantImageClassifier.sceneTiles(in:)` 切出的同一批 tiles。
///
/// 模型本身是二元（healthy / withered）；「這塊有沒有植物」用信心門檻當代理判斷：
/// 最高信心低於門檻就當 `noPlant`（不計入枯萎比例分母）。彙整成比例的邏輯在
/// `WitherScoreResolver`，跨幀平滑在 `TemporalWitherSmoother`。
public final class WitherImageClassifier {
    public static let healthyLabel = "healthy"
    public static let witheredLabel = "withered"

    /// 單一區塊要被算成「有植物（健康/枯萎）」的最低信心；低於此視為 noPlant。
    /// 這是枯萎分類器自己的門檻，與 `PlantImageClassifier` 的投票閾值無關。
    static let tileConfidenceThreshold: Float = 0.7

    private let visionModel: VNCoreMLModel

    public convenience init(modelName: String = "WitherClassifier") throws {
        guard let modelURL = CoreMLModelLocator.findModelURL(named: modelName) else {
            throw WitherImageClassifierError.modelNotFound(modelName)
        }
        try self.init(modelURL: modelURL)
    }

    public init(modelURL: URL) throws {
        let compiledModelURL = try CoreMLModelLocator.compiledModelURL(from: modelURL)
        let model = try MLModel(contentsOf: compiledModelURL)
        visionModel = try VNCoreMLModel(for: model)
    }

    /// 對一批已切好的區塊逐塊判定健康/枯萎/無植物。重用既有 tiles，不重新切圖。
    public func classifyTiles(_ tiles: [CGImage]) -> [WitherTileClassification] {
        tiles.map { tile in
            guard let top = (try? classifications(in: tile))?.first else { return .noPlant }
            return Self.tileClassification(label: top.identifier, confidence: top.confidence)
        }
    }

    /// 純函式：把單塊的最高信心觀測映射成枯萎判定。信心不足、或標籤不是
    /// healthy/withered（例如未來模型加了 background 類）→ noPlant。抽出以便單元測試。
    static func tileClassification(
        label: String,
        confidence: Float,
        threshold: Float = tileConfidenceThreshold
    ) -> WitherTileClassification {
        guard confidence >= threshold else { return .noPlant }
        switch label {
        case healthyLabel: return .healthy
        case witheredLabel: return .withered
        default: return .noPlant
        }
    }

    private func classifications(in image: CGImage) throws -> [VNClassificationObservation] {
        let request = VNCoreMLRequest(model: visionModel)
        request.imageCropAndScaleOption = .centerCrop
        try VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results as? [VNClassificationObservation]) ?? []
    }
}
