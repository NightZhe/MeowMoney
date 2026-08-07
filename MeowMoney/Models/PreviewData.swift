import Foundation
import SwiftData

/// 給 Xcode Preview 用的記憶體資料庫，不會寫進真實資料。
enum PreviewData {
    @MainActor static let container: ModelContainer = {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: Expense.self, configurations: config)
        let context = container.mainContext
        let calendar = Calendar.current
        let now = Date()

        let samples: [(Decimal, ExpenseCategory, String, Int, Bool)] = [
            (120, .food, "便當", 0, false),
            (65, .food, "手搖飲", 0, false),
            (30, .transport, "捷運", 0, false),
            (1_280, .shopping, "球鞋", 1, false),
            (390, .entertainment, "電影", 2, false),
            (18_000, .home, "房租", 3, false),
            (130_000, .income, "薪水", 3, true),
            (250, .medical, "藥局", 5, false)
        ]

        for sample in samples {
            let date = calendar.date(byAdding: .day, value: -sample.3, to: now) ?? now
            context.insert(
                Expense(
                    amount: sample.0,
                    category: sample.1,
                    note: sample.2,
                    date: date,
                    isIncome: sample.4,
                    transcript: ""
                )
            )
        }
        return container
    }()
}
