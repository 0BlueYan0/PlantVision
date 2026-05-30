import CoreGraphics
import Foundation
import ScreenCaptureKit

public enum ScreenCaptureError: LocalizedError, Equatable {
    case invalidImageSize
    case frameCreationFailed
    case mainDisplayUnavailable
    case permissionDenied
    case captureTargetUnavailable

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
        case .captureTargetUnavailable:
            "找不到選取的擷取目標，請重新整理目標清單。"
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

    public static func canReadTargets(hasAccess: Bool, requestPermissionIfNeeded: Bool, requestAccess: () -> Bool) -> Bool {
        hasAccess || (requestPermissionIfNeeded && requestAccess())
    }

    public func availableTargets() async throws -> [CaptureTarget] {
        let content = try await shareableContent()
        let displays = content.displays.map { display in
            let title = display.displayID == CGMainDisplayID() ? "主螢幕" : "Display \(display.displayID)"
            return CaptureTarget.display(
                id: display.displayID,
                title: title,
                width: display.width,
                height: display.height
            )
        }

        let windows = content.windows
            .filter {
                CaptureTarget.isListableWindow(
                    isOnScreen: $0.isOnScreen,
                    title: $0.title,
                    ownerName: $0.owningApplication?.applicationName
                )
            }
            .map { window in
                CaptureTarget.window(
                    id: window.windowID,
                    title: window.title ?? "",
                    ownerName: window.owningApplication?.applicationName ?? ""
                )
            }

        return displays + windows
    }

    public func captureMainDisplayFrame() async throws -> CapturedFrame {
        try await captureFrame(target: nil)
    }

    public func captureFrame(target: CaptureTarget?) async throws -> CapturedFrame {
        let content = try await shareableContent()
        let filter: SCContentFilter

        if let target {
            filter = try contentFilter(for: target, content: content)
        } else {
            let mainDisplayID = CGMainDisplayID()
            guard let display = content.displays.first(where: { $0.displayID == mainDisplayID }) ?? content.displays.first else {
                throw ScreenCaptureError.mainDisplayUnavailable
            }
            filter = SCContentFilter(display: display, excludingWindows: [])
        }

        let streamInfo = SCShareableContent.info(for: filter)
        let configuration = SCStreamConfiguration()
        configuration.width = max(1, Int(streamInfo.contentRect.width * CGFloat(streamInfo.pointPixelScale)))
        configuration.height = max(1, Int(streamInfo.contentRect.height * CGFloat(streamInfo.pointPixelScale)))
        configuration.showsCursor = true
        configuration.capturesAudio = false

        let image = try await captureImage(contentFilter: filter, configuration: configuration)
        return CapturedFrame(cgImage: image)
    }

    private func shareableContent() async throws -> SCShareableContent {
        guard hasScreenCaptureAccess else {
            throw ScreenCaptureError.permissionDenied
        }

        do {
            return try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            let nsError = error as NSError
            if nsError.domain == SCStreamErrorDomain && nsError.code == -3801 {
                throw ScreenCaptureError.permissionDenied
            }
            throw error
        }
    }

    private func contentFilter(for target: CaptureTarget, content: SCShareableContent) throws -> SCContentFilter {
        switch target {
        case .display(let id, _, _, _):
            guard let display = content.displays.first(where: { $0.displayID == id }) else {
                throw ScreenCaptureError.captureTargetUnavailable
            }
            return SCContentFilter(display: display, excludingWindows: [])
        case .window(let id, _, _):
            guard let window = content.windows.first(where: { $0.windowID == id }) else {
                throw ScreenCaptureError.captureTargetUnavailable
            }
            return SCContentFilter(desktopIndependentWindow: window)
        }
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
