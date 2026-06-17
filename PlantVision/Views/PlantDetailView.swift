import SwiftUI

struct PlantDetailView: View {
    let result: RecognitionResult?
    /// 最新綜合植物健康（枯萎＋黃化＋趨勢，與植物辨識獨立的另一條訊號）。
    /// nil 或無任何訊號時不顯示健康卡。
    var health: PlantHealthStatus?

    private var showsHealth: Bool { health?.hasAnySignal ?? false }

    var body: some View {
        NavigationStack {
            Group {
                if result != nil || showsHealth {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 22) {
                            if let result {
                                ResultHeader(result: result)
                                Divider()
                                InfoRows(plant: result.plant, confidence: result.confidence)
                            }
                            if let health, showsHealth {
                                if result != nil { Divider() }
                                PlantHealthCard(health: health, plantID: result?.plant.id)
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

/// 植物健康卡片：整體等級徽章 + 趨勢修飾語 + 各子訊號（枯萎／黃化）比例 + 一般性照護建議。
private struct PlantHealthCard: View {
    let health: PlantHealthStatus
    let plantID: String?

    /// 整體等級（卡片只在 hasAnySignal 時顯示，故此處必有值；保險起見以 0 後備）。
    private var overallLevel: Int { health.overallLevel ?? 0 }

    private var advice: WitherAdvice {
        WitherAdviceCatalog.advice(plantID: plantID, level: overallLevel)
    }

    private func color(forLevel level: Int) -> Color {
        switch min(max(level, 0), 3) {
        case 0: .green
        case 1: .yellow
        case 2: .orange
        default: .red
        }
    }

    private var accentColor: Color { color(forLevel: overallLevel) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Label("植物健康", systemImage: "heart.text.square")
                    .font(.title3.weight(.semibold))
                Spacer()
                if let overallLabel = health.overallLabel {
                    Text(overallLabel)
                        .font(.callout.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(accentColor.opacity(0.22), in: Capsule())
                        .foregroundStyle(accentColor)
                        .accessibilityLabel("整體健康：\(overallLabel)")
                }
            }

            if let trend = health.trend, let modifier = health.trendModifier {
                Label(modifier, systemImage: trend.systemImage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if let wither = health.wither {
                SignalRow(
                    title: "枯萎面積比例",
                    percentText: wither.percentText,
                    levelLabel: wither.levelLabel,
                    ratio: wither.ratio,
                    tint: color(forLevel: wither.level)
                )
            }

            if let yellowing = health.yellowing {
                SignalRow(
                    title: "葉片黃化比例",
                    percentText: yellowing.percentText,
                    levelLabel: yellowing.levelLabel,
                    ratio: yellowing.ratio,
                    tint: color(forLevel: yellowing.level)
                )
                if let hint = health.yellowingHint {
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

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

/// 單一健康子訊號的一列：標題 + 等級徽章 + 百分比大字 + 進度條。
private struct SignalRow: View {
    let title: String
    let percentText: String
    let levelLabel: String
    let ratio: Double
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.callout.weight(.medium))
                Spacer()
                Text(levelLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(percentText)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(tint)
                ProgressView(value: ratio)
                    .tint(tint)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(percentText)，\(levelLabel)")
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
