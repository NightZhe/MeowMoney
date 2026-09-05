import Foundation

/// 統計頁「本月的發現」的一張觀察卡。
struct Insight: Identifiable, Equatable {
    let id: String
    let title: String       // 例：「餐飲比上個月多 38%」
    let detail: String      // 例：「這個月 3,200，上個月 2,320」
    let kind: InsightKind
}

enum InsightKind: Equatable {
    case categoryTrend
    case frequency
    case weekdayPattern
}

/// 從歷史帳目算出「值得讓使用者看到」的觀察，全部在本機算、不碰 UI、不碰 SwiftData context。
///
/// 資料太少時，算出來的「趨勢」是噪音而不是洞察（例如第一個月沒有「上個月」可比、
/// 只有兩三筆帳就在講「比上個月多 300%」）。所以每種洞察都各自設了資料量門檻，
/// 門檻沒過就不產生那張卡，門檻怎麼定寫在下面每個 private 常數旁的註解。
enum InsightEngine {

    // MARK: - 門檻（資料量不足時不顯示，見各常數註解）

    /// 本月至少要有這麼多筆支出，才值得算任何洞察。低於此門檻直接回傳空陣列，
    /// 這是 PM 提案裡「不夠就不顯示這張卡」的具體數字：2-3 筆算噪音，5 筆是一個粗略但
    /// 不會太晚出現（不會晚到使用者已經流失）的下限。
    private static let minMonthlyRecordsForAnyInsight = 5

    /// 分類趨勢：上個月同分類至少要有這麼多筆，才有資格當比較基準。
    private static let minPreviousMonthRecordsForTrend = 3

    /// 分類趨勢：上個月該分類金額至少要有這麼多，避免「10 元變 30 元」這種
    /// 基期太小、百分比看起來嚇人但其實無意義的情況。
    private static let minPreviousMonthAmountForTrend: Decimal = 100

    /// 分類趨勢：變化幅度至少要到這個百分比才值得講，太小的波動不算「趨勢」。
    private static let minTrendPercentChange = 20.0

    /// 頻率：這週同分類至少要有這麼多筆，才算「常態」而不是單次事件。
    private static let minWeeklyCountForFrequency = 3

    /// 星期模式：至少要出現在這麼多個「不同的星期幾」上，「哪天花最多」才有比較意義
    /// （不然只花在同一個星期幾，講「這天花最多」是廢話）。
    private static let minDistinctWeekdaysForPattern = 2

    /// 星期模式：拿來當分母的那個星期幾，至少要有這麼多筆紀錄，避免單一一筆極端消費
    /// 把平均拉高就被講成「這天花最多」。
    private static let minOccurrencesForWeekdayPattern = 2

    private static let weekdayNames = ["", "日", "一", "二", "三", "四", "五", "六"]

    // MARK: - 對外入口

