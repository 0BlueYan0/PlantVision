# ScanView Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign `ScanView` with an Apple-inspired visual rhythm while preserving visionOS-native controls and existing scan behavior.

**Architecture:** Keep most visual changes inside `PlantVision/Views/ScanView.swift`. Adjust the app/root default window footprint so Scan can show controls, result, and Relay status simultaneously without a primary scroll surface. Add a secondary plant-detail `WindowGroup` so detailed results can be placed independently in MR space.

**Tech Stack:** SwiftUI, visionOS glass surfaces, existing `PlantVisionModel`, existing recognition result components.

---

### Task 1: Recompose ScanView Layout

**Files:**
- Modify: `PlantVision/Views/ScanView.swift`
- Modify: `PlantVision/PlantVisionApp.swift`
- Modify: `PlantVision/Views/RootView.swift`

- [x] Replace the previous tool-panel structure with a wide three-panel layout.
- [x] Add a hero scan panel for recognition state and scan actions.
- [x] Move Relay URL and pairing code into a quieter utility panel.
- [x] Remove the primary `ScrollView` from Scan so all core panels are visible together.

### Task 2: Redesign Result Presentation

**Files:**
- Modify: `PlantVision/Views/ScanView.swift`

- [x] Convert result content into a product-style information tile.
- [x] Add a confidence pill and source chip.
- [x] Keep history and spatial-label actions wired to the existing model calls.

### Task 3: Preserve Behavior and Verify

**Files:**
- Modify: `PlantVision/Views/ScanView.swift`
- Modify: `PlantVision/PlantVisionApp.swift`
- Modify: `PlantVision/Stores/PlantVisionModel.swift`

- [x] Preserve `connectRelay()`, `runDemoRecognition()`, `addCurrentResultToHistory()`, and `openImmersiveSpace(id:)` call sites.
- [x] Add a plant-detail secondary window and wire Scan's result action to `openWindow(id:)`.
- [x] Run `xcodebuild -project PlantVision.xcodeproj -scheme PlantVision -destination 'platform=visionOS Simulator,name=Apple Vision Pro,OS=26.4' build`.
