import SwiftUI

/// 錨在真實/擺放植物旁的「整株」空間資訊卡(對齊提案 p.5):中文名、學名、科屬、原產地、
/// 形態特徵、照護建議、辨識信心,外加「觀看生長動畫 / 加入歷史紀錄」兩個 CTA。
/// 與只標單一部位的 `SpatialPartLabel` 互補——那個指花/葉,這張呈現整株資訊。
struct SpatialInfoCard: View {
    @EnvironmentObject private var appModel: PlantVisionModel
    let plant: Plant

    @State private var addedToHistory = false

    /// 信心/來源:若 relay 的 currentResult 正好是同一株,沿用其數值;否則用 demo 後備。
    private var resolved: (confidence: Double, source: RecognitionSource) {
        if let result = appModel.currentResult, result.plant.id == plant.id {
            return (result.confidence, result.source)
        }
        return (plant.demoConfidence, .demo)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(plant.chineseName)
                    .font(.title2.weight(.bold))
                Text(plant.scientificName)
                    .font(.callout)
                    .italic()
                    .foregroundStyle(.secondary)
            }

            Divider()

            labeledRow("科屬", "\(plant.family) / \(plant.genus)")
            labeledRow("原產地", plant.origin)
            chipSection("形態特徵", items: plant.morphology, systemImage: "leaf")
            chipSection("照護建議", items: plant.careAdvice, systemImage: "drop")

            HStack {
                Text("辨識信心")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(resolved.confidence * 100))%")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.green)
            }

            Divider()

            HStack(spacing: 10) {
                Button {
                    appModel.requestGrowthMode()
                } label: {
                    Label("觀看生長動畫", systemImage: "play.circle")
                }

                Button {
                    appModel.addToHistory(plant: plant, confidence: resolved.confidence, source: resolved.source)
                    addedToHistory = true
                } label: {
                    Label(addedToHistory ? "已加入歷史" : "加入歷史紀錄",
                          systemImage: addedToHistory ? "checkmark" : "plus.rectangle.on.folder")
                }
                .disabled(addedToHistory)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(16)
        .frame(width: 320, alignment: .leading)
        .glassBackgroundEffect()
    }

    private func labeledRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .font(.caption)
                .multilineTextAlignment(.trailing)
        }
    }

    private func chipSection(_ title: String, items: [String], systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 6)], alignment: .leading, spacing: 6) {
                ForEach(items, id: \.self) { item in
                    Label(item, systemImage: systemImage)
                        .font(.caption2)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
            }
        }
    }
}
