import SwiftUI
import SwiftData

struct StatsView: View {
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @State private var monthOffset = 0
    @Environment(\.colorScheme) private var scheme

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
        .background(MM.bgBase.ignoresSafeArea())
    }

    // 月份切換器整條列玻璃化（Glass實作規格.md §4）：外層一個共用玻璃膠囊容器，
    // 箭頭不再各自套不透明 chip（避免把玻璃切成三塊不連續視覺）。
    private var monthSwitcher: some View {
        HStack {
            iconButton("chevron.left") {
                withAnimation(MM.softPop) { monthOffset -= 1 }
            }
            .accessibilityLabel("上個月")

            Spacer()

            Text(anchorMonth.formatted(.dateTime.year().month(.wide).locale(Locale(identifier: "zh_TW"))))
                .font(MM.font(22, .bold, relativeTo: .title2))
                .foregroundStyle(MM.textPrimary)
                .contentTransition(.numericText())

            Spacer()

            iconButton("chevron.right") {
                withAnimation(MM.softPop) { monthOffset += 1 }
            }
            .disabled(monthOffset >= 0)
            .opacity(monthOffset >= 0 ? 0.3 : 1)
            .accessibilityLabel("下個月")
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .background {
            if #available(iOS 26, *) {
                // 同 RootTabView 的修正：Capsule() 需要透明填色，
                // 否則預設前景色會蓋住玻璃效果（見 Glass實作規格.md 修正記錄）。
                Capsule().fill(.clear).glassEffect(.regular, in: .capsule)
            } else {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Capsule().strokeBorder(
                            scheme == .dark ? MM.glassRegularStroke : MM.hairline,
                            lineWidth: 1
                        )
                    )
            }
        }
        .padding(.top, 6)
    }

    /// 觸控目標 44×44pt（既存缺陷從 38×38 放大，見 Glass 規格 §4.2）；
    /// 圖示本身仍是 15pt，不畫任何底色——底色由外層共用玻璃容器負責。
    private func iconButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(MM.textPrimary)
                .frame(width: 44, height: 44)
        }
        .squishy()
    }

    private var balanceCard: some View {
        VStack(spacing: 14) {
            HStack(spacing: 0) {
                statColumn(title: "支出", value: spent, color: MM.expense)
                Rectangle().fill(MM.hairline).frame(width: 1, height: 40)
                statColumn(title: "收入", value: income, color: MM.income)
            }

            let net = income - spent
            HStack(spacing: 6) {
                Text("結餘")
                    .font(MM.font(12, .medium, relativeTo: .caption))
                    .tracking(1.2) // +10%
                    .foregroundStyle(MM.textTertiary)
                // 這張卡的主角：原本跟支出/收入同級 20px，字級落差不足，拉到 34px（README §6.6 規則 3）
                Text("\(net < 0 ? "-" : "")$\(Money.string(net < 0 ? -net : net))")
                    .font(MM.font(34, .heavy, relativeTo: .largeTitle))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .foregroundStyle(net < 0 ? MM.expense : MM.income)
            }
        }
        .mmCard(padding: 20)
    }

    private func statColumn(title: String, value: Decimal, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(MM.font(12, .medium, relativeTo: .caption))
                .tracking(1.2) // +10%
                .foregroundStyle(MM.textTertiary)
            Text("$\(Money.string(value))")
                .font(MM.font(22, .bold, relativeTo: .title3))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.55)
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
                .mmCard(padding: 12)
            } else {
                VStack(spacing: 14) {
                    ForEach(slices) { slice in
                        sliceRow(slice)
                    }
                }
                .mmCard(padding: 18)
            }
        }
    }

    private func sliceRow(_ slice: Slice) -> some View {
        let ratio = spent > 0 ? slice.total.doubleValue / spent.doubleValue : 0
        return VStack(spacing: 6) {
            HStack(spacing: 8) {
                // 分類 emoji 本階段維持（emoji→SF Symbols 是既定改動，但不在本次三項範圍內）
                Text(slice.category.emoji)
                Text(slice.category.title)
                    .font(MM.font(16, .semibold, relativeTo: .callout))
                    .foregroundStyle(MM.textPrimary)
                Spacer()
                Text("\(Int((ratio * 100).rounded()))%")
                    .font(MM.font(12, .medium, relativeTo: .caption))
                    .foregroundStyle(MM.textTertiary)
                Text("$\(Money.string(slice.total))")
                    .font(MM.font(16, .bold, relativeTo: .callout))
                    .monospacedDigit()
                    .foregroundStyle(MM.textPrimary)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(MM.surfaceTrack)
                    // 分類色本身（category.color）來自 Models，本階段不動——
                    // Dark 降飽和版需要改 Model 層,超出本次範圍（見回報）。
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
        .modelContainer(PreviewData.container)
}
