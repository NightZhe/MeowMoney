---
version: 2.0
name: MeowMoney-design
description: >
  喵嗚記帳（MeowMoney）是一款 iOS 語音記帳 App。設計語言的核心判斷是「可愛放在內容裡，
  紀律放在結構裡」——品牌的柔軟來自吉祥物錢錢貓、暖奶油底色與珊瑚品牌色，而版面、圓角、
  字級、間距一律收斂克制。Liquid Glass 只出現在導航層（tab bar／sheet／月份切換器／
  麥克風光暈），內容層的卡片與列表一律不透明。全 app 只有一個 resting color（珊瑚
  #FF9E93／#FF9184），收入綠是唯一的語意例外。層次在淺色靠收斂陰影＋hairline，
  在暗色靠 hairline＋上緣內高光，暗色下禁用 drop shadow。畫面必須有唯一主角：
  最小標籤與主數字的字級落差至少 4 倍。
platform: iOS / SwiftUI
units: pt（不是 px；本檔所有數值都是 pt）
source-of-truth: ProjectDesignGuide/04-MeowMoney2.0-DesignSystem/（README.md ＋ implementation.md ＋ 階段1-設計規格.md ＋ Glass實作規格.md）
color-modes: Light / Dark（只有兩個模式）
contrast-baseline: 所有對比值都是對同模式的 surface/card 實算（Light 對 #FFFFFF、Dark 對 #1E1917），WCAG 相對亮度公式

# ── Light（預設）────────────────────────────────────────────
colors:
  "bg/base": "#FFF6EC"          # 地面。平色，不用漸層
  "surface/card": "#FFFFFF"     # 卡片、列表列、圓鈕
  "surface/track": "#EDE6E0"    # 長條圖軌道
  "border/hairline": "#EFE3D8"
  "text/primary": "#4A342C"     # 對 bg/base 11.55 ✅AA
  "text/secondary": "#7A6258"   # 5.65 ✅AA
  "text/tertiary": "#8C7468"    # 4.36 ⚠️ 僅限 ≥18pt 或非文字用途
  "brand/primary-fill": "#FF9E93"      # 純裝飾填色、光暈。❌ 禁止在上面放字
  "brand/primary-deep": "#F97C6B"      # 漸層終點。❌ 禁止在上面放字
  "brand/primary-strong": "#D14434"    # 實心按鈕底色
  "brand/primary-text": "#C7453A"      # 品牌色當可點文字用。4.84 ✅AA
  "brand/mic-grad-start": "#FF9E93"
  "brand/mic-grad-end": "#F97C6B"
  "brand/on-fill": "#1A1310"           # 放在淺蜜桃填色上的圖示色（兩模式同值）
  "text/on-brand": "#FFFFFF"           # 放在 primary-strong 上的前景（會隨模式翻轉）
  "state/expense": "#C7453A"    # 4.84 ✅AA
  "state/income": "#1E7A5F"     # 5.24 ✅AA
  "state/warning": "#B4551A"    # 4.94 ✅AA
  "cat/fur": "#FFE3C9"          # 錢錢貓頭部漸層起（兩模式同值）
  "cat/fur-shade": "#F7CEA9"    # 錢錢貓頭部漸層終（兩模式同值）
  "cat/head-shadow": "#D8B9A8"  # alpha 35%
  "category/food": "#D35F47"
  "category/trans": "#2E86BE"
  "category/shop": "#8358CF"
  "category/home": "#2A9162"
  "category/gift": "#B17515"
  "category/study": "#4B6FC4"
  "category/fun": "#C74C7E"
  "category/med": "#C0453F"
  "glass/regular-fill": "rgba(255,255,255,0.55)"
  "glass/regular-stroke": "rgba(255,255,255,0.70)"
  "glass/clear-fill": "rgba(255,255,255,0.20)"
  "glass/dim": "rgba(0,0,0,0.35)"
  "glass/tint-brand": "rgba(255,158,147,0.30)"