    static func insights(
        for expenses: [Expense],
        month: Date,
        calendar: Calendar = .current
    ) -> [Insight] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: month) else { return [] }

        let spending = expenses.filter { !$0.isIncome }
        let currentMonthExpenses = spending.filter { monthInterval.contains($0.date) }

        guard currentMonthExpenses.count >= minMonthlyRecordsForAnyInsight else { return [] }

        let candidates: [Insight?] = [
            categoryTrendInsight(spending: spending, monthInterval: monthInterval, month: month, calendar: calendar),
            frequencyInsight(spending: spending, month: month, calendar: calendar),
            weekdayPatternInsight(currentMonthExpenses: currentMonthExpenses, calendar: calendar)
        ]

        return Array(candidates.compactMap { $0 }.prefix(3))
    }

    // MARK: - 分類趨勢

    private static func categoryTrendInsight(
        spending: [Expense],
        monthInterval: DateInterval,
        month: Date,
        calendar: Calendar
    ) -> Insight? {
        guard let previousMonthDate = calendar.date(byAdding: .month, value: -1, to: month),
              let previousInterval = calendar.dateInterval(of: .month, for: previousMonthDate) else {
            return nil
        }

        let currentExpenses = spending.filter { monthInterval.contains($0.date) }
        let previousExpenses = spending.filter { previousInterval.contains($0.date) }
        guard previousExpenses.count >= minPreviousMonthRecordsForTrend else { return nil }

        let currentTotals = totals(by: \.category, in: currentExpenses)
        let previousTotals = totals(by: \.category, in: previousExpenses)

        var best: (category: ExpenseCategory, current: Decimal, previous: Decimal, percentChange: Double)?

        for (category, previousTotal) in previousTotals where previousTotal >= minPreviousMonthAmountForTrend {
            let currentTotal = currentTotals[category] ?? 0
            let percentChange = ((currentTotal - previousTotal) / previousTotal).doubleValue * 100
            guard abs(percentChange) >= minTrendPercentChange else { continue }

            if let currentBest = best, abs(currentBest.percentChange) >= abs(percentChange) {
                continue
            }
            best = (category, currentTotal, previousTotal, percentChange)
        }

        guard let winner = best else { return nil }

        return Insight(
            id: "categoryTrend-\(winner.category.rawValue)",
            title: trendTitle(
                categoryTitle: winner.category.title,
                current: winner.current,
                previous: winner.previous,
                percentChange: winner.percentChange
            ),
            detail: "這個月 \(Money.string(winner.current))，上個月 \(Money.string(winner.previous))",
            kind: .categoryTrend
        )
    }

    // MARK: - 分類趨勢文案級距

    /// 百分比在基期很小時會失真——上個月 365、這個月 98 億會算出 27 億 %，
    /// 數學沒錯但當成產品輸出是壞的。改用「倍數」分三級講這件事：
    /// - 倍數 < 10：沿用原本的百分比講法（現況保留，不動）
    /// - 10-100 倍（含兩端）：百分比已經大到不好懂，改講「倍數」
    /// - > 100 倍：連倍數都失去意義，直接講絕對值，不講比例
    private static let percentDisplayCeiling: Decimal = 10
    private static let multipleDisplayCeiling: Decimal = 100

    private static func trendTitle(
        categoryTitle: String,
        current: Decimal,
        previous: Decimal,
        percentChange: Double
    ) -> String {
        let isIncrease = current > previous
        let direction = isIncrease ? "多" : "少"

        // 倍數 = 「變大那邊 / 變小那邊」，恆 >= 1，兩個方向共用同一套級距語言。
        // current 或 previous 其中一邊是 0 時無法相除，直接視為「差距大到超過
        // 任何級距」（previous 理論上不會是 0，因為呼叫端已擋在 >= 100 的門檻之後，
        // 這裡仍防呆處理）。
        let multiple: Decimal? = isIncrease
            ? (previous == 0 ? nil : current / previous)
            : (current == 0 ? nil : previous / current)

        guard let multiple, multiple <= multipleDisplayCeiling else {
            // > 100 倍，或基期趨近於 0：百分比、倍數都已經失真，乾脆直接講絕對值。
            // 小的那邊（不管是上個月還是這個月）講「幾乎沒花」，大的那邊講實際金額。
            if isIncrease {
                return "\(categoryTitle)上個月幾乎沒花，這個月 \(Money.string(current))"
            } else {
                return "\(categoryTitle)這個月幾乎沒花，上個月 \(Money.string(previous))"
            }
        }

        guard multiple < percentDisplayCeiling else {
            // 10-100 倍（含兩端）：改講倍數。減少方向的「少了 N 倍」在中文裡數學上說不通
            // （減少不可能超過 100%），所以用「只剩上個月的 N 分之一」對稱地表達同一件事。
            let roundedMultiple = Int(multiple.doubleValue.rounded())
            return isIncrease
                ? "\(categoryTitle)比上個月多了 \(roundedMultiple) 倍"
                : "\(categoryTitle)只剩上個月的 \(roundedMultiple) 分之一"
        }

        // < 10 倍：現況保留，沿用原本的百分比講法。
        let roundedPercent = Int(abs(percentChange).rounded())
        return "\(categoryTitle)比上個月\(direction) \(roundedPercent)%"
    }

    // MARK: - 頻率

    private static func frequencyInsight(
        spending: [Expense],
        month: Date,
        calendar: Calendar
    ) -> Insight? {
        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: month) else { return nil }
        let weekExpenses = spending.filter { weekInterval.contains($0.date) }
        guard !weekExpenses.isEmpty else { return nil }

        let grouped = Dictionary(grouping: weekExpenses, by: \.category)
        let ranked = grouped
            .map { category, items in
                (category: category, count: items.count, total: items.reduce(Decimal(0)) { $0 + $1.amount })
            }
            .sorted { lhs, rhs in
                lhs.count != rhs.count ? lhs.count > rhs.count : lhs.total > rhs.total
            }

        guard let top = ranked.first, top.count >= minWeeklyCountForFrequency else { return nil }

        return Insight(
            id: "frequency-\(top.category.rawValue)",
            title: "這週\(top.category.title)消費 \(top.count) 次",
            detail: "共 \(Money.string(top.total)) 元",
            kind: .frequency
        )
    }

    // MARK: - 星期模式

    private static func weekdayPatternInsight(
        currentMonthExpenses: [Expense],
        calendar: Calendar
    ) -> Insight? {
        // key：星期幾（1=週日...7=週六，Calendar 的 weekday 定義固定不受 firstWeekday 影響）
        var totalsByWeekday: [Int: Decimal] = [:]
        var datesByWeekday: [Int: Set<DateComponents>] = [:]

        for expense in currentMonthExpenses {
            let weekday = calendar.component(.weekday, from: expense.date)
            totalsByWeekday[weekday, default: 0] += expense.amount
            let dayComponents = calendar.dateComponents([.year, .month, .day], from: expense.date)
            datesByWeekday[weekday, default: []].insert(dayComponents)
        }

        guard totalsByWeekday.count >= minDistinctWeekdaysForPattern else { return nil }

        let averages: [(weekday: Int, average: Decimal, occurrences: Int)] = totalsByWeekday.compactMap { weekday, total in
            let occurrences = datesByWeekday[weekday]?.count ?? 0
            guard occurrences >= minOccurrencesForWeekdayPattern else { return nil }
            return (weekday, total / Decimal(occurrences), occurrences)
        }

        guard let winner = averages.max(by: { $0.average < $1.average }) else { return nil }

        return Insight(
            id: "weekdayPattern-\(winner.weekday)",
            title: "你週\(weekdayNames[winner.weekday])平均花最多",
            detail: "平均每次 \(Money.string(winner.average)) 元",
            kind: .weekdayPattern
        )
    }

    // MARK: - 共用

    private static func totals(
        by keyPath: KeyPath<Expense, ExpenseCategory>,
        in expenses: [Expense]
    ) -> [ExpenseCategory: Decimal] {
        Dictionary(grouping: expenses, by: { $0[keyPath: keyPath] })
            .mapValues { $0.reduce(Decimal(0)) { $0 + $1.amount } }
    }
}
