import Foundation

/// 一句話解析後的結果。金額可能為 nil（沒聽到數字），由 UI 提示使用者補。
struct ParsedEntry: Equatable {
    var amount: Decimal?
    var category: ExpenseCategory
    var note: String
    var date: Date
    var isIncome: Bool
    var transcript: String

    var isUsable: Bool {
        if let amount { return amount > 0 }
        return false
    }
}

/// 把一句中文口語轉成一筆帳。
///
/// 例：
/// - 「午餐便當一百二」→ 120 / 餐飲 / 便當
/// - 「昨天搭計程車 250 元」→ 250 / 交通 / 計程車（日期 -1 天）
/// - 「薪水入帳十三萬」→ 130000 / 收入
enum ExpenseParser {

    // MARK: - 對外入口

    static func parse(_ raw: String, now: Date = Date(), calendar: Calendar = .current) -> ParsedEntry {
        let normalized = normalize(raw)

        var working = normalized
        let dateResult = extractDate(from: working, now: now, calendar: calendar)
        working = dateResult.remaining

        let isIncome = detectIncome(in: normalized)

        let amountResult = extractAmount(from: working)
        working = amountResult.remaining

        let category: ExpenseCategory = isIncome ? .income : detectCategory(in: normalized) ?? .other
        let note = makeNote(from: working, fallback: category, isIncome: isIncome)

        return ParsedEntry(
            amount: amountResult.amount,
            category: category,
            note: note,
            date: dateResult.date,
            isIncome: isIncome,
            transcript: raw.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    // MARK: - 正規化

    /// 全形轉半形、小寫化、標點換成空白。中文字元不受影響。
    static func normalize(_ raw: String) -> String {
        var text = raw.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? raw
        text = text.lowercased()
        text = text.replacingOccurrences(of: ",", with: "")
        let punctuation: Set<Character> = ["，", "、", "。", "！", "!", "？", "?", "；", ";", "：", ":", "~", "-"]
        text = String(text.map { punctuation.contains($0) ? " " : $0 })
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - 日期

    private static let relativeDayWords: [(word: String, offset: Int)] = [
        ("大前天", -3), ("前天", -2), ("昨天", -1), ("昨日", -1),
        ("今天", 0), ("今日", 0), ("剛剛", 0), ("剛才", 0)
    ]

    static func extractDate(
        from text: String,
        now: Date,
        calendar: Calendar
    ) -> (date: Date, remaining: String) {
        var working = text

        // 1. 明確日期：X月Y號 / X月Y日
        if let explicit = extractExplicitDate(from: working, now: now, calendar: calendar) {
            return (explicit.date, explicit.remaining)
        }

        // 2. 相對日期：昨天 / 前天 …
        for entry in relativeDayWords where working.contains(entry.word) {
            working = working.replacingOccurrences(of: entry.word, with: " ")
            let date = calendar.date(byAdding: .day, value: entry.offset, to: now) ?? now
            return (date, working)
        }

        return (now, working)
    }

    private static func extractExplicitDate(
        from text: String,
        now: Date,
        calendar: Calendar
    ) -> (date: Date, remaining: String)? {
        let chars = Array(text)
        guard let monthMarker = chars.firstIndex(of: "月") else { return nil }

        // 「月」之前的數字 = 月份
        var start = monthMarker - 1
        while start >= 0, ChineseNumberParser.isNumericCharacter(chars[start]) { start -= 1 }
        let monthStart = start + 1
        guard monthStart < monthMarker else { return nil }
        guard let month = ChineseNumberParser.value(of: String(chars[monthStart..<monthMarker])),
              month >= 1, month <= 12 else { return nil }

        // 「月」之後的數字 = 日
        let dayStart = monthMarker + 1
        guard dayStart < chars.count else { return nil }
        var dayEnd = dayStart
        while dayEnd < chars.count, ChineseNumberParser.isNumericCharacter(chars[dayEnd]) { dayEnd += 1 }
        guard dayEnd > dayStart,
              let day = ChineseNumberParser.value(of: String(chars[dayStart..<dayEnd])),
              day >= 1, day <= 31 else { return nil }

        // 吃掉後面的「日」或「號」
        var removeEnd = dayEnd
        if removeEnd < chars.count, chars[removeEnd] == "日" || chars[removeEnd] == "號" {
            removeEnd += 1
        }

        var components = calendar.dateComponents([.year], from: now)
        components.month = (month as NSDecimalNumber).intValue
        components.day = (day as NSDecimalNumber).intValue
        components.hour = 12
        guard let date = calendar.date(from: components) else { return nil }

        var remaining = String(chars[0..<monthStart])
        remaining += " "
        if removeEnd < chars.count { remaining += String(chars[removeEnd...]) }
        return (date, remaining)
    }

    // MARK: - 金額

    private static let currencySuffixes: Set<Character> = ["元", "塊", "圓", "$"]
    /// 量詞：接在數字後面代表「數量」而不是金額，例如「兩個便當」。
    private static let counterWords: Set<Character> = [
        "個", "顆", "杯", "碗", "隻", "張", "份", "位", "瓶", "包", "件",
        "次", "趟", "天", "點", "人", "台", "支", "本", "盒", "條", "片", "碟"
    ]

    struct AmountCandidate {
        var value: Decimal
        var start: Int
        var end: Int          // exclusive，已含吃掉的後綴
        var hasCurrency: Bool
        var isCounter: Bool
    }

    static func extractAmount(from text: String) -> (amount: Decimal?, remaining: String) {
        let chars = Array(text)
        var candidates: [AmountCandidate] = []

        var i = 0
        while i < chars.count {
            guard ChineseNumberParser.isNumericCharacter(chars[i]) else {
                i += 1
                continue
            }
            var j = i
            while j < chars.count, ChineseNumberParser.isNumericCharacter(chars[j]) { j += 1 }

            var runEnd = j
            // 去掉尾端多餘的小數點，例如「100.」
            while runEnd > i, chars[runEnd - 1] == "." { runEnd -= 1 }
            let run = String(chars[i..<runEnd])

            var value = ChineseNumberParser.value(of: run)
            var consumedEnd = j
            var hasCurrency = false
            var isCounter = false

            if consumedEnd < chars.count {
                let next = chars[consumedEnd]
                if next == "k" {
                    value = value.map { $0 * 1000 }
                    consumedEnd += 1
                    hasCurrency = true
                } else if currencySuffixes.contains(next) {
                    hasCurrency = true
                    consumedEnd += 1
                    // 「元」「塊」後面常接「錢」「整」
                    if consumedEnd < chars.count,
                       chars[consumedEnd] == "錢" || chars[consumedEnd] == "整" {
                        consumedEnd += 1
                    }
                } else if counterWords.contains(next) {
                    isCounter = true
                }
            }

            // 前面帶 $ 也算金額訊號，而且要連 $ 一起吃掉，
            // 否則「買Zara $170」的備註會殘留一個孤零零的 $。
            var startIndex = i
            if startIndex > 0, chars[startIndex - 1] == "$" {
                hasCurrency = true
                startIndex -= 1
                // 一併吃掉 "NT$" 的 NT（正規化時已轉小寫）
                if startIndex >= 2, chars[startIndex - 2] == "n", chars[startIndex - 1] == "t" {
                    startIndex -= 2
                }
            }

            if let value, value > 0 {
                candidates.append(
                    AmountCandidate(
                        value: value,
                        start: startIndex,
                        end: consumedEnd,
                        hasCurrency: hasCurrency,
                        isCounter: isCounter
                    )
                )
            }
            i = j
        }

        guard let chosen = pickAmount(from: candidates) else {
            return (nil, text)
        }

        var remaining = String(chars[0..<chosen.start])
        remaining += " "
        if chosen.end < chars.count { remaining += String(chars[chosen.end...]) }
        return (chosen.value, remaining)
    }

    private static func pickAmount(from candidates: [AmountCandidate]) -> AmountCandidate? {
        guard !candidates.isEmpty else { return nil }
        // 優先序：帶幣別後綴 > 一般數字 > 量詞數字。同組取最大值。
        let withCurrency = candidates.filter(\.hasCurrency)
        if !withCurrency.isEmpty { return withCurrency.max(by: { $0.value < $1.value }) }

        let plain = candidates.filter { !$0.isCounter }
        if !plain.isEmpty { return plain.max(by: { $0.value < $1.value }) }

        return candidates.max(by: { $0.value < $1.value })
    }

    // MARK: - 收入 / 分類

    static func detectIncome(in text: String) -> Bool {
        ExpenseCategory.income.keywords.contains { text.contains($0) }
    }

    /// 取命中關鍵字最長（最具體）的分類；同長度時取命中數量多的。
    static func detectCategory(in text: String) -> ExpenseCategory? {
        var best: (category: ExpenseCategory, length: Int, count: Int)?

        for category in ExpenseCategory.expenseCases {
            var maxLength = 0
            var count = 0
            for keyword in category.keywords where text.contains(keyword) {
                count += 1
                maxLength = max(maxLength, keyword.count)
            }
            guard count > 0 else { continue }
            if let current = best {
                if maxLength > current.length || (maxLength == current.length && count > current.count) {
                    best = (category, maxLength, count)
                }
            } else {
                best = (category, maxLength, count)
            }
        }

        return best?.category
    }

    // MARK: - 備註

    /// 依長度由長到短移除，避免短詞先吃掉長詞的一部分。
    private static let fillerWords: [String] = [
        "幫我記一筆", "幫我記帳", "記一筆", "記帳", "記下", "幫我",
        "總共花了", "一共花了", "總共", "一共", "花了", "花費", "支出", "收入",
        "付了", "刷了", "大概", "差不多", "左右", "而已", "然後", "還有",
        // 不放單獨的「錢」：它會把「撿到錢」吃成「撿到」。
        // 數字後面的「元/塊/錢」已由 extractAmount 的幣別後綴處理掉了。
        "塊錢", "元整", "元", "塊", "圓", "花", "共", "了", "的", "喔", "啦", "吧", "嗎", "呢"
    ]

    static func makeNote(from text: String, fallback: ExpenseCategory, isIncome: Bool) -> String {
        var working = text
        for word in fillerWords.sorted(by: { $0.count > $1.count }) {
            working = working.replacingOccurrences(of: word, with: " ")
        }
        working = working
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined()

        if working.count > 24 {
            working = String(working.prefix(24))
        }
        if working.isEmpty {
            return isIncome ? "收入" : fallback.title
        }
        return working
    }
}
