import SwiftUI
import UIKit

/// 帳目詳情：使用者永遠要能看到完整內容的解法（階段1規格 §3.2(c)）。
/// 刻意不顯示 `expense.transcript`（語音原話回溯屬階段 2，任務範圍明講排除）。
/// 資料必然存在（由既有 `Expense` 點擊觸發），不需要 loading/empty/error 三態。
struct ExpenseDetailSheet: View {
    let expense: Expense

    @Environment(\.dismiss) private var dismiss

    private var normalizedNote: String {
        Expense.normalizedDisplayText(expense.note)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: MM.R.chip, style: .continuous)
                            .fill(expense.category.color.opacity(0.14))
                            .frame(width: 46, height: 46)
                        Text(expense.category.emoji)
                            .font(.system(size: 22))
                    }
                    Text(expense.category.title)
                        .font(MM.font(16, .semibold, relativeTo: .callout))
                        .foregroundStyle(MM.textPrimary)
                    Spacer()
                }

                Text(Money.signed(expense.amount, isIncome: expense.isIncome))
                    .font(MM.font(34, .heavy, relativeTo: .largeTitle))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .foregroundStyle(expense.isIncome ? MM.income : MM.expense)

                if !normalizedNote.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("備註")
                                .font(MM.font(12, .medium, relativeTo: .caption))
                                .tracking(1.2) // +10%
                                .foregroundStyle(MM.textTertiary)
                            Spacer()
                            Button(action: copyNote) {
                                Label("複製備註", systemImage: "doc.on.doc")
                                    .font(MM.font(13, .semibold, relativeTo: .footnote))
                                    .foregroundStyle(MM.brandText)
                                    .frame(minHeight: 44)
                            }
                            .accessibilityLabel("複製備註文字")
                        }
                        // 完整備註，多行自然換行，無 lineLimit——這是任務要求
                        // 「使用者永遠要能看到完整內容」的最終落地處。
                        Text(normalizedNote)
                            .font(MM.font(17, .medium, relativeTo: .body))
                            .foregroundStyle(MM.textPrimary)
                            .textSelection(.enabled)
                    }
                }

                Text(expense.date.formatted(.dateTime.year().month().day().hour().minute().locale(Locale(identifier: "zh_TW"))))
                    .font(MM.font(13, .medium, relativeTo: .footnote))
                    .foregroundStyle(MM.textSecondary)
            }
            .padding(22)
            .mmCard(padding: 0)
            .padding(.horizontal, 22)
            .padding(.top, 20)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(MM.bgBase.ignoresSafeArea())
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(MM.R.xl)
    }

    private func copyNote() {
        UIPasteboard.general.string = normalizedNote
        UIAccessibility.post(notification: .announcement, argument: "已複製")
    }
}

#Preview {
    Color.gray
        .sheet(isPresented: .constant(true)) {
            ExpenseDetailSheet(
                expense: Expense(amount: 390, category: .entertainment, note: "跟同事吃飯順便買了個蛋糕，慶祝一下這個月的專案結案", date: .now)
            )
        }
}
