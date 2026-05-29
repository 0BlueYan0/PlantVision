import SwiftUI

struct ScanView: View {
    @EnvironmentObject private var appModel: PlantVisionModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace

    var body: some View {
        NavigationStack {
            HStack(spacing: 24) {
                scanPanel
                resultPanel
            }
            .padding(28)
            .navigationTitle("植物辨識")
        }
    }

    private var scanPanel: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("Vision Pro Demo", systemImage: "visionpro")
                .font(.title2.weight(.semibold))

            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.green.opacity(0.12))
                VStack(spacing: 18) {
                    Image(systemName: "viewfinder.circle.fill")
                        .font(.system(size: 86))
                        .foregroundStyle(.green)
                    Text(appModel.recognitionState.message)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
                    Text("第一優先嘗試主鏡頭 CameraFrameProvider；若 entitlement、裝置或模擬器不支援，會自動切到 Demo Mode。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 460)
                }
                .padding()
            }
            .frame(minHeight: 330)

            relayControls

            HStack(spacing: 12) {
                Button {
                    appModel.connectRelay()
                } label: {
                    Label("連線 Relay", systemImage: "link")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    appModel.scanWithCameraFirst()
                } label: {
                    Label("主鏡頭 Demo", systemImage: "camera.viewfinder")
                }

                Button {
                    Task {
                        await appModel.runDemoRecognition()
                    }
                } label: {
                    Label("Demo 樣本", systemImage: "photo")
                }

                Button {
                    Task {
                        _ = await openImmersiveSpace(id: PlantVisionModel.immersiveSpaceID)
                    }
                } label: {
                    Label("開啟空間", systemImage: "cube.transparent")
                }
                .disabled(appModel.currentResult == nil)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .glassBackgroundEffect()
    }

    private var relayControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Socket.IO Relay")
                .font(.headline)

            Text(appModel.relayStatus.message)
                .font(.callout)
                .foregroundStyle(.secondary)

            TextField("Relay URL", text: $appModel.relayURLText)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            TextField("配對碼", text: $appModel.relayPairingCode)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
    }

    @ViewBuilder
    private var resultPanel: some View {
        if let result = appModel.currentResult {
            VStack(alignment: .leading, spacing: 18) {
                ResultHeader(result: result)
                Divider()
                InfoRows(plant: result.plant, confidence: result.confidence)

                HStack {
                    Button {
                        appModel.addCurrentResultToHistory()
                    } label: {
                        Label("加入歷史紀錄", systemImage: "plus.rectangle.on.folder")
                    }

                    Button {
                        Task {
                            _ = await openImmersiveSpace(id: PlantVisionModel.immersiveSpaceID)
                        }
                    } label: {
                        Label("放置空間標籤", systemImage: "mappin.and.ellipse")
                    }
                }
            }
            .frame(width: 390, alignment: .leading)
            .padding(22)
            .glassBackgroundEffect()
        } else {
            VStack(spacing: 18) {
                Image(systemName: "leaf.circle")
                    .font(.system(size: 72))
                    .foregroundStyle(.green)
                Text("尚無辨識結果")
                    .font(.title3.weight(.semibold))
                Text("開始辨識後會顯示植物名稱、形態特徵、照護建議與信心分數。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(width: 390)
            .frame(minHeight: 460)
            .padding(22)
            .glassBackgroundEffect()
        }
    }
}

struct ResultHeader: View {
    let result: RecognitionResult

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(result.plant.chineseName)
                    .font(.largeTitle.weight(.bold))
                Spacer()
                Text("\(Int(result.confidence * 100))%")
                    .font(.title2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.green)
            }
            Text(result.plant.scientificName)
                .font(.title3)
                .italic()
            Label(result.source.rawValue, systemImage: result.source == .camera ? "camera" : "photo")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(result.note)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

struct InfoRows: View {
    let plant: Plant
    let confidence: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            LabeledContent("科屬", value: "\(plant.family) / \(plant.genus)")
            LabeledContent("原產地", value: plant.origin)

            VStack(alignment: .leading, spacing: 8) {
                Text("形態特徵")
                    .font(.headline)
                ChipGrid(items: plant.morphology, systemImage: "leaf")
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("照護建議")
                    .font(.headline)
                ChipGrid(items: plant.careAdvice, systemImage: "drop")
            }

            Gauge(value: confidence) {
                Text("辨識信心")
            }
            .gaugeStyle(.accessoryLinearCapacity)
            .tint(.green)
        }
    }
}

struct ChipGrid: View {
    let items: [String]
    let systemImage: String

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(items, id: \.self) { item in
                Label(item, systemImage: systemImage)
                    .font(.caption)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}
