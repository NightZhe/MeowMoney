import SwiftUI
import SwiftData

struct HomeView: View {
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @State private var showVoiceSheet = false
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(TabRouter.self) private var router

    private var calendar: Calendar { .current }

    private struct TodaySummary {
        let hasAny: Bool
        let spent: Decimal
    }

    private struct MonthSummary {
        let spent: Decimal
        let income: Decimal
    }

    /// 原本 todayExpenses／todaySpent 各自過濾一次今天的資料，改成單次迴圈同時
    /// 算出「今天有沒有帳」與「今天花了多少」。
    private var todaySummary: TodaySummary {
        var spent = Decimal(0)
        var hasAny = false
        for expense in expenses where calendar.isDateInToday(expense.date) {
            hasAny = true
            if !expense.isIncome { spent += expense.amount }
        }
        return TodaySummary(hasAny: hasAny, spent: spent)
    }

    /// 原本 monthSpent／monthIncome 各自對 `expenses` 全量過濾一次，改成單次迴圈。
    private var monthSummary: MonthSummary {
        var spent = Decimal(0)
        var income = Decimal(0)
        for expense in expenses where calendar.isDate(expense.date, equalTo: Date(), toGranularity: .month) {
            if expense.isIncome { income += expense.amount } else { spent += expense.amount }
        }
        return MonthSummary(spent: spent, income: income)
    }

    var body: some View {
        let today = todaySummary
        let month = monthSummary

        ScrollView {
            VStack(spacing: 22) {
                header(hasExpenseToday: today.hasAny)
                summaryCard(today: today, month: month)
                micSection
                recentSection
            }
            .padding(.horizontal, 22)
            .padding(.top, 12)
            .padding(.bottom, 24)
            // 附帶修正：`.safeAreaInset(edge: .bottom) { tabBar }` 掛在 RootTabView 的
            // 每個子畫面上（見該檔註解），在「不需要捲動」的情況下運作正常——標準字級
            // 下 4 筆最近的帳從來塞不滿一屏，這條路徑沒問題。但 AX5 下 4 筆就會讓內容
            // 高度超出可視範圍、真的需要捲動，這時 ScrollView 的最大捲動距離會少算
            // 大約一個 tab bar 的高度：捲到底後最後一到兩筆卡片本體被膠囊蓋住，
            // 而且再也捲不出來（模擬器實測：AX5＋5 筆帳，捲到底部仍看得到「餐飲」
            // 文字卡在膠囊材質後面，不是純視覺穿透，是內容真的被吃掉一截）。
            // 這是 `.safeAreaInset` 在 ScrollView 真的進入捲動狀態時的既知限制，不是
            // 這裡的排版錯——用內容層自己的 padding 補足，不依賴 safeAreaInset 在
            // 捲動路徑上的行為。只在 AX 級距加，標準字級版面不變。
            .padding(.bottom, dynamicTypeSize.isAccessibilitySize ? MM.scaledValue(base: 88) : 0)
        }
        .scrollIndicators(.hidden)
        .background(MM.bgBase.ignoresSafeArea())
        .sheet(isPresented: $showVoiceSheet) {
            EntrySheet(mode: .voice)
        }
        .onAppear { if !reduceMotion { pulse = true } }
    }

    // MARK: - 區塊

    private func header(hasExpenseToday: Bool) -> some View {
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
            CatFaceView(mood: hasExpenseToday ? .idle : .sleepy, size: 54)
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

    private func summaryCard(today: TodaySummary, month: MonthSummary) -> some View {
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
                    Text(Money.string(today.spent))
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
                miniStat(title: "本月支出", value: month.spent, color: MM.expense)
                Rectangle()
                    .fill(MM.hairline)
                    .frame(width: 1, height: 34)
                miniStat(title: "本月收入", value: month.income, color: MM.income)
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
                    // 兩圈**實心**光暈在呼吸，不是 1px 細環。2.0 一度改成細環（依據當時
                    // README §6.6 規則 4「不要暈開的實心色塊」），但那條規則沒有任何驗證
                    // 支撐；使用者實機比對 1.0 與 2.0 後判定 1.0 的漸層呼吸更有質感，
                    // 2026-09-09 改回。尺寸也回到 1.0 的 168／136——比 2.0 的 196／168 更貼近
                    // 核心，讀起來才像「從按鈕散出來的光」而不是兩圈漣漪。
                    // 深色的兩層都調亮一階，補上深色不能用投影所少掉的發光感。
                    Circle()
                        .fill(MM.brandFill.opacity(scheme == .dark ? 0.22 : 0.16))
                        .frame(width: 168, height: 168)
                        .scaleEffect(pulse ? 1.08 : 0.94)

                    Circle()
                        .fill(MM.brandFill.opacity(scheme == .dark ? 0.30 : 0.22))
                        .frame(width: 136, height: 136)
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
                        // 核心的同色發光是 1.0 質感的主要來源。深色下不掛投影——
                        // 暖色投影在深底上會糊成髒污（README §6.5 Spotify 研究），
                        // 該模式的發光由上面兩層較高的不透明度負責。
                        .shadow(
                            color: scheme == .dark ? .clear : MM.brandFill.opacity(0.5),
                            radius: 16, x: 0, y: 8
                        )
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
                // 最多 4 筆包在一個分組容器裡，列與列之間用 Divider 分隔，
                // 不再逐列各自套殼（材質版視覺規格 §2.2）。
                let recent = Array(expenses.prefix(4))
                VStack(spacing: 0) {
                    ForEach(Array(recent.enumerated()), id: \.element.id) { index, expense in
                        ExpenseRow(expense: expense)
                        if index < recent.count - 1 {
                            Divider().background(MM.hairline)
                        }
                    }
                }
                .mmCard(padding: 0)
            }
        }
    }
}

#Preview {
    HomeView()
        .environment(TabRouter())
        .modelContainer(PreviewData.container)
}
