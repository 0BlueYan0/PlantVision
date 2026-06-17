import SwiftUI

/// 指向真實植物某個部位(花/葉)的精簡標籤卡。比資訊卡小,聚焦單一部位說明。
///
/// 重設計:標頭改用「部位色 tinted 圓形 icon chip + 部位名」,植物中文名作 subtitle;
/// 退掉原本左側 4pt 細色條,讓花黃/葉綠的色彩語意更明確。字級放大、改用語意樣式,
/// 確保在 1–2m 仍好讀(HIG SL-02)。材質維持 visionOS 系統玻璃(非 Liquid Glass)。
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                // 部位色 tinted 圓形 icon chip:取代左側細色條,色彩語意更明確,也更像一張刻意設計的 callout 卡。
                Image(systemName: part.symbolName)
                    .font(.headline)
                    .foregroundStyle(part.markerColor)
                    .frame(width: 40, height: 40)
                    .background(part.markerColor.opacity(0.18), in: Circle())
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(part.displayName)
                        .font(.title3.weight(.semibold))
                    Text(plant.chineseName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Text(note)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        // 固定寬、並讓高度貼齊內容,避免被 RealityView attachment 的大尺寸提案撐高(見 commit 022186e)。
        .frame(width: 240, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .glassPanel(cornerRadius: 22)
        // 整張卡合併為單一 VoiceOver 元素,一次讀完「部位 · 植物 · 說明」。
        .accessibilityElement(children: .combine)
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
            .glassPanel(cornerRadius: Theme.cardCorner)
    }
}
