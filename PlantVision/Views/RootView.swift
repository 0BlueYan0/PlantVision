import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appModel: PlantVisionModel

    var body: some View {
        TabView {
            ScanView()
                .tabItem {
                    Label("Scan", systemImage: "viewfinder")
                }

            PlantDetailView(result: appModel.currentResult)
                .tabItem {
                    Label("Detail", systemImage: "leaf")
                }

            GrowthView()
                .tabItem {
                    Label("Growth", systemImage: "cube")
                }

            HistoryView()
                .tabItem {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
        }
        .tint(.green)
    }
}
