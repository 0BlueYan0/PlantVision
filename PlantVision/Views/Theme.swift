import SwiftUI

/// 全 app 共用的 visionOS 設計 token 與玻璃面板樣式。
///
/// 取代原先散落在各 View 的硬編顏色與間距(尤其是 `ScanView` 內的 private `ScanTheme`),
/// 讓 2D 視窗 UI 的品牌色、間距、圓角、材質一致。
///
/// 材質採 visionOS 2 的 `.glassBackgroundEffect()`(非 iOS 26 的 Liquid Glass `.glassEffect()`,
/// 本專案 `XROS_DEPLOYMENT_TARGET = 2.0` 無法使用且不需要)。
enum Theme {
    /// 單一品牌 accent:綠(植物識別)。整支 app 用 `.tint(Theme.accent)` 套用。
    /// 退掉原本 `ScanView` 的自訂藍 `actionBlue`,避免兩套品牌色互相打架。
    static let accent: Color = .green

    // MARK: 間距

    /// 視窗主要區塊之間的間距。
    static let gutter: CGFloat = 18
    /// 玻璃面板內距。
    static let panelPadding: CGFloat = 24
    /// 面板內各區段之間的間距。
    static let sectionSpacing: CGFloat = 18

    // MARK: 圓角(連續曲率)

    /// 大面板(hero / 結果卡)的圓角。
    static let panelCorner: CGFloat = 28
    /// 次要卡片(工具面板 / 資訊卡)的圓角。
    static let cardCorner: CGFloat = 18
}

extension View {
    /// 統一的玻璃面板背景:連續圓角 + visionOS 系統玻璃。
    ///
    /// 直接取代各處的 `.glassBackgroundEffect()`,讓所有面板用一致的圓角與材質;
    /// 並避免在玻璃上再疊半透明白色填充(HIG MD-06:shared space 不要不透明面板)。
    /// 呼叫端維持自己的 `.padding(...)`,本 modifier 只負責背景。
    func glassPanel(cornerRadius: CGFloat = Theme.panelCorner) -> some View {
        glassBackgroundEffect(
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
    }
}