# ── Dark（= README §6.5 的「v2」，唯一現行版本）─────────────
colors-dark:
  "bg/base": "#141010"          # 平色暖黑
  "surface/card": "#1E1917"
  "surface/elevated": "#282220" # 浮起層
  "surface/track": "#332B28"
  "border/hairline": "rgba(255,255,255,0.09)"   # 暗色 hairline 用白 6–9%，不是色碼
  "text/primary": "#F5EDE9"           # 15.06 ✅AA
  "text/secondary": "#A99B94"         # 6.47 ✅AA
  "text/tertiary": "#9A8A80"          # 5.24 ✅AA
  "brand/primary-fill": "#FF9E93"      # 與 Light 同值（小面積品牌焦點不降飽和）
  "brand/primary-deep": "#F97C6B"
  "brand/primary-strong": "#FF9184"    # ⚠️ 不是 #D14434
  "brand/primary-text": "#FF9184"      # 7.99 ✅AA
  "brand/mic-grad-start": "#FF9E93"
  "brand/mic-grad-end": "#F97C6B"
  "brand/on-fill": "#1A1310"           # 同 Light
  "text/on-brand": "#1A1310"           # ⚠️ 翻轉成深色，白字只有 2.18
  "state/expense": "#F5EDE9"           # 15.06。⚠️ 中性白，不是珊瑚。支出佔 95% 的列，不該搶眼
  "state/income": "#5CCFA6"            # 9.06 ✅AA
  "state/warning": "#F0BE5C"           # 10.13 ✅AA
  "cat/fur": "#FFE3C9"
  "cat/fur-shade": "#F7CEA9"
  "cat/head-shadow": "rgba(0,0,0,0)"   # 全透明＝暗色下不打陰影
  "category/*": "降飽和 55% 版，色碼在 Figma MM/Color 變數集合，未落到文字檔（見 Known Gaps）"
  "glass/regular-fill": "rgba(255,255,255,0.10)"
  "glass/regular-stroke": "rgba(255,255,255,0.24)"
  "glass/clear-fill": "rgba(255,255,255,0.07)"
  "glass/dim": "rgba(0,0,0,0.35)"
  "glass/tint-brand": "rgba(255,158,147,0.24)"

typography:
  # 字族：iOS 一律系統 .rounded（SF Pro Rounded，中文由系統 fallback 到 PingFang TC）
  # 一律用 .custom(size:relativeTo:) 綁 Dynamic Type，禁止寫死 size
  "Home/hero":   { size: 52, weight: heavy,    tracking: -3%,  use: 首頁今日金額。全 app 唯一的主角 }
  "Amount/XL":   { size: 40, weight: bold,     tracking: -2%,  use: 保留級距，目前未用滿 }
  "Amount/L":    { size: 34, weight: bold,     tracking: -2%,  use: Stats 結餘、明細 sheet 金額 }
  "Amount/M":    { size: 22, weight: bold,     tracking: -1%,  use: mini stat 數值 }
  "Amount/row":  { size: 21, weight: bold,     tracking: -2%,  use: ExpenseRow 金額 }
  "Title/1":     { size: 28, weight: bold,                     use: 頁面大標題（帳本） }
  "Title/2":     { size: 22, weight: bold,                     use: 月份文字 }
  "Title/3":     { size: 20, weight: semibold,                 use: 保留給後續階段 }
  "Headline":    { size: 17, weight: semibold,                 use: 問候語、SectionHeader、空狀態標題 }
  "Body":        { size: 17, weight: regular, lineHeight: 27,  use: 項目名稱、備註全文。中文行高 1.59 }
  "Callout":     { size: 16, weight: semibold,                 use: 統計列分類名與金額 }
  "Subhead":     { size: 15, weight: regular,                  use: 麥克風提示、日期列、看更多按鈕 }
  "Footnote":    { size: 13, weight: regular, tracking: +8%,   use: 分類・時間、收支小計 }
  "Caption":     { size: 12, weight: medium,  tracking: +10%,  use: 「今天花了」這類 tertiary 小標籤 }
  "TabLabel":    { size: 11, weight: medium,                   use: Tab bar（系統控制，不手動指定） }

rounded:
  chip: 12      # 分類圖示底（圓角方，不是正圓）
  sm: 12        # 小標籤
  md: 14        # 列表列、按鈕
  lg: 18        # 卡片
  xl: 34        # sheet（HIG 要求，這個不收）
  pill: 999     # Capsule 型按鈕用 Capsule() 形狀，不用數字
  # 同心規則：外圓角 = 內圓角 + 兩者間距。iOS 26+ 用 ConcentricRectangle(corners: .concentric)

spacing: [4, 8, 12, 16, 20, 24, 32, 40]   # 4pt 基準；卡片內距預設 20

sizes:
  "tap-min": 44       # 觸控目標下限，不可低於
  "mic-core": 112     # 麥克風實心核心
  "mic-halo": 168     # 內細環
  "mic-halo-outer": 196  # 外細環
  "tabbar-h": 60
  "cat-face": 130     # 錢錢貓最大直徑（savedView）

