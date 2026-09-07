import Foundation
import SwiftData

/// 一筆帳。金額一律存正數，用 `isIncome` 區分收支。
@Model
final class Expense {
    var amount: Decimal = Decimal(0)
    var categoryRaw: String = ExpenseCategory.other.rawValue
    var note: String = ""
    var date: Date = Date()
    var isIncome: Bool = false
    /// 語音原文，之後要調整解析規則時可以回頭看使用者實際怎麼說。
    var transcript: String = ""
    var createdAt: Date = Date()

    init(
        amount: Decimal,
        category: ExpenseCategory,
        note: String = "",
        date: Date = Date(),
        isIncome: Bool = false,
        transcript: String = ""
    ) {
        self.amount = amount
        self.categoryRaw = category.rawValue
        self.note = note
        self.date = date
        self.isIncome = isIncome
        self.transcript = transcript
        self.createdAt = Date()
    }

    var category: ExpenseCategory {
        get { ExpenseCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    /// 帶正負號的金額，做加總用。
    var signedAmount: Decimal {
        isIncome ? amount : -amount
    }

    /// 顯示用標題：有備註就用正規化後的備註，否則用分類名。
    /// 備註來自語音辨識，可能含首尾空白或內部連續換行/空白，正規化後再顯示
    /// 才不會讓 `lineLimit(1)` 的列表列出現擠壓或空白行。
    var displayTitle: String {
        let normalizedNote = Expense.normalizedDisplayText(note)
        return normalizedNote.isEmpty ? category.title : normalizedNote
    }

    /// 把文字的首尾空白去掉，並把內部連續的換行/空白 collapse 成單一半形空格。
    /// 純函式，無失敗情況。
    static func normalizedDisplayText(_ text: String) -> String {
        text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
