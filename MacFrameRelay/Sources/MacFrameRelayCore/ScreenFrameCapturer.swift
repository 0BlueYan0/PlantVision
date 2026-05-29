import CoreGraphics
import Foundation
import ScreenCaptureKit

public enum ScreenCaptureError: LocalizedError, Equatable {
    case invalidImageSize
    case frameCreationFailed
    case mainDisplayUnavailable
    case permissionDenied

    public var errorDescription: String? {
        switch self {
        case .invalidImageSize:
            "抽幀尺寸無效"
        case .frameCreationFailed:
            "無法建立抽幀影像"
        case .mainDisplayUnavailable:
            "無法擷取 Mac 主螢幕。請確認已允許螢幕錄製權限，且 Vision Pro 鏡像畫面正在顯示於 Mac。"
        case .permissionDenied:
            "尚未允許 MacFrameRelayApp 擷取螢幕。請在系統設定的螢幕與系統音訊錄製權限中允許此 app。"
        }
    }
}

public struct ScreenFrameCapturer: Sendable {
    public init() {}

    public var hasScreenCaptureAccess: Bool {
        CGPreflightScreenCaptureAccess()
    }

    public func requestScreenCaptureAccess() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    public func captureMainDisplayFrame() async throws -> CapturedFrame {
        guard hasScreenCaptureAccess else {
            throw ScreenCaptureError.permissionDenied
        }

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.current
        } catch {
            let nsError = error as NSError
            if nsError.domain == SCStreamErrorDomain && nsError.code == -3801 {
                throw ScreenCaptureError.permissionDenied
            }
            throw error
        }

        let mainDisplayID = CGMainDisplayID()
        guard let display = content.displays.first(where: { $0.displayID == mainDisplayID }) ?? content.displays.first else {
            throw ScreenCaptureError.mainDisplayUnavailable
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let streamInfo = SCShareableContent.info(for: filter)
        let configuration = SCStreamConfiguration()
        configuration.width = max(1, Int(streamInfo.contentRect.width * CGFloat(streamInfo.pointPixelScale)))
        configuration.height = max(1, Int(streamInfo.contentRect.height * CGFloat(streamInfo.pointPixelScale)))
        configuration.showsCursor = true
        configuration.capturesAudio = false

        let image = try await captureImage(contentFilter: filter, configuration: configuration)
        return CapturedFrame(cgImage: image)
    }

    private func captureImage(contentFilter: SCContentFilter, configuration: SCStreamConfiguration) async throws -> CGImage {
        try await withCheckedThrowingContinuation { continuation in
            SCScreenshotManager.captureImage(contentFilter: contentFilter, configuration: configuration) { image, error in
                if let image {
                    continuation.resume(returning: image)
                } else if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(throwing: ScreenCaptureError.frameCreationFailed)
                }
            }
        }
    }
}
