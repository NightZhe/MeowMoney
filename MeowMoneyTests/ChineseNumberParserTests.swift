import XCTest
@testable import MeowMoney

final class ChineseNumberParserTests: XCTestCase {

    private func value(_ text: String) -> Decimal? {
        ChineseNumberParser.value(of: text)
    }

    func testArabicNumbers() {
        XCTAssertEqual(value("120"), 120)
        XCTAssertEqual(value("0"), 0)
        XCTAssertEqual(value("35.5"), Decimal(string: "35.5"))
    }

    func testBasicChineseNumbers() {
        XCTAssertEqual(value("十"), 10)
        XCTAssertEqual(value("十五"), 15)
        XCTAssertEqual(value("三十五"), 35)
        XCTAssertEqual(value("兩百"), 200)
        XCTAssertEqual(value("一百二十五"), 125)
        XCTAssertEqual(value("三千"), 3000)
        XCTAssertEqual(value("一萬"), 10000)
        XCTAssertEqual(value("十三萬"), 130_000)
        XCTAssertEqual(value("一萬二千五百"), 12500)
    }

    /// 台灣口語會把尾巴的單位吃掉：「一百二」= 120 而不是 102。
    func testColloquialEllipsis() {
        XCTAssertEqual(value("一百二"), 120)
        XCTAssertEqual(value("兩千五"), 2500)
        XCTAssertEqual(value("一萬二"), 12000)
        XCTAssertEqual(value("三百五"), 350)
    }

    /// 「零」會擋掉口語省略推算：「一百零二」= 102。
    func testZeroBlocksEllipsis() {
        XCTAssertEqual(value("一百零二"), 102)
        XCTAssertEqual(value("一千零五"), 1005)
    }

    func testMixedArabicAndUnit() {
        XCTAssertEqual(value("3萬"), 30000)
        XCTAssertEqual(value("1.5萬"), 15000)
        XCTAssertEqual(value("2千"), 2000)
    }

    func testInvalidInput() {
        XCTAssertNil(value(""))
        XCTAssertNil(value("便當"))
        XCTAssertNil(value("abc"))
    }
}
