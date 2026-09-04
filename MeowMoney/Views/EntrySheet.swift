import SwiftUI
import SwiftData
import UIKit
import Speech
import AVFoundation

/// 可編輯的一筆帳（尚未寫入資料庫）。
struct EntryDraft {
    var amountText: String = ""
    var category: ExpenseCategory = .food
    var note: String = ""
    var date: Date = Date()
    var isIncome: Bool = false
    var transcript: String = ""

    var amount: Decimal? {
        let cleaned = amountText.replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty, let value = Decimal(string: cleaned), value > 0 else { return nil }
        return value
    }

    init() {}

    init(parsed: ParsedEntry) {
        amountText = parsed.amount.map { Money.string($0) } ?? ""
        category = parsed.category
        note = parsed.note
        date = parsed.date
        isIncome = parsed.isIncome
        transcript = parsed.transcript
    }
}

/// 語音／手動新增一筆帳。語音辨識完成後會停在確認畫面，讓使用者改完再存。
struct EntrySheet: View {
    enum Mode { case voice, manual }
    private enum Stage { case listening, editing, saved }

    let mode: Mode

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase

    @State private var recognizer = SpeechRecognizer()
    @State private var stage: Stage = .listening
    @State private var draft = EntryDraft()
    @State private var typedText: String = ""
    @State private var detent: PresentationDetent = .medium
    @State private var showDatePicker = false
    @FocusState private var amountFocused: Bool

    var body: some View {
        ZStack {
            MM.bgBase.ignoresSafeArea()

            switch stage {
            case .listening: listeningView
            case .editing: editingView
            case .saved: savedView
            }
        }
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(MM.R.xl)
        .onAppear(perform: setUp)
        .onDisappear { recognizer.cancel() }
        .onChange(of: scenePhase) { _, newPhase in
            // 聆聽中被切到背景（切別的 App／接電話）：不能假裝還在錄音，先取消收工，
            // 回前景後畫面停在 .listening 但顯示「已暫停」文案（見 promptText）。
            guard newPhase == .background, stage == .listening, recognizer.state.isListening else { return }
            recognizer.cancel()
        }
    }

    // MARK: - 啟動

    private func setUp() {
        switch mode {
        case .manual:
            stage = .editing
            detent = .large
        case .voice:
            stage = .listening
            detent = .medium
            recognizer.onFinish = { text in
                accept(text: text)
            }
            Task { await recognizer.start() }
        }
    }

    private func accept(text: String) {
        let parsed = ExpenseParser.parse(text)
        draft = EntryDraft(parsed: parsed)
        withAnimation(MM.bouncy) {
            stage = .editing
            detent = .large
        }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    // MARK: - 權限

    /// 系統已經不會再跳權限視窗（使用者拒絕過，且不是「尚未詢問」狀態）。
    /// 只讀系統權限狀態，不做任何解析/計算——不是商業邏輯，等同讀
    /// `\.accessibilityReduceMotion` 這類環境值。
    private var isPermissionPermanentlyDenied: Bool {
        SFSpeechRecognizer.authorizationStatus() == .denied
            || AVAudioApplication.shared.recordPermission == .denied
    }

    // MARK: - 聆聽中

    private var listeningView: some View {
        // 用 ScrollView 包住：Dynamic Type 拉到最大時，貓臉＋提示文字＋按鈕＋打字輸入
        // 疊在一起會超過 .medium detent 的高度，沒有 ScrollView 會被硬擠壓到文字被截斷。
        ScrollView {
            listeningContent
                .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
    }

    private var listeningContent: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 8)

            CatFaceView(
                mood: recognizer.state.isListening ? .listening : .confused,
                size: 110,
                level: recognizer.level
            )

            SoundWaveView(level: recognizer.level, isActive: recognizer.state.isListening)

            Text(promptText)
                .font(MM.font(19, .semibold, relativeTo: .title3))
                .foregroundStyle(recognizer.transcript.isEmpty ? MM.textSecondary : MM.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
                .frame(minHeight: 56)
                .animation(.easeOut(duration: 0.15), value: recognizer.transcript)

            if case .denied(let message) = recognizer.state {
                Text(isPermissionPermanentlyDenied ? "請至設定 App 開啟麥克風權限" : message)
                    .font(MM.font(13, .medium, relativeTo: .footnote))
                    .foregroundStyle(MM.warning)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)

                if isPermissionPermanentlyDenied {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Text("前往設定")
                            .font(MM.font(15, .bold, relativeTo: .subheadline))
                            .foregroundStyle(MM.textOnBrand)
                            .padding(.horizontal, 22)
                            .frame(minHeight: 44)
                            .background(Capsule().fill(MM.brandStrong))
                    }
                    .squishy()
                    .accessibilityLabel("前往設定")
                    .accessibilityHint("到系統設定開啟喵嗚記帳的麥克風與語音辨識權限")
                }
            }
            if case .failed(let message) = recognizer.state {
                Text(message)
                    .font(MM.font(13, .medium, relativeTo: .footnote))
                    .foregroundStyle(MM.warning)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
            }

