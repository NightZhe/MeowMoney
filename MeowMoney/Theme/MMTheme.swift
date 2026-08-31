import SwiftUI
import UIKit

/// 2.0 Design tokens。顏色全部來自 Asset Catalog（Light／Dark 兩個外觀，會自動跟隨系統），
/// 取代 `Cute` 的顏色定義。依據
/// `ProjectDesignGuide/04-MeowMoney2.0-DesignSystem/README.md` §2 與 `implementation.md` §1。
///
/// `Cute`（見 `CuteTheme.swift`）刻意保留、不刪除、不改值——
/// `Models/ExpenseCategory.swift` 的分類色還依賴它，Models 不在本次改動範圍內。
enum MM {

    // MARK: - 表面

    static let bgBase       = Color("bg/base")
    static let surfaceCard  = Color("surface/card")
    static let surfaceTrack = Color("surface/track")
    static let hairline     = Color("border/hairline")

    // MARK: - 文字

    static let textPrimary   = Color("text/primary")
    static let textSecondary = Color("text/secondary")
    /// 對比僅 4.36:1（Light），只能用在 ≥18pt 的文字。
    static let textTertiary  = Color("text/tertiary")
    /// 放在會隨模式翻轉深淺的品牌填色上（例如 `brandStrong` 實心按鈕、`income` 填色）。
    /// 不要跟 `onFill` 混用——那個兩模式都是深色，用在 `brandFill`/`micStart`/`micEnd` 上。
    static let textOnBrand = Color("text/on-brand")

    // MARK: - 品牌（用途不可互換，見 README §2「兩個 on- token 不要搞混」）

    /// 純裝飾填色（麥克風光暈環）。**禁止放字或圖示**：對白字只有 1.99:1。
    static let brandFill = Color("brand/primary-fill")
    /// 實心按鈕填色，配 `textOnBrand`。
    static let brandStrong = Color("brand/primary-strong")
    /// 品牌色當可點文字用（連結、選中態文字）。
    static let brandText = Color("brand/primary-text")
    static let micStart = Color("brand/mic-grad-start")
    static let micEnd = Color("brand/mic-grad-end")
    /// 放在淺色品牌填色（`micStart`/`micEnd`/`brandFill`）上的圖示色。兩模式都是深色 `#1A1310`。
    static let onFill = Color("brand/on-fill")

    // MARK: - 狀態

    static let expense = Color("state/expense")
    static let income  = Color("state/income")
    static let warning = Color("state/warning")

    // MARK: - 玻璃（Glass實作規格.md §0；只用 Regular 變體，Clear/dim 本次不適用）

    /// iOS 17–25 降級軌的玻璃容器填色（真玻璃軌用 `.glassEffect` 自帶填色，不需要這個 token）。
    static let glassRegularFill = Color("glass/regular-fill")
    /// 降級軌玻璃容器的描邊（Dark 專用；Light 降級軌沿用 `MM.hairline`，見 Glass 規格 §2.2）。
    static let glassRegularStroke = Color("glass/regular-stroke")

    /// Light 模式卡片陰影色（暖褐，README §1.3）。不是 Asset Catalog token——
    /// 陰影色本來就不用跟隨 Dark（Dark 完全不用陰影），沒有理由為它建 Color Set。
    /// 集中定義在這裡，view 檔一律引用這個，不要各自寫 `Color(hex:)` 常數。
    static let cardShadowLight = Color(hex: 0x7A4A38)

    // MARK: - 圓角（2026-08-21 質感修正後收緊；同心規則：外 = 內 + padding）

    enum R {
        /// 分類圖示底（原本是正圓，改圓角方）
        static let chip: CGFloat = 12
        static let sm: CGFloat = 12
        /// 列表列、按鈕
        static let md: CGFloat = 14
        /// 卡片
        static let lg: CGFloat = 18
        /// Sheet（HIG 要求 sheet 圓角放大，這個不收）
        static let xl: CGFloat = 34
    }

    // MARK: - 字級

    /// 字級一律綁 Dynamic Type：用 `UIFontMetrics` 依 `relativeTo` 的文字樣式縮放，
    /// **不是**寫死的固定 size（`Cute.font()` 是固定 size，不會隨系統字級變化）。
    static func font(
        _ size: CGFloat,
        _ weight: Font.Weight = .semibold,
        relativeTo style: Font.TextStyle = .body
    ) -> Font {
        let base = UIFont.systemFont(ofSize: size, weight: weight.uiWeight)
        let roundedDescriptor = base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor
        let rounded = UIFont(descriptor: roundedDescriptor, size: size)
        let scaled = UIFontMetrics(forTextStyle: style.uiTextStyle).scaledFont(for: rounded)
        return Font(scaled)
    }

