import XCTest
@testable import MeowMoney

final class ExpenseTests: XCTestCase {

    // MARK: - normalizedDisplayText（純函式）

    func testNormalizedDisplayTextKeepsNormalNote() {
        XCTAssertEqual(Expense.normalizedDisplayText("跟同事吃飯"), "跟同事吃飯")
    }

    func testNormalizedDisplayTextTrimsLeadingAndTrailingWhitespace() {
        XCTAssertEqual(Expense.normalizedDisplayText("  跟同事吃飯  "), "跟同事吃飯")
    }

    func testNormalizedDisplayTextCollapsesInternalNewlines() {
        XCTAssertEqual(Expense.normalizedDisplayText("跟同事\n\n吃飯"), "跟同事 吃飯")
    }

    func testNormalizedDisplayTextCollapsesInternalSpaces() {
        XCTAssertEqual(Expense.normalizedDisplayText("跟同事    吃飯"), "跟同事 吃飯")
    }

    func testNormalizedDisplayTextWhitespaceOnlyBecomesEmpty() {
        XCTAssertEqual(Expense.normalizedDisplayText("   \n\n   "), "")
    }

    func testNormalizedDisplayTextEmptyStringStaysEmpty() {
        XCTAssertEqual(Expense.normalizedDisplayText(""), "")
    }

    // MARK: - displayTitle（整合正規化 + fallback）

    func testDisplayTitleUsesNormalizedNoteWhenPresent() {
        let expense = Expense(amount: 120, category: .food, note: "  跟同事\n吃飯  ")
        XCTAssertEqual(expense.displayTitle, "跟同事 吃飯")
    }

    func testDisplayTitleFallsBackToCategoryWhenNoteIsWhitespaceOnly() {
        let expense = Expense(amount: 120, category: .food, note: "   \n  ")
        XCTAssertEqual(expense.displayTitle, ExpenseCategory.food.title)
    }

    func testDisplayTitleFallsBackToCategoryWhenNoteIsEmpty() {
        let expense = Expense(amount: 120, category: .transport, note: "")
        XCTAssertEqual(expense.displayTitle, ExpenseCategory.transport.title)
    }
}