components:
  card:
    backgroundColor: "{colors.surface/card}"
    rounded: "{rounded.lg}"
    padding: 20
    border: "Light {colors.border/hairline} 1pt ／ Dark 白 6–9% 1pt"
    shadow: "Light y=4 blur=14 spread=-4 alpha=0.10 暖色 ／ Dark 禁用，改上緣內高光"
    use: summaryCard（Home）、balanceCard／breakdown（Stats）
  list-row:
    backgroundColor: "{colors.surface/card}"
    rounded: "{rounded.md}"
    border: 同 card
    shadow: "Light y=2 blur=8 alpha=0.07 ／ Dark 禁用"
    use: ExpenseRow（Home 與 Records 共用）
  category-chip:
    backgroundColor: "{colors.category/*} alpha 14%"
    textColor: "{colors.category/*}"
    rounded: "{rounded.chip}"
    size: 40
    iconSize: 20
    note: 圓角方，不是正圓。正圓＋圓體字＋糖果色三者疊加＝玩具感
  button-primary:
    backgroundColor: "{colors.brand/primary-strong}"
    textColor: "{colors.text/on-brand}"      # 一律綁 token，不可寫死白色
    rounded: "{rounded.md}"
    minHeight: 44
  text-link:
    textColor: "{colors.brand/primary-text}"
    typography: "{typography.Subhead}"
    note: 唯一允許用品牌色當文字的地方——它明確是連結，不是狀態
  mic-core:
    fill: "linear-gradient({colors.brand/mic-grad-start} → {colors.brand/mic-grad-end}, topLeading→bottomTrailing)"
    iconColor: "{colors.brand/on-fill}"      # 深色圖示。白圖示只有 1.99:1
    size: "{sizes.mic-core}"
    note: 這顆實心圓不加玻璃——官方禁止玻璃疊玻璃
  mic-halo:
    stroke: "{colors.brand/primary-fill} 30%，1pt，套 glassEffect(.regular)"
    size: "{sizes.mic-halo}"
    outerRing: "{colors.brand/primary-fill} 16%，1pt，{sizes.mic-halo-outer}"
    note: 兩圈 1pt 細環，不是暈開的半透明色塊。全 app 唯一的自訂玻璃
  tab-bar:
    material: 系統 TabView 原生 Liquid Glass
    height: "{sizes.tabbar-h}"
    selectedColor: "{colors.brand/primary-text}"
    note: 不可手刻。圓角由系統決定，app 端無法設定
  sheet:
    rounded: "{rounded.xl}"
    material: 系統決定，不加自訂背景
  progress-bar:
    track: "{colors.surface/track}"
    fill: "{colors.category/*}"
    height: 6
  amount-text:
    typography: "{typography.Amount/row}"
    color: "收入 {colors.state/income} ／ 支出 {colors.state/expense}"
    note: 一律 monospacedDigit()，否則數字更新時寬度會跳動
---

## Overview

喵嗚記帳是一款**語音優先**的 iOS 記帳 App：主畫面正中央是一顆麥克風，說一句「午餐便當一百二」
就記完一筆。吉祥物「錢錢貓」有五種表情，聆聽時嘴巴會跟著音量開合——它不是裝飾，是產品核心。

視覺語言的核心判斷只有一句：

> **可愛放在內容裡，紀律放在結構裡。**

品牌的柔軟來自貓臉、暖奶油底色、珊瑚品牌色與文案；而圓角、字級、間距、層次一律克制。
Duolingo 與 Headspace 都很可愛卻不廉價，原因就在這裡。2026-08-21 做過 A/B 實測：
同一組顏色、同樣的內容，只改結構（圓角、hairline、字級落差、精準幾何），質感差距立刻可見。
**讓畫面看起來廉價的從來不是粉紅色，是結構。**

**Key Characteristics**

- **玻璃只在導航層**：tab bar、sheet、月份切換器、麥克風光暈。卡片與列表列一律不透明——
  這是 Apple HIG 明文規則，不是折衷。
- **一個 resting color**：珊瑚（Light `#FF9E93`／Dark `#FF9184`），只給麥克風與選中態。
  收入綠是唯一的語意例外，與珊瑚色相差 153°，一眼可分。
- **暗色不打陰影**：卡片 `#1E1917` 與地面 `#141010` 只差 1.09:1，層次全靠 hairline
  ＋上緣內高光。黑底上的黑影等於沒作用。
