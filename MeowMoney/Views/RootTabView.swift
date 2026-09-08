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

        /// 選中態用 filled、未選中用 outline（材質版視覺規格 §1.0）：顏色不可是唯一的
        /// 選中態信號，形狀（filled/outline）要一起變化。
        func icon(selected: Bool) -> String {
            switch self {
            case .home: selected ? "mic.fill" : "mic"
            case .records: selected ? "list.bullet.rectangle.portrait.fill" : "list.bullet.rectangle.portrait"
            case .stats: selected ? "chart.pie.fill" : "chart.pie"
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
            // （@Query 不重新 fetch、ScrollView 位置與 @State 都保留）。
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
                let isSelected = router.tab == item

                Button {
                    // 導覽列的選中回饋必須是立即的。原本包 withAnimation(MM.softPop)
                    // ＝ spring(response: 0.3)，底色與圖示都跟著彈簧跑，實機上讀起來
                    // 像「延遲了一下」（2026-09-09 使用者實機回報）。Apple 與 LINE 的
                    // tab bar 都是瞬間切換；按壓手感由 .squishy() 負責，不靠這裡。
                    router.tab = item
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: item.icon(selected: isSelected))
                            .font(.system(size: 17, weight: .semibold))
                        // 導覽層 chrome：用 navFont 封頂 Dynamic Type，
                        // 否則 AX 級距會把這個固定高度的浮動膠囊撐爆（見 MM.navFont 註解）。
                        // 選中態 Semibold／未選中 Regular（材質版視覺規格 §1.0）：這兩個字重
                        // 是 PingFang 中文三個實體檔裡差距最大的一對，.bold／.heavy 對中文會
                        // 靜默收斂成 semibold，不要換成那兩個。
                        Text(item.title)
                            .font(MM.navFont(11, isSelected ? .semibold : .regular, relativeTo: .caption2))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    // 候選 A（全中性化，材質版視覺規格 §1.1）：選中態不出現任何品牌色，
                    // 純靠中性明度差＋icon 形狀切換區分，跟 LINE tab bar 的一手觀察一致。
                    .foregroundStyle(isSelected ? MM.textPrimary : MM.textSecondary)
                    .background(
                        Capsule()
                            .fill(isSelected ? (scheme == .dark ? MM.surfaceElevated : MM.surfaceTrack) : .clear)
                    )
                }
                .squishy()
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
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
        // 這裡曾經墊一層淡出漸層（末端是完全不透明的 bgBase），原本是 iOS 17 降級軌
        // 專用、真玻璃軌會跳過。2026-09-08 移除玻璃時被誤改成無條件套用，
        // 結果不透明的底色直接堵死 .ultraThinMaterial 的穿透感——使用者實機看到的是
        // 一塊實色板子。材質要有半透明感就必須讓內容透得過來（參照使用者提供的
        // LINE 實機錄影：內容直接跑到膠囊後方，沒有遮罩），所以整層移除。
    }
}

#Preview {
    RootTabView()
        .modelContainer(PreviewData.container)
}
