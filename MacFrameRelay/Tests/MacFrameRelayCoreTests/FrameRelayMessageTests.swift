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
func successMessagePayloadIncludesClassificationResult() throws {
    let message = FrameRelayMessage.successFrameCaptured(
        classification: PlantClassificationResult(label: "pelargonium-hortorum", confidence: 0.91)
    )
    let payload = try JSONSerialization.jsonObject(with: message.jsonPayload) as? [String: Any]

    #expect(payload?["plantID"] as? String == "pelargonium-hortorum")
    #expect(payload?["confidence"] as? Double == 0.91)
}

@Test
func successMessagePayloadIncludesWitherFields() throws {
    let message = FrameRelayMessage.successFrameCaptured(
        classification: PlantClassificationResult(label: "lantana-camara", confidence: 0.8),
        wither: WitherSummary(ratio: 0.42, level: 2)
    )
    let payload = try JSONSerialization.jsonObject(with: message.jsonPayload) as? [String: Any]

    #expect(payload?["witherRatio"] as? Double == 0.42)
    #expect(payload?["witherLevel"] as? Int == 2)
}

@Test
func witherSummaryDerivesLevelFromRatio() {
    // 只給比例時，等級用 WitherLevel 的預設閾值自動推出（0.5 → 中度=2）
    let summary = WitherSummary(ratio: 0.5)
    #expect(summary.level == WitherLevel.moderate)
}

@Test
func successMessagePayloadOmitsWitherFieldsWhenAbsent() throws {
    // 向後相容：沒有枯萎資料時，payload 不應出現這兩個 key，舊端解析才不會壞
    let json = String(data: FrameRelayMessage.successFrameCaptured().jsonPayload, encoding: .utf8) ?? ""

    #expect(!json.contains("witherRatio"))
    #expect(!json.contains("witherLevel"))
}

@Test
func successMessagePayloadIncludesTrendField() throws {
    let message = FrameRelayMessage.successFrameCaptured(
        classification: PlantClassificationResult(label: "lantana-camara", confidence: 0.8),
        wither: WitherSummary(ratio: 0.42, level: 2),
        trend: .worsening
    )
    let payload = try JSONSerialization.jsonObject(with: message.jsonPayload) as? [String: Any]

    #expect(payload?["witherTrend"] as? String == "worsening")
}

@Test
func successMessagePayloadOmitsTrendFieldWhenAbsent() throws {
    // 向後相容：沒有趨勢資料時，payload 不應出現這個 key
    let json = String(data: FrameRelayMessage.successFrameCaptured().jsonPayload, encoding: .utf8) ?? ""

    #expect(!json.contains("witherTrend"))
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
func automaticCaptureShortcutRequiresBothOptionKeys() {
    #expect(FrameRelayCaptureShortcut.shouldStartAutomaticCapture(modifierFlagsRawValue: 0x20 | 0x40))
    #expect(!FrameRelayCaptureShortcut.shouldStartAutomaticCapture(modifierFlagsRawValue: 0x20))
    #expect(!FrameRelayCaptureShortcut.shouldStartAutomaticCapture(modifierFlagsRawValue: 0x40))
    #expect(!FrameRelayCaptureShortcut.shouldStartAutomaticCapture(modifierFlagsRawValue: 1 << 19))
}

@Test
func automaticCaptureStopShortcutRequiresLeftOptionAndRightCommand() {
    #expect(FrameRelayCaptureShortcut.shouldStopAutomaticCapture(modifierFlagsRawValue: 0x20 | 0x10))
    #expect(!FrameRelayCaptureShortcut.shouldStopAutomaticCapture(modifierFlagsRawValue: 0x20))
    #expect(!FrameRelayCaptureShortcut.shouldStopAutomaticCapture(modifierFlagsRawValue: 0x10))
    #expect(!FrameRelayCaptureShortcut.shouldStopAutomaticCapture(modifierFlagsRawValue: 0x20 | 0x08))
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