- **字級落差至少 4 倍**：最小標籤 12pt／字距 +10%／tertiary；首頁主數字 52pt／字距 −3%。
- **精準幾何，不用暈開的色塊**：麥克風光暈是兩圈 1pt 細環，不是一團半透明糊。
- **背景是平色**，兩個模式都是。漸層在暗色下只會讓卡片邊界變糊。
- **品牌色分四支，用途不可互換**：填色的不能放字，放字的不能當填色。

## Colors

### 品牌四支（1.0 最大的無障礙缺陷就在這裡）

1.0 只有一支 `#FFA59D`，既當填色又承載白字，白字對比只有 **1.89:1**。2.0 拆成四支：

| Token | 用途 | 紅線 |
|-------|------|------|
| `brand/primary-fill` | 純裝飾填色、光暈 | 白字 1.99 ❌ **禁止放字** |
| `brand/primary-deep` | 漸層終點 | 白字 2.59 ❌ 禁止放字 |
| `brand/primary-strong` | 實心按鈕底色 | 前景一律綁 `text/on-brand`，**不可寫死白色** |
| `brand/primary-text` | 品牌色當可點文字用 | 4.84／7.99 ✅AA |

**兩個 `on-` token 不要搞混**（這是曾經發生過的實際錯誤）：

| Token | 值 | 放在什麼上面 | 判斷法 |
|-------|----|--------------|--------|
| `text/on-brand` | L `#FFFFFF` ／ D `#1A1310`（**會翻轉**） | `brand/primary-strong` 這種會隨模式變深淺的填色 | 底色隨模式翻轉 → 用這個 |
| `brand/on-fill` | `#1A1310`（**兩模式相同**） | `brand/primary-fill`、`mic-grad-*` 這種兩模式都是淺蜜桃的填色 | 底色兩模式都淺 → 用這個 |

麥克風圖示用 `brand/on-fill`（9.23／7.10 ✅）。用白色就退回 1.0 的 1.99:1 bug。

### 文字與表面

Light 的 `text/tertiary` 只有 4.36:1，**僅限 ≥18pt 或非文字用途**；小標籤雖然用它，
但那是 12pt——這是刻意的取捨（小標籤是可跳過的輔助資訊），不是疏漏，
但不要把重要資訊放在 tertiary 上。

Dark 的四階暖中性明度階梯（層次靠明度，不靠色相）：
`#141010`（地面）→ `#1E1917`（卡片）→ `#282220`（浮起）→ `#332B28`（玻璃底／軌道）。

### 狀態色

`state/expense` 在 **Dark 是中性白 `#F5EDE9`**，不是珊瑚——支出佔了 95% 的列，
本來就不該搶眼。這是「一個 resting color」原則的直接後果，不是漏改。

## Typography

字族：iOS 一律系統 `.rounded`（SF Pro Rounded，中文由系統 fallback 到 PingFang TC）。
**一律用 `.custom(size:relativeTo:)` 綁 Dynamic Type，禁止寫死 size**——1.0 的
`Cute.font()` 用固定 size，不隨系統縮放，這是要修掉的既存缺陷。

字級落差是質感的關鍵，不是可選項：小標籤要「更小、更疏、更淡」，主數字要「更大、更緊」。
落差不到 4 倍就沒有主角。全部金額一律 `monospacedDigit()`。

> ⚠️ Figma 稿的字型是代用品：**SF Pro Rounded 在 Figma 無法渲染**（字型列得出來，
> 但文字寬度為 0），emoji 同樣渲染不出。稿件用 `Noto Sans TC` ＋ `Nunito` 代表。
> 這是稿件限制，不是設計決定——實作一律用系統 `.rounded`。

## Layout

- 間距 4pt 基準：`4 / 8 / 12 / 16 / 20 / 24 / 32 / 40`。卡片內距預設 20。
- **背景一律平色 `bg/base`，兩個模式都是。** 不要用漸層。
- 三欄式統計列用 `.frame(maxWidth: .infinity)` 平分寬度，不要在大字級下改成垂直堆疊
  （那會讓卡片在標準字級下也變得過高）。

## Elevation & Depth

**這一節是明暗兩套做法，不是同一套換顏色。**

