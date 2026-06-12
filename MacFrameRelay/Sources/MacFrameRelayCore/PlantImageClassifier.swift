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
    public static let backgroundLabel = "background"

    /// 單一區塊要達到的信心門檻
    private static let tileConfidenceThreshold: Float = 0.9
    /// 同一植物需在幾個重疊區塊同時過門檻才算偵測到，用來濾掉單一區塊的偶發誤判
    private static let minimumCorroboratingTiles = 2

    private let visionModel: VNCoreMLModel

    public convenience init(modelName: String = "PlantClassifier") throws {
        try self.init(modelURL: Self.findModelURL(named: modelName))
    }

    public init(modelURL: URL) throws {
        let compiledModelURL = try Self.compiledModelURL(from: modelURL)
        let model = try MLModel(contentsOf: compiledModelURL)
        visionModel = try VNCoreMLModel(for: model)
    }

    public func classify(_ image: CGImage) throws -> PlantClassificationResult {
        guard let observation = try classifications(in: image).first else {
            throw PlantImageClassifierError.noClassificationResult
        }

        return PlantClassificationResult(
            label: observation.identifier,
            confidence: Double(observation.confidence)
        )
    }

    /// 掃描整個畫面的多個方形區塊再彙整結果。模型是用植物特寫訓練的，
    /// 植物若只佔鏡像畫面一小塊，整張 centerCrop 會被判成 background，
    /// 所以改用滑動窗讓佔比小、位置偏的植物也能被個別區塊看成特寫。
    public func classifyScene(_ image: CGImage) throws -> PlantClassificationResult? {
        var bestConfidence: [String: Float] = [:]
        var confidentTileCounts: [String: Int] = [:]

        for tileRect in Self.tileRects(width: image.width, height: image.height) {
            guard let tile = image.cropping(to: tileRect) else { continue }
            for observation in try classifications(in: tile) {
                bestConfidence[observation.identifier] = max(
                    observation.confidence,
                    bestConfidence[observation.identifier] ?? 0
                )
                if observation.confidence >= Self.tileConfidenceThreshold {
                    confidentTileCounts[observation.identifier, default: 0] += 1
                }
            }
        }

        let detectedPlant = confidentTileCounts
            .filter { $0.key != Self.backgroundLabel && $0.value >= Self.minimumCorroboratingTiles }
            .keys
            .max { (bestConfidence[$0] ?? 0) < (bestConfidence[$1] ?? 0) }

        if let detectedPlant {
            return PlantClassificationResult(
                label: detectedPlant,
                confidence: Double(bestConfidence[detectedPlant] ?? 0)
            )
        }

        if let backgroundConfidence = bestConfidence[Self.backgroundLabel] {
            return PlantClassificationResult(
                label: Self.backgroundLabel,
                confidence: Double(backgroundConfidence)
            )
        }

        return nil
    }

    private func classifications(in image: CGImage) throws -> [VNClassificationObservation] {
        let request = VNCoreMLRequest(model: visionModel)
        request.imageCropAndScaleOption = .centerCrop
        try VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results as? [VNClassificationObservation]) ?? []
    }

    /// 全幅中央正方形＋半幅滑動窗（步幅為邊長一半，相鄰區塊重疊，
    /// 讓真正的植物能同時出現在多個區塊）
    private static func tileRects(width: Int, height: Int) -> [CGRect] {
        let fullSide = min(width, height)
        var rects = [CGRect(
            x: (width - fullSide) / 2,
            y: (height - fullSide) / 2,
            width: fullSide,
            height: fullSide
        )]

        let side = fullSide / 2
        guard side > 0 else { return rects }
        let stride = max(1, side / 2)

        var y = 0
        while true {
            var x = 0
            while true {
                rects.append(CGRect(x: x, y: y, width: side, height: side))
                if x + side >= width { break }
                x = min(x + stride, width - side)
            }
            if y + side >= height { break }
            y = min(y + stride, height - side)
        }
        return rects
    }

    private static func findModelURL(named modelName: String) throws -> URL {
        for fileExtension in ["mlmodelc", "mlpackage", "mlmodel"] {
            if let url = modelBundle.url(forResource: modelName, withExtension: fileExtension) {
                return url
            }
        }
        throw PlantImageClassifierError.modelNotFound(modelName)
    }

    private static var modelBundle: Bundle {
        #if SWIFT_PACKAGE
        Bundle.module
        #else
        Bundle.main
        #endif
    }

    private static func compiledModelURL(from modelURL: URL) throws -> URL {
        if modelURL.pathExtension == "mlmodelc" {
            return modelURL
        }
        return try MLModel.compileModel(at: modelURL)
    }
}
