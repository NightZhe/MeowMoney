import SwiftUI
import UIKit

// MARK: - 分類膠囊

struct CategoryChip: View {
    let category: ExpenseCategory
    let isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(category.emoji)
                Text(category.title)
                    .font(MM.font(15, .semibold, relativeTo: .callout))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                // 分類色（category.color）來自 Models/ExpenseCategory.swift，本階段不動
                // （見階段1規格 §1.2 備註：分類色 Light/Dark 分版是下一輪的事）。
                Capsule()
                    .fill(isSelected ? category.color : category.color.opacity(0.16))
            )
            .foregroundStyle(isSelected ? MM.textOnBrand : MM.textPrimary)
            .overlay(
                Capsule()
                    .stroke(category.color.opacity(isSelected ? 0 : 0.35), lineWidth: 1.5)
            )
        }
        // 視覺膠囊仍是原本的 34–36pt 高度（不撐大湊尺寸），
        // 觸控區用透明 frame 擴到 44pt，contentShape 讓整個 44pt 範圍都能點
        // （驗收退回 BUG-1，見 階段1-設計規格.md §無障礙／HIG 44×44）。
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .squishy()
        .accessibilityLabel(category.title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - 帳目列

struct ExpenseRow: View {
    let expense: Expense
    /// 只有帳本頁給 true：長按跳出「複製備註／刪除」的 context menu。
    /// Home 的預覽列表刻意不給刪除入口，避免使用者在首頁誤刪（階段1規格 §3.2(c)）。
    var allowsContextMenu: Bool = false

    @Environment(\.modelContext) private var context
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showDetail = false
    @State private var confirmingDelete = false
    /// 「手動修正」的第二個 sheet：兩個 sheet 前後接力，不疊加
    /// （階段2-3規格 §1.4）——`showDetail` 先關，這個才開。
    @State private var editingExpense: Expense?

    var body: some View {
        Button {
            showDetail = true
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    // 圓角方，不是正圓——正圓＋圓體字＋糖果色三者疊加會變玩具感（README §6.6）
                    RoundedRectangle(cornerRadius: MM.R.chip, style: .continuous)
                        .fill(expense.category.color.opacity(0.14))
                        .frame(width: 46, height: 46)
                    Text(expense.category.emoji)
                        .font(.system(size: 22))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(expense.displayTitle)
                        .font(MM.font(16, .semibold, relativeTo: .body))
                        .foregroundStyle(MM.textPrimary)
                        // 標準字級單行截斷；AX 級距（Accessibility Sizes）放寬到 2 行，
                        // 否則中文超大字級單行常常只剩 3–4 字（階段1規格 §3.2(a)）。
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    // 沒有 lineLimit 的話，金額欄拿到 layoutPriority(1) 後這欄會被擠到
                    // 接近 0 寬，沒有上限的 Text 會硬繞成幾十行、把整列撐爆成一大塊
                    // 空白（驗收 BUG-2 用超長備註＋最大 AX 級距實測到的真的會發生，
                    // 不是假設）。鎖住 1 行＋沿用同一支 minimumScaleFactor 收尾。
                    Text("\(expense.category.title)・\(expense.date.formatted(date: .omitted, time: .shortened))")
                        .font(MM.font(13, .medium, relativeTo: .footnote))
                        .tracking(1.04) // +8%
                        .foregroundStyle(MM.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                // 金額拿 layoutPriority(1) 後，標題欄在極端案例（超長備註＋極大金額＋
                // 最大 AX 級距同時出現）會被擠到 0 寬、整段文字直接消失不見——比原本
                // 「金額被裁」更糟。給標題欄一個保底寬度，HStack 協商時金額還是優先，
                // 但標題不會被擠到完全看不見。
                .frame(minWidth: 60, alignment: .leading)

                Spacer(minLength: 8)

                // 金額不可截斷／換行，縮小字級代替（階段1規格 §3.1）。
                // 0.55 在最大 AX 級距＋極大金額（例如 999,999,999）下仍不夠縮，
                // 驗收退回 BUG-2：降到 0.35，並用 layoutPriority 讓標題欄先讓出空間，
                // 不是金額欄先被擠。
                Text(Money.signed(expense.amount, isIncome: expense.isIncome))
                    .font(MM.font(21, .bold, relativeTo: .body))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.35)
                    .layoutPriority(1)
                    .foregroundStyle(expense.isIncome ? MM.income : MM.expense)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .mmRow(padding: 0, cornerRadius: MM.R.md)
        }
        .buttonStyle(.plain)
        .squishy()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(expense.displayTitle)，\(expense.category.title)，\(Money.signed(expense.amount, isIncome: expense.isIncome)) 元"
        )
        .accessibilityHint("點兩下查看完整內容")
        .contextMenu {
            if allowsContextMenu {
                Button {
                    copyNote()
                } label: {
                    Label("複製備註", systemImage: "doc.on.doc")
                }
                Button(role: .destructive) {
                    confirmingDelete = true
                } label: {
                    Label("刪除", systemImage: "trash")
                }
            }
        }
        .confirmationDialog(
            "確定要刪除這筆帳嗎？",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("刪除", role: .destructive) {
                context.delete(expense)
                try? context.save()
            }
            Button("取消", role: .cancel) {}
        }
        .sheet(isPresented: $showDetail) {
            ExpenseDetailSheet(expense: expense, onRequestEdit: { expense in
                showDetail = false
                editingExpense = expense
            })
        }
        .sheet(item: $editingExpense) { expense in
            EntrySheet(mode: .edit(expense))
        }
    }

    private func copyNote() {
        UIPasteboard.general.string = Expense.normalizedDisplayText(expense.note)
        UIAccessibility.post(notification: .announcement, argument: "已複製")
    }
}

