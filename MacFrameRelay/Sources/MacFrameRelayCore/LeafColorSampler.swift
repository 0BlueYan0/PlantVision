import CoreGraphics
import Foundation

/// 從一批已切好的區塊抽樣像素、轉成 HSV、再交給 `LeafYellowingResolver.classifyPixel` 歸類。
/// 這層是**非純的 I/O**（讀 CGImage bitmap），刻意與純判定邏輯分離——比照
/// `WitherImageClassifier.classifyTiles` 把模型推論的 I/O 留在外層、純邏輯（`classifyPixel` /
/// `resolve`）抽到 `LeafYellowingResolver` 單元測試。本檔不寫單元測試。
///
/// 為效能可降採樣（每 `stride` 個像素取一點）；統計用途下取樣不影響比例的代表性。
public enum LeafColorSampler {
    public static func samplePixels(in tiles: [CGImage], stride: Int = 4) -> [LeafPixelClass] {
        var result: [LeafPixelClass] = []
        for tile in tiles {
            result.append(contentsOf: samplePixels(in: tile, stride: max(1, stride)))
        }
        return result
    }

    private static func samplePixels(in image: CGImage, stride: Int) -> [LeafPixelClass] {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return [] }

        // 統一畫進 RGBA8 的點陣 context，避免處理各種來源色彩格式。
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var buffer = [UInt8](repeating: 0, count: bytesPerRow * height)
        guard let context = CGContext(
            data: &buffer,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return [] }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var classes: [LeafPixelClass] = []
        var y = 0
        while y < height {
            var x = 0
            while x < width {
                let offset = y * bytesPerRow + x * bytesPerPixel
                let red = Double(buffer[offset]) / 255.0
                let green = Double(buffer[offset + 1]) / 255.0
                let blue = Double(buffer[offset + 2]) / 255.0
                let hsv = rgbToHSV(red: red, green: green, blue: blue)
                classes.append(
                    LeafYellowingResolver.classifyPixel(
                        hue: hsv.hue,
                        saturation: hsv.saturation,
                        value: hsv.value
                    )
                )
                x += stride
            }
            y += stride
        }
        return classes
    }

    /// RGB（0–1）轉 HSV：hue 為度（0–360），saturation/value 為 0–1。
    static func rgbToHSV(red: Double, green: Double, blue: Double) -> (hue: Double, saturation: Double, value: Double) {
        let maxComponent = max(red, green, blue)
        let minComponent = min(red, green, blue)
        let delta = maxComponent - minComponent

        let value = maxComponent
        let saturation = maxComponent == 0 ? 0 : delta / maxComponent

        var hue: Double = 0
        if delta != 0 {
            if maxComponent == red {
                hue = 60 * (((green - blue) / delta).truncatingRemainder(dividingBy: 6))
            } else if maxComponent == green {
                hue = 60 * (((blue - red) / delta) + 2)
            } else {
                hue = 60 * (((red - green) / delta) + 4)
            }
        }
        if hue < 0 { hue += 360 }
        return (hue, saturation, value)
    }
}
