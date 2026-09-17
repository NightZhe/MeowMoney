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

    // MARK: - 孤立幣別符號殘留（2026-09-09 實機案例）
    //
    // 實機原話「$120的晚餐$」：語音辨識把講出來的幣別單位吐成了 $，
    // 而且句尾多吐了一個沒有貼著任何數字的孤立 $，`amountEnd` 只會吃掉貼著金額的那個。

    func testRealDevice_isolatedDollarSignAtSentenceEnd() {
        let result = parse("$120的晚餐$")
        XCTAssertEqual(result.amount, 120)
        XCTAssertEqual(result.note, "晚餐")
    }

    func testIsolatedDollarSignAtStart() {
        let result = parse("$買咖啡100")
        XCTAssertEqual(result.amount, 100)
        XCTAssertEqual(result.note, "買咖啡")
    }

    func testIsolatedDollarSignInMiddle() {
        let result = parse("午餐$晚餐300")
        XCTAssertEqual(result.amount, 300)
        XCTAssertEqual(result.note, "午餐晚餐")
    }

    /// 備註被孤立符號清空之後，行為要跟「原本就解析不出品項」一致，不能留白備註。
    func testNoteBecomesEmptyAfterCurrencyCleanupFallsBackToCategoryTitle() {
        let result = parse("$300$")
        XCTAssertEqual(result.amount, 300)
        XCTAssertEqual(result.note, ExpenseCategory.other.title)
    }

    /// 貼著數字的 $ 可能是品項名稱本身的一部分（不是這筆選中的金額），不可以清掉。
    func testDollarSignAttachedToDigitInItemNameIsPreserved() {
        let result = parse("帽子$1商店買了300元")
        XCTAssertEqual(result.amount, 300)
        XCTAssertTrue(result.note.contains("$1"), "貼著數字的 $ 是品項名稱的一部分，不該被清掉")
    }

    /// 「元」「塊」出現在品項名稱中間（不是跟在數字後面當幣別單位）時，不可以被削掉。
    func testItemNameContainingYuanCharacterIsPreserved() {
        let result = parse("元氣早餐100")
        XCTAssertEqual(result.amount, 100)
        XCTAssertEqual(result.note, "元氣早餐")
    }

    func testItemNameContainingKuaiCharacterIsPreserved() {
        let result = parse("大塊牛排500")
        XCTAssertEqual(result.amount, 500)
        XCTAssertEqual(result.note, "大塊牛排")
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

    // MARK: - 金額在前的語序
    //
    // 「一百二十塊的午餐和三十塊的捷運」這種句子，切點在**下一筆金額的開頭**，
    // 不是在金額之後——切錯位置會讓「午餐」跑到下一段，金額配到錯的品項上。
    // 因此以下每個測試都斷言「品項＋金額」的配對，只斷言筆數是驗不到這個 bug 的。

    /// 把 [(備註, 金額)] 攤平成好比對的形狀。
    private func pairs(_ entries: [ParsedEntry]) -> [String] {
        entries.map { "\($0.note)=\($0.amount.map { "\($0)" } ?? "nil")" }
    }

    func testAmountFirstTwoEntriesPairCorrectly() {
        let result = parseMultiple("一百二十塊的午餐和三十塊的捷運")
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(pairs(result), ["午餐=120", "捷運=30"])
        XCTAssertEqual(result.map(\.category), [.food, .transport])
    }

    /// 常見連接詞都要能切，而且配對不變。
    func testAmountFirstConnectorVariants() {
        for connector in ["和", "跟", "還有", "加上", "然後", "以及", "再加"] {
            let result = parseMultiple("一百二十塊的午餐\(connector)三十塊的捷運")
            XCTAssertEqual(pairs(result), ["午餐=120", "捷運=30"], "連接詞「\(connector)」切錯了")
        }
    }

    /// 語音辨識常常一個連接詞都沒有。
    func testAmountFirstWithoutConnector() {
        let result = parseMultiple("一百二十塊的午餐三十塊的捷運")
        XCTAssertEqual(pairs(result), ["午餐=120", "捷運=30"])
    }

    func testAmountFirstWithArabicDigits() {
        XCTAssertEqual(pairs(parseMultiple("120塊的午餐和30塊的捷運")), ["午餐=120", "捷運=30"])
        XCTAssertEqual(pairs(parseMultiple("120元的午餐和30元的捷運")), ["午餐=120", "捷運=30"])
    }

    func testAmountFirstThreeEntries() {
        let result = parseMultiple("一百塊的早餐和三十塊的捷運和兩百塊的午餐")
        XCTAssertEqual(pairs(result), ["早餐=100", "捷運=30", "午餐=200"])
        XCTAssertEqual(result.map(\.category), [.food, .transport, .food])
    }

    /// 單筆的「金額在前」是配對正確的前提：備註要是「捷運」，不是「的捷運」或空字串。
    func testAmountFirstSingleEntryNote() {
        let result = parseMultiple("三十塊的捷運")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(pairs(result), ["捷運=30"])
        XCTAssertEqual(result.first?.category, .transport)
    }

    /// 日期詞在句首時只屬於第一筆，不影響切點。
    func testAmountFirstKeepsDatePrefix() {
        let result = parseMultiple("昨天一百二十塊的午餐和三十塊的捷運")
        XCTAssertEqual(pairs(result), ["午餐=120", "捷運=30"])
        XCTAssertEqual(calendar.dateComponents([.day], from: result[0].date, to: now).day, 1)
    }

    // MARK: - 混合語序

    /// 前一筆品項在前、後一筆金額在前。
    func testMixedOrderItemFirstThenAmountFirst() {
        let result = parseMultiple("午餐300和三十塊的捷運")
        XCTAssertEqual(pairs(result), ["午餐=300", "捷運=30"])
        XCTAssertEqual(result.map(\.category), [.food, .transport])
    }

    /// 前一筆金額在前、後一筆品項在前：中間只有一個連接詞，界線才明確。
    func testMixedOrderAmountFirstThenItemFirst() {
        let result = parseMultiple("一百二十塊的午餐和晚餐500")
        XCTAssertEqual(pairs(result), ["午餐=120", "晚餐=500"])
    }

    /// 界線不明就退回單筆——寧可不切，也不可把金額配給錯的品項。
    func testMixedOrderWithAmbiguousBoundaryStaysSingleEntry() {
        // 兩個連接詞，無從判斷「飲料」屬於哪一筆。
        let twoConnectors = parseMultiple("一百二十塊的午餐和飲料和晚餐500")
        XCTAssertEqual(twoConnectors.count, 1)
        XCTAssertEqual(twoConnectors.first?.amount, 120)

        // 完全沒有連接詞，「午餐飲料晚餐」切不出界線。
        let noConnector = parseMultiple("一百二十塊的午餐飲料晚餐500")
        XCTAssertEqual(noConnector.count, 1)
        XCTAssertEqual(noConnector.first?.amount, 120)
    }

    /// 「和牛」的「和」是品項的一部分，不是連接詞，不可以被切點清掉。
    func testConnectorTrimDoesNotEatItemName() {
        let result = parseMultiple("午餐300和牛500")
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(pairs(result), ["午餐=300", "和牛=500"])
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

    // MARK: - 「塊」：幣別 vs 量詞
    //
    // 「塊」同時是幣別（午餐30塊）與量詞（一塊蛋糕）。判準是**它前面有沒有品項**。
    // 這兩組測試同等重要：只驗筆數看不出金額配到哪個品項，所以一律斷言「品項＝金額」。

    /// 量詞用法：「一塊蛋糕30元」是 30 元的蛋糕，不是一筆 1 元加一筆 30 元。
    func testLeadingKuaiIsCounterNotCurrency() {
        XCTAssertEqual(pairs(parseMultiple("一塊蛋糕30元")), ["蛋糕=30"])
        XCTAssertEqual(pairs(parseMultiple("兩塊蛋糕60元")), ["蛋糕=60"])
        XCTAssertEqual(pairs(parseMultiple("三塊雞排120")), ["雞排=120"])
        XCTAssertEqual(pairs(parseMultiple("3塊雞排120")), ["雞排=120"])
    }

    /// 量詞用法而且沒講金額：數量不可以被當成金額，要留 nil 讓 UI 請使用者補。
    func testCounterKuaiWithoutAmountLeavesAmountNil() {
        let result = parseMultiple("一塊蛋糕")
        XCTAssertEqual(result.count, 1)
        XCTAssertNil(result.first?.amount, "「一塊蛋糕」的一是量詞，不是 1 元")
        XCTAssertEqual(result.first?.note, "蛋糕")
    }

    /// 「半」不是數字，這句沒有量詞問題——備註要完整保留，不可以被削掉「塊」。
    func testHalfKuaiKeepsNoteIntact() {
        let result = parseMultiple("半塊蛋糕20元")
        XCTAssertEqual(pairs(result), ["半塊蛋糕=20"])
    }

    /// 時間詞不算品項，「昨天」開頭的句子仍算「一塊」在片段開頭。
    func testCounterKuaiAfterRelativeDayWord() {
        XCTAssertEqual(pairs(parseMultiple("昨天一塊蛋糕30元")), ["蛋糕=30"])
    }

    /// 量詞判斷不可以蔓延到後面的筆數。
    func testCounterKuaiFollowedByAnotherEntry() {
        XCTAssertEqual(pairs(parseMultiple("一塊蛋糕30元晚餐500")), ["蛋糕=30", "晚餐=500"])
    }

    // 以下是「塊」當幣別的既有行為，修量詞不可以改壞任何一條。

    /// 「塊」前面有品項 → 幣別。
    func testKuaiAfterItemIsCurrency() {
        XCTAssertEqual(pairs(parseMultiple("午餐30塊晚餐50塊")), ["午餐=30", "晚餐=50"])
        XCTAssertEqual(pairs(parseMultiple("早餐50塊午餐120塊")), ["早餐=50", "午餐=120"])
        XCTAssertEqual(pairs(parseMultiple("午餐30塊")), ["午餐=30"])
        XCTAssertEqual(pairs(parseMultiple("午餐三十塊")), ["午餐=30"])
        XCTAssertEqual(pairs(parseMultiple("蛋糕30塊錢")), ["蛋糕=30"])
    }

    /// 「塊」在開頭但後面接「的」→ 金額在前語序，仍是幣別。
    func testKuaiBeforeStopwordIsCurrency() {
        XCTAssertEqual(pairs(parseMultiple("三十塊的捷運")), ["捷運=30"])
        XCTAssertEqual(pairs(parseMultiple("一百二十塊的午餐和三十塊的捷運")), ["午餐=120", "捷運=30"])
    }

    /// 「塊」後面沒有品項（句尾、或接「錢」）→ 幣別。
    func testKuaiWithoutFollowingItemIsCurrency() {
        XCTAssertEqual(parseMultiple("一塊").first?.amount, 1)
        XCTAssertEqual(parseMultiple("一塊錢").first?.amount, 1)
        XCTAssertEqual(parseMultiple("找我五塊").first?.amount, 5)
    }

    /// 其他量詞的備註本來就完整保留，量詞修法不可以動到它們。
    func testOtherCounterWordsKeepNoteIntact() {
        XCTAssertEqual(pairs(parseMultiple("一杯咖啡80元")), ["一杯咖啡=80"])
        XCTAssertEqual(pairs(parseMultiple("兩碗麵150")), ["兩碗麵=150"])
        XCTAssertEqual(pairs(parseMultiple("三包衛生紙99元")), ["三包衛生紙=99"])
        XCTAssertEqual(pairs(parseMultiple("一份雞排70")), ["一份雞排=70"])
    }

    /// 上一輪修好的孤立幣別符號清理，不可以回退。
    func testDollarResidueStillStripped() {
        XCTAssertEqual(pairs(parseMultiple("$120的晚餐$")), ["晚餐=120"])
    }

    // MARK: - 「金額在前」語序＋幣別符號在數字前（實機真實輸入）

    /// 實機真實案例：語音辨識把「塊」吐成 `$` 並放在數字前面。
    /// 「和」是連接詞、後面緊接的 `$` 是下一筆的幣別符號，兩者都不該殘留在第一筆備註裡。
    func testDollarPrefixAmountFirstStripsConnectorAndResidue() {
        let result = parseMultiple("$120的午餐和$30的捷運")
        XCTAssertEqual(pairs(result), ["午餐=120", "捷運=30"])
        XCTAssertEqual(result.map(\.category), [.food, .transport])
    }

    /// 同一種形態下，其他連接詞也不該殘留（不管單字或多字連接詞）。
    func testDollarPrefixAmountFirstConnectorVariants() {
        for connector in ["和", "跟", "還有", "加上", "然後", "以及", "再加"] {
            let result = parseMultiple("$120的午餐\(connector)$30的捷運")
            XCTAssertEqual(pairs(result), ["午餐=120", "捷運=30"], "連接詞「\(connector)」在 $ 前綴形態下切錯了")
        }
    }

    /// 連接詞落在後段片段的開頭、後面又緊接 $ 時，單字連接詞（和／跟）也要清得掉——
    /// 之前只在「後面直接接數字」時才判定是連接詞，$ 夾在中間會擋住這個判斷。
    func testDollarPrefixConnectorAtHeadOfNextPiece() {
        for connector in ["和", "跟"] {
            let result = parseMultiple("午餐300\(connector)$30的捷運")
            XCTAssertEqual(pairs(result), ["午餐=300", "捷運=30"], "連接詞「\(connector)」在片段開頭＋$ 形態下切錯了")
        }
    }

    /// 「和牛」不可以被誤判成連接詞——即使後面接的是 $ 開頭的金額，也要維持既有行為。
    func testDollarPrefixDoesNotMakeConnectorEatItemName() {
        let result = parseMultiple("午餐300和牛$500")
        XCTAssertEqual(pairs(result), ["午餐=300", "和牛=500"])
    }

    // MARK: - 2.0 送審驗收（2026-09-17）
    //
    // 以下每一句都是驗收時逐句重現過的錯誤，一律斷言「品項＝金額」配對。

    /// 問題 A：單獨的「公」不是單位延續字，「公車」「公園」要能切開；完整單位詞「公斤」仍不切。
    func testGongIsNotUnitContinuationUnlessFullUnitWord() {
        XCTAssertEqual(pairs(parseMultiple("捷運二十五公車十五")), ["捷運=25", "公車=15"])
        XCTAssertEqual(pairs(parseMultiple("早餐50公車15")), ["早餐=50", "公車=15"])
        XCTAssertEqual(pairs(parseMultiple("午餐一百公園門票五十")), ["午餐=100", "公園門票=50"])
        XCTAssertEqual(pairs(parseMultiple("買了一公斤蘋果200")), ["買一公斤蘋果=200"])
        XCTAssertEqual(pairs(parseMultiple("騎了3公里油錢50")), ["騎3公里油錢=50"])
    }

    /// 問題 B：品項在前語序，切點後片段開頭的「和／跟」是連接詞。
    func testLeadingSingleCharConnectorIsTrimmedAfterItemFirstSplit() {
        XCTAssertEqual(pairs(parseMultiple("咖啡60和蛋糕90")), ["咖啡=60", "蛋糕=90"])
        XCTAssertEqual(pairs(parseMultiple("早餐40跟午餐100")), ["早餐=40", "午餐=100"])
    }

    /// 問題 B 的例外：以「和／跟」開頭的品項名稱不可以被削掉。
    func testConnectorLeadingItemWordsArePreserved() {
        XCTAssertEqual(pairs(parseMultiple("午餐300和牛500")), ["午餐=300", "和牛=500"])
        XCTAssertEqual(pairs(parseMultiple("咖啡60和菓子120")), ["咖啡=60", "和菓子=120"])
        XCTAssertEqual(pairs(parseMultiple("晚餐200和風沙拉90")), ["晚餐=200", "和風沙拉=90"])
        XCTAssertEqual(pairs(parseMultiple("咖啡60跟團費3000")), ["咖啡=60", "跟團費=3000"])
    }

    /// 問題 C：店名裡的數字不是金額，不參與金額與切點判斷。
    func testStoreNameDigitsAreNotAmounts() {
        XCTAssertEqual(pairs(parseMultiple("7-11咖啡45")), ["7-11咖啡=45"])
        XCTAssertEqual(pairs(parseMultiple("711買咖啡45")), ["711買咖啡=45"])
        XCTAssertEqual(pairs(parseMultiple("85度C咖啡60")), ["85度C咖啡=60"])
        XCTAssertEqual(pairs(parseMultiple("7-ELEVEN咖啡45")), ["7-Eleven咖啡=45"])
        XCTAssertEqual(pairs(parseMultiple("７－１１咖啡４５")), ["7-11咖啡=45"])
        XCTAssertEqual(pairs(parseMultiple("50嵐珍奶55")), ["50嵐珍奶=55"])
        XCTAssertEqual(pairs(parseMultiple("五十嵐紅茶三十五")), ["五十嵐紅茶=35"])
        XCTAssertEqual(pairs(parseMultiple("去台北101看夜景門票600")), ["去台北101看夜景門票=600"])
        XCTAssertEqual(pairs(parseMultiple("統一超商咖啡45")), ["統一超商咖啡=45"])
        XCTAssertEqual(pairs(parseMultiple("全家買飲料35")), ["全家買飲料=35"])
    }

    /// 店名跟前一筆的阿拉伯數字金額黏在一起時，金額不可以吃進店名開頭的中文數字（55 不是 558）。
    func testStoreNameRightAfterAmountStartsNewEntry() {
        XCTAssertEqual(pairs(parseMultiple("50嵐珍奶55八方雲集鍋貼六十")), ["50嵐珍奶=55", "八方雲集鍋貼=60"])
        XCTAssertEqual(pairs(parseMultiple("午餐300去711買咖啡45")), ["午餐=300", "去711買咖啡=45"])
    }

    /// 純數字的店名（711、101）本身可能是金額，沒有地點上下文時仍當金額。
    func testPureDigitStoreNameNeedsContext() {
        XCTAssertEqual(pairs(parseMultiple("午餐101晚餐200")), ["午餐=101", "晚餐=200"])
        XCTAssertEqual(pairs(parseMultiple("101元的便當")), ["便當=101"])
        XCTAssertEqual(pairs(parseMultiple("今天711買咖啡45")), ["711買咖啡=45"])
        XCTAssertEqual(pairs(parseMultiple("昨天在711買便當85")), ["在711買便當=85"])
    }

    /// 問題 D：單獨的「花」是品項的一部分，只有動詞用法才清。
    func testFlowerCharacterIsKeptInItemNames() {
        XCTAssertEqual(pairs(parseMultiple("爆米花150")), ["爆米花=150"])
        XCTAssertEqual(pairs(parseMultiple("花枝丸60")), ["花枝丸=60"])
        XCTAssertEqual(pairs(parseMultiple("花生湯40")), ["花生湯=40"])
        XCTAssertEqual(pairs(parseMultiple("買花300")), ["買花=300"])
        XCTAssertEqual(pairs(parseMultiple("豆花50")), ["豆花=50"])
    }

    /// 問題 D：動詞用法的「花」照樣清掉。
    func testSpendVerbHuaIsStripped() {
        XCTAssertEqual(pairs(parseMultiple("今天花了200吃午餐")), ["吃午餐=200"])
        XCTAssertEqual(pairs(parseMultiple("今天花200吃午餐")), ["吃午餐=200"])
        XCTAssertEqual(pairs(parseMultiple("花200買書")), ["買書=200"])
        XCTAssertEqual(pairs(parseMultiple("花掉500買衣服")), ["買衣服=500"])
        XCTAssertEqual(pairs(parseMultiple("總共花300買菜")), ["買菜=300"])
    }

    /// 送審前的回歸清單：修 A～D 不可以改壞任何一條。
    func testAcceptanceRegressionList() {
        let cases: [(String, [String])] = [
            ("午餐300晚餐500", ["午餐=300", "晚餐=500"]),
            ("午餐200晚餐300宵夜200", ["午餐=200", "晚餐=300", "宵夜=200"]),
            ("$120的午餐和$30的捷運", ["午餐=120", "捷運=30"]),
            ("一百二十塊的午餐和三十塊的捷運", ["午餐=120", "捷運=30"]),
            ("一塊蛋糕30元", ["蛋糕=30"]),
            ("一塊蛋糕", ["蛋糕=nil"]),
            ("半塊蛋糕20元", ["半塊蛋糕=20"]),
            ("30塊車資", ["車資=30"]),
            ("$120的晚餐$", ["晚餐=120"]),
            ("元氣早餐100", ["元氣早餐=100"]),
            ("大塊牛排500", ["大塊牛排=500"]),
            ("買球鞋3,280元", ["買球鞋=3280"]),
            ("買了3個便當共300", ["買3個便當=300"]),
            ("一杯咖啡80元", ["一杯咖啡=80"]),
            ("兩碗麵150", ["兩碗麵=150"]),
            ("三包衛生紙99元", ["三包衛生紙=99"]),
            ("一份雞排70", ["一份雞排=70"]),
            ("午餐300和牛500", ["午餐=300", "和牛=500"]),
            ("全家買飲料35", ["全家買飲料=35"]),
            ("買了一公斤蘋果200", ["買一公斤蘋果=200"]),
            ("今天花了200吃午餐", ["吃午餐=200"])
        ]
        for (input, expected) in cases {
            XCTAssertEqual(pairs(parseMultiple(input)), expected, "「\(input)」")
        }
        // $ 開頭的第二筆：備註不可以夾著「和」或「$」。
        let dollar = parseMultiple("$120的午餐和$30的捷運")
        XCTAssertFalse(dollar.contains { $0.note.contains("和") || $0.note.contains("$") })
    }
}
