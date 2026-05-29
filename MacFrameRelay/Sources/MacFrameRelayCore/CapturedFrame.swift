import CoreGraphics
import Foundation

public struct CapturedFrame: Sendable {
    public let cgImage: CGImage
    public let capturedAt: Date

    public var width: Int {
        cgImage.width
    }

    public var height: Int {
        cgImage.height
    }

    public init(cgImage: CGImage, capturedAt: Date = Date()) {
        self.cgImage = cgImage
        self.capturedAt = capturedAt
    }

    public static func makePlaceholder(width: Int, height: Int) throws -> CapturedFrame {
        guard width > 0, height > 0 else {
            throw ScreenCaptureError.invalidImageSize
        }

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw ScreenCaptureError.frameCreationFailed
        }

        context.setFillColor(CGColor(red: 0.05, green: 0.22, blue: 0.12, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(red: 0.25, green: 0.78, blue: 0.35, alpha: 1))
        context.fill(CGRect(x: 24, y: 24, width: max(1, width - 48), height: max(1, height - 48)))

        guard let image = context.makeImage() else {
            throw ScreenCaptureError.frameCreationFailed
        }

        return CapturedFrame(cgImage: image)
    }
}