| | Light | Dark |
|---|-------|------|
| 卡片 | 陰影 y=4 / blur 14 / spread −4 / alpha 0.10（暖色）**＋** `border/hairline` 描邊 | **禁用陰影**。`stroke` 白 6–9% ＋ `INNER_SHADOW` 白 7–9% / offset y=1 / radius 0（模擬光從上方打在邊緣） |
| 列表列 | 陰影 y=2 / blur 8 / alpha 0.07 ＋ hairline | 同上規則 |
| 錢錢貓頭部 | `cat/head-shadow` 35% | `cat/head-shadow` 全透明（關掉），輪廓交給既有的白色 hairline overlay |

淺色的陰影與 hairline **要並用**，兩者一起才有銳利感；不要因為有陰影就省掉描邊。

## Shapes

圓角**寧收勿放**：卡片 18、列 14、分類底 12、sheet 34。
（1.0 的 26／20／正圓已失效——大圓角＋圓體字＋高飽和色三個「可愛」訊號同時出現在
**結構**上就會變玩具感。）

分類圖示底是**圓角方**，不是正圓。同心規則：外圓角 = 內圓角 + 兩者間距。

## Components

見上方 frontmatter 的 `components:`。三個一定要記住的：

1. **麥克風**是全 app 唯一的自訂玻璃。外圈玻璃細環 + 實心漸層核心 + 深色圖示。
   核心那顆實心圓**不再加玻璃**（官方禁止玻璃疊玻璃）。
2. **卡片絕對不能改成 `.glassEffect()`**。它在內容層。
3. **Tab bar 用系統 `TabView`**，不手刻。手刻的永遠拿不到 Liquid Glass 與捲動收合。

## 狀態（iOS 專屬，不可省）

| 狀態 | 觸發 | 做法 |
|------|------|------|
| 語音權限被拒 | 使用者拒絕麥克風／語音辨識 | 提示文字用 `state/warning`（這是警告，不是品牌色） |
| 權限被拒・不再詢問後 | 授權狀態 `.denied` 且系統不再跳窗 | 文案換成「請至設定 App 開啟麥克風權限」＋ 一顆 `brand/primary-strong` 實心「前往設定」按鈕 |
| 語音辨識失敗 | 收不到聲音／逾時 | 同警告色，文案「聽不到聲音，可以先用打字的」 |
| 從背景恢復・聆聽中 | 聆聽中途切走再回來 | `scenePhase` 轉 `.background` 時 `recognizer.cancel()`；恢復時顯示「已暫停，點『重新聆聽』繼續」，**不要假裝還在錄音** |
| 從背景恢復・其他畫面 | Home／Records／Stats | 無特殊處理。SwiftData `@Query` 自動反映，**不需要 loading 畫面** |
| 首次使用（空資料庫） | 全新安裝 | 沿用既有 `CuteEmptyState`，套本檔 token 即可，不需要新畫面 |
| 離線 | — | **不適用**：純本地 SwiftData，沒有網路依賴功能。這是誠實標註，不是漏掉 |

## Do's and Don'ts

**Do**
- 品牌色前景一律綁 token（`text/on-brand`／`brand/on-fill`），不要寫死顏色
- 選中態同時要有形狀變化，顏色不可是唯一的資訊載體
- 金額一律 `monospacedDigit()` ＋ `minimumScaleFactor(0.55)`
- 暗色的層次交給 hairline 與內高光

**Don't**
| ✗ | 為什麼 |
|---|--------|
| 把卡片、列表列改成玻璃 | 官方明文禁止在內容層用 Liquid Glass；也會殺掉品牌 |
| 玻璃疊玻璃 | 官方明文：避免把 Liquid Glass 元素互相堆疊 |
| 在 `brand/primary-fill` 上放白字或白圖示 | 1.99:1 |
| 用蜜桃粉單獨表達狀態 | 顏色不可是唯一資訊載體 |
| 自己手刻 tab bar | 拿不到系統玻璃與捲動收合 |
| 暗色下用 drop shadow 撐層次 | 黑底上的黑影等於沒作用 |
| 把錢錢貓當「粗糙的裝飾」拿掉 | 那是拿品牌換銳利度。正解是把它畫好 |

## iPhone 行為

- **安全區域**：用系統 `List`／`.sheet` 的預設行為，不手動 padding 硬擠開瀏海／Home Indicator。
- **iPhone SE（375pt 寬）**：不開特例。全部金額套 `minimumScaleFactor(0.55)`，
  SE 是這條規則的主要受益機型。
- **Dynamic Type 放大後**：列表標題在 AX 級距放寬到 2 行；按鈕用
  `.fixedSize(horizontal: false, vertical: true)` 讓高度隨文字增高，不要鎖固定高度。
