import SwiftUI
import UIKit

/// 帳目詳情：使用者永遠要能看到完整內容的解法（階段1規格 §3.2(c)）。
/// 階段 2 加回「原話」區塊（`expense.transcript`）＋「重新解析」／「手動修正」兩個動作
/// （階段2-3規格 §1）。資料必然存在（由既有 `Expense` 點擊觸發），不需要 loading/empty
/// 三態；「重新解析後仍找不到金額」是設計好的正常分支，不是 error 態（見 §1.5）。
struct ExpenseDetailSheet: View {
    /// 重新解析後的三種呈現分支；`.editing` 是轉場用的過渡值——一旦命中，畫面即將
    /// 由呼叫方（`ExpenseRow`）關閉本 sheet 並開出編輯用的 `EntrySheet`，不需要自己的內容。
    private enum DetailStage {
        case viewing
        case reparsePreview
        case editing
    }

    let expense: Expense
    /// 「手動修正」的實際跳轉不歸本畫面管——呼叫方決定怎麼接力開編輯表單
    /// （階段2-3規格 §1.4：關掉本 sheet → 開 `EntrySheet(mode: .edit(expense))`）。
    var onRequestEdit: (Expense) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var stage: DetailStage = .viewing
    @State private var reparseResult: ParsedEntry?

    private var normalizedNote: String {
        Expense.normalizedDisplayText(expense.note)
    }

    /// 「原話」信任承諾是一字不改，刻意不套 `normalizedDisplayText`
    /// （那是給備註在 `lineLimit(1)` 列表裡用的顯示優化，跟原話忠實度是两件事）。
    private var trimmedTranscript: String {
        expense.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        ScrollView {
            Group {
                switch stage {
                case .viewing, .editing:
                    viewingContent
                case .reparsePreview:
                    reparsePreviewContent
                }
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

    // MARK: - 檢視中

    private var viewingContent: some View {
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

            if !trimmedTranscript.isEmpty {
                transcriptSection
            } else {
                // transcript 為空（1.0 手動記帳或本 App 的手動輸入）：沒有原話可回溯，
                // 但「手動修正」不依賴原話，任何一筆帳都該能修正，改放單獨一顆
                // 撐滿寬度的按鈕（階段2-3規格 §1.2）。
                manualEditButton
            }

            Text(expense.date.formatted(.dateTime.year().month().day().hour().minute().locale(Locale(identifier: "zh_TW"))))
                .font(MM.font(13, .medium, relativeTo: .footnote))
                .foregroundStyle(MM.textSecondary)
        }
    }

    private var transcriptSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Rectangle()
                .fill(MM.hairline)
                .frame(height: 1)

            Text("你當時說的是這句")
                .font(MM.font(12, .medium, relativeTo: .caption))
                .tracking(1.2) // +10%
                .foregroundStyle(MM.textTertiary)

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "quote.opening")
                    .font(.system(size: 11))
                    .foregroundStyle(MM.textSecondary)
                    .padding(.top, 3)
                Text(expense.transcript)
                    .font(MM.font(17, .medium, relativeTo: .body))
                    .foregroundStyle(MM.textPrimary)
                    .textSelection(.enabled)
            }

