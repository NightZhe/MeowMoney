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

    /// 「手動修正」用既有值初始化，不是 parse 結果（階段2-3規格 §1.4）。
    init(expense: Expense) {
        amountText = Money.string(expense.amount)
        category = expense.category
        note = expense.note
        date = expense.date
        isIncome = expense.isIncome
        transcript = expense.transcript
    }
}

/// 語音／手動新增一筆帳。語音辨識完成後會停在確認畫面，讓使用者改完再存。
struct EntrySheet: View {
    /// `.edit`：「手動修正」（01）與「一句話記多筆」卡片內編輯（07，本階段不做）共用同一個
    /// 表單機制——跳過聆聽，直接用既有 `Expense` 的值進editing，存檔時寫回而不新建
    /// （階段2-3規格 §1.4／§5 第 4 項）。
    enum Mode { case voice, manual, edit(Expense) }
    private enum Stage { case listening, editing, saved }

    let mode: Mode

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var recognizer = SpeechRecognizer()
    @State private var stage: Stage = .listening
    @State private var draft = EntryDraft()
    @State private var typedText: String = ""
    @State private var detent: PresentationDetent = .medium
    @State private var showDatePicker = false
    @FocusState private var amountFocused: Bool
    /// ③ 完全聽不懂：解析不出金額時，在 editingView 頂部提示「用鍵盤補上」。
    /// 只在語音／打字辨識結果本身沒有金額時觸發（`.manual`／`.edit` 都不該顯示這個）；
    /// 一旦使用者開始輸入金額（哪怕金額還無效）就收掉，不用等到金額有效才消失
    /// （階段2-3規格 §2.3）。
    @State private var showAmountHint = false
    /// ④ 環境太吵／靜音太久：目前架構下跟「App 被切到背景暫停」共用同一個
    /// `SpeechRecognizer.State.idle`，沒有專屬狀態可以分辨（見規格 §2.4 對 Services 的
    /// 需求，本階段小a 範圍不含 Services/，這裡先用「是不是背景中斷造成的」這個
    /// View 層才知道的訊號，在 promptText 分岔文案；小b 若之後補上專屬 `.timeout` state，
    /// 這裡可以直接改吃那個訊號，不用動 UI 結構）。
    @State private var wasInterruptedByBackground = false

    // MARK: - 07 一句話多筆

