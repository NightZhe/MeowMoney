import SwiftUI

struct RootTabView: View {
    enum Tab: String, CaseIterable {
        case home, records, stats

        var title: String {
            switch self {
            case .home: "記帳"
            case .records: "帳本"
            case .stats: "統計"
            }
        }

        var icon: String {
            switch self {
            case .home: "mic.fill"
            case .records: "list.bullet.rectangle.portrait.fill"
            case .stats: "chart.pie.fill"
            }
        }
    }

    @State private var tab: Tab = .home

    var body: some View {
        ZStack {
            Cute.background.ignoresSafeArea()

            Group {
                switch tab {
                case .home: HomeView()
                case .records: RecordsView()
                case .stats: StatsView()
                }
            }
            .safeAreaInset(edge: .bottom) {
                tabBar
            }
        }
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(Tab.allCases, id: \.self) { item in
                Button {
                    withAnimation(Cute.softPop) { tab = item }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: item.icon)
                            .font(.system(size: 17, weight: .semibold))
                        Text(item.title)
                            .font(Cute.font(11, .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundStyle(tab == item ? Color.white : Cute.cocoaSoft)
                    .background(
                        Capsule()
                            .fill(tab == item ? Cute.peach : .clear)
                    )
                }
                .squishy()
            }
        }
        .padding(6)
        .background(
            Capsule()
                .fill(Cute.card)
                .shadow(color: Cute.shadow, radius: 14, x: 0, y: 6)
        )
        .padding(.horizontal, 26)
        .padding(.bottom, 6)
        // 捲動內容會從浮動膠囊兩側穿出來，加一層淡出讓它化掉而不是被切斷。
        .background(
            LinearGradient(
                colors: [Cute.creamDeep.opacity(0), Cute.creamDeep.opacity(0.92), Cute.creamDeep],
                startPoint: .top,
                endPoint: .bottom
            )
            .padding(.top, -34)
            .ignoresSafeArea(edges: .bottom)
            .allowsHitTesting(false)
        )
    }
}

#Preview {
    RootTabView()
        .modelContainer(PreviewData.container)
}
