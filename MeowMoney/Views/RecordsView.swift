import SwiftUI
import SwiftData

struct RecordsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @State private var showManualSheet = false
    /// 清單分頁：一次最多顯示這麼多筆，「看更多」每按一次 +20（階段1規格 §2.1）。
    @State private var visibleLimit = 20

    private var calendar: Calendar { .current }

    private struct DayGroup: Identifiable {
        let id: Date
        let items: [Expense]
        var spent: Decimal { items.filter { !$0.isIncome }.reduce(Decimal(0)) { $0 + $1.amount } }
        var income: Decimal { items.filter(\.isIncome).reduce(Decimal(0)) { $0 + $1.amount } }
    }

    private var groups: [DayGroup] {
        let buckets = Dictionary(grouping: expenses) { calendar.startOfDay(for: $0.date) }
        return buckets
            .map { DayGroup(id: $0.key, items: $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.id > $1.id }
    }

    /// 把按日分組後的陣列攤平裁到 `visibleLimit` 筆（階段1規格 §2.1：view 層 slicing，
    /// 不是分頁查詢）。跨到裁切邊界的那一天，該天只顯示部分筆數，小計也只算已顯示的部分——
    /// 這是已知的視覺取捨，不是漏做（見回報）。
    private var visibleGroups: [DayGroup] {
        var remaining = visibleLimit
        var result: [DayGroup] = []
        for group in groups {
            guard remaining > 0 else { break }
            if group.items.count <= remaining {
                result.append(group)
                remaining -= group.items.count
            } else {
                result.append(DayGroup(id: group.id, items: Array(group.items.prefix(remaining))))
                remaining = 0
            }
        }
        return result
    }

    private var hasMore: Bool { visibleLimit < expenses.count }
    private var remainingCount: Int { max(0, expenses.count - visibleLimit) }

    var body: some View {
        VStack(spacing: 0) {
            header

            if expenses.isEmpty {
                CuteEmptyState(
                    title: "帳本還是空的",
                    subtitle: "回「記帳」頁說一句話，\n或按右上角的加號手動新增。"
                )
                Spacer()
            } else {
                List {
                    ForEach(visibleGroups) { group in
                        Section {
                            ForEach(group.items) { expense in
                                ExpenseRow(expense: expense, allowsContextMenu: true)
                                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                            }
                            .onDelete { offsets in
                                delete(offsets, in: group)
                            }
                        } header: {
                            dayHeader(group)
                        }
                    }

                    paginationFooter
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.defaultMinListHeaderHeight, 34)
            }
        }
        .background(MM.bgBase.ignoresSafeArea())
        .sheet(isPresented: $showManualSheet) {
            EntrySheet(mode: .manual)
        }
    }

    // MARK: - 分頁footer（階段1規格 §2.3、§2.4）

    @ViewBuilder
    private var paginationFooter: some View {
        if hasMore {
            Button {
                withAnimation(MM.softPop) { visibleLimit += 20 }
            } label: {
                Text("看更多（還有 \(remainingCount) 筆）")
                    .font(MM.font(15, .semibold, relativeTo: .subheadline))
                    .foregroundStyle(MM.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)
                    .frame(minWidth: 160, minHeight: 44)
                    .background(Capsule().fill(MM.surfaceTrack))
            }
            .squishy()
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 22)
            .padding(.vertical, 8)
            .accessibilityLabel("看更多，還有 \(remainingCount) 筆")
        } else {
            Text("已經是全部了・共 \(expenses.count) 筆")
                .font(MM.font(13, .medium, relativeTo: .footnote))
                .foregroundStyle(MM.textTertiary)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
        }
    }

    private var header: some View {
        HStack {
            Text("帳本")
                .font(MM.font(28, .bold, relativeTo: .title))
                .foregroundStyle(MM.textPrimary)
            Spacer()
            Button {
                showManualSheet = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .bold))
                    // Dark 的 brand/primary-strong 是亮珊瑚，白圖示只有 2.18:1。
                    // 改綁 text/on-brand，會隨模式翻轉，兩邊都過（4.58／8.42）。
                    .foregroundStyle(MM.textOnBrand)
                    // 既存缺陷：原本 40×40 未達 44×44 觸控目標下限，順手修掉
                    // （跟月份箭頭 38→44 同一類問題，見 Glass實作規格.md §4.2）。
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(MM.brandStrong))
            }
            .squishy()
            .accessibilityLabel("手動新增一筆帳")
        }
        .padding(.horizontal, 22)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private func dayHeader(_ group: DayGroup) -> some View {
        HStack {
            Text(dayTitle(group.id))
                .font(MM.font(15, .bold, relativeTo: .subheadline))
                .foregroundStyle(MM.textPrimary)
            Spacer()
            if group.income > 0 {
                Text("+\(Money.string(group.income))")
                    .font(MM.font(13, .semibold, relativeTo: .footnote))
                    .monospacedDigit()
                    .foregroundStyle(MM.income)
            }
            if group.spent > 0 {
                Text("-\(Money.string(group.spent))")
                    .font(MM.font(13, .semibold, relativeTo: .footnote))
                    .monospacedDigit()
                    .foregroundStyle(MM.textSecondary)
            }
        }
        .padding(.vertical, 4)
        .textCase(nil)
    }

    private func dayTitle(_ date: Date) -> String {
        if calendar.isDateInToday(date) { return "今天" }
        if calendar.isDateInYesterday(date) { return "昨天" }
        return date.formatted(.dateTime.month().day().weekday(.abbreviated).locale(Locale(identifier: "zh_TW")))
    }

    private func delete(_ offsets: IndexSet, in group: DayGroup) {
        for index in offsets {
            context.delete(group.items[index])
        }
        try? context.save()
    }
}

#Preview {
    RecordsView()
        .modelContainer(PreviewData.container)
}
