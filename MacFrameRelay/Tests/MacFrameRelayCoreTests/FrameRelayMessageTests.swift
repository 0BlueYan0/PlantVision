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

@Test
func captureTargetLabelsDistinguishDisplaysAndWindows() {
    let display = CaptureTarget.display(id: 1, title: "Main Display", width: 2560, height: 1664)
    let window = CaptureTarget.window(id: 42, title: "Vision Pro Mirror", ownerName: "QuickTime Player")

    #expect(display.label == "螢幕：Main Display (2560 x 1664)")
    #expect(window.label == "視窗：QuickTime Player - Vision Pro Mirror")
    #expect(display.stableID == "display-1")
    #expect(window.stableID == "window-42")
}
