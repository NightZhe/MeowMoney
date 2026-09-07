import Foundation

// MARK: - 金額格式

/// 金額的顯示格式。原本放在 `Theme/CuteTheme.swift`，2026-09-07 搬到 `Models/`：
/// 這是純資料層的格式化，沒有任何 SwiftUI 相依，而 `Services/InsightEngine`
/// 也要用它——服務層反過來相依 Theme 層是錯的方向。
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
