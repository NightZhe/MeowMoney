import SwiftUI

/// 記帳分類。`rawValue` 會存進資料庫，之後要改中文顯示名請改 `title`，不要改 rawValue。
enum ExpenseCategory: String, CaseIterable, Codable, Identifiable {
    case food          // 餐飲
    case transport     // 交通
    case shopping      // 購物
    case entertainment // 娛樂
    case home          // 居家
    case medical       // 醫療
    case education     // 學習
    case social        // 人情
    case income        // 收入
    case other         // 其他

    var id: String { rawValue }

    var title: String {
        switch self {
        case .food: "餐飲"
        case .transport: "交通"
        case .shopping: "購物"
        case .entertainment: "娛樂"
        case .home: "居家"
        case .medical: "醫療"
        case .education: "學習"
        case .social: "人情"
        case .income: "收入"
        case .other: "其他"
        }
    }

    var emoji: String {
        switch self {
        case .food: "🍜"
        case .transport: "🚌"
        case .shopping: "🛍️"
        case .entertainment: "🎮"
        case .home: "🏠"
        case .medical: "💊"
        case .education: "📚"
        case .social: "🎁"
        case .income: "💰"
        case .other: "🐾"
        }
    }

    var color: Color {
        switch self {
        case .food: Cute.peach
        case .transport: Cute.sky
        case .shopping: Cute.lilac
        case .entertainment: Color(hex: 0xF6A6C1)
        case .home: Color(hex: 0xB0D68A)
        case .medical: Color(hex: 0xF29E9E)
        case .education: Color(hex: 0x9FC6F5)
        case .social: Cute.butter
        case .income: Cute.mint
        case .other: Cute.cocoaSoft
        }
    }

    /// 支出分類（給選擇器用，收入另外處理）。
    static var expenseCases: [ExpenseCategory] {
        allCases.filter { $0 != .income }
    }

    /// 語音辨識關鍵字。順序不影響；比對時取命中字數最多的分類。
    var keywords: [String] {
        switch self {
        case .food:
            ["早餐", "午餐", "晚餐", "宵夜", "便當", "飯", "麵", "麵包", "咖啡", "飲料", "手搖",
             "奶茶", "珍奶", "吃", "喝", "餐", "food", "星巴克", "麥當勞", "超商", "全家",
             "7-11", "小七", "便利商店", "火鍋", "燒烤", "壽司", "披薩", "雞排", "滷肉飯",
             "水果", "零食", "點心", "蛋糕", "早午餐", "自助餐", "牛肉麵", "便當店", "餐廳",
             // 實機測試發現「今天早上去菜市場買240」會落到「其他」
             "菜市場", "傳統市場", "買菜", "市場", "蔬菜", "豬肉", "雞肉", "牛肉", "海鮮",
             "拉麵", "義大利麵", "便當菜", "小吃", "夜市", "路邊攤", "宵夜場"]
        case .transport:
            ["捷運", "公車", "計程車", "小黃", "uber", "加油", "油錢", "停車", "停車費",
             "高鐵", "火車", "台鐵", "客運", "機票", "ubike", "youbike", "腳踏車", "過路費",
             "etag", "悠遊卡", "一卡通", "車資", "交通", "運費", "機車", "保養", "維修"]
        case .shopping:
            // 不放「買」：太通用，會蓋掉「買一本書」「買便當」這種更明確的線索。
            ["購物", "衣服", "褲子", "鞋", "包包", "網購", "蝦皮", "momo", "pchome",
             "淘寶", "家樂福", "全聯", "好市多", "costco", "日用品", "化妝品", "保養品",
             "3c", "手機", "耳機", "電腦", "生活用品", "洗髮精", "衛生紙",
             // 實機測試發現「買Zara $170」會落到「其他」——服飾品牌與百貨通路
             "zara", "uniqlo", "h&m", "gu", "net", "lativ", "服飾", "專櫃", "百貨",
             "新光", "三越", "sogo", "大創", "宜得利", "ikea", "屈臣氏", "康是美", "寶雅"]
        case .entertainment:
            ["電影", "遊戲", "ktv", "唱歌", "訂閱", "netflix", "spotify", "youtube", "門票",
             "展覽", "演唱會", "旅遊", "住宿", "飯店", "娛樂", "steam", "課金", "書展",
             "健身", "健身房", "運動", "球賽", "電競"]
        case .home:
            ["房租", "租金", "水費", "電費", "瓦斯", "網路費", "管理費", "家具", "家電",
             "電話費", "手機費", "房貸", "裝潢", "傢俱", "清潔", "水電"]
        case .medical:
            ["看醫生", "醫院", "診所", "掛號", "藥", "藥局", "牙醫", "健檢", "看牙",
             "保健食品", "維他命", "醫療", "眼鏡", "隱形眼鏡"]
        case .education:
            ["書", "課程", "學費", "補習", "教材", "線上課", "證照", "考試", "文具", "講座"]
        case .social:
            ["紅包", "禮物", "請客", "聚餐", "婚禮", "喜酒", "捐款", "孝親費", "包紅包",
             "生日", "白包", "人情"]
        case .income:
            ["薪水", "薪資", "收入", "獎金", "紅利", "入帳", "賺", "退款", "退錢", "中獎",
             "股利", "配息", "利息", "報酬", "兼職", "接案", "零用錢", "年終",
             // 實機測試發現「今天撿到錢加100」原本被判成支出
             "撿到", "發票中", "回饋金", "補助"]
        case .other:
            []
        }
    }
}
