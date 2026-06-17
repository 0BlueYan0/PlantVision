import SwiftUI

/// 「生長動畫」分頁:開啟生長動畫 immersive space,並控制 播放/暫停/階段切換/重播 的 2D 面板。
/// 比照 `ManualPlacementView` 的開/關空間慣例(openImmersiveSpace / dismissImmersiveSpace + 轉場鎖)。
struct GrowthView: View {
    @EnvironmentObject private var appModel: PlantVisionModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

    @State private var isOpen = false
    @State private var isTransitioning = false   // 轉場中鎖住按鈕,避免並發 open/dismiss

    var body: some View {
        NavigationStack {
            HStack(spacing: 24) {
                preview
                controls
            }
            .padding(28)
            .navigationTitle("生長動畫")
        }
    }

    private var preview: some View {
        VStack(spacing: 20) {
            Image(systemName: "play.circle.fill")
                .font(.system(size: 120))
                .foregroundStyle(.green)
                .padding()
            Text("3D 生長動畫")
                .font(.largeTitle.weight(.bold))
            Text("以程式生成的植物模型,從發芽、長葉、開花到成熟逐階段平滑展示生長過程。開啟空間後可播放/暫停、直接切到某個階段,或從頭重播。")
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
            Text("動畫控制")
                .font(.title2.weight(.semibold))

            Button {
                Task {
                    isTransitioning = true
                    await dismissImmersiveSpace()   // 關掉任何已開的空間,避免衝突
                    let result = await openImmersiveSpace(id: PlantVisionModel.growthImmersiveSpaceID)
                    isOpen = (result == .opened)
                    isTransitioning = false
                }
            } label: {
                Label("開啟生長動畫空間", systemImage: "cube.transparent")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isTransitioning)

            GrowthControlsView()
                .disabled(!isOpen || isTransitioning)

            Button {
                Task {
                    isTransitioning = true
                    await dismissImmersiveSpace()
                    isOpen = false
                    isTransitioning = false
                }
            } label: {
                Label("關閉空間", systemImage: "xmark.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(!isOpen || isTransitioning)

            Divider()

            Label("捏合植物模型也可切換播放/暫停", systemImage: "hand.tap")
            Label("各階段以 scale / 透明度 / 位置平滑轉場", systemImage: "wand.and.stars")
        }
        .font(.callout)
        .frame(width: 360, alignment: .leading)
        .padding(22)
        .glassBackgroundEffect()
        // 由空間資訊卡「觀看生長動畫」CTA 進來時,空間已由 RootView 開啟,這裡同步狀態。
        .onChange(of: appModel.growthModeRequestToken) { _, _ in
            isOpen = true
        }
    }
}

/// 播放/暫停 + 階段切換(segmented) + 重播。可獨立放在 2D 面板或其他容器。
struct GrowthControlsView: View {
    @EnvironmentObject private var appModel: PlantVisionModel

    private var stageBinding: Binding<GrowthStage> {
        Binding(
            get: { appModel.selectedStage },
            set: { appModel.setStage($0) }   // 「切換」:跳到該階段並停止自動播放
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("目前階段:\(appModel.selectedStage.title)")
                    .font(.headline)
                Text(appModel.selectedStage.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                appModel.toggleGrowthPlayback()
            } label: {
                Label(appModel.isGrowthPlaying ? "暫停" : "播放",
                      systemImage: appModel.isGrowthPlaying ? "pause.fill" : "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Picker("階段", selection: stageBinding) {
                ForEach(GrowthStage.allCases) { stage in
                    Text(stage.title).tag(stage)
                }
            }
            .pickerStyle(.segmented)

            Button {
                appModel.replayGrowth()
            } label: {
                Label("從頭重播", systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }
}
