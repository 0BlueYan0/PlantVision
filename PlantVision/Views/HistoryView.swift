import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var appModel: PlantVisionModel

    var body: some View {
        NavigationStack {
            Group {
                if appModel.history.isEmpty {
                    EmptyStateView(
                        systemImage: "clock.badge.questionmark",
                        title: "尚無歷史紀錄",
                        message: "辨識植物後可以把結果加入紀錄，方便後續查詢與整理。"
                    )
                } else {
                    List {
                        ForEach(appModel.history) { record in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(record.chineseName)
                                        .font(.headline)
                                    Spacer()
                                    Text("\(Int(record.confidence * 100))%")
                                        .font(.callout.monospacedDigit())
                                        .foregroundStyle(.green)
                                }
                                Text(record.scientificName)
                                    .italic()
                                Text("\(record.source) · \(record.createdAt.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 6)
                        }
                    }
                }
            }
            .navigationTitle("歷史紀錄")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        appModel.clearHistory()
                    } label: {
                        Label("清除", systemImage: "trash")
                    }
                    .disabled(appModel.history.isEmpty)
                }
            }
        }
    }
}
