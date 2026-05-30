import CoreGraphics
import CoreML
import Foundation
import Vision

public enum PlantImageClassifierError: LocalizedError, Equatable {
    case modelNotFound(String)
    case noClassificationResult

    public var errorDescription: String? {
        switch self {
        case .modelNotFound(let modelName):
            "找不到 Core ML 模型：\(modelName).mlmodel、\(modelName).mlpackage 或 \(modelName).mlmodelc"
        case .noClassificationResult:
            "Core ML 模型沒有回傳分類結果"
        }
    }
}

public final class PlantImageClassifier {
    private let request: VNCoreMLRequest

    public init(modelName: String = "PlantClassifier") throws {
        let modelURL = try Self.findModelURL(named: modelName)
        let compiledModelURL = try Self.compiledModelURL(from: modelURL)
        let model = try MLModel(contentsOf: compiledModelURL)
        let visionModel = try VNCoreMLModel(for: model)
        let request = VNCoreMLRequest(model: visionModel)
        request.imageCropAndScaleOption = .centerCrop
        self.request = request
    }

    public func classify(_ image: CGImage) throws -> PlantClassificationResult {
        try VNImageRequestHandler(cgImage: image).perform([request])

        guard let observation = request.results?.first as? VNClassificationObservation else {
            throw PlantImageClassifierError.noClassificationResult
        }

        return PlantClassificationResult(
            label: observation.identifier,
            confidence: Double(observation.confidence)
        )
    }

    private static func findModelURL(named modelName: String) throws -> URL {
        for fileExtension in ["mlmodelc", "mlpackage", "mlmodel"] {
            if let url = Bundle.module.url(forResource: modelName, withExtension: fileExtension) {
                return url
            }
        }
        throw PlantImageClassifierError.modelNotFound(modelName)
    }

    private static func compiledModelURL(from modelURL: URL) throws -> URL {
        if modelURL.pathExtension == "mlmodelc" {
            return modelURL
        }
        return try MLModel.compileModel(at: modelURL)
    }
}
