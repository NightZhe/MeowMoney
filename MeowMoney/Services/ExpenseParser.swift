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

    // MARK: - 一句話多筆（07）

    /// 把「早餐五十 捷運三十 午餐一百二」這種一次講好幾筆的話，切成多個 `ParsedEntry`。
    ///
    /// 也切得開語音辨識輸出的「午餐300晚餐500」——中文語音辨識不會插入空白或標點，
    /// 所以除了停頓與標點，還會找「金額結束、後面又接非金額文字」的邊界（見
    /// `splitByAmountBoundaries`）。兩種語序都支援：品項在前（`午餐300`）與
    /// 金額在前（`三十塊的捷運`）；切點位置取決於語序，切錯位置會把品項配到別筆的金額上。
    /// 每一段都直接丟給既有的 `parse`，核心解析邏輯不重寫。
    ///
    /// - 單句輸入（切不出第二段）回傳單一元素，結果與直接呼叫 `parse` 相同。
    /// - 完全沒有內容（空字串、純空白、純標點）回傳空陣列，不回傳「空的一筆」。
    /// - 切出來的某段沒有金額，仍會回傳該筆（`amount` 為 nil），交給 UI 決定要不要讓使用者補。
    static func parseMultiple(
        _ raw: String,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [ParsedEntry] {
        splitIntoSentences(raw).map { parse($0, now: now, calendar: calendar) }
    }

    /// 半形逗號故意不當句界：「3,280」這種千分位寫法在既有 `parse` 裡是合法金額，
    /// 切句規則不該把它拆成「3」「280」兩段。全形頓號/逗號在中文口語裡不會拿來寫千分位，
    /// 才收進句界標點。
    private static let sentenceBoundaryPunctuation: Set<Character> = [
        "、", "，", "。", "；", ";"
    ]

    /// 兩階段切句：
    /// 1. 先照停頓（空白/換行）與列舉標點切——使用者若真的有停頓，那是最可靠的訊號。
    /// 2. 每一段再照「金額邊界」切——中文語音辨識**不會**插入空白或標點，
    ///    實機存下的 transcript 長這樣：`午餐300晚餐500`、`午餐200晚餐300宵夜200`。
    static func splitIntoSentences(_ raw: String) -> [String] {
        splitByExplicitSeparators(raw).flatMap(splitByAmountBoundaries)
    }

    private static func splitByExplicitSeparators(_ raw: String) -> [String] {
        var segments: [String] = []
        var current = ""
        for char in raw {
            if char.isWhitespace || sentenceBoundaryPunctuation.contains(char) {
                if !current.isEmpty {
                    segments.append(current)
                    current = ""
                }
            } else {
                current.append(char)
            }
        }
        if !current.isEmpty {
            segments.append(current)
        }
        return segments
    }

    // MARK: - 無分隔符切句

    /// 接在數字後面、代表「這個數字不是一筆帳的金額」或「數字還沒講完」的字。
    /// 例：「3月8號」的月、「30度」的度、「300多」的多。碰到這些字就不切。
    private static let amountContinuationCharacters: Set<Character> = [
        "月", "日", "號", "年", "時", "分", "秒", "半",
        "多", "幾", "成", "折", "樓", "層", "歲", "度", "倍", "週", "周",
        "公", "克", "斤", "磅", "升", "米", "尺", "吋", "%", "％"
    ]

    /// 第一個字雖然落在量詞/延續字裡，但兩個字合起來是一般詞彙，不該擋住切句。
    /// 例：「點」是量詞（三點），但「點心」是品項。
    private static let continuationExceptions: Set<String> = ["點心", "包子"]

    /// 不可能當品項開頭的虛字。「金額＋的」是「金額在前」語序的判斷訊號
    /// （見 `AmountSpan.isAmountFirst`），所以在「品項在前」的切點上碰到它就不切。
    private static let boundaryStopwords: Set<Character> = ["的", "之"]

    /// 口語連接詞。它出現在切點上時不屬於任何一筆，要從片段的頭尾拿掉，
    /// 否則備註會變成「和捷運」。依長度由長到短比對。
    private static let connectorWords = ["還有", "加上", "以及", "然後", "再加", "和", "跟"]

    /// 一段文字裡的一個數字片段，含位置與語序判斷。
    private struct AmountSpan {
        /// 數字起點。
        var start: Int
        /// exclusive，已含幣別後綴（「300元」的「元」算在內）。
        var end: Int
        /// 後面接「的」＋文字，例如「三十塊的捷運」：這筆的品項在金額**後面**。
        var isAmountFirst: Bool
    }

    /// 在沒有任何分隔符的口語裡切出多筆。切點位置取決於語序：
    /// - 品項在前（`午餐300晚餐500`）：切在金額（含幣別後綴）之後，也就是下一個品項的開頭。
    /// - 金額在前（`一百二十塊的午餐和三十塊的捷運`）：切在**下一筆金額的開頭**，
    ///   否則「午餐」會留在下一段，變成金額配錯品項。
    ///
    /// 刻意保守——「寧可少切，不可切錯；寧可不切，也不可把金額配給錯的品項」：
    /// - 後面沒有第二個金額就不切（「午餐300很好吃」維持一筆，金額仍是 300）。
    /// - 數字後面接量詞就不切（「買了3個便當共300」是一筆）。
    /// - 語序混合而且中間沒有唯一的連接詞可當切點時不切（見 `splitPoint`）。
    static func splitByAmountBoundaries(_ segment: String) -> [String] {
        let chars = Array(segment)
        guard chars.count > 1 else { return chars.isEmpty ? [] : [segment] }
        // 偵測用副本：只把全形阿拉伯數字換成半形，長度 1:1，索引才對得上原字串。
        let probe = chars.map(halfWidthDigit)

        let cuts = splitPoints(in: probe)
        guard !cuts.isEmpty else { return [segment] }

        let bounds = [0] + cuts + [chars.count]
        var pieces: [String] = []
        for i in 0..<(bounds.count - 1) {
            let piece = String(chars[bounds[i]..<bounds[i + 1]])
            pieces.append(trimConnectors(piece, head: i > 0, tail: i < bounds.count - 2))
        }
        return pieces.filter { !$0.isEmpty }
    }

    /// 掃出所有「值 > 0」的數字片段，順便判斷每一段的語序。
    private static func amountSpans(in probe: [Character]) -> [AmountSpan] {
        var spans: [AmountSpan] = []
        var index = 0
        while index < probe.count {
            guard ChineseNumberParser.isNumericCharacter(probe[index]) else {
                index += 1
                continue
            }
            let runEnd = numericRunEnd(in: probe, from: index)
            guard let value = numericValue(in: probe, from: index, to: runEnd), value > 0 else {
                index = max(runEnd, index + 1)
                continue
            }
            let end = amountEnd(in: probe, runEnd: runEnd)
            spans.append(
                AmountSpan(start: index, end: end, isAmountFirst: isAmountFirst(in: probe, at: end))
            )
            index = max(runEnd, index + 1)
        }
        return spans
    }

    /// 「金額在前」的訊號：金額（含幣別後綴）之後接「的／之」，而且後面還有字當品項。
    private static func isAmountFirst(in probe: [Character], at end: Int) -> Bool {
        guard end < probe.count, boundaryStopwords.contains(probe[end]) else { return false }
        let itemStart = end + 1
        guard itemStart < probe.count else { return false }
        return !ChineseNumberParser.isNumericCharacter(probe[itemStart])
    }

    private static func splitPoints(in probe: [Character]) -> [Int] {
        let spans = amountSpans(in: probe)
        guard spans.count > 1 else { return [] }

        var cuts: [Int] = []
        for (a, b) in zip(spans, spans.dropFirst()) {
            guard let cut = splitPoint(between: a, and: b, in: probe) else { continue }
            guard cut > (cuts.last ?? 0), cut < probe.count else { continue }
            cuts.append(cut)
        }
        return cuts
    }

    /// 決定相鄰兩筆金額之間的切點。回傳 nil = 判斷不了，維持同一段。
    private static func splitPoint(between a: AmountSpan, and b: AmountSpan, in probe: [Character]) -> Int? {
        guard a.isAmountFirst else {
            // 品項在前：切在這筆金額之後，那裡就是下一個品項的開頭。
            guard a.end < probe.count, isBoundary(in: probe, at: a.end) else { return nil }
            return a.end
        }
        if b.isAmountFirst {
            // 兩筆都是金額在前：切在下一筆金額的開頭，中間必須真的有品項文字。
            guard hasItemText(in: probe, from: a.end, to: b.start) else { return nil }
            return b.start
        }
        // 語序混合（前一筆金額在前、後一筆品項在前）：中間的文字同時是前一筆的品項
        // 與後一筆的品項，只有出現唯一一個連接詞時才知道界線在哪，否則寧可不切。
        guard let connector = soleConnectorRange(in: probe, from: a.end, to: b.start),
              hasItemText(in: probe, from: a.end, to: connector.lowerBound) else { return nil }
        // 切在連接詞之後，連接詞留在前一段的尾巴，由 `trimConnectors` 拿掉。
        return connector.upperBound
    }

    /// 兩個位置之間扣掉虛字、空白與連接詞後還有沒有東西可以當品項。
    private static func hasItemText(in probe: [Character], from start: Int, to end: Int) -> Bool {
        guard start < end else { return false }
        let text = trimConnectors(String(probe[start..<end]), head: true, tail: true)
        return text.contains {
            !boundaryStopwords.contains($0) && !$0.isWhitespace
        }
    }

    /// 區間內唯一一個連接詞的範圍。沒有或超過一個都回傳 nil（超過一個 = 界線不明）。
    private static func soleConnectorRange(in probe: [Character], from start: Int, to end: Int) -> Range<Int>? {
        guard start < end else { return nil }
        var found: Range<Int>?
        var index = start
        while index < end {
            if let word = connectorWords.first(where: { matches($0, in: probe, at: index, limit: end) }) {
                if found != nil { return nil }
                found = index..<(index + word.count)
                index += word.count
            } else {
                index += 1
            }
        }
        return found
    }

    private static func matches(_ word: String, in probe: [Character], at index: Int, limit: Int) -> Bool {
        let characters = Array(word)
        guard index + characters.count <= limit else { return false }
        return Array(probe[index..<(index + characters.count)]) == characters
    }

    /// 切點上的連接詞不屬於任何一筆，拿掉它。`head`／`tail` 只在該端真的是切點時為 true，
    /// 所以沒被切過的整句不受影響。
    /// 單字連接詞（和／跟）只在後面直接接數字時才拿掉——否則「和牛500」會被削成「牛500」。
    private static func trimConnectors(_ piece: String, head: Bool, tail: Bool) -> String {
        var text = piece
        if head {
            for word in connectorWords where text.hasPrefix(word) {
                if word.count == 1,
                   let next = text.dropFirst().first,
                   !ChineseNumberParser.isNumericCharacter(next) {
                    break
                }
                text = String(text.dropFirst(word.count))
                break
            }
        }
        if tail {
            for word in connectorWords where text.hasSuffix(word) {
                text = String(text.dropLast(word.count))
                break
            }
        }
        return text
    }

    /// 數字片段的結束位置（exclusive）。夾在阿拉伯數字之間的半形逗號算數字的一部分。
    private static func numericRunEnd(in chars: [Character], from start: Int) -> Int {
        var end = start
        while end < chars.count {
            if ChineseNumberParser.isNumericCharacter(chars[end]) {
                end += 1
            } else if chars[end] == ",",
                      end > start,
                      end + 1 < chars.count,
                      isArabicDigit(chars[end - 1]),
                      isArabicDigit(chars[end + 1]) {
                end += 1
            } else {
                break
            }
        }
        // 去掉尾端多餘的小數點，例如「100.」
        while end > start, chars[end - 1] == "." { end -= 1 }
        return end
    }

    private static func numericValue(in chars: [Character], from start: Int, to end: Int) -> Decimal? {
        guard end > start else { return nil }
        let digits = String(chars[start..<end]).replacingOccurrences(of: ",", with: "")
        return ChineseNumberParser.value(of: digits)
    }

    /// 把幣別後綴一併算進金額範圍，這樣「午餐300元晚餐500」會切在「元」之後。
    private static func amountEnd(in chars: [Character], runEnd: Int) -> Int {
        var end = runEnd
        guard end < chars.count else { return end }
        let next = chars[end]
        if next == "k" || next == "K" {
            end += 1
        } else if currencySuffixes.contains(next) {
            end += 1
            if end < chars.count, chars[end] == "錢" || chars[end] == "整" { end += 1 }
        }
        return end
    }

    /// 「品項在前」語序的切點檢查：金額之後這個位置能不能當下一筆的開頭。
    private static func isBoundary(in chars: [Character], at index: Int) -> Bool {
        let next = chars[index]
        // 數字沒切乾淨（例如「300元500」）就保守不切。
        if ChineseNumberParser.isNumericCharacter(next) { return false }
        if next == "," || next == "." { return false }
        if boundaryStopwords.contains(next) { return false }
        if amountContinuationCharacters.contains(next) || counterWords.contains(next) {
            let pair = index + 1 < chars.count ? String([next, chars[index + 1]]) : String(next)
            if !continuationExceptions.contains(pair) { return false }
        }
        // 「後面必須還有另一筆金額」由呼叫端保證：切點只在相鄰兩筆金額之間才會被詢問。
        return true
    }

    private static func isArabicDigit(_ c: Character) -> Bool {
        c.isASCII && c.isNumber
    }

    /// 全形阿拉伯數字 → 半形。其餘字元原樣回傳，維持 1:1 的長度。
    private static func halfWidthDigit(_ c: Character) -> Character {
        guard c.unicodeScalars.count == 1,
              let scalar = c.unicodeScalars.first,
              (0xFF10...0xFF19).contains(scalar.value),
              let converted = Unicode.Scalar(scalar.value - 0xFF10 + 0x30) else { return c }
        return Character(converted)
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

    /// 錢流向「我」的說法。中文靠語序決定方向：「男友給我」是進帳，「我給男友」是支出。
    private static let inboundMarkers = [
        "給我", "給了我", "匯給我", "轉給我", "轉帳給我", "匯款給我", "包給我",
        "還我", "還給我", "退我", "退給我", "拿給我", "塞給我", "贊助我", "資助我"
    ]

    /// 錢流出去的說法。這些要壓過下面的「人名＋給」推論。
    private static let outboundMarkers = [
        "我給", "我付", "我轉", "我匯", "我請", "我包", "我借",
        "付給", "轉給", "匯給", "借給", "還給", "包給", "拿給", "送給"
    ]

    /// 會出現在「X 給我錢」裡的人。用來判斷「男友給5000」這種省略了「我」的說法。
    private static let personWords = [
        "男友", "女友", "男朋友", "女朋友", "老公", "老婆", "先生", "太太",
        "爸", "媽", "爸爸", "媽媽", "父母", "阿公", "阿嬤", "爺爺", "奶奶",
        "哥", "姊", "弟", "妹", "哥哥", "姊姊", "弟弟", "妹妹",
        "老闆", "公司", "客戶", "同事", "朋友", "家人", "長輩", "叔叔", "阿姨", "親戚"
    ]

    static func detectIncome(in text: String) -> Bool {
        // 1. 明確的收入詞（薪水、獎金、退款…）最優先
        if ExpenseCategory.income.keywords.contains(where: { text.contains($0) }) { return true }

        // 2. 明確流向我的說法。要先於第 3 步，否則「還給我」會被「還給」誤判成支出
        if inboundMarkers.contains(where: { text.contains($0) }) { return true }

        // 3. 明確流出去的說法
        if outboundMarkers.contains(where: { text.contains($0) }) { return false }

        // 4. 「人名 + 給」而且沒有出現「我給」：省略主詞的進帳，例如「男友給5000」
        if personWords.contains(where: { text.contains($0 + "給") }) { return true }

        return false
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
