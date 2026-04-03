import SwiftUI
import NaturalLanguage
import AppKit

struct SmartCorrectionSheet: View {

    var onComplete: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    // MARK: - Phase

    private enum Phase {
        case input, generating, preview
    }

    @State private var phase: Phase = .input

    // MARK: - Input phase state

    private enum InputMode: String, CaseIterable {
        case manual, history
    }

    @State private var inputMode: InputMode = .manual
    @State private var manualText: String = ""
    @State private var historyRecords: [(id: String, date: Date, rawText: String)] = []
    @State private var selectedHistoryId: String?
    @State private var tokens: [String] = []
    @State private var selectedTokens: Set<Int> = []
    @State private var correctText: String = ""

    // MARK: - Generating phase state

    @State private var generationTask: Task<Void, Never>?
    @State private var errorMessage: String?

    // MARK: - Preview phase state

    @State private var snippetSuggestions: [VariantSuggestion] = []
    @State private var hotwordSuggestions: [HotwordSuggestion] = []
    @State private var hotwordReason: String = ""

    private let historyStore = HistoryStore()
    private let generator = ASRVariantGenerator()

    // MARK: - Computed

    private var selectedText: String {
        selectedTokens.sorted().compactMap { idx in
            idx < tokens.count ? tokens[idx] : nil
        }.joined()
    }

    private var canGenerate: Bool {
        !selectedText.isEmpty && !correctText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var selectedCount: Int {
        snippetSuggestions.filter { $0.isSelected && !$0.isDuplicate }.count
        + hotwordSuggestions.filter { $0.isSelected && !$0.isDuplicate }.count
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Title
            Text(L("智能纠正", "Smart Correction"))
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(TF.settingsText)
                .padding(.bottom, 4)

            Text(L("选择错误识别的文本，输入正确写法，AI 自动生成变体映射。",
                    "Select misrecognized text, enter the correct form, and AI generates variant mappings."))
                .font(.system(size: 11))
                .foregroundStyle(TF.settingsTextTertiary)
                .padding(.bottom, 16)

            // Main content
            switch phase {
            case .input:
                inputPhaseView
            case .generating:
                generatingPhaseView
            case .preview:
                previewPhaseView
            }

            Spacer()

            // Bottom buttons
            SettingsDivider()
            bottomButtons
                .padding(.top, 8)
        }
        .padding(20)
        .frame(minWidth: 480, maxWidth: 480, minHeight: 400)
        .onAppear {
            loadHistory()
        }
    }

    // MARK: - Input Phase

    @ViewBuilder
    private var inputPhaseView: some View {
        // Mode picker
        Picker("", selection: $inputMode) {
            Text(L("手动输入", "Manual Input")).tag(InputMode.manual)
            Text(L("从历史记录", "From History")).tag(InputMode.history)
        }
        .pickerStyle(.segmented)
        .frame(width: 240)
        .padding(.bottom, 12)

        if inputMode == .manual {
            manualInputView
        } else {
            historyInputView
        }

        // Word grid (after tokenization)
        if !tokens.isEmpty {
            SettingsDivider()
            wordGridView
                .padding(.top, 8)
        }

        // Correct form input
        if !tokens.isEmpty {
            correctFormView
                .padding(.top, 12)
        }
    }

    private var manualInputView: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(L("输入被错误识别的文本...", "Enter misrecognized text..."), text: $manualText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(TF.settingsTextTertiary.opacity(0.3), lineWidth: 1)
                )
                .onSubmit { tokenize(manualText) }

