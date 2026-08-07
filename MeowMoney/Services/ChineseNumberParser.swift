import Foundation

/// 把中文數字（含口語省略說法）轉成數值。
///
/// 支援：
/// - 阿拉伯數字：`120`、`1200`、`35.5`
/// - 中文數字：`一百二十`、`三十五`、`兩千`、`一萬二千五百`
/// - 台灣口語省略：`一百二` = 120、`兩千五` = 2500、`一萬二` = 12000
/// - 「零」阻斷省略：`一百零二` = 102
/// - 單位後綴：`3萬` = 30000、`5k` = 5000
enum ChineseNumberParser {

    private static let digitMap: [Character: Int] = [
        "零": 0, "〇": 0, "○": 0,
        "一": 1, "壹": 1, "幺": 1,
        "二": 2, "貳": 2, "兩": 2, "两": 2,
        "三": 3, "參": 3, "叁": 3,
        "四": 4, "肆": 4,
        "五": 5, "伍": 5,
        "六": 6, "陸": 6,
        "七": 7, "柒": 7,
        "八": 8, "捌": 8,
        "九": 9, "玖": 9
    ]

    private static let unitMap: [Character: Int] = [
        "十": 10, "拾": 10,
        "百": 100, "佰": 100,
        "千": 1000, "仟": 1000
    ]

    /// 一個字元是否可能屬於數字片段。
    static func isNumericCharacter(_ c: Character) -> Bool {
        if c.isNumber { return true }
        if c == "." { return true }
        if digitMap[c] != nil { return true }
        if unitMap[c] != nil { return true }
        if c == "萬" || c == "万" || c == "億" || c == "亿" { return true }
        return false
    }

    /// 解析一段純數字片段。無法解析回傳 nil。
    static func value(of raw: String) -> Decimal? {
        let text = raw.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }

        // 純阿拉伯數字（可含小數點）走快路徑，保留小數。
        // 注意：Character.isNumber 對「十」「百」等中文數字也是 true，
        // 所以這裡必須限定 ASCII，否則中文數字會被誤判成無法解析。
        if text.allSatisfy(isArabicDigitOrDot) {
            return Decimal(string: text)
        }

        // 阿拉伯數字＋單位後綴的混寫，例如「1.5萬」「3千」。
        if let last = text.last, let multiplier = multiplierValue(of: last) {
            let head = String(text.dropLast())
            if !head.isEmpty,
               head.allSatisfy(isArabicDigitOrDot),
               let base = Decimal(string: head) {
                return base * Decimal(multiplier)
            }
        }

        var total = 0            // 已結算的「萬」以上部分
        var section = 0          // 目前這一節（萬以下）已結算的部分
        var current = 0          // 尚未套用單位的數字
        var hasCurrent = false   // current 是否被寫入過（區分 0 與未填）
        var lastUnit = 0         // 最近一次用到的單位倍數，供口語省略推算
        var zeroBlocksEllipsis = false // 出現「零」之後就不做口語省略推算
        var sawAnything = false

        for c in text {
            if let d = digitValue(of: c) {
                if c == "零" || c == "〇" || c == "○" {
                    zeroBlocksEllipsis = true
                    sawAnything = true
                    continue
                }
                current = current * 10 + d
                hasCurrent = true
                sawAnything = true
            } else if let unit = unitMap[c] {
                let multiplier = hasCurrent ? current : 1
                section += multiplier * unit
                current = 0
                hasCurrent = false
                lastUnit = unit
                zeroBlocksEllipsis = false
                sawAnything = true
            } else if c == "萬" || c == "万" {
                let base = section + current
                total += (base == 0 ? 1 : base) * 10_000
                section = 0
                current = 0
                hasCurrent = false
                lastUnit = 10_000
                zeroBlocksEllipsis = false
                sawAnything = true
            } else if c == "億" || c == "亿" {
                let base = total + section + current
                total = (base == 0 ? 1 : base) * 100_000_000
                section = 0
                current = 0
                hasCurrent = false
                lastUnit = 100_000_000
                zeroBlocksEllipsis = false
                sawAnything = true
            } else if c == "." {
                // 中文數字中出現小數點屬於混寫，交給下一層處理。
                return nil
            } else {
                return nil
            }
        }

        guard sawAnything else { return nil }

        // 口語省略：「一百二」的尾數 2 其實是下一個單位（十位）。
        // 只有在尾數前有百以上的單位、且沒出現「零」時才推算。
        if hasCurrent, lastUnit >= 100, !zeroBlocksEllipsis, current < 10 {
            current *= lastUnit / 10
        }

        return Decimal(total + section + current)
    }

    /// 單一字元代表的倍數（給「1.5萬」這種混寫用）。
    private static func multiplierValue(of c: Character) -> Int? {
        if let unit = unitMap[c] { return unit }
        if c == "萬" || c == "万" { return 10_000 }
        if c == "億" || c == "亿" { return 100_000_000 }
        return nil
    }

    private static func isArabicDigitOrDot(_ c: Character) -> Bool {
        (c.isASCII && c.isNumber) || c == "."
    }

    /// 只回傳「個位數字」。中文的十/百/千不算數字，要交給單位分支處理，
    /// 所以這裡不能用 `wholeNumberValue`（它對「十」會回傳 10）。
    private static func digitValue(of c: Character) -> Int? {
        if let d = digitMap[c] { return d }
        if c.isASCII, let d = c.wholeNumberValue { return d }
        return nil
    }
}
