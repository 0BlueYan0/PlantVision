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

@Test
func listableWindowDoesNotRequireZeroWindowLayer() {
    #expect(CaptureTarget.isListableWindow(isOnScreen: true, title: "Vision Pro", ownerName: "QuickTime Player"))
    #expect(CaptureTarget.isListableWindow(isOnScreen: true, title: "", ownerName: "QuickTime Player"))
    #expect(CaptureTarget.isListableWindow(isOnScreen: true, title: "Vision Pro", ownerName: ""))
    #expect(!CaptureTarget.isListableWindow(isOnScreen: false, title: "Vision Pro", ownerName: "QuickTime Player"))
    #expect(!CaptureTarget.isListableWindow(isOnScreen: true, title: "", ownerName: ""))
}

@Test
func targetRefreshRequestsAccessOnlyWhenUserInitiated() {
    var requestCount = 0
    let automaticRefreshAllowed = ScreenFrameCapturer.canReadTargets(
        hasAccess: false,
        requestPermissionIfNeeded: false
    ) {
        requestCount += 1
        return true
    }

    #expect(!automaticRefreshAllowed)
    #expect(requestCount == 0)

    let userRefreshAllowed = ScreenFrameCapturer.canReadTargets(
        hasAccess: false,
        requestPermissionIfNeeded: true
    ) {
        requestCount += 1
        return true
    }

    #expect(userRefreshAllowed)
    #expect(requestCount == 1)
}

@Test
func automaticCaptureIntervalIsOneTenthOfASecond() {
    #expect(FrameRelayCapturePolicy.automaticCaptureIntervalSeconds == 0.1)
    #expect(FrameRelayCapturePolicy.automaticCaptureIntervalNanoseconds == 100_000_000)
}

@Test
func settingsStorePersistsRelayURLAndPairingCode() {
    let suiteName = "FrameRelaySettingsStoreTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer {
        defaults.removePersistentDomain(forName: suiteName)
    }

    let store = FrameRelaySettingsStore(defaults: defaults)
    store.relayURL = "https://relay.example.com"
    store.pairingCode = "135790"

    let reloadedStore = FrameRelaySettingsStore(defaults: defaults)
    #expect(reloadedStore.relayURL == "https://relay.example.com")
    #expect(reloadedStore.pairingCode == "135790")
}
