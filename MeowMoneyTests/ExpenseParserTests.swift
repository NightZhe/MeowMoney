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

    // MARK: - 金錢流向
    //
    // 中文靠語序決定錢的方向：「男友給我」是進帳，「我給男友」是支出。
    // 原本只比對收入關鍵字，兩種都判成支出。

    func testSomeoneGivesMeIsIncome() {
        XCTAssertTrue(parse("男友給我5000").isIncome)
        XCTAssertTrue(parse("媽媽給我2000").isIncome)
        XCTAssertTrue(parse("老婆轉給我一萬").isIncome)
        XCTAssertTrue(parse("公司退我停車費300").isIncome)
        XCTAssertTrue(parse("爸爸包給我紅包6000").isIncome)
    }

    /// 省略「我」的說法：「男友給5000」在口語裡就是他給我。
    func testPersonGivesWithoutObjectIsIncome() {
        let result = parse("男友給5000")
        XCTAssertEqual(result.amount, 5000)
        XCTAssertTrue(result.isIncome)
        XCTAssertEqual(result.category, .income)
    }

    /// 反方向必須維持支出，否則修一個 bug 會製造另一個。
    func testIGiveSomeoneIsExpense() {
        XCTAssertFalse(parse("我給男友5000").isIncome)
        XCTAssertFalse(parse("給男友5000").isIncome)
        XCTAssertFalse(parse("我轉給老婆一萬").isIncome)
        XCTAssertFalse(parse("我還朋友500").isIncome)
        XCTAssertFalse(parse("包紅包給朋友3600").isIncome)
        XCTAssertFalse(parse("送給女友禮物2000").isIncome)
    }

    /// 「還給我」含有「還給」，方向判斷的順序不能讓它被誤判成支出。
    func testInboundBeatsOutboundWhenBothMatch() {
        XCTAssertTrue(parse("朋友還給我1200").isIncome)
        XCTAssertFalse(parse("我還給朋友1200").isIncome)
    }

    /// NT$ 這種寫法也要整串吃掉。
    func testNewTaiwanDollarPrefix() {
        let result = parse("買咖啡NT$85")
        XCTAssertEqual(result.amount, 85)
        XCTAssertEqual(result.category, .food)
        XCTAssertFalse(result.note.contains("$"))
        XCTAssertFalse(result.note.lowercased().contains("nt"))
    }

    // MARK: - 一句話多筆（07）

    private func parseMultiple(_ text: String) -> [ParsedEntry] {
        ExpenseParser.parseMultiple(text, now: now, calendar: calendar)
    }

    func testParseMultipleSingleSentenceMatchesParse() {
        let text = "午餐便當一百二"
        let multiple = parseMultiple(text)
        XCTAssertEqual(multiple.count, 1)
        XCTAssertEqual(multiple.first, parse(text))
    }

    func testParseMultipleThreeSentencesSplitBySpace() {
        let result = parseMultiple("早餐五十 捷運三十 午餐一百二")
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result[0].amount, 50)
        XCTAssertEqual(result[0].category, .food)
        XCTAssertEqual(result[1].amount, 30)
        XCTAssertEqual(result[1].category, .transport)
        XCTAssertEqual(result[2].amount, 120)
        XCTAssertEqual(result[2].category, .food)
    }

    func testParseMultipleSplitsOnPunctuation() {
        let result = parseMultiple("早餐五十、捷運三十，午餐一百二。")
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result.map(\.amount), [50, 30, 120])
    }

    func testParseMultipleEmptyStringReturnsEmpty() {
        XCTAssertEqual(parseMultiple(""), [])
    }

    func testParseMultipleWhitespaceOnlyReturnsEmpty() {
        XCTAssertEqual(parseMultiple("   \n\t  "), [])
    }

    func testParseMultipleCompletelyUnparseableReturnsEmpty() {
        // 純標點、沒有任何實質內容——不是「切不出金額」，是根本沒有可切的句子。
        XCTAssertEqual(parseMultiple("，，，、。；"), [])
    }

    func testParseMultipleSegmentWithoutAmountIsStillReturned() {
        let result = parseMultiple("早餐五十 心情不錯 午餐一百二")
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result[0].amount, 50)
        XCTAssertNil(result[1].amount)
        XCTAssertFalse(result[1].isUsable)
        XCTAssertEqual(result[2].amount, 120)
    }

    /// 千分位逗號不該被當成句界（半形逗號故意排除在句界標點之外）。
    func testParseMultipleDoesNotSplitThousandSeparatorComma() {
        let result = parseMultiple("買球鞋3,280元")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.amount, 3280)
    }

    // MARK: - 無分隔符的真實語音輸入（07 修正）
    //
    // 以下四個字串是從使用者 iPhone 的 SwiftData store 撈出來的實際 `Expense.transcript`，
    // 一個空白、一個標點都沒有。舊版切句只認空白與標點，所以這些輸入從來沒被切開過。

    func testRealTranscriptTwoEntries() {
        let result = parseMultiple("午餐300晚餐500")
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.map(\.amount), [300, 500])
        XCTAssertEqual(result.map(\.note), ["午餐", "晚餐"])
        XCTAssertEqual(result.map(\.category), [.food, .food])
    }

    func testRealTranscriptThreeEntries() {
        let result = parseMultiple("午餐200晚餐300宵夜200")
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result.map(\.amount), [200, 300, 200])
        XCTAssertEqual(result.map(\.note), ["午餐", "晚餐", "宵夜"])
    }

    func testRealTranscriptTwoEntriesShortAmounts() {
        let result = parseMultiple("午餐120晚餐200")
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.map(\.amount), [120, 200])
        XCTAssertEqual(result.map(\.note), ["午餐", "晚餐"])
    }

    func testRealTranscriptThreeEntriesOutOfOrder() {
        let result = parseMultiple("午餐300宵夜200晚餐500")
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result.map(\.amount), [300, 200, 500])
        XCTAssertEqual(result.map(\.note), ["午餐", "宵夜", "晚餐"])
    }

    /// 每一段自己的 transcript 要是自己的片段（「重新解析」功能依賴這個行為）。
    func testRealTranscriptKeepsPerEntryTranscript() {
        let result = parseMultiple("午餐300晚餐500")
        XCTAssertEqual(result.map(\.transcript), ["午餐300", "晚餐500"])
    }

    // MARK: - 無分隔符的邊界情況

    /// 量詞：「3個」是數量不是金額，不可以在這裡切。
    func testNoSplitOnCounterWord() {
        let result = parseMultiple("買了3個便當共300")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.amount, 300)
    }

    /// 千分位逗號在沒有分隔符的句子裡仍然不是句界。
    func testSplitsAfterThousandSeparatorAmountOnly() {
        let result = parseMultiple("買球鞋3,280元晚餐500")
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.map(\.amount), [3280, 500])
    }

    /// 幣別單位（元／塊／塊錢）屬於金額的一部分，切點要在單位之後。
    func testSplitsAfterCurrencySuffix() {
        XCTAssertEqual(parseMultiple("午餐300元晚餐500").map(\.amount), [300, 500])
        XCTAssertEqual(parseMultiple("午餐300塊晚餐500").map(\.amount), [300, 500])
        XCTAssertEqual(parseMultiple("午餐300塊錢晚餐500").map(\.amount), [300, 500])
    }

    /// 中文數字（含台灣口語省略「一百二」＝120）也要切得開。
    func testSplitsChineseNumeralsWithoutSeparator() {
        let result = parseMultiple("午餐一百二晚餐三百")
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.map(\.amount), [120, 300])

        let commute = parseMultiple("早餐五十捷運三十")
        XCTAssertEqual(commute.count, 2)
        XCTAssertEqual(commute.map(\.amount), [50, 30])
        XCTAssertEqual(commute.map(\.category), [.food, .transport])
    }

    /// 時間詞開頭不是品項，維持單筆，而且日期照樣要解析出來。
    func testTimeWordPrefixStaysSingleEntry() {
        let today = parseMultiple("今天午餐200")
        XCTAssertEqual(today.count, 1)
        XCTAssertEqual(today.first?.amount, 200)

        let yesterday = parseMultiple("昨天晚餐300")
        XCTAssertEqual(yesterday.count, 1)
        XCTAssertEqual(yesterday.first?.amount, 300)
        XCTAssertEqual(calendar.dateComponents([.day], from: yesterday[0].date, to: now).day, 1)
    }

    /// 時間詞出現在句中時是下一筆的開頭。
    func testTimeWordInsideSentenceStartsNewEntry() {
        let result = parseMultiple("今天午餐200昨天晚餐300")
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.map(\.amount), [200, 300])
        XCTAssertEqual(calendar.dateComponents([.day], from: result[1].date, to: now).day, 1)
    }

    /// 「8月8號」的月/號是日期單位，不是新品項的開頭。
    func testExplicitDateIsNotSplit() {
        let result = parseMultiple("8月8號午餐300")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.amount, 300)
    }

    /// 後面沒有第二筆金額就不切——寧可少切，不可切錯。
    func testDoesNotSplitWhenNoSecondAmount() {
        let result = parseMultiple("午餐300很好吃")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.amount, 300)
    }

    /// 「金額在前」的句子需要語意理解，維持既有的單筆行為（「的」不當句界）。
    func testAmountFirstSentenceStaysSingleEntry() {
        let result = parseMultiple("一百二十塊的午餐和三十塊的捷運")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.amount, 120)
    }

    /// 語音辨識的雜訊：切不乾淨可以接受，但不可以 crash，也不可以算錯金額。
    func testNoisyTranscriptDoesNotProduceWrongAmounts() {
        let result = parseMultiple("午餐200晚餐宵夜200今天午餐200")
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result.map(\.amount), [200, 200, 200])
    }

    /// 「還有」是語助詞，切在它前面，第二筆的備註不該留下它。
    func testSplitsBeforeFillerWord() {
        let result = parseMultiple("午餐300還有晚餐500")
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.map(\.amount), [300, 500])
        XCTAssertEqual(result[1].note, "晚餐")
    }

    /// 「點」是量詞（三點），但「點心」是品項——不可以被量詞規則擋住。
    func testCounterExceptionForDimSum() {
        let result = parseMultiple("午餐300點心200")
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.map(\.amount), [300, 200])
    }

    /// 全形數字（正規化前）也要切得開。
    func testSplitsFullWidthDigits() {
        let result = parseMultiple("午餐３００晚餐５００")
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.map(\.amount), [300, 500])
    }
}
