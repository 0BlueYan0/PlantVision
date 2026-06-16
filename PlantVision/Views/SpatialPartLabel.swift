import SwiftUI

/// 指向真實植物某個部位(花/葉)的精簡標籤。比資訊卡小,聚焦單一部位說明。
struct SpatialPartLabel: View {
    let part: PlantPart
    let plant: Plant

    private var note: String {
        switch part {
        case .flower: plant.flowerNote
        case .leaf: plant.leafNote
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: part.symbolName)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(part.markerColor)
                Text(part.displayName)
                    .font(.headline)
            }
            Text(note)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(plant.chineseName)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 12)
        .padding(.leading, 18)   // 留給左側部位色直條
        .padding(.trailing, 14)
        // 固定寬、並讓高度貼齊內容,避免被 RealityView attachment 的大尺寸提案撐高。
        .frame(width: 210, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .glassBackgroundEffect()
        // 部位色直條改用 overlay:只填滿卡片(內容決定)的高度,不會反過來把卡片撐高。
        .overlay(alignment: .leading) {
            Capsule()
                .fill(part.markerColor)
                .frame(width: 4)
                .padding(.vertical, 10)
                .padding(.leading, 7)
        }
    }
}

/// 追蹤狀態提示,固定浮在使用者前方,協助實機 bring-up / 校正。
struct SpatialTrackingStatusLabel: View {
    let phase: ObjectTrackingController.Phase

    private var text: String {
        switch phase {
        case .idle: "準備中…"
        case .unsupported: "此裝置/模擬器不支援 Object Tracking(需實機 Vision Pro)。"
        case .needsAuthorization: "需要「世界感測」權限才能追蹤植物,請到設定開啟。"
        case .missingAsset: "找不到對應的 .referenceobject(請確認已加入 app bundle)。"
        case .searching: "正在尋找植物…請把視線對準掃描過的那株盆栽。"
        case .tracking: "已鎖定植物。"
        case .failed(let reason): "追蹤失敗:\(reason)"
        }
    }

    var body: some View {
        Text(text)
            .font(.callout)
            .multilineTextAlignment(.center)
            .padding(16)
            .frame(maxWidth: 360)
            .glassBackgroundEffect()
    }
}
