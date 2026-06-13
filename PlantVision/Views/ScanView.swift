import SwiftUI

struct ScanView: View {
    @EnvironmentObject private var appModel: PlantVisionModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                contentLayout(size: proxy.size)
                    .padding(28)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("PlantVision")
            .tint(ScanTheme.actionBlue)
        }
    }

    @ViewBuilder
    private func contentLayout(size: CGSize) -> some View {
        if size.width < 940 {
            VStack(spacing: 16) {
                heroPanel
                resultPanel
                relayUtilityPanel
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HStack(alignment: .top, spacing: 24) {
                heroPanel
                resultPanel
                relayUtilityPanel
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var heroPanel: some View {
        VStack(spacing: 18) {
            HStack {
                Label("Vision Pro Native Scan", systemImage: "visionpro")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(statusCategory)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusTint)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(statusTint.opacity(0.12), in: Capsule())
            }

            Spacer(minLength: 0)

            VStack(spacing: 16) {
                Image(systemName: "viewfinder.circle")
                    .font(.system(size: 78, weight: .light))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(ScanTheme.actionBlue)
                    .accessibilityHidden(true)

                VStack(spacing: 8) {
                    Text("植物辨識工作區")
                        .font(.system(size: 34, weight: .semibold, design: .default))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.72)

                    Text(appModel.recognitionState.message)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text("Relay 是正式辨識入口，Demo 可用來快速檢查結果展示與空間標籤流程。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            actionRow
        }
        .frame(minWidth: 280, maxWidth: 360, maxHeight: .infinity, alignment: .top)
        .padding(24)
        .background(ScanTheme.heroSurface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .glassBackgroundEffect()
    }

    private var actionRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                scanActions
            }

            VStack(spacing: 12) {
                scanActions
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var scanActions: some View {
        Button {
            appModel.connectRelay()
        } label: {
            Label("連線 Relay", systemImage: "link")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)

        Button {
            Task {
                await appModel.runDemoRecognition()
            }
        } label: {
            Label("Demo 樣本", systemImage: "photo")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)

        Button {
            Task {
                _ = await openImmersiveSpace(id: PlantVisionModel.immersiveSpaceID)
            }
        } label: {
            Label("開啟空間", systemImage: "cube.transparent")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .disabled(appModel.currentResult == nil)
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
        .background(ScanTheme.utilitySurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.primary.opacity(0.08), lineWidth: 1)
        )
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
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(24)
            .glassBackgroundEffect()
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
            .padding(24)
            .glassBackgroundEffect()
        }
    }

    private var statusCategory: String {
        switch appModel.recognitionState {
        case .idle:
            "Ready"
        case .relayConnecting:
            "Scanning"
        case .relayConnected, .relayResult:
            "Result"
        case .demoMode, .failed:
            "Notice"
        }
    }

    private var statusTint: Color {
        switch appModel.recognitionState {
        case .failed:
            .red
        case .demoMode:
            .orange
        case .relayConnected, .relayResult:
            ScanTheme.actionBlue
        default:
            .secondary
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
            ScanTheme.actionBlue
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
                        .font(.system(size: 38, weight: .semibold, design: .default))
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
                    .foregroundStyle(ScanTheme.actionBlue)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(ScanTheme.actionBlue.opacity(0.12), in: Capsule())

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
            .tint(ScanTheme.actionBlue)
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
                    .background(ScanTheme.actionBlue.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }
}

private struct ConfidencePill: View {
    let confidence: Double

    var body: some View {
        Text("\(Int(confidence * 100))%")
            .font(.title3.monospacedDigit().weight(.semibold))
            .foregroundStyle(ScanTheme.actionBlue)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(ScanTheme.actionBlue.opacity(0.12), in: Capsule())
            .accessibilityLabel("辨識信心 \(Int(confidence * 100))%")
    }
}

private enum ScanTheme {
    static let actionBlue = Color(red: 0.0, green: 0.40, blue: 0.80)
    static let heroSurface = Color.white.opacity(0.72)
    static let utilitySurface = Color.white.opacity(0.18)
}
