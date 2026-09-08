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
        @Bindable var router = router

        ZStack {
            MM.bgBase.ignoresSafeArea()

            // 改用 TabView(selection:) 取代手工 switch：UITabBarController 會把三個
            // 分頁的 view controller 都留在記憶體裡，切分頁不再銷毀重建整棵 view tree
            // （@Query 不重新 fetch、ScrollView 位置與 @State 都保留）。原本的
            // withAnimation(MM.softPop) 留在按鈕上，效果是自訂膠囊選中態的滑動動畫，
            // 跟系統的分頁內容轉場是兩件事，互不影響。
            //
            // .safeAreaInset(edge: .bottom) { tabBar } 必須分別掛在「每個子畫面」上，
            // 不能只掛在 TabView 自己身上一次：TabView 底層是 UITabBarController，
            // 每個分頁是獨立的 child view controller，各自有自己的安全區域計算，
            // 掛在 TabView 外層時這個安全區域不會確實傳進每個分頁內部的
            // List／ScrollView——實測結果是 RecordsView 分頁到底時「看更多」按鈕
            // 疊在膠囊底下、完全點不到（膠囊在觸控 z-order 上優先）。分別掛在三個
            // 子畫面上，各自的捲動內容才會確實把底部安全區域讓出來。
            TabView(selection: $router.tab) {
                HomeView()
                    .tag(Tab.home)
                    // 系統原生 tab bar 必須在「子畫面」上隱藏才會生效——下在 TabView
                    // 自己身上不會生效。畫面上只能有下面 tabBar 那個自訂玻璃膠囊。
                    .toolbar(.hidden, for: .tabBar)
                    .safeAreaInset(edge: .bottom) { tabBar }
                RecordsView()
                    .tag(Tab.records)
                    .toolbar(.hidden, for: .tabBar)
                    .safeAreaInset(edge: .bottom) { tabBar }
                StatsView()
                    .tag(Tab.stats)
                    .toolbar(.hidden, for: .tabBar)
                    .safeAreaInset(edge: .bottom) { tabBar }
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
        // 材質膠囊：ultraThinMaterial + hairline 描邊。
        // 原本 iOS 26 走 .glassEffect 真玻璃，2026-09-08 在 iPhone 13 Pro Max
        // （A15／iOS 26.6.1）實機量測後移除——見下方註解。
        .background {
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
        .padding(.horizontal, 26)
        .padding(.bottom, 6)
        .background {
            // 捲動內容穿出膠囊兩側的淡出遮罩：material 穿透感較弱，邊緣容易被硬切。
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

#Preview {
    RootTabView()
        .modelContainer(PreviewData.container)
}