            Button {
                tokenize(manualText)
            } label: {
                HStack(spacing: 4) {
                    Text(L("分词", "Tokenize"))
                        .font(.system(size: 12))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10))
                }
                .foregroundStyle(TF.settingsAccentBlue)
            }
            .buttonStyle(.plain)
            .disabled(manualText.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private var historyInputView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if historyRecords.isEmpty {
                    Text(L("暂无历史记录", "No history records"))
                        .font(.system(size: 12))
                        .foregroundStyle(TF.settingsTextTertiary)
                        .padding(.vertical, 20)
                        .frame(maxWidth: .infinity)
                } else {
                    ForEach(historyRecords, id: \.id) { record in
                        historyRow(record)
                    }
                }
            }
        }
        .frame(maxHeight: 160)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .stroke(TF.settingsTextTertiary.opacity(0.2), lineWidth: 1)
        )
    }

    private func historyRow(_ record: (id: String, date: Date, rawText: String)) -> some View {
        Button {
            selectedHistoryId = record.id
            tokenize(record.rawText)
        } label: {
            HStack(spacing: 8) {
                Text(record.rawText)
                    .font(.system(size: 12))
                    .foregroundStyle(TF.settingsText)
                    .lineLimit(1)

                Spacer()

                Text(relativeDate(record.date))
                    .font(.system(size: 10))
                    .foregroundStyle(TF.settingsTextTertiary)

                if selectedHistoryId == record.id {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(TF.settingsAccentGreen)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            selectedHistoryId == record.id
                ? TF.settingsAccentBlue.opacity(0.08)
                : Color.clear
        )
    }

    private var wordGridView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("点击选择错误词:", "Click to select wrong words:"))
                .font(.system(size: 11))
                .foregroundStyle(TF.settingsTextTertiary)

            WrappingHStack(spacing: 6) {
                ForEach(Array(tokens.enumerated()), id: \.offset) { index, token in
                    tokenTag(token, index: index)
                }
            }

            if !selectedTokens.isEmpty {
                Text(L("选中: \(selectedText)", "Selected: \(selectedText)"))
                    .font(.system(size: 11))
                    .foregroundStyle(TF.settingsTextSecondary)
            }
        }
    }

    private func tokenTag(_ token: String, index: Int) -> some View {
        let isSelected = selectedTokens.contains(index)
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                if isSelected {
                    selectedTokens.remove(index)
                } else {
                    selectedTokens.insert(index)
                }
            }
        } label: {
            Text(token)
                .font(.system(size: 12))
                .foregroundStyle(isSelected ? .white : TF.settingsText)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? TF.settingsAccentBlue : TF.settingsBg)
                )
        }
        .buttonStyle(.plain)
    }

    private var correctFormView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("正确写法:", "Correct form:"))
                .font(.system(size: 11))
                .foregroundStyle(TF.settingsTextTertiary)

            TextField(L("输入正确的文字...", "Enter the correct text..."), text: $correctText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(TF.settingsTextTertiary.opacity(0.3), lineWidth: 1)
                )
        }
    }

    // MARK: - Generating Phase

    private var generatingPhaseView: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
                .scaleEffect(0.8)
            Text(L("正在生成变体...", "Generating variants..."))
                .font(.system(size: 13))
                .foregroundStyle(TF.settingsTextSecondary)

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(TF.settingsAccentRed)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Preview Phase

    @ViewBuilder
    private var previewPhaseView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Snippets section
                HStack {
                    Text(L("片段替换建议", "Snippet Suggestions"))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(TF.settingsText)

                    Spacer()

                    Button {
                        selectAllSnippets()
                    } label: {
                        Text(L("全选", "Select All"))
                            .font(.system(size: 11))
                            .foregroundStyle(TF.settingsAccentBlue)
                    }
                    .buttonStyle(.plain)
                }

                if snippetSuggestions.isEmpty {
                    Text(L("没有生成片段建议", "No snippet suggestions generated"))
                        .font(.system(size: 12))
                        .foregroundStyle(TF.settingsTextTertiary)
                } else {
                    ForEach(Array(snippetSuggestions.enumerated()), id: \.element.id) { index, suggestion in
                        snippetRow(index: index, suggestion: suggestion)
                    }
                }

                // Hotwords section
                if !hotwordSuggestions.isEmpty {
                    SettingsDivider()

                    Text(L("热词建议", "Hotword Suggestions"))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(TF.settingsText)

                    ForEach(Array(hotwordSuggestions.enumerated()), id: \.element.id) { index, suggestion in
                        hotwordRow(index: index, suggestion: suggestion)
                    }

                    if !hotwordReason.isEmpty {
                        Text(hotwordReason)
                            .font(.system(size: 10))
                            .foregroundStyle(TF.settingsTextTertiary)
                            .padding(.top, 2)
                    }
                }
            }
        }
    }

    private func snippetRow(index: Int, suggestion: VariantSuggestion) -> some View {
        HStack(spacing: 8) {
            Toggle("", isOn: Binding(
                get: { suggestion.isSelected },
                set: { snippetSuggestions[index].isSelected = $0 }
            ))
            .toggleStyle(.checkbox)
            .disabled(suggestion.isDuplicate)

            Text(suggestion.trigger)
                .font(.system(size: 12))
                .foregroundStyle(suggestion.isDuplicate ? TF.settingsTextTertiary : TF.settingsText)

            Image(systemName: "arrow.right")
                .font(.system(size: 9))
                .foregroundStyle(TF.settingsTextTertiary)

            Text(suggestion.replacement)
                .font(.system(size: 12))
                .foregroundStyle(suggestion.isDuplicate ? TF.settingsTextTertiary : TF.settingsTextSecondary)

            if suggestion.isDuplicate {
                Text(L("已存在", "Exists"))
                    .font(.system(size: 10))
                    .foregroundStyle(TF.settingsTextTertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4).fill(TF.settingsBg)
                    )
            }

            Spacer()
        }
        .padding(.vertical, 2)
    }

    private func hotwordRow(index: Int, suggestion: HotwordSuggestion) -> some View {
        HStack(spacing: 8) {
            Toggle("", isOn: Binding(
                get: { suggestion.isSelected },
                set: { hotwordSuggestions[index].isSelected = $0 }
            ))
            .toggleStyle(.checkbox)
            .disabled(suggestion.isDuplicate)

            Text(suggestion.word)
                .font(.system(size: 12))
                .foregroundStyle(suggestion.isDuplicate ? TF.settingsTextTertiary : TF.settingsText)

            if suggestion.isDuplicate {
                Text(L("已存在", "Exists"))
                    .font(.system(size: 10))
                    .foregroundStyle(TF.settingsTextTertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4).fill(TF.settingsBg)
                    )
            }

            Spacer()
        }
        .padding(.vertical, 2)
    }

    // MARK: - Bottom Buttons

    @ViewBuilder
    private var bottomButtons: some View {
        HStack {
            switch phase {
            case .input:
                Button(L("取消", "Cancel")) { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(TF.settingsTextTertiary)

                Spacer()

                Button {
                    startGeneration()
                } label: {
                    HStack(spacing: 4) {
                        Text("✨")
                        Text(L("生成变体", "Generate Variants"))
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(canGenerate ? TF.settingsAccentBlue : TF.settingsTextTertiary.opacity(0.3))
                    )
                }
                .buttonStyle(.plain)
                .disabled(!canGenerate)

            case .generating:
                Button(L("取消", "Cancel")) {
                    generationTask?.cancel()
                    withAnimation(.easeInOut(duration: 0.15)) {
                        phase = .input
                    }
                    errorMessage = nil
                }
                .buttonStyle(.plain)
                .foregroundStyle(TF.settingsTextTertiary)

                Spacer()

            case .preview:
                Button(L("返回修改", "Back to Edit")) {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        phase = .input
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(TF.settingsAccentBlue)

                Button(L("取消", "Cancel")) { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(TF.settingsTextTertiary)

                Spacer()

                Button {
                    saveAndDismiss()
                } label: {
                    Text(L("添加选中项 (\(selectedCount))", "Add Selected (\(selectedCount))"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(selectedCount > 0 ? TF.settingsAccentGreen : TF.settingsTextTertiary.opacity(0.3))
                        )
                }
                .buttonStyle(.plain)
                .disabled(selectedCount == 0)
            }
        }
    }

    // MARK: - Actions

    private func loadHistory() {
        Task {
            let records = await historyStore.recentForCorrection(limit: 20)
            await MainActor.run {
                historyRecords = records
            }
        }
    }

    private func tokenize(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = trimmed

        var result: [String] = []
        tokenizer.enumerateTokens(in: trimmed.startIndex..<trimmed.endIndex) { range, _ in
            result.append(String(trimmed[range]))
            return true
        }

        withAnimation(.easeInOut(duration: 0.15)) {
            tokens = result
            selectedTokens = Set(result.indices)  // select all by default
        }
    }

    private func startGeneration() {
        guard canGenerate else { return }
        errorMessage = nil

        withAnimation(.easeInOut(duration: 0.15)) {
            phase = .generating
        }

        let wrong = selectedText
        let correct = correctText.trimmingCharacters(in: .whitespaces)

        generationTask = Task {
            do {
                let result = try await generator.generate(wrong: wrong, correct: correct)

                if Task.isCancelled { return }

                await MainActor.run {
                    snippetSuggestions = result.snippets
                    hotwordSuggestions = result.hotwords
                    hotwordReason = result.hotwordReason
                    withAnimation(.easeInOut(duration: 0.15)) {
                        phase = .preview
                    }
                }
            } catch {
                if Task.isCancelled { return }

                await MainActor.run {
                    errorMessage = error.localizedDescription
                    withAnimation(.easeInOut(duration: 0.15)) {
                        phase = .input
                    }
                }
            }
        }
    }

    private func selectAllSnippets() {
        for i in snippetSuggestions.indices where !snippetSuggestions[i].isDuplicate {
            snippetSuggestions[i].isSelected = true
        }
    }

    private func saveAndDismiss() {
        var currentSnippets = SnippetStorage.load()
        for s in snippetSuggestions where s.isSelected && !s.isDuplicate {
            currentSnippets.append((trigger: s.trigger, value: s.replacement))
        }
        SnippetStorage.save(currentSnippets)

        var currentHotwords = HotwordStorage.load()
        for h in hotwordSuggestions where h.isSelected && !h.isDuplicate {
            currentHotwords.append(h.word)
        }
        HotwordStorage.save(currentHotwords)

        // Trigger reload
        if let url = URL(string: "type4me://reload-vocabulary") {
            NSWorkspace.shared.open(url)
        }

        onComplete?()
        dismiss()
    }

    // MARK: - Helpers

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
