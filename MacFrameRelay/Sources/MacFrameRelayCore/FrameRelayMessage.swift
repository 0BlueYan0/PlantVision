import Foundation

public enum FrameRelayCapturePolicy {
    public static let automaticCaptureIntervalSeconds: TimeInterval = 0.1
    public static let automaticCaptureIntervalNanoseconds: UInt64 = 100_000_000
}

public struct FrameRelayMessage: Equatable, Sendable {
    public let text: String
    public let type: String
    public let capturedAt: Date?
    public let frameWidth: Int?
    public let frameHeight: Int?

    public var jsonPayload: Data {
        let timestamp = capturedAt.map { ISO8601DateFormatter().string(from: $0) }
        let payload = FrameRelayPayload(
            type: type,
            message: text,
            timestamp: timestamp,
            frameWidth: frameWidth,
            frameHeight: frameHeight
        )
        return (try? JSONEncoder().encode(payload)) ?? Data()
    }

    public init(
        text: String,
        type: String = "frameCaptured",
        capturedAt: Date? = nil,
        frameWidth: Int? = nil,
        frameHeight: Int? = nil
    ) {
        self.text = text
        self.type = type
        self.capturedAt = capturedAt
        self.frameWidth = frameWidth
        self.frameHeight = frameHeight
    }

    public static func successFrameCaptured(frame: CapturedFrame? = nil) -> FrameRelayMessage {
        FrameRelayMessage(
            text: "成功抽幀",
            capturedAt: frame?.capturedAt,
            frameWidth: frame?.width,
            frameHeight: frame?.height
        )
    }
}

private struct FrameRelayPayload: Encodable {
    let type: String
    let message: String
    let timestamp: String?
    let frameWidth: Int?
    let frameHeight: Int?
}
