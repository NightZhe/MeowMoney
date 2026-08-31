import SwiftUI

/// 讓子畫面（例如 Home 的「查看全部」）能觸發切換分頁，不用 NotificationCenter。
/// 只做「View 層之間的狀態傳遞」，不含商業邏輯（階段1規格 §2.5）。
@Observable
final class TabRouter {
    var tab: RootTabView.Tab = .home
}

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

    @State private var router = TabRouter()
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            MM.bgBase.ignoresSafeArea()

            Group {
                switch router.tab {
                case .home: HomeView()
                case .records: RecordsView()
                case .stats: StatsView()
                }
            }
            .safeAreaInset(edge: .bottom) {
                tabBar
            }
        }
        .environment(router)
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(Tab.allCases, id: \.self) { item in
                Button {
                    withAnimation(MM.softPop) { router.tab = item }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: item.icon)
                            .font(.system(size: 17, weight: .semibold))
                        // 導覽層 chrome：用 navFont 封頂 Dynamic Type，
                        // 否則 AX 級距會把這個固定高度的浮動膠囊撐爆（見 MM.navFont 註解）。
                        Text(item.title)
                            .font(MM.navFont(11, .semibold, relativeTo: .caption2))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    // 選中態底色（brandStrong）在 Dark 是亮珊瑚，白字只有 2.18:1——
                    // 跟 RecordsView 加號按鈕同一個修正，改綁 textOnBrand。
                    .foregroundStyle(router.tab == item ? MM.textOnBrand : MM.textSecondary)
                    .background(
                        Capsule()
                            .fill(router.tab == item ? MM.brandStrong : .clear)
                    )
                }
                .squishy()
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(router.tab == item ? [.isSelected] : [])
            }
        }
        .padding(6)
        // Liquid Glass 雙軌（Glass實作規格.md §2.2）：iOS 26 用真玻璃，
        // iOS 17–25 降級成 ultraThinMaterial + hairline 描邊。
        .background {
            if #available(iOS 26, *) {
                // Capsule() 當 View 用時預設會用前景色（primary）填滿自身，
                // glassEffect 疊在這個不透明底上等於被蓋住（渲染成灰色板子）。
                // 用 .fill(.clear) 讓形狀本身透明，只留幾何當 glassEffect 的遮罩。
                Capsule()
                    .fill(.clear)
                    .glassEffect(.regular, in: .capsule)
                    // 玻璃本身已有邊緣高光，不額外疊 stroke，避免畫蛇添足。
            } else {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Capsule().strokeBorder(
                            scheme == .dark ? MM.glassRegularStroke : MM.hairline,
                            lineWidth: 1
                        )
                    )
                    .shadow(
                        color: scheme == .dark ? .clear : MM.cardShadowLight.opacity(0.10),
                        radius: 14, x: 0, y: 6
                    )
            }
        }
        .padding(.horizontal, 26)
        .padding(.bottom, 6)
        .background {
            // 捲動內容穿出膠囊兩側的淡出遮罩：只有 iOS 17–25 降級軌需要
            // （material 穿透感較弱，邊緣容易被硬切）。iOS 26 真玻璃本身會自然融合
            // 捲動內容，疊一層不透明漸層等於蓋住玻璃該有的穿透感（Glass 規格 §2.2）。
            if #available(iOS 26, *) {
                EmptyView()
            } else {
                LinearGradient(
                    colors: [MM.bgBase.opacity(0), MM.bgBase.opacity(0.92), MM.bgBase],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .padding(.top, -34)
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
            }
        }
    }
}

#Preview {
    RootTabView()
        .modelContainer(PreviewData.container)
}
