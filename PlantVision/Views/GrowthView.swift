import SwiftUI

struct GrowthView: View {
    @EnvironmentObject private var appModel: PlantVisionModel

    var body: some View {
        NavigationStack {
            HStack(spacing: 24) {
                growthPreview
                controls
            }
            .padding(28)
            .navigationTitle("生長動畫")
        }
    }

    private var growthPreview: some View {
        VStack(spacing: 20) {
            PlantIllustration(stage: appModel.selectedStage)
                .frame(width: 340, height: 340)
                .padding()

            Text(appModel.selectedStage.title)
                .font(.largeTitle.weight(.bold))
            Text(appModel.selectedStage.detail)
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
            Text("階段控制")
                .font(.title2.weight(.semibold))

            ForEach(GrowthStage.allCases) { stage in
                Button {
                    appModel.setStage(stage)
                } label: {
                    HStack {
                        Image(systemName: appModel.selectedStage == stage ? "largecircle.fill.circle" : "circle")
                        VStack(alignment: .leading) {
                            Text(stage.title)
                                .font(.headline)
                            Text(stage.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                .padding(12)
                .background(appModel.selectedStage == stage ? .green.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 8))
            }

            Divider()

            Button {
                appModel.toggleGrowthPlayback()
            } label: {
                Label(appModel.isGrowthPlaying ? "暫停動畫" : "播放動畫", systemImage: appModel.isGrowthPlaying ? "pause.fill" : "play.fill")
            }
            .buttonStyle(.borderedProminent)

            Text("空間場景會同步顯示目前階段的 3D 植物模型。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(width: 360, alignment: .leading)
        .padding(22)
        .glassBackgroundEffect()
    }
}

struct PlantIllustration: View {
    let stage: GrowthStage

    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 8)
                .fill(.green.opacity(0.08))

            VStack(spacing: 0) {
                flower
                    .opacity(stage == .flowering || stage == .mature ? 1 : 0)
                    .scaleEffect(stage == .flowering ? 0.8 : 1)
                leaves
                Rectangle()
                    .fill(.green)
                    .frame(width: 16, height: CGFloat(120 * stage.progress))
                RoundedRectangle(cornerRadius: 8)
                    .fill(.brown.opacity(0.45))
                    .frame(width: 150, height: 58)
            }
            .animation(.smooth(duration: 0.45), value: stage)
            .padding(.bottom, 36)
        }
    }

    private var leaves: some View {
        HStack(spacing: 0) {
            leaf(rotation: -35, scale: 0.72 + stage.progress * 0.5)
            leaf(rotation: 35, scale: 0.72 + stage.progress * 0.5)
        }
        .opacity(stage == .sprout ? 0.45 : 1)
    }

    private var flower: some View {
        Image(systemName: "camera.macro")
            .font(.system(size: 54))
            .foregroundStyle(.yellow, .green)
    }

    private func leaf(rotation: Double, scale: Double) -> some View {
        Image(systemName: "leaf.fill")
            .font(.system(size: 82))
            .foregroundStyle(.green)
            .rotationEffect(.degrees(rotation))
            .scaleEffect(scale)
    }
}
