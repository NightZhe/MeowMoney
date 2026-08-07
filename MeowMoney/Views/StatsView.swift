import SwiftUI
import SwiftData

struct StatsView: View {
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @State private var monthOffset = 0

    private var calendar: Calendar { .current }

    private var anchorMonth: Date {
        calendar.date(byAdding: .month, value: monthOffset, to: Date()) ?? Date()
    }

    private var monthExpenses: [Expense] {
        expenses.filter { calendar.isDate($0.date, equalTo: anchorMonth, toGranularity: .month) }
    }

    private var spent: Decimal {
        monthExpenses.filter { !$0.isIncome }.reduce(Decimal(0)) { $0 + $1.amount }
    }

    private var income: Decimal {
        monthExpenses.filter(\.isIncome).reduce(Decimal(0)) { $0 + $1.amount }
    }

    private struct Slice: Identifiable {
        let category: ExpenseCategory
        let total: Decimal
        var id: String { category.rawValue }
    }

    private var slices: [Slice] {
        let buckets = Dictionary(grouping: monthExpenses.filter { !$0.isIncome }) { $0.category }
        return buckets
            .map { Slice(category: $0.key, total: $0.value.reduce(Decimal(0)) { $0 + $1.amount }) }
            .sorted { $0.total > $1.total }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                monthSwitcher
                balanceCard
                breakdown
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
    }

    private var monthSwitcher: some View {
        HStack {
            Button {
                withAnimation(Cute.softPop) { monthOffset -= 1 }
            } label: {
                arrow("chevron.left")
            }
            .squishy()

            Spacer()

            Text(anchorMonth.formatted(.dateTime.year().month(.wide).locale(Locale(identifier: "zh_TW"))))
                .font(Cute.font(20, .bold))
                .foregroundStyle(Cute.cocoa)
                .contentTransition(.numericText())

            Spacer()

            Button {
                withAnimation(Cute.softPop) { monthOffset += 1 }
            } label: {
                arrow("chevron.right")
            }
            .squishy()
            .disabled(monthOffset >= 0)
            .opacity(monthOffset >= 0 ? 0.3 : 1)
        }
        .padding(.top, 6)
    }

    private func arrow(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(Cute.cocoa)
            .frame(width: 38, height: 38)
            .background(Circle().fill(Cute.card))
    }

    private var balanceCard: some View {
        VStack(spacing: 14) {
            HStack(spacing: 0) {
                statColumn(title: "支出", value: spent, color: Cute.peachDeep)
                Rectangle().fill(Cute.shadow.opacity(0.5)).frame(width: 1, height: 40)
                statColumn(title: "收入", value: income, color: Cute.mint)
            }

            let net = income - spent
            HStack(spacing: 6) {
                Text("結餘")
                    .font(Cute.captionFont)
                    .foregroundStyle(Cute.cocoaSoft)
                Text("\(net < 0 ? "-" : "")$\(Money.string(net < 0 ? -net : net))")
                    .font(Cute.font(20, .heavy))
                    .foregroundStyle(net < 0 ? Cute.peachDeep : Cute.mint)
            }
        }
        .cuteCard(padding: 20)
    }

    private func statColumn(title: String, value: Decimal, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(Cute.captionFont)
                .foregroundStyle(Cute.cocoaSoft)
            Text("$\(Money.string(value))")
                .font(Cute.font(22, .bold))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
    }

    private var breakdown: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(text: "花在哪裡", trailing: slices.isEmpty ? nil : "\(slices.count) 個分類")

            if slices.isEmpty {
                CuteEmptyState(
                    title: "這個月還沒有支出",
                    subtitle: "很省喔，貓貓幫你拍拍手 👏"
                )
                .cuteCard(padding: 12)
            } else {
                VStack(spacing: 14) {
                    ForEach(slices) { slice in
                        sliceRow(slice)
                    }
                }
                .cuteCard(padding: 18)
            }
        }
    }

    private func sliceRow(_ slice: Slice) -> some View {
        let ratio = spent > 0 ? slice.total.doubleValue / spent.doubleValue : 0
        return VStack(spacing: 6) {
            HStack(spacing: 8) {
                Text(slice.category.emoji)
                Text(slice.category.title)
                    .font(Cute.font(15, .semibold))
                    .foregroundStyle(Cute.cocoa)
                Spacer()
                Text("\(Int((ratio * 100).rounded()))%")
                    .font(Cute.captionFont)
                    .foregroundStyle(Cute.cocoaSoft)
                Text("$\(Money.string(slice.total))")
                    .font(Cute.font(15, .bold))
                    .foregroundStyle(Cute.cocoa)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(slice.category.color.opacity(0.18))
                    Capsule()
                        .fill(slice.category.color)
                        .frame(width: max(8, proxy.size.width * ratio))
                }
            }
            .frame(height: 10)
        }
    }
}

#Preview {
    StatsView()
        .background(Cute.background)
        .modelContainer(PreviewData.container)
}
