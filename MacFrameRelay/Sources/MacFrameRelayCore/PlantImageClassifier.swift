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
    /// 當「兩種以上植物類同時達標」時，領先者需在高信心區塊數上至少多出這個差距，
    /// 否則視為兩類拉鋸、回報不確定（落到 background）。用實機 held-out 資料校過：
    /// 設 3 能把「15 vs 14」「6 vs 4」這種瀕臨翻轉的畫面擋成不確定，避免實機在兩類間跳，
    /// 同時不影響「單一植物」或「明確領先（如 23 vs 5）」的判定。
    static let minimumVoteMargin = 3

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

        return Self.resolveScene(bestConfidence: bestConfidence, confidentTileCounts: confidentTileCounts)
    }

    /// 由各區塊彙整出的「高信心區塊數」與「各類最高信心」決定整個畫面的判定。
    /// 抽成純函式以便用真實票數做單元測試。規則：
    /// 1. 取高信心區塊數達 `minimumCorroboratingTiles` 的非背景植物類。
    /// 2. 若有兩種以上植物類同時達標，領先者須多出亞軍 `minimumVoteMargin` 個區塊，
    ///    否則視為兩類拉鋸 → 不確定，落到 background。單一植物則直接接受（不傷小佔比偵測）。
    /// 3. 沒有明確植物時回報 background；連 background 都沒有才回 nil。
    static func resolveScene(
        bestConfidence: [String: Float],
        confidentTileCounts: [String: Int]
    ) -> PlantClassificationResult? {
        let plants = confidentTileCounts
            .filter { $0.key != Self.backgroundLabel && $0.value >= Self.minimumCorroboratingTiles }
            .sorted { $0.value > $1.value }

        if let top = plants.first {
            let ambiguous = plants.count >= 2 && top.value < plants[1].value + Self.minimumVoteMargin
            if !ambiguous {
                return PlantClassificationResult(
                    label: top.key,
                    confidence: Double(bestConfidence[top.key] ?? 0)
                )
            }
            // 兩植物類拉鋸 → 不確定，往下落到 background fallback
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