- **觸控目標全部 ≥44×44pt。**
- **無障礙開關**：Reduce Transparency → 玻璃退化為不透明（**自訂玻璃必須自己補這個分支，
  系統元件才會自動處理**）；Reduce Motion → 麥克風脈動停止；Increase Contrast → 描邊 2pt、
  選中態改實心。

## iOS 版本雙軌（落地前必讀）

1.0 已上架，`minimumOsVersion` = **iOS 17.0**，而 `glassEffect`／`ConcentricRectangle`／
`tabBarMinimizeBehavior` **在 iOS 17 全部不存在**。現行決定是走雙軌（保留舊機型使用者）：

| 項目 | iOS 26+ | iOS 17–25 降級軌 |
|------|---------|------------------|
| Tab bar | 系統 `TabView` ＋ `.tabBarMinimizeBehavior(.onScrollDown)` | 系統 `TabView` 原生外觀；收合那行包 `if #available`，**不要自己刻假的收合動畫** |
| 圓角容器 | `ConcentricRectangle(corners: .concentric)` | `RoundedRectangle(cornerRadius:style:.continuous)` |
| 麥克風外環 | `.glassEffect(.regular, in: .circle)` 包在 `GlassEffectContainer` | `.background(Circle().fill(.ultraThinMaterial))` ＋ 同一組 hairline |
| Sheet 圓角 | `.presentationCornerRadius(34)` | 同一行程式碼可用（iOS 16.4+） |
| 陰影／hairline／圓角／字級落差 | 一致 | **一致——質感四規則與 iOS 版本無關，不因降級放寬** |

## Iteration Guide

1. 一次改一個元件，直接引用 YAML key（`{components.card}`、`{colors.brand/on-fill}`）。
2. **一律用 token 參照，不寫裸色碼。** 顏色走 Asset Catalog Color Set 才能自動跟隨明暗模式。
3. 不記錄 hover（iOS 沒有）。狀態只寫 default／pressed／disabled。
4. 改任何顏色前先實算 WCAG 對比；本檔所有對比值都是實算，不是估計。
5. 動到品牌色或無障礙底線屬於「放寬規則」，要先問使用者。
6. 想不出怎麼強調某個元素時：**先拉字級落差、先收圓角**，再考慮加顏色或加 chrome。
7. 本檔是 `04-MeowMoney2.0-DesignSystem/` 的壓縮投影。**兩者衝突時以那四份原始文件為準**，
   並回頭修正本檔。

## Known Gaps（誠實標註，不要自行補值）

1. **分類色的 Dark 色碼不在任何文字檔裡**，只存在 Figma `MM/Color` 變數集合。
   而且兩份來源對它的描述不一致：README §2 寫「換提亮版（對暗軌道 5.18～7.55）」，
   §6.5③ 寫「降飽和 55%（對軌道 6.06～7.37）」。**要用之前先從 Figma 讀出實際值並重新驗算。**
2. **元件的 pressed／disabled 態沒有在來源文件定義過**，本檔因此沒有列。
   要做互動回饋時需要先補設計，不要自行發明。
3. **`bg/gradient-top`／`bg/gradient-bot` 沒有 WCAG 驗算紀錄**，且已決定改平色。
   建議從 Figma 變數集合移除；`implementation.md` 的 `MM.background` 也要同步改成單一 `bgBase`。
4. **README §6.6 的 tab bar 圓角（30/24→26/20）已失效**——改用系統 `TabView` 後，
   app 端無法設定 tab bar 圓角。
5. **統計頁「用當月最大分類色極淡染背景（4–6%）」尚未實作**，列為可選的下一步。
6. **全部設計尚未在模擬器實測**，對比值也**尚未在實機 P3 色域下目視確認**。
   玻璃效果在截圖上看不出問題，要看動態。
7. **iOS 17 雙軌方案雖已建議（方案 B），但尚未由使用者正式拍板。**
   這件事沒決定之前，不要開始寫 Liquid Glass 的程式。

### 已於 2026-09-01 解決（原第 2～4 條）

- README §2 的 Dark 欄與 `implementation.md` 第 1 節註解的 v1 舊色碼**已同步為 v2**。
- Dark 的對比值**已對 v2 的 `surface/card` `#1E1917` 全部重算**（不再是沿用 v1 底色的舊數字）。
  重算前先驗證慣例：用同一支公式重現 README 既有的 8 個數字，全部吻合到小數點第二位。
- `border/hairline` 的 Dark 值已從 v1 色碼 `#332924` 改為白 9%，與 `MMCard` 實碼一致。
