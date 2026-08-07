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

    /// 顯示用標題：有備註就用備註，否則用分類名。
    var displayTitle: String {
        note.trimmingCharacters(in: .whitespaces).isEmpty ? category.title : note
    }
}
