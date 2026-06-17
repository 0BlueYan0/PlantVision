import SwiftUI

struct PlantDetailView: View {
    let result: RecognitionResult?

    var body: some View {
        NavigationStack {
            Group {
                if let result {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 22) {
                            ResultHeader(result: result)
                            Divider()
                            InfoRows(plant: result.plant, confidence: result.confidence)
                        }
                        .padding(26)
                        .frame(maxWidth: 680, alignment: .leading)
                        .glassPanel()
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

struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 68))
                .foregroundStyle(Theme.accent)
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
