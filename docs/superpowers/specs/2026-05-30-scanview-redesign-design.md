# ScanView Redesign Design

## Goal

Redesign `ScanView` around the visual language in `docs/DESIGN.md` while preserving visionOS-native interaction, glass surfaces, and the existing recognition behavior.

## Scope

The main visual work lives in `PlantVision/Views/ScanView.swift`. `PlantVision/PlantVisionApp.swift` and `PlantVision/Views/RootView.swift` can adjust the default window footprint so the scan workbench has enough horizontal space to show its panels together. `PlantVisionApp` also owns a secondary plant-detail window so detailed results can be placed independently in space. The relay client, history actions, and immersive-space action remain unchanged.

## Visual Direction

The screen becomes a low-chrome scan workbench with no primary scrolling surface. The hero controls, recognition result, and Relay settings are visible at the same time in separate glass panels. Recognition results appear as a product-style information tile with large plant naming, a confidence pill, source metadata, and chip grids for morphology and care advice. A "detach detail card" action opens the full plant detail view as a separate visionOS window that the user can place next to the main workbench.

The web design tokens are translated to native SwiftUI:

- Action color: Apple-style blue for every tappable accent in `ScanView`.
- Surfaces: native glass panels plus white/parchment and near-black inspired fills where useful.
- Typography: system display and text weights, avoiding custom font dependencies.
- Depth: no extra card shadows; glass and surface contrast provide hierarchy.
- Shapes: pill CTAs and compact utility capsules, with larger rounded glass panels appropriate for visionOS.

## Behavior

Existing actions stay mapped to the same model calls:

- Connect Relay calls `appModel.connectRelay()`.
- Demo sample calls `await appModel.runDemoRecognition()`.
- Open space calls `openImmersiveSpace(id:)` and remains disabled until a result exists.
- Detach detail card calls `openWindow(id:)` for the plant-detail window and remains available only when a result exists.
- Result actions add to history and place the spatial label.

Copy must not mention the Vision Pro main camera path. Relay is the formal recognition entry point and Demo remains a local path for checking the result display and spatial-label flow.

## Responsiveness

Wide layouts use a three-panel composition: scan controls, result tile, and Relay utility. The app opens wider by default so these panels can sit side-by-side. Compact fallback stacks the panels, but the normal Scan workbench is designed to keep the primary workflow visible without scrolling.

## Verification

Run a fresh visionOS simulator build for the `PlantVision` scheme after implementation. Since this project currently has no `PlantVision` test target, compilation is the primary automated verification for this UI-only refactor.
