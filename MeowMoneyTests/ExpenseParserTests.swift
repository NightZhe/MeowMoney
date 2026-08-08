import XCTest
@testable import MeowMoney

final class ExpenseParserTests: XCTestCase {

    private let calendar = Calendar(identifier: .gregorian)
    /// 固定基準時間，避免測試隨今天日期飄移。
    private lazy var now: Date = {
        var components = DateComponents()
        components.year = 2026
        components.month = 8
        components.day = 8
        components.hour = 12
        return calendar.date(from: components)!
    }()

    private func parse(_ text: String) -> ParsedEntry {
        ExpenseParser.parse(text, now: now, calendar: calendar)
    }

    // MARK: - 金額

    func testAmountWithChineseNumber() {
        let result = parse("午餐便當一百二")
        XCTAssertEqual(result.amount, 120)
        XCTAssertEqual(result.category, .food)
        XCTAssertEqual(result.note, "午餐便當")
        XCTAssertFalse(result.isIncome)
    }

    func testAmountWithCurrencySuffix() {
        let result = parse("搭計程車250元")
        XCTAssertEqual(result.amount, 250)
        XCTAssertEqual(result.category, .transport)
    }

    func testAmountIgnoresCounterWords() {
        let result = parse("買了兩個便當共240")
        XCTAssertEqual(result.amount, 240)
        XCTAssertEqual(result.category, .food)
    }

    func testFullWidthDigitsAreNormalized() {
        let result = parse("咖啡１２０元")
        XCTAssertEqual(result.amount, 120)
        XCTAssertEqual(result.category, .food)
    }

    func testNoAmountFound() {
        let result = parse("今天沒有花錢")
        XCTAssertNil(result.amount)
        XCTAssertFalse(result.isUsable)
    }

    func testThousandSeparatorIsHandled() {
        let result = parse("買球鞋 3,280 元")
        XCTAssertEqual(result.amount, 3280)
        XCTAssertEqual(result.category, .shopping)
    }

    // MARK: - 收入

    func testIncomeDetection() {
        let result = parse("薪水入帳十三萬")
        XCTAssertEqual(result.amount, 130_000)
        XCTAssertTrue(result.isIncome)
        XCTAssertEqual(result.category, .income)
    }

    // MARK: - 日期

    func testYesterday() {
        let result = parse("昨天晚餐吃拉麵180")
        XCTAssertEqual(result.amount, 180)
        XCTAssertEqual(calendar.component(.day, from: result.date), 7)
        XCTAssertEqual(result.category, .food)
    }

    func testDayBeforeYesterday() {
        let result = parse("前天加油1200")
        XCTAssertEqual(calendar.component(.day, from: result.date), 6)
        XCTAssertEqual(result.category, .transport)
    }

    func testExplicitMonthAndDay() {
        let result = parse("7月5號看電影390")
        XCTAssertEqual(result.amount, 390)
        XCTAssertEqual(calendar.component(.month, from: result.date), 7)
        XCTAssertEqual(calendar.component(.day, from: result.date), 5)
        XCTAssertEqual(result.category, .entertainment)
    }

    // MARK: - 分類

    func testCategoryMapping() {
        XCTAssertEqual(parse("捷運30").category, .transport)
        XCTAssertEqual(parse("蝦皮買衣服599").category, .shopping)
        XCTAssertEqual(parse("房租18000").category, .home)
        XCTAssertEqual(parse("看牙醫1500").category, .medical)
        XCTAssertEqual(parse("買了一本書420").category, .education)
        XCTAssertEqual(parse("包紅包3600").category, .social)
        XCTAssertEqual(parse("哈哈哈 88").category, .other)
    }

    // MARK: - 備註

    func testFillerWordsRemovedFromNote() {
        let result = parse("幫我記帳 今天花了 星巴克 165 元")
        XCTAssertEqual(result.amount, 165)
        XCTAssertEqual(result.note, "星巴克")
    }

    func testNoteFallsBackToCategoryTitle() {
        let result = parse("500")
        XCTAssertEqual(result.amount, 500)
        XCTAssertEqual(result.note, ExpenseCategory.other.title)
    }

    // MARK: - 實機回歸案例
    //
    // 以下五句是 2026-08-08 在 iPhone 13 Pro Max 實機用語音講出來的原話，
    // 直接取自裝置上的資料庫。其中三句當時解析錯誤，修正後在此固定住，
    // 避免之後改關鍵字表又改回去。

    func testRealDevice_lunch() {
        let result = parse("今天午餐1280")
        XCTAssertEqual(result.amount, 1280)
        XCTAssertEqual(result.category, .food)
        XCTAssertEqual(result.note, "午餐")
    }

    func testRealDevice_movieWithFriend() {
        let result = parse("跟朋友看電影380")
        XCTAssertEqual(result.amount, 380)
        XCTAssertEqual(result.category, .entertainment)
        XCTAssertEqual(result.note, "跟朋友看電影")
    }

    /// 當時錯在：分類落到「其他」，而且備註殘留一個 $。
    func testRealDevice_zaraWithDollarSign() {
        let result = parse("買Zara $170")
        XCTAssertEqual(result.amount, 170)
        XCTAssertEqual(result.category, .shopping)
        XCTAssertEqual(result.note, "買zara")
        XCTAssertFalse(result.note.contains("$"), "備註不該殘留貨幣符號")
    }

    /// 當時錯在：判成支出，而且「錢」被當贅詞吃掉變成「撿到」。
    func testRealDevice_foundMoney() {
        let result = parse("今天撿到錢加$100")
        XCTAssertEqual(result.amount, 100)
        XCTAssertTrue(result.isIncome)
        XCTAssertTrue(result.note.contains("錢"), "「撿到錢」的「錢」不該被當成贅詞刪掉")
        XCTAssertFalse(result.note.contains("$"))
    }

    /// 當時錯在：分類落到「其他」，而且備註殘留一個 $。
    func testRealDevice_traditionalMarket() {
        let result = parse("今天早上去菜市場買$240")
        XCTAssertEqual(result.amount, 240)
        XCTAssertEqual(result.category, .food)
        XCTAssertFalse(result.note.contains("$"))
    }

    /// NT$ 這種寫法也要整串吃掉。
    func testNewTaiwanDollarPrefix() {
        let result = parse("買咖啡NT$85")
        XCTAssertEqual(result.amount, 85)
        XCTAssertEqual(result.category, .food)
        XCTAssertFalse(result.note.contains("$"))
        XCTAssertFalse(result.note.lowercased().contains("nt"))
    }
}
