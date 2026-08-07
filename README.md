# 喵喵記帳 MeowMoney

可愛風格的 iOS 語音記帳 app。按一下麥克風，說「午餐便當一百二」，
就自動解析成 **金額 120 / 分類 餐飲 / 備註 午餐便當**，確認後存進帳本。

- 平台：iOS 17.0 以上，**僅 iPhone**、僅直式
  （`TARGETED_DEVICE_FAMILY = "1"`；設成 iPad 相容的話上架要另外準備 iPad 截圖）
- 技術：SwiftUI + SwiftData + Speech Framework
- 資料：**全部留在裝置上**，沒有後端、沒有帳號、不上傳雲端
- Bundle ID：`com.harrylee.meowmoney`（上架前可改，見 `UPLOAD-GUIDE.md`）

---

## 快速開始

```bash
open /Users/ben/harryaiagent/MeowMoney/MeowMoney.xcodeproj
```

在 Xcode 左上角選一台 iPhone 模擬器，按 ⌘R 執行。

> **注意**：語音辨識在模擬器上不一定抓得到麥克風。要測語音功能，
> 請接實機執行；模擬器可以用畫面下方的「或直接打字」欄位測試解析邏輯。

跑測試：

```bash
xcodebuild test -project MeowMoney.xcodeproj -scheme MeowMoney -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
```

---

## 檔案地圖

| 路徑 | 做什麼 |
|------|--------|
| `MeowMoney/MeowMoneyApp.swift` | App 進入點，掛上 SwiftData container |
| `MeowMoney/Models/Expense.swift` | 一筆帳的資料模型（`@Model`） |
| `MeowMoney/Models/ExpenseCategory.swift` | 10 個分類＋每個分類的語音關鍵字表 |
| `MeowMoney/Services/ChineseNumberParser.swift` | 中文數字轉數值（含台灣口語省略說法） |
| `MeowMoney/Services/ExpenseParser.swift` | 一句話 → 金額／分類／備註／日期／收支 |
| `MeowMoney/Services/SpeechRecognizer.swift` | zh-TW 即時語音辨識，停頓 1.6 秒自動收工 |
| `MeowMoney/Views/HomeView.swift` | 首頁：今日花費、大麥克風按鈕、最近的帳 |
| `MeowMoney/Views/EntrySheet.swift` | 語音／手動新增的確認編輯面板 |
| `MeowMoney/Views/RecordsView.swift` | 帳本：依日期分組、左滑刪除 |
| `MeowMoney/Views/StatsView.swift` | 統計：月結餘、分類佔比長條 |
| `MeowMoney/Views/Components/CatFaceView.swift` | 吉祥物「錢錢貓」，純 SwiftUI 形狀繪製 |
| `MeowMoney/Theme/CuteTheme.swift` | 配色、圓角、字體、動畫參數 |
| `MeowMoney/Views/RootTabView.swift` | 底部膠囊分頁列與三個分頁的切換 |
| `MeowMoney/Views/Components/SharedComponents.swift` | 分類膠囊、帳目列、音量波形、空狀態 |
| `MeowMoney/Models/PreviewData.swift` | Xcode Preview 用的記憶體假資料 |
| `MeowMoney/PrivacyInfo.xcprivacy` | 隱私清單，宣告不追蹤、不蒐集資料 |
| `MeowMoneyTests/` | 解析邏輯的單元測試（19 個測試、61 項斷言） |

---

## 語音聽得懂哪些說法

解析器針對台灣口語設計，以下都測過（見 `MeowMoneyTests/`）：

| 你說 | 解析結果 |
|------|----------|
| 午餐便當一百二 | 120・餐飲・午餐便當 |
| 搭計程車250元 | 250・交通 |
| 買了兩個便當共240 | 240・餐飲（「兩個」的 2 不會被當成金額） |
| 咖啡１２０元 | 120・餐飲（全形數字自動轉換） |
| 買球鞋 3,280 元 | 3280・購物（千分位自動處理） |
| 薪水入帳十三萬 | 130000・**收入** |
| 昨天晚餐吃拉麵180 | 180・餐飲・日期自動退一天 |
| 前天加油1200 | 1200・交通・日期退兩天 |
| 7月5號看電影390 | 390・娛樂・日期 7/5 |
| 幫我記帳 今天花了 星巴克 165 元 | 165・餐飲・星巴克（贅詞自動清掉） |

**台灣口語的數字省略也支援**：
`一百二` = 120、`兩千五` = 2500、`一萬二` = 12000。
說「一百**零**二」則正確解析成 102（「零」會擋掉省略推算）。

解析不準時不會硬存——所有結果都會先進確認面板，金額、分類、備註、日期都能手動改。

---

## 設計決策

**為什麼不接 LLM API 做語意解析？**
規則式解析在裝置上跑，零延遲、零成本、離線可用，而且使用者的消費紀錄不會離開手機。
記帳這種高頻小動作，等 1 秒 API 回應的體驗會比打字還差。
代價是遇到沒收錄的說法會落到「其他」分類——所以確認面板是必要的，不是多餘的一步。

**為什麼金額用 `Decimal` 而不是 `Double`？**
避免浮點誤差累積。帳目加總是這個 app 的核心輸出，不能有 0.1 + 0.2 的問題。

**為什麼吉祥物用 SwiftUI 形狀畫而不是圖片？**
任意尺寸都清晰、可以隨狀態變表情（待機／聆聽／成功／沒聽懂）、不佔 app 體積。

---

## 目前的驗證狀態

已實跑驗證（不是「應該可以」）：

- `xcodebuild build` 對 iOS 26.5 模擬器 SDK 建置成功，零 error 零 warning
- `xcodebuild test` 在 iPhone 17 Pro Max（iOS 26.5）模擬器跑完 **19 個測試、0 失敗**
- app 實際安裝啟動，三個分頁都渲染過並截圖確認（首頁、帳本、統計）
- SwiftData 存取 `Decimal` 金額另外寫程式驗過：小數不失真、加總無浮點誤差
- App 圖示 1024×1024、RGB 無 alpha（有 alpha 會被 App Store 上傳擋下）

尚未驗證：實機上的語音辨識行為（見下方限制 1）、上架流程本身。

## 已知限制

1. **語音辨識需要實機測試**：模擬器的麥克風輸入不穩定，`SpeechRecognizer` 的
   完整行為（音量波形、停頓自動收工）尚未在實機驗證過。
2. **裝置端辨識的可用性視機型與語言包而定**：`supportsOnDeviceRecognition` 為 false 時
   會退回 Apple 伺服器辨識（需要網路，語音會送到 Apple）。這點必須寫進隱私政策。
3. **沒有 iCloud 同步**：換手機資料不會跟著走。要做的話是加 `.modelContainer` 的
   CloudKit 設定＋App Group entitlement。
4. **沒有預算功能**：目前只記錄與統計，沒有「本月上限」提醒。

---

## 上架

見 [UPLOAD-GUIDE.md](UPLOAD-GUIDE.md)。
