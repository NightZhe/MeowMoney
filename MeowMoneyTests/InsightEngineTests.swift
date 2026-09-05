import XCTest
@testable import MeowMoney

final class InsightEngineTests: XCTestCase {

    /// 固定 locale/firstWeekday，避免測試結果隨執行機器的地區設定飄移
    /// （`dateInterval(of: .weekOfYear, for:)` 會吃 `firstWeekday`）。
    private lazy var calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "en_US_POSIX")
        cal.firstWeekday = 1
        return cal
    }()

    /// 月中的一天，離月初月底都有安全距離，週區間不會跨到別的月份。
    private lazy var month: Date = {
        var components = DateComponents()
        components.year = 2026
        components.month = 8
        components.day = 15
        components.hour = 12
        return calendar.date(from: components)!
    }()

    private func date(day: Int, month monthOverride: Int = 8) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = monthOverride
        components.day = day
        components.hour = 12
        return calendar.date(from: components)!
    }

    private let weekdayChars = ["", "日", "一", "二", "三", "四", "五", "六"]

    // MARK: - 資料量門檻

    func testEmptyExpensesReturnsEmpty() {
        let result = InsightEngine.insights(for: [], month: month, calendar: calendar)
        XCTAssertEqual(result, [])
    }

    func testSingleRecordReturnsEmpty() {
        let expenses = [Expense(amount: 100, category: .food, date: date(day: 15))]
        let result = InsightEngine.insights(for: expenses, month: month, calendar: calendar)
        XCTAssertEqual(result, [])
    }

    func testNoPreviousMonthDataProducesNoCategoryTrend() {
        // 5 筆、5 個不同分類、同一天：湊過「至少 5 筆」的門檻，
        // 但刻意避開 frequency（同分類要 >=3 筆）與 weekdayPattern（要 >=2 個不同星期幾）的門檻，
        // 只用來驗證「沒有上個月資料就不該有 categoryTrend」。
        let sameDay = date(day: 15)
        let expenses: [Expense] = [
            Expense(amount: 100, category: .food, date: sameDay),
            Expense(amount: 100, category: .transport, date: sameDay),
            Expense(amount: 100, category: .shopping, date: sameDay),
            Expense(amount: 100, category: .entertainment, date: sameDay),
            Expense(amount: 100, category: .home, date: sameDay)
        ]
        let result = InsightEngine.insights(for: expenses, month: month, calendar: calendar)
        XCTAssertFalse(result.contains { $0.kind == .categoryTrend })
        XCTAssertEqual(result, [])
    }

    // MARK: - 三種 kind 各一個正常案例

    func testCategoryTrendKind() {
        var expenses: [Expense] = []
        // 本月：餐飲 4,000（上個月 2,000 的兩倍，變化 +100%，遠超過 20% 門檻）
        expenses.append(Expense(amount: 2000, category: .food, date: date(day: 3)))
        expenses.append(Expense(amount: 2000, category: .food, date: date(day: 5)))
        // 交通變化只有 -40%，用來確認「取變化幅度最大」而不是隨便挑一個
        expenses.append(Expense(amount: 100, category: .transport, date: date(day: 10)))
        expenses.append(Expense(amount: 100, category: .transport, date: date(day: 12)))
        expenses.append(Expense(amount: 50, category: .shopping, date: date(day: 20)))
        // 上個月：餐飲 2,000、交通 500，且總筆數 >= 3 才有資格當比較基準
        expenses.append(Expense(amount: 1000, category: .food, date: date(day: 3, month: 7)))
        expenses.append(Expense(amount: 1000, category: .food, date: date(day: 10, month: 7)))
        expenses.append(Expense(amount: 500, category: .transport, date: date(day: 15, month: 7)))

        let result = InsightEngine.insights(for: expenses, month: month, calendar: calendar)
        let trend = result.first { $0.kind == .categoryTrend }
        XCTAssertEqual(trend?.title, "餐飲比上個月多 100%")
        XCTAssertEqual(trend?.detail, "這個月 \(Money.string(4000))，上個月 \(Money.string(2000))")
    }

    func testFrequencyKind() throws {
        let weekInterval = try XCTUnwrap(calendar.dateInterval(of: .weekOfYear, for: month))
        func inWeek(_ dayOffset: Int) -> Date {
            calendar.date(byAdding: .hour, value: dayOffset * 24 + 12, to: weekInterval.start)!
        }

        var expenses: [Expense] = []
        // 這週餐飲 3 次，觸發 frequency（門檻是 >=3 次）
        expenses.append(Expense(amount: 65, category: .food, date: inWeek(1)))
        expenses.append(Expense(amount: 65, category: .food, date: inWeek(2)))
        expenses.append(Expense(amount: 65, category: .food, date: inWeek(3)))
        // 湊滿本月至少 5 筆的門檻，用其他分類避免互相干擾
        expenses.append(Expense(amount: 30, category: .transport, date: inWeek(4)))
        expenses.append(Expense(amount: 200, category: .shopping, date: inWeek(5)))

        let result = InsightEngine.insights(for: expenses, month: month, calendar: calendar)
        let frequency = result.first { $0.kind == .frequency }
        XCTAssertEqual(frequency?.title, "這週餐飲消費 3 次")
        XCTAssertEqual(frequency?.detail, "共 \(Money.string(195)) 元")
    }

    func testWeekdayPatternKind() throws {
        let weekInterval = try XCTUnwrap(calendar.dateInterval(of: .weekOfYear, for: month))
        func onWeekday(offset: Int, weeksLater: Int) -> Date {
            calendar.date(byAdding: .hour, value: (offset + weeksLater * 7) * 24 + 12, to: weekInterval.start)!
        }

        let highWeekday = onWeekday(offset: 5, weeksLater: 0)
        let highWeekdayNextWeek = onWeekday(offset: 5, weeksLater: 1)
        let lowWeekday = onWeekday(offset: 2, weeksLater: 0)
        let lowWeekdayNextWeek = onWeekday(offset: 2, weeksLater: 1)

        var expenses: [Expense] = [
            Expense(amount: 1000, category: .entertainment, date: highWeekday),
            Expense(amount: 1000, category: .entertainment, date: highWeekdayNextWeek),
            Expense(amount: 100, category: .food, date: lowWeekday),
            Expense(amount: 100, category: .food, date: lowWeekdayNextWeek),
            Expense(amount: 10, category: .other, date: onWeekday(offset: 0, weeksLater: 0))
        ]
        // 全部日期都必須落在 8 月（本月），否則不算進「本月」樣本。
        expenses = expenses.filter { calendar.component(.month, from: $0.date) == 8 }
        XCTAssertEqual(expenses.count, 5, "測試資料設計錯誤：日期跑到別的月份去了")

        let weekdayNumber = calendar.component(.weekday, from: highWeekday)

        let result = InsightEngine.insights(for: expenses, month: month, calendar: calendar)
        let pattern = result.first { $0.kind == .weekdayPattern }
        XCTAssertEqual(pattern?.title, "你週\(weekdayChars[weekdayNumber])平均花最多")
        XCTAssertEqual(pattern?.detail, "平均每次 \(Money.string(1000)) 元")
    }

    // MARK: - 分類趨勢文案級距（倍數）

    /// 建一組「本月只有一個上個月有資料的分類（購物）在變化，其餘 4 筆填其他分類湊滿
    /// 本月至少 5 筆的門檻」的資料。`current == nil` 代表這個月購物完全沒有紀錄
    /// （currentTotal 會是 0），用來測試除以 0 的邊界。
    private func trendExpenses(previousParts: [Decimal], current: Decimal?) -> [Expense] {
        var expenses: [Expense] = [
            Expense(amount: 10, category: .transport, date: date(day: 1)),
            Expense(amount: 10, category: .entertainment, date: date(day: 2)),
            Expense(amount: 10, category: .home, date: date(day: 3)),
            Expense(amount: 10, category: .medical, date: date(day: 4)),
            Expense(amount: 10, category: .education, date: date(day: 5))
        ]
        if let current {
            expenses.append(Expense(amount: current, category: .shopping, date: date(day: 15)))
        }
        for (offset, part) in previousParts.enumerated() {
            expenses.append(Expense(amount: part, category: .shopping, date: date(day: 3 + offset * 8, month: 7)))
        }
        return expenses
    }

    private func categoryTrendTitle(previousParts: [Decimal], current: Decimal?) -> String? {
        let expenses = trendExpenses(previousParts: previousParts, current: current)
        let result = InsightEngine.insights(for: expenses, month: month, calendar: calendar)
        return result.first { $0.kind == .categoryTrend }?.title
    }

    func testCategoryTrend_9x_StillUsesPercent() {
        let title = categoryTrendTitle(previousParts: [40, 30, 30], current: 900)
        XCTAssertEqual(title, "購物比上個月多 800%")
    }

    func testCategoryTrend_10x_UsesMultiple() {
        let title = categoryTrendTitle(previousParts: [40, 30, 30], current: 1000)
        XCTAssertEqual(title, "購物比上個月多了 10 倍")
    }

    func testCategoryTrend_99x_UsesMultiple() {
        let title = categoryTrendTitle(previousParts: [40, 30, 30], current: 9900)
        XCTAssertEqual(title, "購物比上個月多了 99 倍")
    }

    func testCategoryTrend_100x_StillUsesMultiple() {
        let title = categoryTrendTitle(previousParts: [40, 30, 30], current: 10000)
        XCTAssertEqual(title, "購物比上個月多了 100 倍")
    }

    func testCategoryTrend_101x_UsesAbsoluteValue() {
        let title = categoryTrendTitle(previousParts: [40, 30, 30], current: 10100)
        XCTAssertEqual(title, "購物上個月幾乎沒花，這個月 \(Money.string(10100))")
    }

    func testCategoryTrend_9xDecrease_StillUsesPercent() {
        let title = categoryTrendTitle(previousParts: [300, 300, 300], current: 100)
        XCTAssertEqual(title, "購物比上個月少 89%")
    }

    func testCategoryTrend_10xDecrease_UsesMultiple() {
        let title = categoryTrendTitle(previousParts: [340, 330, 330], current: 100)
        XCTAssertEqual(title, "購物只剩上個月的 10 分之一")
    }

    func testCategoryTrend_100xDecrease_StillUsesMultiple() {
        let title = categoryTrendTitle(previousParts: [3334, 3333, 3333], current: 100)
        XCTAssertEqual(title, "購物只剩上個月的 100 分之一")
    }

    func testCategoryTrend_101xDecrease_UsesAbsoluteValue() {
        let title = categoryTrendTitle(previousParts: [3400, 3350, 3350], current: 100)
        XCTAssertEqual(title, "購物這個月幾乎沒花，上個月 \(Money.string(10100))")
    }

    /// 這個月完全沒買（currentTotal 是 0），會踩到「除以 0」的邊界，
    /// 必須直接落到絕對值分支，不能讓 Decimal 除以 0 產生 NaN 或壞字串。
    func testCategoryTrend_CurrentZero_UsesAbsoluteValue() {
        let title = categoryTrendTitle(previousParts: [2000, 1500, 1500], current: nil)
        XCTAssertEqual(title, "購物這個月幾乎沒花，上個月 \(Money.string(5000))")
    }

    /// 實際踩到的案例：上個月 365、這個月 9,876,543,210，原本會算出 27 億 %。
    func testCategoryTrend_RealWorldExtremeCase() {
        let title = categoryTrendTitle(previousParts: [122, 121, 122], current: 9_876_543_210)
        XCTAssertEqual(title, "購物上個月幾乎沒花，這個月 \(Money.string(9_876_543_210))")
    }

    // MARK: - 上限

    func testInsightsNeverExceedsThree() {
        // 合併三個各自獨立會觸發一種 kind 的情境，確認同時觸發時仍然只回 3 條。
        let weekInterval = calendar.dateInterval(of: .weekOfYear, for: month)!
        func inWeek(_ dayOffset: Int) -> Date {
            calendar.date(byAdding: .hour, value: dayOffset * 24 + 12, to: weekInterval.start)!
        }

        let expenses: [Expense] = [
            // categoryTrend：餐飲本月 vs 上個月
            Expense(amount: 2000, category: .food, date: date(day: 3)),
            Expense(amount: 2000, category: .food, date: date(day: 5)),
            Expense(amount: 1000, category: .food, date: date(day: 3, month: 7)),
            Expense(amount: 1000, category: .food, date: date(day: 10, month: 7)),
            Expense(amount: 500, category: .transport, date: date(day: 15, month: 7)),
            // frequency：這週交通 3 次
            Expense(amount: 30, category: .transport, date: inWeek(1)),
            Expense(amount: 30, category: .transport, date: inWeek(2)),
            Expense(amount: 30, category: .transport, date: inWeek(3)),
            // weekdayPattern：同一個星期幾出現兩次、金額明顯偏高
            Expense(amount: 5000, category: .entertainment, date: inWeek(0)),
            Expense(amount: 5000, category: .entertainment, date: calendar.date(byAdding: .day, value: 7, to: inWeek(0))!)
        ]

        let result = InsightEngine.insights(for: expenses, month: month, calendar: calendar)
        XCTAssertLessThanOrEqual(result.count, 3)
        XCTAssertEqual(result.count, 3, "這組資料設計成三種 kind 都該觸發")
        let kinds = Set(result.map(\.kind))
        XCTAssertEqual(kinds, [.categoryTrend, .frequency, .weekdayPattern])
    }
}
