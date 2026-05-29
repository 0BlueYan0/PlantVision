import Foundation
import Testing
@testable import MacFrameRelayCore

@Test
func successMessagePayloadIsStable() throws {
    let message = FrameRelayMessage.successFrameCaptured()

    #expect(message.text == "成功抽幀")
    #expect(String(data: message.jsonPayload, encoding: .utf8)?.contains("\"message\":\"成功抽幀\"") == true)
    #expect(String(data: message.jsonPayload, encoding: .utf8)?.contains("\"type\":\"frameCaptured\"") == true)
}

@Test
func capturedFrameStoresImageDimensions() throws {
    let frame = try CapturedFrame.makePlaceholder(width: 320, height: 180)

    #expect(frame.width == 320)
    #expect(frame.height == 180)
}
