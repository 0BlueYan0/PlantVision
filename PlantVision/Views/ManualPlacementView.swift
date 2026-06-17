import SwiftUI

/// 「擺放」分頁:手動把 3D 植物模型放到地板上(不需物件追蹤)的 2D 控制面板。
struct ManualPlacementView: View {
    @EnvironmentObject private var appModel: PlantVisionModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

    /// 本頁目前開了哪一種 immersive space:模型擺放(無追蹤)或物件追蹤測試。
    private enum OpenSpace { case none, model, tracking }
    @State private var openSpace: OpenSpace = .none
    @State private var isTransitioning = false   // 轉場中(開/關空間)鎖住按鈕,避免並發 open/dismiss
    // TODO: openSpace 是本地狀態;若使用者用系統手勢(數位錶冠/home)關閉空間,這裡不會更新,
    // reset/close 按鈕會仍顯示可用(點下去無害:dismiss 已關空間是 no-op)。日後可由場景在 onDisappear
    // 更新 appModel 的已發布旗標來同步。

    var body: some View {
        NavigationStack {
            HStack(spacing: 24) {
                preview
                controls
            }
            .padding(28)
            .navigationTitle("擺放")
        }
    }

    private var preview: some View {
        VStack(spacing: 20) {
            Image(systemName: "leaf.circle.fill")
                .font(.system(size: 120))
                .foregroundStyle(Theme.accent)
                .padding()
            Text("手動擺放植物")
                .font(.largeTitle.weight(.bold))
            // 說明文字中的「馬纓丹」目前硬編碼,對應 catalog 目前唯一的植物;日後換植物時需一併更新。
            Text("把馬纓丹的 3D 模型放到你面前的地板上;靠近不同部位時,花/葉空間標籤會自動指向最近的那一個。不需要掃描或物件追蹤。")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Theme.panelPadding)
        .glassPanel()
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("擺放控制")
                .font(.title2.weight(.semibold))

            Button {
                Task {
                    isTransitioning = true
                    await dismissImmersiveSpace()   // 關掉任何已開的空間,避免衝突
                    let result = await openImmersiveSpace(id: PlantVisionModel.placementImmersiveSpaceID)
                    openSpace = (result == .opened) ? .model : .none
                    isTransitioning = false
                }
            } label: {
                Label("開啟空間並擺放", systemImage: "cube.transparent")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isTransitioning)

            Button {
                appModel.requestPlacementReset()
            } label: {
                Label("把植物拉回面前", systemImage: "arrow.uturn.backward")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            // reset 只對模型擺放有意義(bump placementResetToken;追蹤場景不觀察)。
            .disabled(openSpace != .model || isTransitioning)

            Button {
                Task {
                    isTransitioning = true
                    await dismissImmersiveSpace()
                    openSpace = .none
                    isTransitioning = false
                }
            } label: {
                Label("關閉空間", systemImage: "xmark.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(openSpace == .none || isTransitioning)

            Divider()

            // 測試用:跳過 Mac 辨識流程,直接啟動物件追蹤,把花/葉空間標籤貼到真實植物上。
            // 與「開啟空間並擺放」互斥——先 dismiss 再開,共用本頁的關閉/狀態邏輯。
            Text("測試")
                .font(.headline)
                .foregroundStyle(.secondary)

            Button {
                Task {
                    isTransitioning = true
                    await dismissImmersiveSpace()   // 關掉任何已開的空間,避免衝突
                    let result = await openImmersiveSpace(id: PlantVisionModel.immersiveSpaceID)
                    openSpace = (result == .opened) ? .tracking : .none
                    isTransitioning = false
                }
            } label: {
                Label("直接啟動物件追蹤(跳過辨識)", systemImage: "viewfinder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(isTransitioning)

            Label("跳過 Mac 辨識,直接用物件追蹤把花/葉標籤貼到真實植物(實機才有追蹤;模擬器顯示示意場景)", systemImage: "testtube.2")

            Divider()

            Label("拖曳植物可沿地板移動位置", systemImage: "hand.draw")
            Label("實機會貼合真實地板;模擬器用預設地板高度", systemImage: "ruler")
            Label("花/葉標籤指向離你最近的部位", systemImage: "tag")
        }
        .font(.callout)
        // 容器層套 .controlSize(.large),所有子按鈕一致放大到 visionOS 注視目標下限(EH-02 ≥ 60pt)。
        .controlSize(.large)
        .frame(width: 360, alignment: .leading)
        .padding(22)
        .glassPanel(cornerRadius: Theme.cardCorner)
    }
}