    /// 導覽層 chrome 專用（目前只有 tab bar 用）：跟 `font()` 一樣綁 Dynamic Type，
    /// 但封頂在 `.extraExtraExtraLarge`（最大的非 Accessibility 級距）。
    /// tab bar 是固定高度的浮動膠囊，AX 級距（放大到 310%）下 icon+雙行文字會把
    /// 膠囊撐爆、文字溢出到膠囊外——這是導航層 chrome 該有的「有上限地跟隨」，
    /// 不是內容層，內容層（金額、標題、列表）一律用 `font()`、不封頂。
    /// 用 `UIFontMetrics(compatibleWith:)` 而不是 SwiftUI `.dynamicTypeSize()`：
    /// 後者只影響 SwiftUI 原生解析 Dynamic Type 的路徑，`font()`／`navFont()` 是
    /// 手動呼叫 `UIFontMetrics`，讀的是全域 trait collection，`.dynamicTypeSize()`
    /// modifier 對它不生效。
    static func navFont(
        _ size: CGFloat,
        _ weight: Font.Weight = .semibold,
        relativeTo style: Font.TextStyle = .body
    ) -> Font {
        let base = UIFont.systemFont(ofSize: size, weight: weight.uiWeight)
        let roundedDescriptor = base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor
        let rounded = UIFont(descriptor: roundedDescriptor, size: size)
        let current = UIApplication.shared.preferredContentSizeCategory
        let capped = current.isAccessibilityCategory ? .extraExtraExtraLarge : current
        let traits = UITraitCollection(preferredContentSizeCategory: capped)
        let scaled = UIFontMetrics(forTextStyle: style.uiTextStyle).scaledFont(for: rounded, compatibleWith: traits)
        return Font(scaled)
    }

    /// 動畫（沿用 1.0 的手感值，非顏色 token，不受 Dark Mode 影響）
    static let bouncy = Animation.spring(response: 0.42, dampingFraction: 0.62)
    static let softPop = Animation.spring(response: 0.3, dampingFraction: 0.7)
}

private extension Font.Weight {
    var uiWeight: UIFont.Weight {
        switch self {
        case .ultraLight: .ultraLight
        case .thin: .thin
        case .light: .light
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        case .heavy: .heavy
        case .black: .black
        default: .regular
        }
    }
}

private extension Font.TextStyle {
    var uiTextStyle: UIFont.TextStyle {
        switch self {
        case .largeTitle: .largeTitle
        case .title: .title1
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .subheadline: .subheadline
        case .body: .body
        case .callout: .callout
        case .footnote: .footnote
        case .caption: .caption1
        case .caption2: .caption2
        default: .body
        }
    }
}

// MARK: - 卡片層次（README §1.3／implementation.md §4）

/// Light：收斂陰影 + hairline。Dark：**禁止陰影**，改 hairline(白 6–9%) + 上緣內高光。
/// iOS 17 降級：用固定圓角 `RoundedRectangle`，不用 `ConcentricRectangle`（26+ API，見 §1.5）。
struct MMSurface: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    var padding: CGFloat
    var cornerRadius: CGFloat
    /// true＝卡片級陰影收斂值；false＝列表列級（更收斂）。
    var isCard: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .padding(padding)
            .background(shape.fill(MM.surfaceCard))
            .overlay(
                shape.strokeBorder(
                    scheme == .dark ? Color.white.opacity(0.08) : MM.hairline,
                    lineWidth: 1
                )
            )
            .overlay {
                if scheme == .dark {
                    // 上緣內高光：模擬光從上方打在邊緣，取代暗色下失效的陰影。
                    shape.strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.08), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
                }
            }
            .shadow(
                color: scheme == .dark ? .clear : MM.cardShadowLight.opacity(isCard ? 0.10 : 0.07),
                radius: isCard ? 14 : 8,
                x: 0,
                y: isCard ? 4 : 2
            )
    }
}

extension View {
    /// 卡片（`summaryCard`／`balanceCard`／`breakdown` 這類容器）。
    func mmCard(padding: CGFloat = 20, cornerRadius: CGFloat = MM.R.lg) -> some View {
        modifier(MMSurface(padding: padding, cornerRadius: cornerRadius, isCard: true))
    }

    /// 列表列（`ExpenseRow`），陰影更收斂。
    func mmRow(padding: CGFloat = 14, cornerRadius: CGFloat = MM.R.md) -> some View {
        modifier(MMSurface(padding: padding, cornerRadius: cornerRadius, isCard: false))
    }
}
