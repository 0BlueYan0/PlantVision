# PlantVision

PlantVision 目前包含 visionOS app、Mac 抽幀 companion app，以及 Socket.IO relay server。

目標流程：

1. Vision Pro 將畫面鏡像到 Mac。
2. Mac app 擷取 Mac 當前主螢幕 frame，並在 Mac app 中顯示抽出的 frame。
3. Mac app 透過 Socket.IO relay 送出 JSON 給 Vision Pro。
4. Vision Pro 端收到 `message: "成功抽幀"` 後再接續後續流程。

## 架構

```text
MacFrameRelayApp  --outbound Socket.IO-->  SocketIORelayServer  <--outbound Socket.IO--  Vision Pro app
```

這個架構不依賴 UDP broadcast、Bonjour/mDNS，也不需要 Vision Pro 直接連進 Mac，所以比較能避開校園網路禁止廣播或裝置互連的限制。部署到外網時，relay server 前面應放 HTTPS，兩端使用 `https://your-domain` 連線。

## Socket.IO Relay Server

位置：

```bash
SocketIORelayServer/
```

安裝依賴：

```bash
cd /Users/0blueyan0/develop/PlantVision/SocketIORelayServer
npm install
```

啟動本機 relay：

```bash
npm start
```

預設監聽：

```text
http://127.0.0.1:8080
```

可用環境變數調整：

```bash
PORT=8080 HOST=0.0.0.0 CORS_ORIGIN="*" npm start
```

背景執行 relay：

```bash
cd /Users/0blueyan0/develop/PlantVision/SocketIORelayServer
nohup npm start > relay.log 2>&1 &
```

如果已經在前景執行 `npm start`，可以先把它轉到背景：

```bash
# 按 Ctrl+Z 暫停
bg
disown
```

之後就可以關閉目前 terminal，relay 會繼續跑。

查看背景 job：

```bash
jobs -l
```

查看 relay process：

```bash
ps aux | grep "node src/server.js"
```

查看 8080 是否正在 listen：

```bash
lsof -nP -iTCP:8080 -sTCP:LISTEN
```

看 relay log：

```bash
tail -f /Users/0blueyan0/develop/PlantVision/SocketIORelayServer/relay.log
```

停止目前 shell 的背景 job：

```bash
kill %1
```

其中 `%1` 是 `jobs -l` 顯示的 job 編號。

停止已脫離 shell 的 relay process：

```bash
pkill -f "node src/server.js"
```

或先查 PID，再指定關閉：

```bash
lsof -nP -iTCP:8080 -sTCP:LISTEN
kill <PID>
```

如果一般 `kill` 無法關閉，再用：

```bash
kill -9 <PID>
```

測試 relay：

```bash
npm test
```

relay 已測試：

- 同一個配對碼 room 會把 Mac 的 `frameResult` 轉發給 Vision Pro。
- 不同配對碼 room 不會互相收到訊息。

## 配對流程

Mac 和 Vision Pro 都連到同一個 Socket.IO relay URL，並使用同一組配對碼。

Mac join：

```json
{
  "role": "mac",
  "code": "482913"
}
```

Vision Pro join：

```json
{
  "role": "vision",
  "code": "482913"
}
```

兩端都 emit `join` event：

```text
event: join
payload: { "role": "mac" | "vision", "code": "482913" }
```

relay 回覆：

```text
event: joined
payload: { "role": "...", "code": "482913" }
```

## Mac App

位置：

```bash
MacFrameRelay/
```

建置 `.app`：

```bash
cd /Users/0blueyan0/develop/PlantVision
MacFrameRelay/Scripts/build_app_bundle.sh
```

輸出位置：

```text
/Users/0blueyan0/develop/PlantVision/MacFrameRelay/.build/MacFrameRelayApp.app
```

開啟 app：

```bash
open /Users/0blueyan0/develop/PlantVision/MacFrameRelay/.build/MacFrameRelayApp.app
```

Mac app 內要設定：

- `Relay URL`：本機測試填 `http://127.0.0.1:8080`
- `配對碼`：例如 `482913`
- 按 `連線 Relay`
- 按 `重新整理目標`
- 在 `擷取目標` 選擇 Vision Pro 鏡像所在的螢幕或鏡像視窗
- Vision Pro 鏡像畫面顯示在選取目標後，按 `開始自動擷取`
- Mac app 會每 0.1 秒擷取一幀並送出一次 `frameResult`，要停止時按 `停止自動擷取`

如果 Vision Pro 鏡像輸出佔滿 Mac 主螢幕，建議選擇「鏡像視窗」或使用第二個螢幕放 Mac app。不要把 MacFrameRelayApp 疊在被擷取的畫面上，否則可能會把控制視窗一起截進 frame。