            HStack(spacing: 12) {
                Button(action: reparse) {
                    Text("重新解析")
                        .font(MM.font(15, .semibold, relativeTo: .subheadline))
                        .foregroundStyle(MM.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Capsule().fill(MM.surfaceCard))
                }
                .squishy()
                .accessibilityLabel("重新解析原話")
                .accessibilityHint("用目前的解析規則重新分析這句話，看金額分類有沒有不同")

                manualEditButton
            }
        }
    }

    /// 主要視覺（`brandStrong` 實心）——手動修正保證能解決問題。
    /// 兩個出現位置（跟「重新解析」並排、或空 transcript 時單獨撐滿寬度）
    /// 樣式完全一樣，都是 `.frame(maxWidth: .infinity)`，父層 HStack／VStack 決定它多寬。
    private var manualEditButton: some View {
        Button(action: requestManualEdit) {
            Text("手動修正")
                .font(MM.font(15, .semibold, relativeTo: .subheadline))
                .foregroundStyle(MM.textOnBrand)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Capsule().fill(MM.brandStrong))
        }
        .squishy()
        .accessibilityLabel("手動修正這筆帳")
        .accessibilityHint("開啟表單直接修改金額、分類、備註與日期")
    }

    // MARK: - 重新解析預覽

    @ViewBuilder
    private var reparsePreviewContent: some View {
        if let result = reparseResult {
            if result.amount == nil {
                reparseNoAmountContent
            } else if isUnchanged(result) {
                reparseUnchangedContent
            } else {
                reparseDiffContent(result)
            }
        } else {
            viewingContent
        }
    }

    private var reparseNoAmountContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("重新解析後仍然沒有偵測到金額")
                .font(MM.font(17, .semibold, relativeTo: .body))
                .foregroundStyle(MM.textPrimary)

            HStack(spacing: 12) {
                secondaryButton("取消") {
                    withAnimation(MM.bouncy) { stage = .viewing }
                }
                primaryButton("改用手動修正", action: requestManualEdit)
            }
        }
    }

    private var reparseUnchangedContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("重新解析結果跟目前一樣，不需要更新")
                .font(MM.font(17, .semibold, relativeTo: .body))
                .foregroundStyle(MM.textPrimary)

            primaryButton("知道了") {
                withAnimation(MM.bouncy) { stage = .viewing }
            }
        }
    }

    private func reparseDiffContent(_ result: ParsedEntry) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("重新解析找到不一樣的結果")
                .font(MM.font(17, .semibold, relativeTo: .body))
                .foregroundStyle(MM.textPrimary)

            VStack(alignment: .leading, spacing: 12) {
                diffRow(label: "分類", oldValue: expense.category.title, newValue: result.category.title, changed: result.category != expense.category)
                diffRow(
                    label: "金額",
                    oldValue: Money.string(expense.amount),
                    newValue: Money.string(result.amount ?? expense.amount),
                    changed: result.amount != expense.amount
                )
                diffRow(
                    label: "備註",
                    oldValue: expense.note.isEmpty ? "（無）" : expense.note,
                    newValue: result.note,
                    changed: result.note != expense.note
                )
            }

            HStack(spacing: 12) {
                secondaryButton("取消") {
                    withAnimation(MM.bouncy) { stage = .viewing }
                }
                primaryButton("套用變更") { applyReparse(result) }
            }
        }
    }

    private func diffRow(label: String, oldValue: String, newValue: String, changed: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(MM.font(13, .medium, relativeTo: .footnote))
                .foregroundStyle(MM.textTertiary)
                .frame(width: 44, alignment: .leading)

            if changed {
                HStack(spacing: 6) {
                    Text(oldValue)
                        .foregroundStyle(MM.textSecondary)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(MM.textTertiary)
                    Text(newValue)
                        .foregroundStyle(MM.warning)
                }
                .font(MM.font(15, .semibold, relativeTo: .subheadline))
            } else {
                Text(newValue)
                    .font(MM.font(15, .medium, relativeTo: .subheadline))
                    .foregroundStyle(MM.textSecondary)
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private func secondaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(MM.font(15, .semibold, relativeTo: .subheadline))
                .foregroundStyle(MM.textSecondary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Capsule().fill(MM.surfaceCard))
        }
        .squishy()
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(MM.font(15, .semibold, relativeTo: .subheadline))
                .foregroundStyle(MM.textOnBrand)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Capsule().fill(MM.brandStrong))
        }
        .squishy()
    }

    // MARK: - 動作

    private func reparse() {
        // 用 `expense.createdAt`（記帳當下）而不是 `Date()`：原話裡「昨天」這類相對
        // 日期詞，若用「現在」重新解析會算出錯誤的日期（階段2-3規格 §1.3 註記的風險）。
        let result = ExpenseParser.parse(expense.transcript, now: expense.createdAt, calendar: .current)
        reparseResult = result
        withAnimation(MM.bouncy) { stage = .reparsePreview }
    }

    private func isUnchanged(_ result: ParsedEntry) -> Bool {
        result.amount == expense.amount
            && result.category == expense.category
            && result.note == expense.note
    }

    private func applyReparse(_ result: ParsedEntry) {
        guard let amount = result.amount else { return }
        // 只套用「重新解析」修正得了的欄位；`expense.date` 不動——重新解析只修正
        // 解析錯誤，不重新猜日期，日期異動屬於「手動修正」的責任範圍（§1.3 第 4 點）。
        expense.amount = amount
        expense.category = result.category
        expense.note = result.note
        try? context.save()
        UIAccessibility.post(notification: .announcement, argument: "已更新")
        withAnimation(MM.bouncy) { stage = .viewing }
    }

    private func requestManualEdit() {
        stage = .editing
        onRequestEdit(expense)
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
                expense: Expense(amount: 390, category: .entertainment, note: "跟同事吃飯順便買了個蛋糕，慶祝一下這個月的專案結案", date: .now, transcript: "跟同事吃飯順便買了個蛋糕慶祝一下這個月的專案結案花了三百九"),
                onRequestEdit: { _ in }
            )
        }
}
