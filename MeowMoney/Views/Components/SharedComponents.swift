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
                    Text("\(expense.category.title)・\(expense.date.formatted(date: .omitted, time: .shortened))")
                        .font(MM.font(13, .medium, relativeTo: .footnote))
                        .tracking(1.04) // +8%
                        .foregroundStyle(MM.textTertiary)
                }

                Spacer(minLength: 8)

                // 金額不可截斷／換行，縮小字級代替（階段1規格 §3.1）。
                Text(Money.signed(expense.amount, isIncome: expense.isIncome))
                    .font(MM.font(21, .bold, relativeTo: .body))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
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
            ExpenseDetailSheet(expense: expense)
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
