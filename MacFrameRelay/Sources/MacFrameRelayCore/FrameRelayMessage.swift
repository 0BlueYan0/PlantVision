import Foundation

public enum FrameRelayCapturePolicy {
    public static let automaticCaptureIntervalSeconds: TimeInterval = 0.1
    public static let automaticCaptureIntervalNanoseconds: UInt64 = 100_000_000
}

public enum FrameRelayCaptureShortcut {
    public static let rightCommandMask: UInt = 0x10
    public static let leftOptionMask: UInt = 0x20
    public static let rightOptionMask: UInt = 0x40

    public static func shouldStartAutomaticCapture(modifierFlagsRawValue: UInt) -> Bool {
        let requiredFlags = leftOptionMask | rightOptionMask
        return (modifierFlagsRawValue & requiredFlags) == requiredFlags
    }

    public static func shouldStopAutomaticCapture(modifierFlagsRawValue: UInt) -> Bool {
        let requiredFlags = leftOptionMask | rightCommandMask
        return (modifierFlagsRawValue & requiredFlags) == requiredFlags
    }
}

public struct PlantClassificationResult: Equatable, Sendable {
    public let label: String
    public let confidence: Double

    public init(label: String, confidence: Double) {
        self.label = label
        self.confidence = confidence
    }
}

/// 一幀的枯萎程度摘要：連續比例（0–1）＋對應等級。兩者一起傳，確保 payload 裡的
/// `witherRatio` 與 `witherLevel` 一致。只給比例時，等級用 `WitherLevel` 的預設閾值推出。
public struct WitherSummary: Equatable, Sendable {
    public let ratio: Double
    public let level: Int

    public init(ratio: Double, level: Int) {
        self.ratio = ratio
        self.level = level
    }

    public init(ratio: Double) {
        self.init(ratio: ratio, level: WitherLevel.level(forRatio: ratio))
    }
}

/// 一幀的葉片黃化摘要：連續比例（0–1）＋對應等級。結構比照 `WitherSummary`，
/// 但用 `LeafYellowingLevel` 的獨立閾值推等級——黃化與枯萎是兩種不同的劣化訊號。
public struct LeafYellowingSummary: Equatable, Sendable {
    public let ratio: Double
    public let level: Int

    public init(ratio: Double, level: Int) {
        self.ratio = ratio
        self.level = level
    }

    public init(ratio: Double) {
        self.init(ratio: ratio, level: LeafYellowingLevel.level(forRatio: ratio))
    }
}

public struct FrameRelayMessage: Equatable, Sendable {
    public let text: String
    public let type: String
    public let capturedAt: Date?
    public let frameWidth: Int?
    public let frameHeight: Int?
    public let classification: PlantClassificationResult?
    /// 枯萎程度摘要。與 `classification`（植物辨識）彼此獨立——兩個模型各跑各的。
    public let wither: WitherSummary?
    /// 葉片黃化摘要。與枯萎、辨識皆為獨立訊號，由顏色統計算出（不需 ML）。
    public let yellowing: LeafYellowingSummary?
    /// 枯萎程度的時間變化趨勢（惡化／改善／穩定）。樣本不足時為 nil。
    public let trend: WitherTrend?

    public var jsonPayload: Data {
        let timestamp = capturedAt.map { ISO8601DateFormatter().string(from: $0) }
        let payload = FrameRelayPayload(
            type: type,
            message: text,
            timestamp: timestamp,
            frameWidth: frameWidth,
            frameHeight: frameHeight,
            plantID: classification?.label,
            confidence: classification?.confidence,
            witherRatio: wither?.ratio,
            witherLevel: wither?.level,
            yellowRatio: yellowing?.ratio,
            yellowLevel: yellowing?.level,
            witherTrend: trend?.rawValue
        )
        return (try? JSONEncoder().encode(payload)) ?? Data()
    }

    public init(
        text: String,
        type: String = "frameCaptured",
        capturedAt: Date? = nil,
        frameWidth: Int? = nil,
        frameHeight: Int? = nil,
        classification: PlantClassificationResult? = nil,
        wither: WitherSummary? = nil,
        yellowing: LeafYellowingSummary? = nil,
        trend: WitherTrend? = nil
    ) {
        self.text = text
        self.type = type
        self.capturedAt = capturedAt
        self.frameWidth = frameWidth
        self.frameHeight = frameHeight
        self.classification = classification
        self.wither = wither
        self.yellowing = yellowing
        self.trend = trend
    }

    public static func successFrameCaptured(
        frame: CapturedFrame? = nil,
        classification: PlantClassificationResult? = nil,
        wither: WitherSummary? = nil,
        yellowing: LeafYellowingSummary? = nil,
        trend: WitherTrend? = nil
    ) -> FrameRelayMessage {
        FrameRelayMessage(
            text: "成功抽幀",
            capturedAt: frame?.capturedAt,
            frameWidth: frame?.width,
            frameHeight: frame?.height,
            classification: classification,
            wither: wither,
            yellowing: yellowing,
            trend: trend
        )
    }
}

private struct FrameRelayPayload: Encodable {
    let type: String
    let message: String
    let timestamp: String?
    let frameWidth: Int?
    let frameHeight: Int?
    let plantID: String?
    let confidence: Double?
    // 可選的健康訊號欄位；為 nil 時 JSONEncoder 會自動省略 key，維持對舊端的向後相容。
    let witherRatio: Double?
    let witherLevel: Int?
    let yellowRatio: Double?
    let yellowLevel: Int?
    let witherTrend: String?
}
