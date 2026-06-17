import SwiftUI

struct ScanView: View {
    @EnvironmentObject private var appModel: PlantVisionModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                contentLayout(size: proxy.size)
                    .padding(28)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("PlantVision")
            .tint(Theme.accent)
        }
    }

    @ViewBuilder
    private func contentLayout(size: CGSize) -> some View {
        if size.width < 940 {
            VStack(spacing: 16) {
                resultPanel
                relayUtilityPanel
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HStack(alignment: .top, spacing: 24) {
                resultPanel
                relayUtilityPanel
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var relayUtilityPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Socket.IO Relay")
                        .font(.headline)
                    Text(appModel.relayStatus.message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                relayStatusPill
            }

            VStack(spacing: 12) {
                TextField("Relay URL", text: $appModel.relayURLText)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                TextField("配對碼", text: $appModel.relayPairingCode)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            // Relay 是唯一辨識入口,連線按鈕直接放在這個工具面板內。
            Button {
                appModel.connectRelay()
            } label: {
                Label("連線 Relay", systemImage: "link")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 8) {
                Label("Mac 端抽幀與分類", systemImage: "macbook.and.visionpro")
                Label("Vision Pro 顯示結果與空間標籤", systemImage: "cube.transparent")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(minWidth: 240, maxWidth: 290, maxHeight: .infinity, alignment: .topLeading)
        .glassPanel(cornerRadius: Theme.cardCorner)
    }

    @ViewBuilder
    private var resultPanel: some View {
        if let result = appModel.currentResult {
            VStack(alignment: .leading, spacing: 20) {
                ScanResultHeader(result: result, isHolding: appModel.isHolding)
                    .contentShape(Rectangle())
                    .onTapGesture { appModel.toggleHold() }
                ScanInfoRows(plant: result.plant, confidence: result.confidence)

                Text(appModel.isHolding ? "已鎖定：捏合結果卡即可解鎖。" : "提示：捏合結果卡可鎖定，看資訊卡 / App 視窗時不會被判成背景而消失。")
                    .font(.caption)
                    .foregroundStyle(appModel.isHolding ? .orange : .secondary)
                    .fixedSize(horizontal: false, vertical: true)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], alignment: .leading, spacing: 12) {
                    Button {
                        openWindow(id: PlantVisionModel.plantDetailWindowID)
                    } label: {
                        Label("分離資訊卡", systemImage: "rectangle.on.rectangle")
                    }

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

                    Button {
                        Task {
                            // 同時只能開一個 immersive space:先關掉任何已開的再開,避免 .error。
                            await dismissImmersiveSpace()
                            _ = await openImmersiveSpace(id: PlantVisionModel.objectAlignedPlacementImmersiveSpaceID)
                        }
                    } label: {
                        Label("放置虛擬模型", systemImage: "cube.transparent")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(Theme.panelPadding)
            .glassPanel()
        } else {
            VStack(spacing: 16) {
                Image(systemName: "leaf")
                    .font(.system(size: 68, weight: .light))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("等待辨識結果")
                    .font(.title2.weight(.semibold))
                Text("辨識完成後會在這裡顯示植物名稱、來源、特徵與照護資訊。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(Theme.panelPadding)
            .glassPanel()
        }
    }

    private var relayStatusPill: some View {
        Label(relayStatusTitle, systemImage: relayStatusIcon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(relayStatusTint)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(relayStatusTint.opacity(0.12), in: Capsule())
    }

    private var relayStatusTitle: String {
        switch appModel.relayStatus {
        case .disconnected:
            "Offline"
        case .connecting:
            "Connecting"
        case .connected, .joined:
            "Online"
        case .failed:
            "Failed"
        }
    }

    private var relayStatusIcon: String {
        switch appModel.relayStatus {
        case .disconnected:
            "circle"
        case .connecting:
            "arrow.triangle.2.circlepath"
        case .connected, .joined:
            "checkmark.circle.fill"
        case .failed:
            "exclamationmark.circle.fill"
        }
    }

    private var relayStatusTint: Color {
        switch appModel.relayStatus {
        case .connected, .joined:
            Theme.accent
        case .failed:
            .red
        default:
            .secondary
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
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .layoutPriority(1)
                Spacer()
                Text("\(Int(result.confidence * 100))%")
                    .font(.title2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.green)
            }
            Text(result.plant.scientificName)
                .font(.title3)
                .italic()
            Label(result.source.rawValue, systemImage: result.source == .relay ? "macbook.and.visionpro" : "photo")
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

private struct ScanResultHeader: View {
    let result: RecognitionResult
    var isHolding: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(result.plant.chineseName)
                        .font(.largeTitle.weight(.semibold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.72)
                        .layoutPriority(1)
                    Text(result.plant.scientificName)
                        .font(.title3)
                        .italic()
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                ConfidencePill(confidence: result.confidence)
            }

            HStack(spacing: 8) {
                Label(result.source.rawValue, systemImage: sourceIcon)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Theme.accent.opacity(0.12), in: Capsule())

                if isHolding {
                    Label("已鎖定", systemImage: "lock.fill")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(.orange.opacity(0.14), in: Capsule())
                        .accessibilityLabel("結果已鎖定")
                }
            }

            Text(result.note)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var sourceIcon: String {
        switch result.source {
        case .demo:
            "photo"
        case .relay:
            "macbook.and.visionpro"
        }
    }
}

private struct ScanInfoRows: View {
    let plant: Plant
    let confidence: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            LabeledContent("科屬", value: "\(plant.family) / \(plant.genus)")
            LabeledContent("原產地", value: plant.origin)

            VStack(alignment: .leading, spacing: 8) {
                Text("形態特徵")
                    .font(.headline)
                ScanChipGrid(items: plant.morphology, systemImage: "leaf")
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("照護建議")
                    .font(.headline)
                ScanChipGrid(items: plant.careAdvice, systemImage: "drop")
            }

            Gauge(value: confidence) {
                Text("辨識信心")
            }
            .gaugeStyle(.accessoryLinearCapacity)
            .tint(Theme.accent)
        }
    }
}

private struct ScanChipGrid: View {
    let items: [String]
    let systemImage: String

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(items, id: \.self) { item in
                Label(item, systemImage: systemImage)
                    .font(.caption)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Theme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }
}

private struct ConfidencePill: View {
    let confidence: Double

    var body: some View {
        Text("\(Int(confidence * 100))%")
            .font(.title3.monospacedDigit().weight(.semibold))
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Theme.accent.opacity(0.12), in: Capsule())
            .accessibilityLabel("辨識信心 \(Int(confidence * 100))%")
    }
}
