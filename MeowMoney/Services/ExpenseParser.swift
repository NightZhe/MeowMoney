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
        let masked = maskStoreNames(in: normalized)

        var working = masked.text
        let dateResult = extractDate(from: working, now: now, calendar: calendar)
        working = dateResult.remaining
        working = stripLeadingQuantity(working)

        let isIncome = detectIncome(in: normalized)

        let amountResult = extractAmount(from: working)
        working = amountResult.remaining

        let category: ExpenseCategory = isIncome ? .income : detectCategory(in: normalized) ?? .other
        let note = restoreStoreNames(
            in: makeNote(from: working, fallback: category, isIncome: isIncome),
            names: masked.names
        )

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
        "克", "斤", "磅", "升", "米", "尺", "吋", "%", "％"
    ]

    /// 接在數字後面的完整單位詞。「公」不能單獨當延續字：它擋住了「捷運二十五公車十五」
    /// 「午餐一百公園門票五十」這類切點，後一筆整筆被併進前一筆、金額丟失（2026-09 驗收案例）。
    /// 只有整個單位詞出現時才算「數字還沒講完」（「買了一公斤蘋果200」）。
    private static let amountContinuationWords = ["公斤", "公克", "公升", "公里", "公分", "公尺", "公噸", "公頃"]

    /// 第一個字雖然落在量詞/延續字裡，但兩個字合起來是一般詞彙，不該擋住切句。
    /// 例：「點」是量詞（三點），但「點心」是品項。
    private static let continuationExceptions: Set<String> = ["點心", "包子"]

    /// 不可能當品項開頭的虛字。「金額＋的」是「金額在前」語序的判斷訊號
    /// （見 `AmountSpan.isAmountFirst`），所以在「品項在前」的切點上碰到它就不切。
    private static let boundaryStopwords: Set<Character> = ["的", "之"]

    /// 口語連接詞。它出現在切點上時不屬於任何一筆，要從片段的頭尾拿掉，
    /// 否則備註會變成「和捷運」。依長度由長到短比對。
    private static let connectorWords = ["還有", "加上", "以及", "然後", "再加", "和", "跟"]

    /// 以單字連接詞（和／跟）開頭、但整個是品項名稱的詞。切點後的片段開頭若是「和／跟」，
    /// 預設當連接詞拿掉（「咖啡60和蛋糕90」的第二筆是「蛋糕」）；只有這些詞例外保留，
    /// 否則「午餐300和牛500」會被削成「牛」。清單可擴充——漏收的代價是品項名少一個字，
    /// 金額與筆數不受影響。
    private static let connectorLeadingItemWords = ["和牛", "和菓子", "和風", "和服", "和室", "跟團"]

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
    private static func amountSpans(in probe: [Character], storeNames: [Range<Int>]) -> [AmountSpan] {
        let storeNameEnds = Dictionary(
            uniqueKeysWithValues: storeNames.map { ($0.lowerBound, $0.upperBound) }
        )
        var spans: [AmountSpan] = []
        var index = 0
        while index < probe.count {
            // 店名裡的數字（7-11、85度C）不是金額，整段跳過，不參與金額與切點判斷。
            if let storeEnd = storeNameEnds[index] {
                index = storeEnd
                continue
            }
            guard ChineseNumberParser.isNumericCharacter(probe[index]) else {
                index += 1
                continue
            }
            // 數字不可以吃進緊接在後面的店名（「珍奶55八方雲集」的 55 不是 558）。
            let nextStoreStart = storeNames.map(\.lowerBound).filter { $0 > index }.min() ?? probe.count
            let runEnd = min(numericRunEnd(in: probe, from: index), nextStoreStart)
            guard let value = numericValue(in: probe, from: index, to: runEnd), value > 0 else {
                index = max(runEnd, index + 1)
                continue
            }
            // 片段開頭的「一塊蛋糕」是在數東西，不是一筆帳——不建 span，
            // 否則會在「一塊」與「蛋糕」之間切一刀，憑空多出一筆 1 元。
            if isQuantityCounterBlock(in: probe, value: value, numberStart: index, unitIndex: runEnd) {
                index = runEnd + 1
                continue
            }
            let end = amountEnd(in: probe, runEnd: runEnd)
            let start = amountStart(in: probe, numberStart: index)
            spans.append(
                AmountSpan(start: start, end: end, isAmountFirst: isAmountFirst(in: probe, at: end))
            )
            index = max(runEnd, index + 1)
        }
        return spans
    }

    /// 金額片段的起點：把緊貼在數字前面的幣別符號（`$`／`＄`）一併算進去，
    /// 跟 `extractAmount` 的規則一致——否則像「金額在前」語序的第二筆
    /// `$30的捷運`，切點會落在數字開頭而不是 `$` 前面，把 `$` 誤留在前一段的尾巴
    /// （實機案例：`$120的午餐和$30的捷運` 會切成「$120的午餐和$」＋「30的捷運」，
    /// 連接詞「和」跟著殘留的 `$` 一起卡在前一段結尾，`trimConnectors` 的 suffix
    /// 比對抓不到，因為片段真正的結尾字元是 `$` 不是「和」）。
    private static func amountStart(in probe: [Character], numberStart: Int) -> Int {
        guard numberStart > 0, probe[numberStart - 1] == "$" || probe[numberStart - 1] == "＄" else {
            return numberStart
        }
        return numberStart - 1
    }

    /// 「金額在前」的訊號：金額（含幣別後綴）之後接「的／之」，而且後面還有字當品項。
    private static func isAmountFirst(in probe: [Character], at end: Int) -> Bool {
        guard end < probe.count, boundaryStopwords.contains(probe[end]) else { return false }
        let itemStart = end + 1
        guard itemStart < probe.count else { return false }
        return !ChineseNumberParser.isNumericCharacter(probe[itemStart])
    }

    private static func splitPoints(in probe: [Character]) -> [Int] {
        let storeNames = storeNameRanges(in: probe)
        let spans = amountSpans(in: probe, storeNames: storeNames)
        guard spans.count > 1 else { return [] }

        let storeNameStarts = Set(storeNames.map(\.lowerBound))
        var cuts: [Int] = []
        for (a, b) in zip(spans, spans.dropFirst()) {
            guard let cut = splitPoint(between: a, and: b, in: probe, storeNameStarts: storeNameStarts) else { continue }
            guard cut > (cuts.last ?? 0), cut < probe.count else { continue }
            cuts.append(cut)
        }
        return cuts
    }

    /// 決定相鄰兩筆金額之間的切點。回傳 nil = 判斷不了，維持同一段。
    private static func splitPoint(
        between a: AmountSpan,
        and b: AmountSpan,
        in probe: [Character],
        storeNameStarts: Set<Int>
    ) -> Int? {
        guard a.isAmountFirst else {
            // 品項在前：切在這筆金額之後，那裡就是下一個品項的開頭。緊接著店名時一定是新的品項。
            guard a.end < probe.count,
                  storeNameStarts.contains(a.end) || isBoundary(in: probe, at: a.end) else { return nil }
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
    /// 開頭的「和／跟」若屬於 `connectorLeadingItemWords`（和牛、和菓子…）就保留。
    private static func trimConnectors(_ piece: String, head: Bool, tail: Bool) -> String {
        var text = piece
        if head, !connectorLeadingItemWords.contains(where: { text.hasPrefix($0) }) {
            for word in connectorWords where text.hasPrefix(word) {
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
        if amountContinuationWords.contains(where: { matches($0, in: chars, at: index, limit: chars.count) }) {
            return false
        }
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

    // MARK: - 帶數字的店名

    /// 帶數字的台灣常見店名／品牌。這些數字不是金額：不保護的話「7-11咖啡45」會切成
    /// 7 元、11 元、45 元三筆，「85度C咖啡60」會記成 85 元。
    ///
    /// 取捨原則：寧可少切，不可切錯；金額錯 > 多一筆 > 品項名多幾個字。
    /// - 帶非數字識別字的名稱（7-11、85度C、50嵐、五十嵐、八方雲集…）不會跟一般講法撞，一律保護。
    /// - 純數字的名稱（711、101）本身就可能是金額（「午餐101晚餐200」），只在上下文明確是
    ///   地點時才保護，見 `hasStoreContext`。
    /// - 中文數字開頭的店名只收整個詞不會有第二種意思的幾個；「一蘭」「一芳」「二十五度」
    ///   這類短名稱容易跟數量講法撞，刻意不收。
    ///
    /// 清單可擴充：加一筆 `StoreName` 即可，`alias` 用小寫、分隔號寫「-」
    /// （比對時大小寫、全半形、「-」與空白視為相同，見 `storeNameFold`）。
    private struct StoreName {
        let alias: String
        let display: String
        /// 純數字名稱：需要上下文佐證才算店名。
        let needsContext: Bool
    }

    private static let storeNames: [StoreName] = [
        StoreName(alias: "7-eleven", display: "7-Eleven", needsContext: false),
        StoreName(alias: "7eleven", display: "7-Eleven", needsContext: false),
        StoreName(alias: "7-11", display: "7-11", needsContext: false),
        StoreName(alias: "711", display: "711", needsContext: true),
        StoreName(alias: "85度c", display: "85度C", needsContext: false),
        StoreName(alias: "85°c", display: "85°C", needsContext: false),
        StoreName(alias: "50嵐", display: "50嵐", needsContext: false),
        StoreName(alias: "五十嵐", display: "五十嵐", needsContext: false),
        StoreName(alias: "台北101", display: "台北101", needsContext: false),
        StoreName(alias: "101", display: "101", needsContext: true),
        StoreName(alias: "八方雲集", display: "八方雲集", needsContext: false),
        StoreName(alias: "三商巧福", display: "三商巧福", needsContext: false),
        StoreName(alias: "四海遊龍", display: "四海遊龍", needsContext: false),
        // 「統一超商」「統一發票」：「一」在這裡從來不是數量。
        StoreName(alias: "統一", display: "統一", needsContext: false)
    ].sorted { $0.alias.count > $1.alias.count }

    /// 純數字店名前面可以接的字：表示「去某個地方」。
    private static let storeLocationPrefixes: Set<Character> = ["在", "去", "到", "逛", "從"]

    /// 比對用的字元折疊：小寫、全形轉半形、各種橫線與空白都當成「-」。長度 1:1，索引對得上原字串。
    /// 空白也要當成「-」：`normalize` 會把「7-11」的「-」換成空白。
    private static func storeNameFold(_ c: Character) -> Character {
        if c.isWhitespace || c == "-" || c == "－" || c == "—" || c == "–" || c == "‐" { return "-" }
        let half = String(c).applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? String(c)
        let lowered = half.lowercased()
        return lowered.count == 1 ? Character(lowered) : c
    }

    /// 找出文字裡所有店名的位置（不重疊，由左到右，長名稱優先）。
    private static func storeNameRanges(in chars: [Character]) -> [Range<Int>] {
        storeNameMatches(in: chars).map(\.range)
    }

    private static func storeNameMatches(in chars: [Character]) -> [(range: Range<Int>, name: StoreName)] {
        let folded = chars.map(storeNameFold)
        var found: [(range: Range<Int>, name: StoreName)] = []
        var index = 0
        while index < folded.count {
            let hit = storeNames.first { name in
                let alias = Array(name.alias)
                guard index + alias.count <= folded.count,
                      Array(folded[index..<(index + alias.count)]) == alias else { return false }
                return isStoreNameBoundary(in: chars, range: index..<(index + alias.count), name: name)
            }
            if let hit {
                let range = index..<(index + hit.alias.count)
                found.append((range, hit))
                index = range.upperBound
            } else {
                index += 1
            }
        }
        return found
    }

    /// 店名兩端不能黏著**同一種寫法**的數字（「37-11」「7-1145」「三百五十嵐」是講不清楚的數字，
    /// 不是店名），純數字名稱另外要有上下文。阿拉伯數字接中文數字開頭的店名
    /// （「珍奶55八方雲集」）不算黏著：兩種寫法混在一起本來就不是一個數字。
    private static func isStoreNameBoundary(in chars: [Character], range: Range<Int>, name: StoreName) -> Bool {
        if range.lowerBound > 0, isSameNumeralScript(chars[range.lowerBound - 1], chars[range.lowerBound]) {
            return false
        }
        if range.upperBound < chars.count, isSameNumeralScript(chars[range.upperBound - 1], chars[range.upperBound]) {
            return false
        }
        guard name.needsContext else { return true }
        return hasStoreContext(in: chars, range: range)
    }

    /// 兩個字元是否都是數字，而且同為阿拉伯數字或同為中文數字。
    private static func isSameNumeralScript(_ a: Character, _ b: Character) -> Bool {
        guard ChineseNumberParser.isNumericCharacter(a), ChineseNumberParser.isNumericCharacter(b) else { return false }
        return isArabicDigit(halfWidthDigit(a)) == isArabicDigit(halfWidthDigit(b))
    }

    /// 純數字店名（711、101）的上下文：
    /// - 後面必須接一般文字——接幣別（「101元」）、量詞、延續字、「的」、或句尾，都當金額。
    /// - 前面必須是片段開頭、只有時間詞（「今天711買咖啡45」）、或「在／去／到…」。
    /// 「午餐101晚餐200」前面有品項，所以 101 仍是金額。
    private static func hasStoreContext(in chars: [Character], range: Range<Int>) -> Bool {
        guard range.upperBound < chars.count else { return false }
        let next = chars[range.upperBound]
        if next.isWhitespace || next == "k" || next == "K" || next == "," || next == "." { return false }
        if currencySuffixes.contains(next) || counterWords.contains(next)
            || amountContinuationCharacters.contains(next) || boundaryStopwords.contains(next) {
            return false
        }

        var prefixStart = range.lowerBound
        while prefixStart > 0, !chars[prefixStart - 1].isWhitespace { prefixStart -= 1 }
        guard prefixStart < range.lowerBound else { return true }
        if storeLocationPrefixes.contains(chars[range.lowerBound - 1]) { return true }
        var prefix = String(chars[prefixStart..<range.lowerBound])
        for word in relativeDayWords.map(\.word).sorted(by: { $0.count > $1.count }) {
            prefix = prefix.replacingOccurrences(of: word, with: "")
        }
        return prefix.isEmpty
    }

    /// 解析前把店名換成佔位字元（Unicode 私用區，一個店名一個字元），金額、日期、量詞判斷
    /// 都看不到它裡面的數字；備註產生後再用 `restoreStoreNames` 換回顯示名稱。
    private static func maskStoreNames(in text: String) -> (text: String, names: [String]) {
        let chars = Array(text)
        let matches = storeNameMatches(in: chars)
        guard !matches.isEmpty else { return (text, []) }

        var result: [Character] = []
        var names: [String] = []
        var index = 0
        for match in matches {
            result.append(contentsOf: chars[index..<match.range.lowerBound])
            result.append(storeNamePlaceholder(names.count))
            names.append(match.name.display)
            index = match.range.upperBound
        }
        result.append(contentsOf: chars[index...])
        return (String(result), names)
    }

    private static func restoreStoreNames(in note: String, names: [String]) -> String {
        guard !names.isEmpty else { return note }
        var result = note
        for (i, name) in names.enumerated() {
            result = result.replacingOccurrences(of: String(storeNamePlaceholder(i)), with: name)
        }
        return result
    }

    private static func storeNamePlaceholder(_ index: Int) -> Character {
        Character(Unicode.Scalar(0xE000 + UInt32(index))!)
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

    /// 口語裡「數東西」的數字上限。超過這個值就當幣別——「30塊車資」是 30 元的車資，
    /// 不是 30 塊車資。這條是量詞判斷的安全閥：判錯量詞只是備註多幾個字，
    /// 判錯幣別會讓整筆金額變成 nil。
    private static let maxCounterQuantity: Decimal = 10

    /// `塊` 同時是幣別（`午餐30塊`）與量詞（`一塊蛋糕`）。它不能直接放進 `counterWords`，
    /// 那會讓「午餐30塊」的 30 也失效——那是比誤判量詞嚴重得多的損失。
    ///
    /// 判別依據不是「`塊` 後面接什麼」，而是**「`塊` 前面有沒有品項」**：
    /// - `一塊蛋糕30元`：數字在片段開頭，前面沒有品項，`塊` 後面直接接品項文字 → 量詞
    /// - `午餐30塊晚餐50塊`：`30` 前面有「午餐」 → 幣別
    /// - `三十塊的捷運`：雖在開頭，但後面接「的」，屬於「金額在前」語序 → 幣別
    /// - `一塊`／`一塊錢`：`塊` 後面沒有品項文字 → 幣別
    /// - `30塊車資`：形態符合，但沒有人「數 30 塊車資」，數字太大 → 幣別（見 `maxCounterQuantity`）
    ///
    /// 刻意只認「片段開頭」這一種形態，其餘一律當幣別（寧可漏判量詞，不可漏判金額）。
    ///
    /// - Parameters:
    ///   - value: 數字片段的值，用來擋掉「數字大到不可能是數量」的情況。
    ///   - numberStart: 數字片段的起點。
    ///   - unitIndex: 數字片段結束後緊接的位置，也就是候選的單位字位置。
    private static func isQuantityCounterBlock(
        in chars: [Character],
        value: Decimal,
        numberStart: Int,
        unitIndex: Int
    ) -> Bool {
        guard unitIndex < chars.count, chars[unitIndex] == "塊" else { return false }
        guard value <= maxCounterQuantity else { return false }
        guard isItemFreePrefix(String(chars[0..<numberStart])) else { return false }

        let itemStart = unitIndex + 1
        guard itemStart < chars.count else { return false }   // 句尾，沒有品項可數
        let next = chars[itemStart]
        if next.isWhitespace { return false }
        if ChineseNumberParser.isNumericCharacter(next) { return false }
        if boundaryStopwords.contains(next) { return false }  // 「三十塊的捷運」
        if currencyUnitTrailers.contains(next) { return false } // 「一塊錢」「一塊整」
        if connectorWords.contains(where: { matches($0, in: chars, at: itemStart, limit: chars.count) }) {
            return false
        }
        return true
    }

    /// 出現在數字前面、但不是品項的字：拿東西的動作。
    /// 刻意**不收**「花了」「付了」「刷了」這類花錢的動詞——「花了五塊買糖果」的
    /// 五塊是金額不是數量，收進來會讓那筆的金額變成 nil。
    private static let quantityPrefixWords = ["買了", "買", "吃了", "吃", "喝了", "喝", "點了", "叫了"]

    /// 數字前面這段有沒有東西能當品項。時間詞（昨天、今天…）與拿東西的動作
    /// （買了、吃了…）都不算品項，所以「昨天買了一塊蛋糕30元」的「一塊」仍算在片段開頭。
    private static func isItemFreePrefix(_ prefix: String) -> Bool {
        guard !prefix.allSatisfy(\.isWhitespace) else { return true }
        var text = prefix
        let words = relativeDayWords.map(\.word) + quantityPrefixWords
        for word in words.sorted(by: { $0.count > $1.count }) {
            text = text.replacingOccurrences(of: word, with: "")
        }
        return text.allSatisfy(\.isWhitespace)
    }

    /// 片段開頭的「數字＋塊」是量詞時，把它從文字裡拿掉：它既不是金額，
    /// 留著也只會讓備註變成「一塊蛋糕」而不是「蛋糕」。
    /// 不是量詞用法就原樣回傳（`三十塊的捷運`、`午餐30塊` 都走這條）。
    private static func stripLeadingQuantity(_ text: String) -> String {
        let chars = Array(text)
        var start = 0
        while start < chars.count, chars[start].isWhitespace { start += 1 }
        guard start < chars.count, ChineseNumberParser.isNumericCharacter(chars[start]) else { return text }

        let runEnd = numericRunEnd(in: chars, from: start)
        guard let value = numericValue(in: chars, from: start, to: runEnd),
              isQuantityCounterBlock(in: chars, value: value, numberStart: start, unitIndex: runEnd)
        else { return text }
        return String(chars[(runEnd + 1)...])
    }

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
        "總共花了", "一共花了", "總共花", "一共花", "總共", "一共", "花了", "花掉", "花費", "支出", "收入",
        "付了", "刷了", "大概", "差不多", "左右", "而已", "然後", "還有",
        // 不放單獨的「錢」：它會把「撿到錢」吃成「撿到」。
        // 不放「元/塊/圓」：盲目整段替換會把「元氣早餐」「大塊牛排」這類品項名稱削壞
        // （2026-09-09 實機案例）。交給 `stripCurrencyResidue` 只在確定是幣別殘留時才清。
        // 不放單獨的「花」：它會把「爆米花」「花枝丸」「買花」削壞。動詞用法由上面的
        // 「花了／花掉」與 `stripStandaloneSpendVerb` 處理。
        "共", "了", "的", "喔", "啦", "吧", "嗎", "呢"
    ]

    /// 幣別「單位字」。混在句子裡當殘留時，判斷依據不是它前面有沒有數字——
    /// `extractAmount` 把選中金額連同緊貼的單位字一起吃掉之後，數字本身也從
    /// 文字裡消失了，往前找數字找不到東西。真正管用的訊號是：它有沒有以
    /// **獨立詞彙**的樣子單獨站著（左右都是空白或字串邊界）。
    private static let currencyUnitWords: Set<Character> = ["元", "塊", "圓"]
    /// 接在幣別單位字後面的收尾字，例如「元整」「塊錢」，跟著單位字一起判斷、一起清掉。
    private static let currencyUnitTrailers: Set<Character> = ["整", "錢"]

    /// 語音辨識偶爾會把講出來的貨幣單位吐成孤立的 `$`／`＄`，或吐成沒有緊跟在金額後面的
    /// 「元」「塊」，而且位置不固定——可能在句尾、句中，甚至頭尾各一個
    /// （實機案例：`$120的晚餐$`，句尾的 `$` 沒人清；`165 元` 中間隔了空白，「元」沒被
    /// `extractAmount` 的幣別後綴一起吃掉，選中的金額 165 又已經從文字裡整段移除，
    /// 往前也找不到數字可以比對）。
    ///
    /// 兩類分開判斷，因為文法角色與可用訊號不同：
    /// - `$`／`＄`：只清「兩側都不貼著數字」的——貼著數字的 `$` 可能是品項名稱本身
    ///   的一部分（例如「$1 商店」），保留不動。
    /// - `元`／`塊`／`圓`（含收尾字「整」「錢」）：只清「以獨立詞彙站著」的，也就是
    ///   左右都接空白或字串邊界——這才是單獨殘留的幣別單位；緊貼著別的字（「元氣」
    ///   「大塊」）代表它是詞彙本身的一部分，保留不動。
    /// 判斷不了就不清，寧可留一個 `$`，也不要把「元氣早餐」削成「氣早餐」。
    ///
    /// `NT`／`NT$` 不在這裡處理：跟金額結合的已由 `extractAmount` 整串吃掉，
    /// 沒結合的很可能是品項名稱的一部分（例如「大戶NT專案」），沒有安全的判斷方式，故不清。
    private static func stripCurrencyResidue(_ text: String) -> String {
        let chars = Array(text)
        var result: [Character] = []
        result.reserveCapacity(chars.count)
        var i = 0
        while i < chars.count {
            let char = chars[i]

            if char == "$" || char == "＄" {
                let prevIsDigit = i > 0 && ChineseNumberParser.isNumericCharacter(chars[i - 1])
                let nextIsDigit = i + 1 < chars.count && ChineseNumberParser.isNumericCharacter(chars[i + 1])
                if prevIsDigit || nextIsDigit {
                    result.append(char) // 貼著數字，可能是品項名稱本身，不清
                }
                // 否則：兩側都不是數字，判定為孤立殘留，不寫入結果 = 清掉。
                i += 1
                continue
            }

            if currencyUnitWords.contains(char) {
                let leftIsBoundary = i == 0 || chars[i - 1].isWhitespace
                var afterIndex = i + 1
                if afterIndex < chars.count, currencyUnitTrailers.contains(chars[afterIndex]) {
                    afterIndex += 1
                }
                let rightIsBoundary = afterIndex == chars.count || chars[afterIndex].isWhitespace
                if leftIsBoundary && rightIsBoundary {
                    i = afterIndex
                    continue // 左右都是邊界，判定為獨立殘留的幣別單位，不寫入結果 = 清掉
                }
                // 否則：緊貼著別的字，判定為詞彙本身的一部分，保留不動。
            }

            result.append(char)
            i += 1
        }
        return String(result)
    }

    /// 「今天花200吃午餐」「花200買書」的「花」是動詞：金額被拿掉之後，它左右都是空白或
    /// 字串邊界。只清這種形態——前面有字的「買花」「豆花」、後面接字的「花枝丸」「花生湯」
    /// 都是品項，一律保留。代價：「午餐花200」的備註是「午餐花」（多一個字，金額不受影響）。
    private static func stripStandaloneSpendVerb(_ text: String) -> String {
        let chars = Array(text)
        var result: [Character] = []
        result.reserveCapacity(chars.count)
        for (i, char) in chars.enumerated() {
            let leftIsBoundary = i == 0 || chars[i - 1].isWhitespace
            let rightIsBoundary = i + 1 == chars.count || chars[i + 1].isWhitespace
            if char == "花", leftIsBoundary, rightIsBoundary { continue }
            result.append(char)
        }
        return String(result)
    }

    static func makeNote(from text: String, fallback: ExpenseCategory, isIncome: Bool) -> String {
        var working = stripStandaloneSpendVerb(stripCurrencyResidue(text))
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
