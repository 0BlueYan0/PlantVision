import SwiftUI

@main
struct PlantVisionApp: App {
    @StateObject private var appModel = PlantVisionModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appModel)
        }
        .defaultSize(width: 1320, height: 760)

        WindowGroup(id: PlantVisionModel.plantDetailWindowID) {
            PlantDetailView(result: appModel.currentResult)
                .environmentObject(appModel)
        }
        .defaultSize(width: 560, height: 620)

        ImmersiveSpace(id: PlantVisionModel.immersiveSpaceID) {
            SpatialPlantSceneView()
                .environmentObject(appModel)
        }

        ImmersiveSpace(id: PlantVisionModel.placementImmersiveSpaceID) {
            ManualPlacementSceneView()
                .environmentObject(appModel)
        }

        ImmersiveSpace(id: PlantVisionModel.objectAlignedPlacementImmersiveSpaceID) {
            ObjectAlignedPlacementSceneView()
                .environmentObject(appModel)
        }
    }
}
