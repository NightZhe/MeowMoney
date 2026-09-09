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
        let spent: Decimal
        let income: Decimal

        /// spent／income 原本是各自獨立過濾 items 的 computed property，且每次被讀取
        /// 都重算一次；dayHeader 同時讀兩者等於一天的資料被過濾兩次。改成建構時
        /// 單次迴圈算好、存成值，之後讀取是 O(1)。
        init(id: Date, items: [Expense]) {
            self.id = id
            self.items = items
            var spent = Decimal(0)
            var income = Decimal(0)
            for item in items {
                if item.isIncome { income += item.amount } else { spent += item.amount }
            }
            self.spent = spent
            self.income = income
        }
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
                            // 每筆帳目維持各自獨立的 List row，`.onDelete`／滑動刪除
                            // 才吃得到——單一 row 裡塞多筆項目時滑動手勢無法對應到
                            // 「其中一筆」，這是上一輪材質版視覺的回歸（拿掉了已上架
                            // 1.0 就有的滑動刪除）。視覺上要維持「整天一張卡」，改用
                            // `.listRowBackground` 依位置給圓角：第一列圓上緣、最後
                            // 一列圓下緣、中間不圓（`mmGroupedRow`），列與列之間交給
                            // List 原生分隔線（`.listRowSeparatorTint`），最後一列的
                            // 分隔線隱藏（那是卡片下緣，不是列之間的分界）。
                            // 長按 context menu（`allowsContextMenu: true`）維持原本
                            // 的刪除入口，滑動是補回來的第二個入口，不是取代。
                            ForEach(Array(group.items.enumerated()), id: \.element.id) { index, expense in
                                let isFirst = index == 0
                                let isLast = index == group.items.count - 1
                                ExpenseRow(expense: expense, allowsContextMenu: true)
                                    .listRowInsets(EdgeInsets(
                                        top: isFirst ? 4 : 0,
                                        leading: 0,
                                        bottom: isLast ? 4 : 0,
                                        trailing: 0
                                    ))
                                    .listRowBackground(
                                        Color.clear.mmGroupedRow(isFirst: isFirst, isLast: isLast)
                                    )
                                    .listRowSeparator(isLast ? .hidden : .visible)
                                    .listRowSeparatorTint(MM.hairline)
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
                // 34 是標準字級下的視覺高度基準；用 MM.scaledValue 讓它跟著
                // Dynamic Type 縮放，修掉 AX5 下 pinned header 蓋住第一列的重疊
                // （見 MMTheme.swift 該函式註解）。
                .environment(\.defaultMinListHeaderHeight, MM.scaledValue(base: 34))
            }
        }
        .background(MM.bgBase.ignoresSafeArea())
        .sheet(isPresented: $showManualSheet) {
            EntrySheet(mode: .manual)
        }
    }

    /// 對應 1.0 既有的 `delete(_:in:)`（見 `origin/main:Views/RecordsView.swift`）：
    /// `offsets` 是相對於這一天分組內的索引，不是整個 `expenses` 陣列。
    private func delete(_ offsets: IndexSet, in group: DayGroup) {
        for index in offsets {
            context.delete(group.items[index])
        }
        try? context.save()
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
        // 附帶修正（同一類問題）：這三個 Text 原本都沒有 lineLimit，AX5 下 HStack
        // 塞不進去時會整列換成 2–3 行（不掉資料，但不符合規格 §3.1「縮字不換行」）。
        // 日期標題最短、最不需要縮，鎖 1 行即可；兩個金額欄比照 HomeView miniStat
        // 同一套 lineLimit(1) + minimumScaleFactor，不用 layoutPriority 搶位。
        HStack {
            Text(dayTitle(group.id))
                .font(MM.font(15, .bold, relativeTo: .subheadline))
                .foregroundStyle(MM.textPrimary)
                .lineLimit(1)
            Spacer()
            if group.income > 0 {
                Text("+\(Money.string(group.income))")
                    .font(MM.font(13, .semibold, relativeTo: .footnote))
                    .monospacedDigit()
                    .foregroundStyle(MM.income)
                    .lineLimit(1)
                    .minimumScaleFactor(0.2)
            }
            if group.spent > 0 {
                Text("-\(Money.string(group.spent))")
                    .font(MM.font(13, .semibold, relativeTo: .footnote))
                    .monospacedDigit()
                    .foregroundStyle(MM.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.2)
            }
        }
        .padding(.vertical, 4)
        // `.plain` list style 把 section header 釘在頂端浮動捲動（UITableView 既有行為），
        // 這個 HStack 本身沒有底色的話，浮動時後面捲過的列會直接透出來蓋在文字上——
        // 標準字級下列高與 header 高度相近，這層透出幾乎看不到；AX5 下列高暴增，
        // 同一時間有更多列的內容停留在 header 底下，透出變成清楚可讀的文字重疊
        // （2026-09-10 模擬器重現：捲動時「今天」跟第一列文字疊在一起）。補一層跟
        // List 背景一致的不透明底色即可讓浮動 header 正確遮住底下內容。
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            // 系統在 pinned header 上下緣都多留了一點自己的間距（不算進這個 HStack
            // 的 layout），這段沒有被我們的底色蓋到，AX5 下同樣會透出鄰近列的殘影
            // （模擬器截圖確認：修好主要重疊後，上緣與下緣都各剩一條淡淡的殘影）。
            // 底色上下都多蓋一點、跟著字級一起長，蓋住系統自己那段間距。
            MM.bgBase.padding(.vertical, -MM.scaledValue(base: 12))
        )
        .textCase(nil)
    }

    private func dayTitle(_ date: Date) -> String {
        if calendar.isDateInToday(date) { return "今天" }
        if calendar.isDateInYesterday(date) { return "昨天" }
        return date.formatted(.dateTime.month().day().weekday(.abbreviated).locale(Locale(identifier: "zh_TW")))
    }
}

#Preview {
    RecordsView()
        .modelContainer(PreviewData.container)
}
