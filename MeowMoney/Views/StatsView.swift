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
        .background(MM.bgBase.ignoresSafeArea())
    }

    // 月份切換器（驗收退回 BUG-3，拿掉玻璃）：這一列隨內容一起捲動、背後永遠是
    // 純色底，沒有東西會從它底下經過，玻璃在此無可折射的內容，改回一般的
    // surface/card 填色 ＋ hairline 描邊（跟內容層卡片同一套規則，README §6.6
    // 規則 1／1b；tab bar 與語音 sheet 存檔列那兩處確實有內容穿透，玻璃保留不動）。
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
        .mmPill()
        .padding(.top, 6)
    }

    /// 觸控目標 44×44pt（既存缺陷從 38×38 放大，見 Glass 規格 §4.2）；
    /// 圖示本身仍是 15pt，不畫任何底色——底色由外層 `mmPill()` 容器負責。
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
                // 跟金額欄同一個 HStack、金額欄拿 layoutPriority(1)：極端月結餘
                // （最大 AX 級距＋10 位數以上）下這顆標籤原本沒有任何保護，
                // 會被擠到 0 寬直接消失（驗收退回 BUG-2 要求整頁掃過一輪）。
                // 比照 ExpenseRow／sliceRow 同款保底寬度 + 縮放字級。
                Text("結餘")
                    .font(MM.font(12, .medium, relativeTo: .caption))
                    .tracking(1.2) // +10%
                    .foregroundStyle(MM.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(minWidth: 30, alignment: .leading)
                // 這張卡的主角：原本跟支出/收入同級 20px，字級落差不足，拉到 34px（README §6.6 規則 3）
                //
                // `.layoutPriority(1)` 曾經放在這裡，用意是讓「結餘」標籤先讓出空間——
                // 但實測 AX5＋10 位數以上金額同時出現時，layoutPriority 讓這顆 Text
                // 永遠優先拿到「理想寬度」，HStack 協商空間不夠時反而是它把整張卡往右
                // 撐出螢幕（驗收退回 BUG-3：兩個 10 位數金額並存，統計卡橫向溢出、
                // 金額被螢幕右緣裁掉，用 AX5 + 10 位數金額實測重現）。
                // 拿掉 layoutPriority，讓它跟「結餘」標籤用同一個優先度公平協商——
                // minimumScaleFactor 才會在空間不夠時真正被觸發，兩者一起收斂到不溢出。
                Text("\(net < 0 ? "-" : "")$\(Money.string(net < 0 ? -net : net))")
                    .font(MM.font(34, .heavy, relativeTo: .largeTitle))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.2)
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
                // 這欄只有卡片一半寬（跟另一欄對半分），比整寬的「結餘」欄更早撞到
                // 極限，0.35 實測仍會裁掉尾數，收到 0.2 才穩定塞得下 9 位數。
                .minimumScaleFactor(0.2)
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
                HStack(spacing: 6) {
                    Text(slice.category.emoji)
                        .lineLimit(1)
                    Text(slice.category.title)
                        .font(MM.font(16, .semibold, relativeTo: .callout))
                        .foregroundStyle(MM.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                // 跟 ExpenseRow 同一個問題：金額欄 layoutPriority(1) 在最大 AX 級距下
                // 會把這欄擠到 0 寬，emoji／分類名整個消失（不只是被裁一點點）。
                // 給保底寬度，金額協商時還是優先，但這欄不會完全看不見（驗收退回 BUG-2）。
                .frame(minWidth: 60, alignment: .leading)

                Spacer()

                // 這欄原本完全沒有保護（沒有 minimumScaleFactor、沒有保底寬度）——
                // 跟金額欄同一個 HStack、金額欄拿 layoutPriority(1)，最大 AX 級距下
                // 直接被擠成 0 寬、整段消失（不是截斷，是完全空白）。獨立驗收實測到的
                // 真的會發生（驗收退回 BUG-2）。比照分類名欄同一套保底寬度 + 縮放字級。
                Text("\(Int((ratio * 100).rounded()))%")
                    .font(MM.font(12, .medium, relativeTo: .caption))
                    .foregroundStyle(MM.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(minWidth: 28, alignment: .trailing)
                // 金額不可截斷／被裁掉，縮小字級代替（階段1規格 §3.1；驗收退回 BUG-2）。
                //
                // 同「結餘」欄同一個坑：`.layoutPriority(1)` 讓這顆 Text 在空間不足時
                // 拿到「理想寬度」優先權而不縮小，AX5＋兩個分類同時 10 位數金額時，
                // 是它把整張「花在哪裡」卡往右撐出螢幕（驗收退回 BUG-3，AX5 + 10 位數
                // 金額實測重現）。拿掉 layoutPriority，跟分類名／百分比欄公平協商，
                // minimumScaleFactor 才會確實把它壓進可用寬度內。
                Text("$\(Money.string(slice.total))")
                    .font(MM.font(16, .bold, relativeTo: .callout))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.2)
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