            HStack(spacing: 14) {
                Button {
                    recognizer.cancel()
                    dismiss()
                } label: {
                    Text("取消")
                        .font(MM.font(16, .semibold, relativeTo: .callout))
                        .foregroundStyle(MM.textSecondary)
                        .padding(.horizontal, 20)
                        .frame(minWidth: 92, minHeight: 50)
                        .background(Capsule().fill(MM.surfaceCard))
                }
                .squishy()

                Button {
                    recognizer.stop()
                } label: {
                    Text(recognizer.state.isListening ? "說完了" : "重新聆聽")
                        .font(MM.font(17, .bold, relativeTo: .headline))
                        // 原本用白字配淺蜜桃只有 1.99:1，跟 mic 按鈕同一個 bug，一併修正。
                        .foregroundStyle(MM.textOnBrand)
                        .padding(.horizontal, 20)
                        .frame(minWidth: 150, minHeight: 50)
                        .background(Capsule().fill(MM.brandStrong))
                }
                .squishy()
                .disabled(recognizer.state == .preparing)
            }

            typingFallback

            Spacer(minLength: 8)
        }
        .padding(.vertical, 12)
    }

    private var promptText: String {
        if !recognizer.transcript.isEmpty { return recognizer.transcript }
        switch recognizer.state {
        case .preparing: return "準備中…"
        case .listening: return "說說看：「午餐便當一百二」"
        case .denied: return "沒有權限，可以先用打字的"
        case .failed: return "聽不到聲音，可以先用打字的"
        case .idle: return "已暫停，點「重新聆聽」繼續"
        }
    }

    private var typingFallback: some View {
        HStack(spacing: 10) {
            TextField("或直接打字，例如：計程車 250", text: $typedText)
                .font(MM.font(16, .medium, relativeTo: .body))
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                // 標準字級下含 padding 只有 43pt，差一點點就不足 44——
                // 一併修掉（驗收退回 BUG-1 要求整個 App 掃過一輪）。
                .frame(minHeight: 44)
                .background(Capsule().fill(MM.surfaceCard))
                .submitLabel(.done)
                .onSubmit(submitTypedText)

            Button(action: submitTypedText) {
                Image(systemName: "arrow.right")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(MM.textOnBrand)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(typedText.isEmpty ? MM.textSecondary : MM.brandStrong))
            }
            .squishy()
            .disabled(typedText.isEmpty)
            .accessibilityLabel("送出打字內容")
        }
        .padding(.horizontal, 24)
    }

    private func submitTypedText() {
        let text = typedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        recognizer.cancel()
        typedText = ""
        accept(text: text)
    }

    // MARK: - 確認與編輯

    private var editingView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 20) {
                    if !draft.transcript.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "quote.opening")
                                .font(.system(size: 11))
                            Text(draft.transcript)
                                .font(MM.font(13, .medium, relativeTo: .footnote))
                                .lineLimit(2)
                        }
                        .foregroundStyle(MM.textSecondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(MM.surfaceCard.opacity(0.8)))
                    }

                    typeToggle
                    amountField
                    categoryPicker

                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(text: "備註")
                        TextField("例如：跟同事吃飯", text: $draft.note)
                            .font(MM.font(16, .medium, relativeTo: .body))
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: MM.R.md, style: .continuous).fill(MM.surfaceCard))
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(text: "日期")
                        dateField
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 18)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)

            saveBar
        }
        .sheet(isPresented: $showDatePicker) {
            datePickerSheet
        }
    }

    // 系統 compact DatePicker 本身的可點按鈕實測只有約 36pt 高，且是原生控件——
    // `.frame(minHeight:)`／`.controlSize(.large)` 都只會撐大外層版位或完全沒效果，
    // 不會撐大它真正的命中範圍（模擬器實機點擊驗證過：外層多出來的空間點下去沒反應，
    // `.controlSize(.large)` 對這顆 compact picker 也量不出尺寸變化）。改成自訂
    // Button 開全螢幕的日期時間 sheet，觸控區完全由我們自己定義，保證 ≥44pt
    // （驗收退回 BUG-1）。
    private var dateField: some View {
        Button {
            showDatePicker = true
        } label: {
            HStack(spacing: 8) {
                Text(draft.date.formatted(.dateTime.year().month().day().locale(Locale(identifier: "zh_TW"))))
                Text(draft.date.formatted(.dateTime.hour().minute().locale(Locale(identifier: "zh_TW"))))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MM.textTertiary)
            }
            .font(MM.font(16, .medium, relativeTo: .body))
            .foregroundStyle(MM.textPrimary)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: MM.R.md, style: .continuous).fill(MM.surfaceCard))
        }
        .squishy()
        .accessibilityLabel("日期與時間，\(draft.date.formatted(.dateTime.month().day().hour().minute()))")
        .accessibilityHint("點兩下修改日期與時間")
    }

    // `.graphical` 樣式在有 `.hourAndMinute` 時，時間列會被畫在月曆格線下方，
    // 整體高度超過 `.medium` detent、且內容不可捲動——時間永遠看不到也點不到
    // （獨立驗收實測：連續 swipe 前後截圖完全相同，時間根本無法修改）。
    // 改用 `.wheel`：日期與時間三顆滾輪一次展開、無隱藏內容、不需捲動，
    // 滾輪本身是系統控件，命中範圍遠大於 44pt，不會重蹈原生 compact picker 的
    // 觸控目標問題（那次的問題是「小按鈕」，這裡是「大滾輪」，本質不同）。
    private var datePickerSheet: some View {
        NavigationStack {
            DatePicker(
                "日期與時間",
                selection: $draft.date,
                displayedComponents: [.date, .hourAndMinute]
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
            .tint(MM.brandStrong)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 8)
            .navigationTitle("日期與時間")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { showDatePicker = false }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private var typeToggle: some View {
        HStack(spacing: 0) {
            ForEach([false, true], id: \.self) { incomeOption in
                Button {
                    withAnimation(MM.softPop) {
                        draft.isIncome = incomeOption
                        draft.category = incomeOption ? .income : (draft.category == .income ? .food : draft.category)
                    }
                } label: {
                    Text(incomeOption ? "收入" : "支出")
                        .font(MM.font(16, .bold, relativeTo: .callout))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .foregroundStyle(draft.isIncome == incomeOption ? MM.textOnBrand : MM.textSecondary)
                        .background(
                            Capsule().fill(
                                draft.isIncome == incomeOption
                                ? (incomeOption ? MM.income : MM.brandStrong)
                                : Color.clear
                            )
                        )
                }
                // 視覺膠囊維持原本 vertical padding 11 的高度，觸控區用透明 frame
                // 擴到 44pt（驗收退回 BUG-1，同 CategoryChip 的做法）。
                .frame(minHeight: 44)
                .contentShape(Rectangle())
                .squishy()
                .accessibilityAddTraits(draft.isIncome == incomeOption ? [.isSelected] : [])
            }
        }
        .padding(5)
        .background(Capsule().fill(MM.surfaceCard))
    }

    private var amountField: some View {
        VStack(spacing: 6) {
            Text(draft.isIncome ? "收入金額" : "花了多少")
                .font(MM.font(12, .medium, relativeTo: .caption))
                .tracking(1.2) // +10%
                .foregroundStyle(MM.textTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("$")
                    .font(MM.font(26, .bold, relativeTo: .title2))
                    .foregroundStyle(MM.textSecondary)
                // `.fixedSize(horizontal: true)` 曾經讓這顆 TextField 永遠用它「想要」的
                // 寬度渲染，金額一長就把整張 sheet 往外撐寬，「分類／備註／日期」的標籤
                // 被推出左邊界（驗收退回 BUG-4）。拿掉 fixedSize 讓它服從父層給的寬度，
                // 加 minimumScaleFactor 讓長數字用縮小字級表示而不是撐版；
                // amountText 另外設輸入長度上限（12 位數，含千萬級以上台幣金額仍綽綽有餘），
                // 兩者一起防線，單靠縮放字級在極端輸入下仍可能小到看不清。
                TextField("0", text: $draft.amountText)
                    .font(MM.font(44, .heavy, relativeTo: .largeTitle))
                    .foregroundStyle(draft.isIncome ? MM.income : MM.textPrimary)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .focused($amountFocused)
                    .onChange(of: draft.amountText) { _, newValue in
                        if newValue.count > 12 {
                            draft.amountText = String(newValue.prefix(12))
                        }
                    }
            }
        }
        .frame(maxWidth: .infinity)
        .mmCard(padding: 22)
    }

    private var categoryPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(text: "分類")
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 92), spacing: 10)],
                alignment: .leading,
                spacing: 10
            ) {
                ForEach(draft.isIncome ? [ExpenseCategory.income] : ExpenseCategory.expenseCases) { category in
                    CategoryChip(category: category, isSelected: draft.category == category) {
                        withAnimation(MM.softPop) { draft.category = category }
                    }
                }
            }
        }
    }

    private var saveBar: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Text("取消")
                    .font(MM.font(16, .semibold, relativeTo: .callout))
                    .foregroundStyle(MM.textSecondary)
                    .padding(.horizontal, 16)
                    .frame(minWidth: 88, minHeight: 52)
                    .background(Capsule().fill(MM.surfaceCard))
            }
            .squishy()

            Button(action: save) {
                Text("存進帳本")
                    .font(MM.font(18, .bold, relativeTo: .title3))
                    .foregroundStyle(MM.textOnBrand)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Capsule().fill(draft.amount == nil ? MM.textSecondary : MM.brandStrong))
            }
            .squishy()
            .disabled(draft.amount == nil)
        }
        .padding(.horizontal, 22)
        .padding(.top, 10)
        .padding(.bottom, 14)
        // Liquid Glass 雙軌（Glass實作規格.md §3.2）：Rectangle 而非帶圓角形狀——
        // saveBar 貼齊 sheet 左右與底部安全區，圓角由 sheet 本身的 presentationCornerRadius 負責。
        .background {
            if #available(iOS 26, *) {
                // 同 RootTabView 的修正：Rectangle() 需要透明填色，
                // 否則預設前景色會蓋住玻璃效果（見 Glass實作規格.md 修正記錄）。
                Rectangle().fill(.clear).glassEffect(.regular, in: .rect)
            } else {
                Rectangle().fill(.ultraThinMaterial)
            }
        }
    }

    private func save() {
        guard let amount = draft.amount else { return }
        let expense = Expense(
            amount: amount,
            category: draft.isIncome ? .income : draft.category,
            note: draft.note,
            date: draft.date,
            isIncome: draft.isIncome,
            transcript: draft.transcript
        )
        context.insert(expense)
        try? context.save()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(MM.bouncy) {
            stage = .saved
            detent = .medium
        }
        Task {
            try? await Task.sleep(nanoseconds: 900_000_000)
            dismiss()
        }
    }

    // MARK: - 存檔完成

    private var savedView: some View {
        VStack(spacing: 16) {
            CatFaceView(mood: .happy, size: 130)
            Text("記好了！")
                .font(MM.font(24, .bold, relativeTo: .title2))
                .foregroundStyle(MM.textPrimary)
            Text("\(draft.isIncome ? "收入" : "支出") $\(draft.amountText)")
                .font(MM.font(17, .semibold, relativeTo: .headline))
                .monospacedDigit()
                .foregroundStyle(draft.isIncome ? MM.income : MM.expense)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    Color.gray
        .sheet(isPresented: .constant(true)) {
            EntrySheet(mode: .manual)
        }
        .modelContainer(PreviewData.container)
}
