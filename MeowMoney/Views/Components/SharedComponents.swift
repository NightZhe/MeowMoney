import SwiftUI

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
                    .font(Cute.font(15, .semibold))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                Capsule()
                    .fill(isSelected ? category.color : category.color.opacity(0.16))
            )
            .foregroundStyle(isSelected ? .white : Cute.cocoa)
            .overlay(
                Capsule()
                    .stroke(category.color.opacity(isSelected ? 0 : 0.35), lineWidth: 1.5)
            )
        }
        .squishy()
    }
}

// MARK: - 帳目列

struct ExpenseRow: View {
    let expense: Expense

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(expense.category.color.opacity(0.22))
                    .frame(width: 46, height: 46)
                Text(expense.category.emoji)
                    .font(.system(size: 22))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(expense.displayTitle)
                    .font(Cute.font(16, .semibold))
                    .foregroundStyle(Cute.cocoa)
                    .lineLimit(1)
                Text("\(expense.category.title)・\(expense.date.formatted(date: .omitted, time: .shortened))")
                    .font(Cute.captionFont)
                    .foregroundStyle(Cute.cocoaSoft)
            }

            Spacer(minLength: 8)

            Text(Money.signed(expense.amount, isIncome: expense.isIncome))
                .font(Cute.font(18, .bold))
                .foregroundStyle(expense.isIncome ? Cute.mint : Cute.cocoa)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Cute.card)
        )
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
                    .fill(Cute.peach)
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
                .font(Cute.font(18, .bold))
                .foregroundStyle(Cute.cocoa)
            Text(subtitle)
                .font(Cute.bodyFont)
                .foregroundStyle(Cute.cocoaSoft)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

// MARK: - 區塊標題

struct SectionHeader: View {
    let text: String
    var trailing: String?

    var body: some View {
        HStack {
            Text(text)
                .font(Cute.font(17, .bold))
                .foregroundStyle(Cute.cocoa)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(Cute.captionFont)
                    .foregroundStyle(Cute.cocoaSoft)
            }
        }
    }
}
