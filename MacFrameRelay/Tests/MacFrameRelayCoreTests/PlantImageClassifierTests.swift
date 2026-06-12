import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import MacFrameRelayCore

private func fixtureURL(_ name: String, _ ext: String) throws -> URL {
    try #require(Bundle.module.url(forResource: name, withExtension: ext))
}

private func fixtureImage(_ name: String, _ ext: String) throws -> CGImage {
    let url = try fixtureURL(name, ext)
    let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
    return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
}

private func makeClassifier() throws -> PlantImageClassifier {
    try PlantImageClassifier(modelURL: fixtureURL("TestPlantClassifier", "mlmodel"))
}

/// 把植物圖縮小貼到背景圖中央，模擬植物只佔鏡像畫面一小部分的情況
private func compositeImage(plant: CGImage, background: CGImage, widthFraction: CGFloat) throws -> CGImage {
    let width = background.width
    let height = background.height
    let context = try #require(CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    context.draw(background, in: CGRect(x: 0, y: 0, width: width, height: height))
    let plantWidth = CGFloat(width) * widthFraction
    let plantHeight = plantWidth * CGFloat(plant.height) / CGFloat(plant.width)
    context.draw(plant, in: CGRect(
        x: (CGFloat(width) - plantWidth) / 2,
        y: (CGFloat(height) - plantHeight) / 2,
        width: plantWidth,
        height: plantHeight
    ))
    return try #require(context.makeImage())
}

@Test
func classifySceneDetectsPlantOccupyingSmallPartOfFrame() throws {
    let classifier = try makeClassifier()
    let composite = try compositeImage(
        plant: fixtureImage("lobelia-sample", "jpeg"),
        background: fixtureImage("background-sample", "jpg"),
        widthFraction: 0.25
    )

    let result = try #require(try classifier.classifyScene(composite))

    #expect(result.label == "lobelia-erinus")
    #expect(result.confidence >= 0.9)
}

@Test
func classifySceneDetectsFullFramePlant() throws {
    let classifier = try makeClassifier()

    let result = try #require(try classifier.classifyScene(fixtureImage("lobelia-sample", "jpeg")))

    #expect(result.label == "lobelia-erinus")
    #expect(result.confidence >= 0.9)
}

@Test
func classifySceneReportsBackgroundForPlainScene() throws {
    let classifier = try makeClassifier()

    let result = try #require(try classifier.classifyScene(fixtureImage("background-sample", "jpg")))

    #expect(result.label == PlantImageClassifier.backgroundLabel)
}

@Test
func classifySceneRejectsSingleTileFalsePositive() throws {
    // 火星地表照：單一區塊會出現 95% 的 catharanthus 誤判，
    // 需靠「至少兩個區塊同時高信心」的規則濾掉
    let classifier = try makeClassifier()

    let result = try #require(try classifier.classifyScene(fixtureImage("mars-sample", "jpg")))

    #expect(result.label == PlantImageClassifier.backgroundLabel)
}
