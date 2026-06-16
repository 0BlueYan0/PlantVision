import SwiftUI

struct PlantDetailView: View {
    let result: RecognitionResult?
    /// 最新枯萎程度（與植物辨識獨立的另一條訊號）。nil 時不顯示枯萎卡。
    var wither: WitherStatus?

    var body: some View {
        NavigationStack {
            Group {
                if result != nil || wither != nil {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 22) {
                            if let result {
                                ResultHeader(result: result)
                                Divider()
                                InfoRows(plant: result.plant, confidence: result.confidence)
                            }
                            if let wither {
                                if result != nil { Divider() }
                                WitherCard(wither: wither, plantID: result?.plant.id)
                            }
                        }
                        .padding(26)
                        .frame(maxWidth: 680, alignment: .leading)
                        .glassBackgroundEffect()
                        .padding(28)
                    }
                } else {
                    EmptyStateView(
                        systemImage: "info.circle",
                        title: "等待辨識資料",
                        message: "先到 Scan 連線 Relay 或執行 Demo 樣本辨識。"
                    )
                }
            }
            .navigationTitle("資訊展示")
        }
    }
}

/// 枯萎程度卡片：等級徽章 + 百分比 + 一般性照護建議。
private struct WitherCard: View {
    let wither: WitherStatus
    let plantID: String?

    private var advice: WitherAdvice {
        WitherAdviceCatalog.advice(plantID: plantID, level: wither.level)
    }

    private var accentColor: Color {
        switch WitherLevel.clampedLevel(wither.level) {
        case WitherLevel.healthy: .green
        case WitherLevel.mild: .yellow
        case WitherLevel.moderate: .orange
        default: .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Label("枯萎程度", systemImage: "leaf.arrow.triangle.circlepath")
                    .font(.title3.weight(.semibold))
                Spacer()
                Text(wither.levelLabel)
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(accentColor.opacity(0.22), in: Capsule())
                    .foregroundStyle(accentColor)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(wither.percentText)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(accentColor)
                Text("枯萎面積比例")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: wither.ratio)
                .tint(accentColor)

            Text(advice.summary)
                .font(.callout.weight(.medium))

            VStack(alignment: .leading, spacing: 6) {
                ForEach(advice.actions, id: \.self) { action in
                    Label(action, systemImage: "checkmark.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Text(WitherAdviceCatalog.generalNote)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 68))
                .foregroundStyle(.green)
            Text(title)
                .font(.title2.weight(.semibold))
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
