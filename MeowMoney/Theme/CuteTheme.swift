import SwiftUI

/// 全 app 共用的可愛風格：奶油底色、蜜桃粉主色、圓潤字體、軟陰影。
enum Cute {

    // MARK: - 顏色

    static let cream = Color(hex: 0xFFF6EC)          // 背景奶油白
    static let card = Color.white
    static let peach = Color(hex: 0xFFA59D)          // 主色：蜜桃粉
    static let peachDeep = Color(hex: 0xFF7E71)
    static let mint = Color(hex: 0x8ED6BE)           // 收入 / 正向
    static let butter = Color(hex: 0xFFD37E)         // 強調
    static let sky = Color(hex: 0x8FC9EE)
    static let lilac = Color(hex: 0xC5B3EF)
    static let cocoa = Color(hex: 0x5A463F)          // 主要文字
    static let cocoaSoft = Color(hex: 0x9C8880)      // 次要文字
    static let shadow = Color(hex: 0xD8B9A8).opacity(0.35)

    /// 主背景漸層（由上而下微微變化，避免大面積死白）
    static var background: LinearGradient {
        LinearGradient(
            colors: [Color(hex: 0xFFF9F3), cream, Color(hex: 0xFFEFE2)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: - 圓角

    static let radiusCard: CGFloat = 24
    static let radiusChip: CGFloat = 16

    // MARK: - 字體（一律 rounded，可愛感的來源之一）

    static func font(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static let titleFont = font(28, .bold)
    static let numberFont = font(34, .heavy)
    static let bodyFont = font(16, .medium)
    static let captionFont = font(13, .medium)

    // MARK: - 動畫

    static let bouncy = Animation.spring(response: 0.42, dampingFraction: 0.62)
    static let softPop = Animation.spring(response: 0.3, dampingFraction: 0.7)
}

// MARK: - Color(hex:)

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

// MARK: - 共用修飾器

/// 白色圓角卡片＋柔和陰影。
struct CuteCard: ViewModifier {
    var padding: CGFloat = 18
    var radius: CGFloat = Cute.radiusCard

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Cute.card)
                    .shadow(color: Cute.shadow, radius: 12, x: 0, y: 6)
            )
    }
}

extension View {
    func cuteCard(padding: CGFloat = 18, radius: CGFloat = Cute.radiusCard) -> some View {
        modifier(CuteCard(padding: padding, radius: radius))
    }

    /// 按下時輕微縮小，做出「軟軟的」觸感。
    func squishy() -> some View {
        buttonStyle(SquishyButtonStyle())
    }
}

struct SquishyButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(Cute.softPop, value: configuration.isPressed)
    }
}

// MARK: - 金額格式

enum Money {
    /// 台幣顯示：無小數、有千分位。例：1200 -> "1,200"
    static func string(_ value: Decimal) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = value.isWholeNumber ? 0 : 2
        f.minimumFractionDigits = 0
        return f.string(from: value as NSDecimalNumber) ?? "0"
    }

    static func signed(_ value: Decimal, isIncome: Bool) -> String {
        (isIncome ? "+" : "-") + string(value)
    }
}

extension Decimal {
    var isWholeNumber: Bool {
        var original = self
        var rounded = Decimal()
        NSDecimalRound(&rounded, &original, 0, .plain)
        return rounded == self
    }

    var doubleValue: Double { (self as NSDecimalNumber).doubleValue }
}
