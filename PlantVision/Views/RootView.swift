import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appModel: PlantVisionModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @State private var selectedSection: WorkbenchSection = .scan
    @State private var isSwitchingSpace = false

    var body: some View {
        HStack(spacing: 18) {
            workbenchRail
            sectionContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(18)
        .frame(minWidth: 1120, minHeight: 620)
        .tint(.green)
        // 空間資訊卡「觀看生長動畫」CTA → 切到 Growth 分頁並換成生長動畫 immersive space。
        .onChange(of: appModel.growthModeRequestToken) { _, _ in
            switchToGrowthSpace()
        }
    }

    /// 單一時間只能開一個 immersive space:先關掉目前的(追蹤/擺放),再開生長動畫空間。
    private func switchToGrowthSpace() {
        guard !isSwitchingSpace else { return }
        selectedSection = .growth
        Task {
            isSwitchingSpace = true
            await dismissImmersiveSpace()
            _ = await openImmersiveSpace(id: PlantVisionModel.growthImmersiveSpaceID)
            isSwitchingSpace = false
        }
    }

    private var workbenchRail: some View {
        VStack(spacing: 12) {
            VStack(spacing: 8) {
                Image(systemName: "leaf.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(.green)
                Text("PlantVision")
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.bottom, 12)

            ForEach(WorkbenchSection.allCases) { section in
                Button {
                    selectedSection = section
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: section.systemImage)
                            .font(.title2)
                        Text(section.title)
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .frame(width: 72, height: 64)
                    .contentShape(RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                .foregroundStyle(selectedSection == section ? .green : .primary)
                .background(
                    selectedSection == section ? .green.opacity(0.16) : .clear,
                    in: RoundedRectangle(cornerRadius: 16)
                )
                .accessibilityLabel(section.accessibilityLabel)
            }

            Spacer(minLength: 12)

            Button {
                selectedSection = .detail
            } label: {
                Image(systemName: appModel.currentResult == nil ? "leaf" : "leaf.fill")
                    .font(.title3)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(appModel.currentResult == nil ? Color.secondary : Color.green)
            .background(.white.opacity(0.08), in: Circle())
            .disabled(appModel.currentResult == nil)
            .accessibilityLabel("查看目前辨識結果")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 18)
        .frame(width: 104)
        .frame(maxHeight: .infinity)
        .glassBackgroundEffect()
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch selectedSection {
        case .scan:
            ScanView()
        case .detail:
            PlantDetailView(result: appModel.currentResult, health: appModel.plantHealth)
        case .place:
            ManualPlacementView()
        case .growth:
            GrowthView()
        case .history:
            HistoryView()
        }
    }
}

private enum WorkbenchSection: String, CaseIterable, Identifiable {
    case scan
    case detail
    case place
    case growth
    case history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .scan: "Scan"
        case .detail: "Detail"
        case .place: "Place"
        case .growth: "Growth"
        case .history: "History"
        }
    }

    var systemImage: String {
        switch self {
        case .scan: "viewfinder"
        case .detail: "leaf"
        case .place: "move.3d"
        case .growth: "play.circle"
        case .history: "clock.arrow.circlepath"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .scan: "開啟掃描工作區"
        case .detail: "開啟植物資訊"
        case .place: "開啟手動擺放工作區"
        case .growth: "開啟生長動畫工作區"
        case .history: "開啟歷史紀錄"
        }
    }
}
