import SwiftUI
import SwiftData

struct HomeView: View {
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @State private var showVoiceSheet = false
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(TabRouter.self) private var router

    private var calendar: Calendar { .current }

    private var todayExpenses: [Expense] {
        expenses.filter { calendar.isDateInToday($0.date) }
    }

    private var todaySpent: Decimal {
        todayExpenses.filter { !$0.isIncome }.reduce(Decimal(0)) { $0 + $1.amount }
    }

    private var monthSpent: Decimal {
        expenses
            .filter { !$0.isIncome && calendar.isDate($0.date, equalTo: Date(), toGranularity: .month) }
            .reduce(Decimal(0)) { $0 + $1.amount }
    }

    private var monthIncome: Decimal {
        expenses
            .filter { $0.isIncome && calendar.isDate($0.date, equalTo: Date(), toGranularity: .month) }
            .reduce(Decimal(0)) { $0 + $1.amount }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                header
                summaryCard
                micSection
                recentSection
            }
            .padding(.horizontal, 22)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(MM.bgBase.ignoresSafeArea())
        .sheet(isPresented: $showVoiceSheet) {
            EntrySheet(mode: .voice)
        }
        .onAppear { if !reduceMotion { pulse = true } }
    }

    // MARK: - 區塊

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(greeting)
                    .font(MM.font(17, .bold, relativeTo: .headline))
                    .foregroundStyle(MM.textPrimary)
                Text(Date().formatted(.dateTime.month(.wide).day().weekday(.wide).locale(Locale(identifier: "zh_TW"))))
                    .font(MM.font(13, .medium, relativeTo: .footnote))
                    .foregroundStyle(MM.textSecondary)
            }
            Spacer()
            CatFaceView(mood: todayExpenses.isEmpty ? .sleepy : .idle, size: 54)
        }
    }

    private var greeting: String {
        let hour = calendar.component(.hour, from: Date())
        switch hour {
        case 5..<11: return "早安 ☀️"
        case 11..<14: return "午安 🍱"
        case 14..<18: return "下午好 ☕️"
        case 18..<23: return "晚安 🌙"
        default: return "夜貓子 🐈‍⬛"
        }
    }

    private var summaryCard: some View {
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                Text("今天花了")
                    .font(MM.font(12, .medium, relativeTo: .caption))
                    .tracking(1.2) // +10%
                    .foregroundStyle(MM.textTertiary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("$")
                        .font(MM.font(20, .bold, relativeTo: .title3))
                        .foregroundStyle(MM.textSecondary)
                    Text(Money.string(todaySpent))
                        .font(MM.font(52, .heavy, relativeTo: .largeTitle))
                        .tracking(-1.56) // −3%
                        .monospacedDigit()
                        .foregroundStyle(MM.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                        .contentTransition(.numericText())
                }
            }

            Divider().background(MM.hairline)

            HStack(spacing: 0) {
                miniStat(title: "本月支出", value: monthSpent, color: MM.expense)
                Rectangle()
                    .fill(MM.hairline)
                    .frame(width: 1, height: 34)
                miniStat(title: "本月收入", value: monthIncome, color: MM.income)
            }
        }
        .mmCard(padding: 20)
    }

    private func miniStat(title: String, value: Decimal, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(title)
                .font(MM.font(12, .medium, relativeTo: .caption))
                .tracking(1.2) // +10%
                .foregroundStyle(MM.textTertiary)
            Text("$\(Money.string(value))")
                .font(MM.font(22, .bold, relativeTo: .title3))
                .monospacedDigit()
                .lineLimit(1)
                // 跟 StatsView 結餘欄同一類坑，但成因不同：這裡沒有 layoutPriority 搶位，
                // 是欄寬本身（卡片對半分）在 AX5＋10 位數金額同時出現時，0.55 這個地板
                // 縮不夠——實測 9,876,543,210＋1,234,567,890 相加後仍會被 `.lineLimit(1)`
                // 截斷成「$11,111...」。跟 StatsView 一樣，把地板降到 0.2 讓
                // minimumScaleFactor 真正兜住這個極端案例，不靠 layoutPriority。
                .minimumScaleFactor(0.2)
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
    }

    private var micSection: some View {
        VStack(spacing: 12) {
            Button {
                showVoiceSheet = true
            } label: {
                ZStack {
                    // 兩圈 1px 細環，不是暈開的實心色塊（README §6.6 規則 4）
                    Circle()
                        .strokeBorder(MM.brandFill.opacity(0.16), lineWidth: 1)
                        .frame(width: 196, height: 196)
                        .scaleEffect(pulse ? 1.08 : 0.94)

                    // 中間那圈是全 app 唯一的自訂玻璃（README §0；Glass實作規格.md §5）。
                    Group {
                        if reduceTransparency {
                            // 兩軌、RT 開啟時共用同一種降級：純 hairline，不追求玻璃感。
                            Circle().strokeBorder(MM.hairline, lineWidth: 1)
                        } else if #available(iOS 26, *) {
                            Circle()
                                .strokeBorder(MM.brandFill.opacity(0.30), lineWidth: 1)
                                .glassEffect(.regular, in: .circle)
                        } else {
                            // iOS 17–25：material 圓環，不是純色線稿——否則退化軌完全沒有「玻璃感」。
                            Circle()
                                .fill(.ultraThinMaterial)
                                .overlay(Circle().strokeBorder(MM.brandFill.opacity(0.30), lineWidth: 1))
                        }
                    }
                    .frame(width: 168, height: 168)
                    .scaleEffect(pulse ? 1.04 : 0.96)

                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [MM.micStart, MM.micEnd],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 112, height: 112)
                    Image(systemName: "mic.fill")
                        .font(.system(size: 42, weight: .semibold))
                        // 深色圖示，不是白色：白色對淺蜜桃只有 1.99:1。
                        .foregroundStyle(MM.onFill)
                }
                .frame(height: 196)
            }
            .squishy()
            .accessibilityLabel("開始語音記帳")
            .accessibilityHint("點兩下後說出你花了什麼，例如「午餐便當一百二」")
            // Reduce Motion 必須停止脈動，不能無條件 .repeatForever（1.0 的既存缺陷）
            .animation(
                reduceMotion ? nil : .easeInOut(duration: 1.6).repeatForever(autoreverses: true),
                value: pulse
            )

            Text("點一下，說出你花了什麼")
                .font(MM.font(15, .semibold, relativeTo: .subheadline))
                .foregroundStyle(MM.textSecondary)
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                text: "最近的帳",
                trailing: expenses.isEmpty ? nil : "查看全部",
                trailingAction: expenses.isEmpty ? nil : { router.tab = .records }
            )

            if expenses.isEmpty {
                CuteEmptyState(
                    title: "還沒有任何一筆帳",
                    subtitle: "按上面的麥克風，說「早餐 50」試試看"
                )
                .mmCard(padding: 12)
            } else {
                VStack(spacing: 8) {
                    ForEach(expenses.prefix(4)) { expense in
                        ExpenseRow(expense: expense)
                    }
                }
            }
        }
    }
}

#Preview {
    HomeView()
        .environment(TabRouter())
        .modelContainer(PreviewData.container)
}