// MARK: - 音量波形

struct SoundWaveView: View {
    var level: Double
    var isActive: Bool

    private let barCount = 5

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<barCount, id: \.self) { index in
                Capsule()
                    .fill(MM.brandFill)
                    .frame(width: 7, height: height(for: index))
                    .animation(.easeOut(duration: 0.18), value: level)
            }
        }
        .frame(height: 54)
        .opacity(isActive ? 1 : 0.35)
    }

    private func height(for index: Int) -> CGFloat {
        // 中間高、兩側低，再乘上目前音量。
        let shape: [Double] = [0.45, 0.75, 1.0, 0.75, 0.45]
        let base = 12.0
        let dynamic = 40.0 * level * shape[index % shape.count]
        return CGFloat(base + (isActive ? dynamic : 0))
    }
}

// MARK: - 空狀態

struct CuteEmptyState: View {
    var mood: CatMood = .sleepy
    var title: String
    var subtitle: String

    var body: some View {
        VStack(spacing: 14) {
            CatFaceView(mood: mood, size: 96)
            Text(title)
                .font(MM.font(18, .bold, relativeTo: .headline))
                .foregroundStyle(MM.textPrimary)
            Text(subtitle)
                .font(MM.font(16, .medium, relativeTo: .body))
                .foregroundStyle(MM.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 區塊標題

struct SectionHeader: View {
    let text: String
    var trailing: String?
    /// 有給就把 `trailing` 變成可點文字按鈕（例如「查看全部」）；nil 就是純文字標籤（例如「共 N 筆」）。
    var trailingAction: (() -> Void)?

    var body: some View {
        HStack {
            Text(text)
                .font(MM.font(17, .bold, relativeTo: .headline))
                .foregroundStyle(MM.textPrimary)
            Spacer()
            if let trailing {
                if let trailingAction {
                    Button(action: trailingAction) {
                        Text(trailing)
                            .font(MM.font(13, .semibold, relativeTo: .footnote))
                            .foregroundStyle(MM.brandText)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .squishy()
                    .accessibilityLabel(trailing)
                    .accessibilityHint("前往帳本頁")
                } else {
                    Text(trailing)
                        .font(MM.font(12, .medium, relativeTo: .caption))
                        .tracking(1.2) // +10%
                        .foregroundStyle(MM.textTertiary)
                }
            }
        }
    }
}
