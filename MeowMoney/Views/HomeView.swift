import SwiftUI
import SwiftData

struct HomeView: View {
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @State private var showVoiceSheet = false
    @State private var pulse = false

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
        .sheet(isPresented: $showVoiceSheet) {
            EntrySheet(mode: .voice)
        }
        .onAppear { pulse = true }
    }

    // MARK: - 區塊

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(greeting)
                    .font(Cute.font(22, .bold))
                    .foregroundStyle(Cute.cocoa)
                Text(Date().formatted(.dateTime.month(.wide).day().weekday(.wide).locale(Locale(identifier: "zh_TW"))))
                    .font(Cute.captionFont)
                    .foregroundStyle(Cute.cocoaSoft)
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
                    .font(Cute.captionFont)
                    .foregroundStyle(Cute.cocoaSoft)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("$")
                        .font(Cute.font(20, .bold))
                        .foregroundStyle(Cute.cocoaSoft)
                    Text(Money.string(todaySpent))
                        .font(Cute.numberFont)
                        .foregroundStyle(Cute.cocoa)
                        .contentTransition(.numericText())
                }
            }

            Divider().background(Cute.shadow)

            HStack(spacing: 0) {
                miniStat(title: "本月支出", value: monthSpent, color: Cute.peachDeep)
                Rectangle()
                    .fill(Cute.shadow.opacity(0.5))
                    .frame(width: 1, height: 34)
                miniStat(title: "本月收入", value: monthIncome, color: Cute.mint)
            }
        }
        .cuteCard(padding: 20)
    }

    private func miniStat(title: String, value: Decimal, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(title)
                .font(Cute.captionFont)
                .foregroundStyle(Cute.cocoaSoft)
            Text("$\(Money.string(value))")
                .font(Cute.font(19, .bold))
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
                    Circle()
                        .fill(Cute.peach.opacity(0.16))
                        .frame(width: 168, height: 168)
                        .scaleEffect(pulse ? 1.08 : 0.94)
                    Circle()
                        .fill(Cute.peach.opacity(0.22))
                        .frame(width: 136, height: 136)
                        .scaleEffect(pulse ? 1.04 : 0.96)
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Cute.peach, Cute.peachDeep],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 112, height: 112)
                        .shadow(color: Cute.peach.opacity(0.5), radius: 16, x: 0, y: 8)
                    Image(systemName: "mic.fill")
                        .font(.system(size: 42, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(height: 176)
            }
            .squishy()
            .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: pulse)

            Text("點一下，說出你花了什麼")
                .font(Cute.font(15, .semibold))
                .foregroundStyle(Cute.cocoaSoft)
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(text: "最近的帳", trailing: expenses.isEmpty ? nil : "共 \(expenses.count) 筆")

            if expenses.isEmpty {
                CuteEmptyState(
                    title: "還沒有任何一筆帳",
                    subtitle: "按上面的麥克風，說「早餐 50」試試看"
                )
                .cuteCard(padding: 12)
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
        .background(Cute.background)
        .modelContainer(PreviewData.container)
}