    /// 非 nil＝確認卡清單模式；nil＝現有單筆表單（階段2-3規格 §3.3）。
    @State private var multiDrafts: [EntryDraft]? = nil
    /// 使用者送出的整句原話，給確認卡上方的引用 chip 用（跟切出來的片段 transcript 不同）。
    @State private var multiEntryRawText: String = ""
    /// 非 nil＝正在編輯 `multiDrafts[index]`，重用單筆表單，`stage` 本身不變。
    @State private var editingCardIndex: Int? = nil
    /// 批次存檔完成後，`savedView` 要顯示「共 N 筆」；nil 代表這次是單筆存檔。
    @State private var savedMultiCount: Int? = nil

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
            wasInterruptedByBackground = true
            recognizer.cancel()
        }
    }

    // MARK: - 啟動

    private func setUp() {
        switch mode {
        case .manual:
            stage = .editing
            detent = .large
        case .edit(let expense):
            draft = EntryDraft(expense: expense)
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

    /// 07：改叫 `parseMultiple`，依片數分三支（階段2-3規格 §3.1）。
    private func accept(text: String) {
        let results = ExpenseParser.parseMultiple(text)
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()

        switch results.count {
        case 0:
            // 完全解析不出東西：沿用③的呈現，空殼 draft 走進現有單筆表單，不新增畫面
            // （規格 §3.1 分支 1）。
            var empty = EntryDraft()
            empty.category = .other
            empty.transcript = text
            draft = empty
            multiDrafts = nil
            showAmountHint = true
            withAnimation(MM.bouncy) {
                stage = .editing
                detent = .large
            }
            amountFocused = true

        case 1:
            // 只解析出一筆：退回單筆流程，跟今天的體驗完全一樣（附錄定案，規格 §3.2 選 A）。
            let parsed = results[0]
            draft = EntryDraft(parsed: parsed)
            multiDrafts = nil
            showAmountHint = parsed.amount == nil
            withAnimation(MM.bouncy) {
                stage = .editing
                detent = .large
            }
            if showAmountHint {
                amountFocused = true
            }

        default:
            // 07：一句話多筆，新增確認卡清單（規格 §3.3）。
            multiEntryRawText = text
            multiDrafts = results.map { EntryDraft(parsed: $0) }
            editingCardIndex = nil
            showAmountHint = false
            withAnimation(MM.bouncy) {
                stage = .editing
                detent = .large
            }
        }
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
        case .idle:
            // ④ 環境太吵／靜音太久 vs 被切到背景暫停：兩種情境目前在 Service 層是
            // 同一個 `.idle`，靠這裡的訊號分岔文案（見 `wasInterruptedByBackground` 註記）。
            return wasInterruptedByBackground
                ? "已暫停，點「重新聆聽」繼續"
                : "沒聽到聲音，可以再說一次"
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

    /// 三種內容互斥切換，`stage` 本身維持 `.editing`，不新增 `Stage` case
    /// （規格 §3.3）：確認卡清單／卡片內編輯（重用單筆表單）／一般單筆表單。
    private var editingView: some View {
        Group {
            if let drafts = multiDrafts, editingCardIndex == nil {
                multiEntryConfirmView(drafts)
            } else {
                singleEntryForm
            }
        }
        .sheet(isPresented: $showDatePicker) {
            datePickerSheet
        }
    }

    private var singleEntryForm: some View {
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

                    if showAmountHint {
                        Text("沒聽清楚金額，用鍵盤補上就好")
                            .font(MM.font(13, .medium, relativeTo: .footnote))
                            .foregroundStyle(MM.warning)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .accessibilityLabel("沒聽清楚金額，用鍵盤補上就好")
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

            entrySaveBar
        }
    }

    // MARK: - 07 一句話多筆：確認卡清單

    private func multiEntryConfirmView(_ drafts: [EntryDraft]) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                if drafts.isEmpty {
                    multiEntryEmptyState
                        .padding(.top, 40)
                } else {
                    VStack(spacing: 20) {
                        SectionHeader(text: "確認這 \(drafts.count) 筆")

                        if !multiEntryRawText.isEmpty {
                            HStack(spacing: 8) {
                                Image(systemName: "quote.opening")
                                    .font(.system(size: 11))
                                Text(multiEntryRawText)
                                    .font(MM.font(13, .medium, relativeTo: .footnote))
                                    .lineLimit(2)
                            }
                            .foregroundStyle(MM.textSecondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(MM.surfaceCard.opacity(0.8)))
                        }

                        LazyVStack(spacing: 12) {
                            ForEach(Array(drafts.enumerated()), id: \.offset) { index, entryDraft in
                                multiEntryCard(entryDraft, index: index)
                            }
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 18)
                    .padding(.bottom, 24)
                }
            }
            .scrollDismissesKeyboard(.interactively)

            if !drafts.isEmpty {
                multiSaveBar(drafts)
            }
        }
    }

    private func multiEntryCard(_ entryDraft: EntryDraft, index: Int) -> some View {
        let hasAmount = entryDraft.amount != nil
        return HStack(spacing: 14) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: MM.R.chip, style: .continuous)
                        .fill(entryDraft.category.color.opacity(0.14))
                        .frame(width: 46, height: 46)
                    Text(entryDraft.category.emoji)
                        .font(.system(size: 22))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(entryDraft.category.title)
                        .font(MM.font(16, .semibold, relativeTo: .callout))
                        .foregroundStyle(MM.textPrimary)
                        .lineLimit(1)
                    if !entryDraft.note.isEmpty {
                        Text(entryDraft.note)
                            .font(MM.font(13, .medium, relativeTo: .footnote))
                            .foregroundStyle(MM.textTertiary)
                            .lineLimit(1)
                    }
                }
                .frame(minWidth: 60, alignment: .leading)

                Spacer(minLength: 8)

                Group {
                    if let amount = entryDraft.amount {
                        Text(Money.signed(amount, isIncome: entryDraft.isIncome))
                            .font(MM.font(22, .bold, relativeTo: .body))
                            .monospacedDigit()
                            .foregroundStyle(entryDraft.isIncome ? MM.income : MM.expense)
                    } else {
                        Text("未填金額")
                            .font(MM.font(13, .medium, relativeTo: .footnote))
                            .foregroundStyle(MM.warning)
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.4)
            }
            .contentShape(Rectangle())
            .onTapGesture { beginEditingCard(index) }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("\(entryDraft.category.title)，\(amountAccessibilityLabel(entryDraft))")
            .accessibilityHint("點兩下編輯這筆")

            deleteButton(index: index, entryDraft: entryDraft)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .mmRow(padding: 0, cornerRadius: MM.R.md)
        .overlay {
            if !hasAmount {
                RoundedRectangle(cornerRadius: MM.R.md, style: .continuous)
                    .stroke(MM.warning, lineWidth: 1.5)
            }
        }
    }

    /// 視覺 20pt 的 `xmark.circle.fill`，觸控區用透明 frame 撐到 44pt（規格 §3.3／§7）。
    private func deleteButton(index: Int, entryDraft: EntryDraft) -> some View {
        Button {
            let animation: Animation? = reduceMotion ? nil : MM.bouncy
            withAnimation(animation) {
                _ = multiDrafts?.remove(at: index)
            }
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(MM.textTertiary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("刪除這筆：\(entryDraft.category.title)，\(amountAccessibilityLabel(entryDraft))")
    }

    private func amountAccessibilityLabel(_ entryDraft: EntryDraft) -> String {
        entryDraft.amount.map { Money.signed($0, isIncome: entryDraft.isIncome) + " 元" } ?? "未填金額"
    }

    /// 全部卡片刪光：卡片清單區改顯示空狀態＋兩個動作，不留下不能動作的空白區塊
    /// （規格 §3.3「Empty」）。
    private var multiEntryEmptyState: some View {
        VStack(spacing: 20) {
            CuteEmptyState(mood: .confused, title: "都刪光了", subtitle: "要不要重新說一次？")

            HStack(spacing: 12) {
                Button {
                    dismiss()
                } label: {
                    Text("取消")
                        .font(MM.font(16, .semibold, relativeTo: .callout))
                        .foregroundStyle(MM.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Capsule().fill(MM.surfaceCard))
                }
                .squishy()

                Button(action: restartListening) {
                    Text("重新輸入")
                        .font(MM.font(16, .bold, relativeTo: .headline))
                        .foregroundStyle(MM.textOnBrand)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Capsule().fill(MM.brandStrong))
                }
                .squishy()
            }
        }
        .padding(.horizontal, 22)
    }

    private func multiSaveBar(_ drafts: [EntryDraft]) -> some View {
        let total = drafts.reduce(Decimal(0)) { $0 + ($1.amount ?? 0) }
        let disabled = drafts.isEmpty || drafts.contains { $0.amount == nil }
        return HStack(spacing: 12) {
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

            Button(action: saveAllMultiDrafts) {
                Text("全部存入帳本・共 \(drafts.count) 筆・$\(Money.string(total))")
                    .font(MM.font(16, .bold, relativeTo: .callout))
                    .multilineTextAlignment(.center)
                    // AX 級距下單行放不下整句，寧可換到 2 行也不截斷文字
                    // （驗收要求「文字不截斷」）；minHeight 52 只是下限，Capsule 隨內容長高。
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(MM.textOnBrand)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Capsule().fill(disabled ? MM.textSecondary : MM.brandStrong))
            }
            .squishy()
            .disabled(disabled)
        }
        .padding(.horizontal, 22)
        .padding(.top, 10)
        .padding(.bottom, 14)
        .background {
            if #available(iOS 26, *) {
                Rectangle().fill(.clear).glassEffect(.regular, in: .rect)
            } else {
                Rectangle().fill(.ultraThinMaterial)
            }
        }
    }

    private func beginEditingCard(_ index: Int) {
        guard let drafts = multiDrafts, drafts.indices.contains(index) else { return }
        draft = drafts[index]
        showAmountHint = false
        editingCardIndex = index
    }

    private func saveAllMultiDrafts() {
        guard let drafts = multiDrafts, !drafts.isEmpty,
              !drafts.contains(where: { $0.amount == nil }) else { return }
        for entryDraft in drafts {
            guard let amount = entryDraft.amount else { continue }
            let expense = Expense(
                amount: amount,
                category: entryDraft.isIncome ? .income : entryDraft.category,
                note: entryDraft.note,
                date: entryDraft.date,
                isIncome: entryDraft.isIncome,
                transcript: entryDraft.transcript
            )
            context.insert(expense)
        }
        try? context.save()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        savedMultiCount = drafts.count
        withAnimation(MM.bouncy) {
            stage = .saved
            detent = .medium
        }
        Task {
            try? await Task.sleep(nanoseconds: 900_000_000)
            dismiss()
        }
    }

    /// 「重新輸入」：回語音輸入，比照 `setUp()` 的 `.voice` 分支重啟聆聽
    /// （規格 §3.3 Empty）。
    private func restartListening() {
        multiDrafts = nil
        multiEntryRawText = ""
        withAnimation(MM.bouncy) {
            stage = .listening
            detent = .medium
        }
        Task { await recognizer.start() }
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
                        // 一旦開始輸入就收掉提示，不用等到金額有效才消失（規格 §2.3）。
                        if showAmountHint, !newValue.isEmpty {
                            showAmountHint = false
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

    /// 一般單筆存檔／「手動修正」更新／07 卡片內編輯完成，三種情境共用同一顆存檔列，
    /// 靠 `editingCardIndex` 分岔文案與行為（規格 §3.3：卡片內編輯的「取消」不是
    /// `dismiss()`，是回卡片清單捨棄變更）。
    private var entrySaveBar: some View {
        HStack(spacing: 12) {
            Button {
                if editingCardIndex != nil {
                    editingCardIndex = nil
                } else {
                    dismiss()
                }
            } label: {
                Text("取消")
                    .font(MM.font(16, .semibold, relativeTo: .callout))
                    .foregroundStyle(MM.textSecondary)
                    .padding(.horizontal, 16)
                    .frame(minWidth: 88, minHeight: 52)
                    .background(Capsule().fill(MM.surfaceCard))
            }
            .squishy()

            Button(action: handleEntrySave) {
                Text(entrySaveTitle)
                    .font(MM.font(18, .bold, relativeTo: .title3))
                    .foregroundStyle(MM.textOnBrand)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Capsule().fill(isEntrySaveDisabled ? MM.textSecondary : MM.brandStrong))
            }
            .squishy()
            .disabled(isEntrySaveDisabled)
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

    /// 「手動修正」：`mode` 是 `.edit`。用來切 saveBar 文案，不涉及解析／計算，
    /// 純粹讀 `Mode` 這個 View 自己的列舉，不是商業邏輯。
    private var isEditingExisting: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var entrySaveTitle: String {
        if editingCardIndex != nil { return "更新" }
        return isEditingExisting ? "更新" : "存進帳本"
    }

    /// 卡片內編輯（07）允許在金額未填時也能「更新」回卡片清單——那筆卡片會顯示
    /// 「未填金額」警示，整批存檔的門檻交給 `multiSaveBar` 的 `disabled` 條件把關，
    /// 不在這裡重複擋（規格 §3.3）。
    private var isEntrySaveDisabled: Bool {
        editingCardIndex == nil && draft.amount == nil
    }

    private func handleEntrySave() {
        if let index = editingCardIndex {
            multiDrafts?[index] = draft
            editingCardIndex = nil
            return
        }
        save()
    }

    private func save() {
        guard let amount = draft.amount else { return }
        switch mode {
        case .voice, .manual:
            let expense = Expense(
                amount: amount,
                category: draft.isIncome ? .income : draft.category,
                note: draft.note,
                date: draft.date,
                isIncome: draft.isIncome,
                transcript: draft.transcript
            )
            context.insert(expense)
        case .edit(let expense):
            // 寫回既有 Expense，不新建。`transcript` 不動——原話永遠不動，
            // 手動修正跟「重新解析」共用同一條原則（階段2-3規格 §1）。
            expense.amount = amount
            expense.category = draft.isIncome ? .income : draft.category
            expense.note = draft.note
            expense.date = draft.date
            expense.isIncome = draft.isIncome
        }
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
            if let savedMultiCount {
                // 07 批次存檔：規格 §3.3「savedView 文案改『記好了！共 N 筆』」。
                Text("記好了！共 \(savedMultiCount) 筆")
                    .font(MM.font(24, .bold, relativeTo: .title2))
                    .foregroundStyle(MM.textPrimary)
            } else {
                Text("記好了！")
                    .font(MM.font(24, .bold, relativeTo: .title2))
                    .foregroundStyle(MM.textPrimary)
                Text("\(draft.isIncome ? "收入" : "支出") $\(draft.amountText)")
                    .font(MM.font(17, .semibold, relativeTo: .headline))
                    .monospacedDigit()
                    .foregroundStyle(draft.isIncome ? MM.income : MM.expense)
            }
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