抽幀成功後，Mac app 會 emit：

```text
event: frameResult
```

payload 範例：

```json
{
  "type": "frameCaptured",
  "message": "成功抽幀",
  "timestamp": "2026-05-29T15:00:00Z",
  "frameWidth": 2560,
  "frameHeight": 1664
}
```

relay 會轉發給同配對碼的 Vision Pro：

```text
event: plantVisionRelay
```

payload 範例：

```json
{
  "code": "482913",
  "data": {
    "type": "frameCaptured",
    "message": "成功抽幀",
    "timestamp": "2026-05-29T15:00:00Z",
    "frameWidth": 2560,
    "frameHeight": 1664
  }
}
```

## Mac 螢幕擷取權限

Mac app 使用 ScreenCaptureKit 擷取目前主螢幕 frame。

第一次使用時，macOS 可能會要求允許螢幕擷取權限。如果 app 顯示權限錯誤：

1. 打開系統設定。
2. 到隱私權與安全性。
3. 找到螢幕與系統音訊錄製。
4. 允許 `MacFrameRelayApp`。
5. 重新開啟 app。

Terminal probe 能抽幀不代表 `.app` 已授權，因為 macOS TCC 權限是依照 app bundle 分開管理。

## 驗證指令

Mac app / core 測試：

```bash
cd /Users/0blueyan0/develop/PlantVision/MacFrameRelay
swift test
```

Mac app bundle 建置：

```bash
cd /Users/0blueyan0/develop/PlantVision
MacFrameRelay/Scripts/build_app_bundle.sh
```

ScreenCaptureKit 實際抽幀 probe：

```bash
cd /Users/0blueyan0/develop/PlantVision/MacFrameRelay
swift -e 'import CoreGraphics; import Foundation; import ScreenCaptureKit; let content = try await SCShareableContent.current; guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) ?? content.displays.first else { print("no display"); exit(1) }; let filter = SCContentFilter(display: display, excludingWindows: []); let info = SCShareableContent.info(for: filter); let config = SCStreamConfiguration(); config.width = max(1, Int(info.contentRect.width * CGFloat(info.pointPixelScale))); config.height = max(1, Int(info.contentRect.height * CGFloat(info.pointPixelScale))); config.showsCursor = true; let image: CGImage = try await withCheckedThrowingContinuation { continuation in SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) { image, error in if let image { continuation.resume(returning: image) } else { continuation.resume(throwing: error ?? NSError(domain: "capture", code: 1)) } } }; print("captured \(image.width)x\(image.height)")'
```

relay server 測試：

```bash
cd /Users/0blueyan0/develop/PlantVision/SocketIORelayServer
npm test
```

## Vision Pro App

Vision Pro app 端已內建最小 Socket.IO v4 client，使用 `URLSessionWebSocketTask` 直接連 Socket.IO relay，不需要額外 Swift Package。

操作流程：

1. 在 Vision Pro app 的掃描頁輸入 `Relay URL`。
2. 輸入和 Mac app 相同的配對碼。
3. 按 `連線 Relay`。
4. Vision Pro 會 emit `join`，payload 使用 `{ "role": "vision", "code": "<配對碼>" }`。
5. Vision Pro 會 listen `plantVisionRelay`。
6. 當 `payload.data.message == "成功抽幀"` 時，app 會更新辨識狀態並顯示 relay 來源的結果。

本機 simulator 測試時可用：

```text
http://127.0.0.1:8080
```

Vision Pro 實機連 Mac 上本機 relay 時可用：

```text
http://<Mac-IP>:8080
```

專案的 `Info.plist` 已加入 `NSAllowsLocalNetworking`，方便本機或區網測試。跨校園網路或正式測試仍建議使用 HTTPS relay domain。

Vision Pro 端接收成功抽幀後，目前會沿用本地植物資料顯示辨識結果，note 會標示這是從 Mac relay 收到「成功抽幀」；後續真正植物辨識結果可直接擴充 `frameResult` payload。

## 部署注意

本機測試可用：

```text
http://127.0.0.1:8080
```

實機跨校園網路建議：

```text
https://your-relay-domain
```

部署時建議：

- relay server 跑在可公開連線的主機。
- 前面用 HTTPS reverse proxy，例如 Caddy、nginx、Cloudflare Tunnel 或其他支援 WebSocket 的平台。
- Mac 和 Vision Pro 都使用 outbound HTTPS/WSS 連線。
- 不要依賴 LAN broadcast、Bonjour 或 Vision Pro 直接連 Mac。
