import SwiftUI

/// 「擺放」分頁:手動把 3D 植物模型放到地板上(不需物件追蹤)的 2D 控制面板。
struct ManualPlacementView: View {
    @EnvironmentObject private var appModel: PlantVisionModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

    @State private var isSpaceOpen = false

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
                .foregroundStyle(.green)
                .padding()
            Text("手動擺放植物")
                .font(.largeTitle.weight(.bold))
            Text("把馬纓丹的 3D 模型放到你面前的地板上;靠近不同部位時,花/葉空間標籤會自動指向最近的那一個。不需要掃描或物件追蹤。")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
        .glassBackgroundEffect()
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("擺放控制")
                .font(.title2.weight(.semibold))

            Button {
                Task {
                    await dismissImmersiveSpace()   // 關掉任何已開的空間,避免衝突
                    let result = await openImmersiveSpace(id: PlantVisionModel.placementImmersiveSpaceID)
                    isSpaceOpen = (result == .opened)
                }
            } label: {
                Label("開啟空間並擺放", systemImage: "cube.transparent")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Button {
                appModel.requestPlacementReset()
            } label: {
                Label("把植物拉回面前", systemImage: "arrow.uturn.backward")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(!isSpaceOpen)

            Button {
                Task {
                    await dismissImmersiveSpace()
                    isSpaceOpen = false
                }
            } label: {
                Label("關閉空間", systemImage: "xmark.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(!isSpaceOpen)

            Divider()

            Label("拖曳植物可沿地板移動位置", systemImage: "hand.draw")
            Label("實機會貼合真實地板;模擬器用預設地板高度", systemImage: "ruler")
            Label("花/葉標籤指向離你最近的部位", systemImage: "tag")
        }
        .font(.callout)
        .frame(width: 360, alignment: .leading)
        .padding(22)
        .glassBackgroundEffect()
    }
}
