import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appModel: PlantVisionModel
    @State private var selectedSection: WorkbenchSection = .scan

    var body: some View {
        // visionOS 會把 TabView 的分頁自動渲染成視窗左側的 leading ornament(HIG WN-04 / OR-03),
        // 免費獲得注視 hover 回饋(EH-03)、選取態與 VoiceOver,取代原本自製的 104pt 玻璃 rail。
        TabView(selection: $selectedSection) {
            ForEach(WorkbenchSection.allCases) { section in
                Tab(section.title, systemImage: section.systemImage, value: section) {
                    content(for: section)
                }
            }
        }
        .frame(minWidth: 1120, minHeight: 620)
        .tint(Theme.accent)
    }

    @ViewBuilder
    private func content(for section: WorkbenchSection) -> some View {
        switch section {
        case .scan:
            ScanView()
        case .detail:
            // Detail 改為常駐分頁:無辨識結果時 PlantDetailView 會顯示 empty state,
            // 取代原本 rail 上那顆只有 44pt(違反 EH-02 60pt)又無 hover 的動態按鈕。
            PlantDetailView(result: appModel.currentResult)
        case .place:
            ManualPlacementView()
        case .history:
            HistoryView()
        }
    }
}

enum WorkbenchSection: String, CaseIterable, Identifiable {
    case scan
    case detail
    case place
    case history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .scan: "Scan"
        case .detail: "Detail"
        case .place: "Place"
        case .history: "History"
        }
    }

    var systemImage: String {
        switch self {
        case .scan: "viewfinder"
        case .detail: "leaf"
        case .place: "move.3d"
        case .history: "clock.arrow.circlepath"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .scan: "開啟掃描工作區"
        case .detail: "開啟植物資訊"
        case .place: "開啟手動擺放工作區"
        case .history: "開啟歷史紀錄"
        }
    }
}
