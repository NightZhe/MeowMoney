import SwiftUI
import SwiftData

struct RecordsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @State private var showManualSheet = false

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
                    ForEach(groups) { group in
                        Section {
                            ForEach(group.items) { expense in
                                ExpenseRow(expense: expense)
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
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.defaultMinListHeaderHeight, 34)
            }
        }
        .sheet(isPresented: $showManualSheet) {
            EntrySheet(mode: .manual)
        }
    }

    private var header: some View {
        HStack {
            Text("帳本")
                .font(Cute.titleFont)
                .foregroundStyle(Cute.cocoa)
            Spacer()
            Button {
                showManualSheet = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Cute.peach))
                    .shadow(color: Cute.shadow, radius: 8, x: 0, y: 4)
            }
            .squishy()
        }
        .padding(.horizontal, 22)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private func dayHeader(_ group: DayGroup) -> some View {
        HStack {
            Text(dayTitle(group.id))
                .font(Cute.font(14, .bold))
                .foregroundStyle(Cute.cocoa)
            Spacer()
            if group.income > 0 {
                Text("+\(Money.string(group.income))")
                    .font(Cute.font(13, .semibold))
                    .foregroundStyle(Cute.mint)
            }
            if group.spent > 0 {
                Text("-\(Money.string(group.spent))")
                    .font(Cute.font(13, .semibold))
                    .foregroundStyle(Cute.cocoaSoft)
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
        .background(Cute.background)
        .modelContainer(PreviewData.container)
}
