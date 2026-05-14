import SwiftUI

@main
struct PlantVisionApp: App {
    @StateObject private var appModel = PlantVisionModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appModel)
        }
        .windowStyle(.volumetric)
        .defaultSize(width: 980, height: 720, depth: 80)

        ImmersiveSpace(id: PlantVisionModel.immersiveSpaceID) {
            SpatialPlantSceneView()
                .environmentObject(appModel)
        }
    }
}
