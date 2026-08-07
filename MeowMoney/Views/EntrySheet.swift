import SwiftUI
import SwiftData
import UIKit

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

    @State private var recognizer = SpeechRecognizer()
    @State private var stage: Stage = .listening
    @State private var draft = EntryDraft()
    @State private var typedText: String = ""
    @State private var detent: PresentationDetent = .medium
    @FocusState private var amountFocused: Bool

    var body: some View {
        ZStack {
            Cute.background.ignoresSafeArea()

            switch stage {
            case .listening: listeningView
            case .editing: editingView
            case .saved: savedView
            }
        }
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(32)
        .onAppear(perform: setUp)
        .onDisappear { recognizer.cancel() }
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
        withAnimation(Cute.bouncy) {
            stage = .editing
            detent = .large
        }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    // MARK: - 聆聽中

    private var listeningView: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 8)

            CatFaceView(
                mood: recognizer.state.isListening ? .listening : .confused,
                size: 110,
                level: recognizer.level
            )

            SoundWaveView(level: recognizer.level, isActive: recognizer.state.isListening)

            Text(promptText)
                .font(Cute.font(19, .semibold))
                .foregroundStyle(recognizer.transcript.isEmpty ? Cute.cocoaSoft : Cute.cocoa)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
                .frame(minHeight: 56)
                .animation(.easeOut(duration: 0.15), value: recognizer.transcript)

            if case .denied(let message) = recognizer.state {
                Text(message)
                    .font(Cute.captionFont)
                    .foregroundStyle(Cute.peachDeep)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
            }
            if case .failed(let message) = recognizer.state {
                Text(message)
                    .font(Cute.captionFont)
                    .foregroundStyle(Cute.peachDeep)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
            }

            HStack(spacing: 14) {
                Button {
                    recognizer.cancel()
                    dismiss()
                } label: {
                    Text("取消")
                        .font(Cute.font(16, .semibold))
                        .foregroundStyle(Cute.cocoaSoft)
                        .frame(width: 92, height: 50)
                        .background(Capsule().fill(Cute.card))
                }
                .squishy()

                Button {
                    recognizer.stop()
                } label: {
                    Text(recognizer.state.isListening ? "說完了" : "重新聆聽")
                        .font(Cute.font(17, .bold))
                        .foregroundStyle(.white)
                        .frame(width: 150, height: 50)
                        .background(Capsule().fill(Cute.peach))
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
        case .idle: return "點「重新聆聽」再說一次"
        }
    }

    private var typingFallback: some View {
        HStack(spacing: 10) {
            TextField("或直接打字，例如：計程車 250", text: $typedText)
                .font(Cute.bodyFont)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Capsule().fill(Cute.card))
                .submitLabel(.done)
                .onSubmit(submitTypedText)

            Button(action: submitTypedText) {
                Image(systemName: "arrow.right")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(typedText.isEmpty ? Cute.cocoaSoft : Cute.mint))
            }
            .squishy()
            .disabled(typedText.isEmpty)
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
                                .font(Cute.captionFont)
                                .lineLimit(2)
                        }
                        .foregroundStyle(Cute.cocoaSoft)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Cute.card.opacity(0.8)))
                    }

                    typeToggle
                    amountField
                    categoryPicker

                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(text: "備註")
                        TextField("例如：跟同事吃飯", text: $draft.note)
                            .font(Cute.bodyFont)
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Cute.card))
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(text: "日期")
                        DatePicker("", selection: $draft.date, displayedComponents: [.date, .hourAndMinute])
                            .labelsHidden()
                            .datePickerStyle(.compact)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Cute.card))
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 18)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)

            saveBar
        }
    }

    private var typeToggle: some View {
        HStack(spacing: 0) {
            ForEach([false, true], id: \.self) { income in
                Button {
                    withAnimation(Cute.softPop) {
                        draft.isIncome = income
                        draft.category = income ? .income : (draft.category == .income ? .food : draft.category)
                    }
                } label: {
                    Text(income ? "收入" : "支出")
                        .font(Cute.font(16, .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .foregroundStyle(draft.isIncome == income ? .white : Cute.cocoaSoft)
                        .background(
                            Capsule().fill(
                                draft.isIncome == income
                                ? (income ? Cute.mint : Cute.peach)
                                : Color.clear
                            )
                        )
                }
                .squishy()
            }
        }
        .padding(5)
        .background(Capsule().fill(Cute.card))
    }

    private var amountField: some View {
        VStack(spacing: 6) {
            Text(draft.isIncome ? "收入金額" : "花了多少")
                .font(Cute.captionFont)
                .foregroundStyle(Cute.cocoaSoft)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("$")
                    .font(Cute.font(26, .bold))
                    .foregroundStyle(Cute.cocoaSoft)
                TextField("0", text: $draft.amountText)
                    .font(Cute.font(44, .heavy))
                    .foregroundStyle(draft.isIncome ? Cute.mint : Cute.cocoa)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: true, vertical: false)
                    .focused($amountFocused)
            }
        }
        .frame(maxWidth: .infinity)
        .cuteCard(padding: 22)
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
                        withAnimation(Cute.softPop) { draft.category = category }
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
                    .font(Cute.font(16, .semibold))
                    .foregroundStyle(Cute.cocoaSoft)
                    .frame(width: 88, height: 52)
                    .background(Capsule().fill(Cute.card))
            }
            .squishy()

            Button(action: save) {
                Text("存進帳本")
                    .font(Cute.font(18, .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Capsule().fill(draft.amount == nil ? Cute.cocoaSoft : Cute.peach))
            }
            .squishy()
            .disabled(draft.amount == nil)
        }
        .padding(.horizontal, 22)
        .padding(.top, 10)
        .padding(.bottom, 14)
        .background(.ultraThinMaterial)
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
        withAnimation(Cute.bouncy) {
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
                .font(Cute.font(24, .bold))
                .foregroundStyle(Cute.cocoa)
            Text("\(draft.isIncome ? "收入" : "支出") $\(draft.amountText)")
                .font(Cute.font(17, .semibold))
                .foregroundStyle(draft.isIncome ? Cute.mint : Cute.peachDeep)
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
