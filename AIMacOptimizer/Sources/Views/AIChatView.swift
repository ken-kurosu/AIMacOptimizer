import SwiftUI

/// AI Chat view — interactive consultation about diagnosis results
struct AIChatView: View {
    @ObservedObject var chatService: AIChatService
    @ObservedObject var license: LicenseManager
    let onBack: () -> Void

    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Header
            chatHeader
            Divider()

            if !chatService.settings.isConfigured {
                apiKeySetupView
            } else {
                // Messages
                chatMessages
                Divider()

                // Input area
                chatInput
            }
        }
    }

    // MARK: - Header

    private var chatHeader: some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)

            Image(systemName: "bubble.left.and.bubble.right.fill")
                .foregroundColor(.purple)
                .font(.system(size: 14))

            Text("AI相談")
                .font(.subheadline)
                .fontWeight(.medium)

            Spacer()

            // プロバイダ切替（無料/有料を常時表示し、誤って有料APIを使わないようにする）
            providerMenu

            Button(action: { chatService.clearChat() }) {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("会話をクリア")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    /// 現在のAIモード（無料/有料）を表示し、いつでも切り替えられるメニュー
    private var providerMenu: some View {
        let current = chatService.settings.provider
        return Menu {
            Section("無料（推奨・キー不要）") {
                ForEach(AIProvider.allCases.filter { $0.isFree }, id: \.self) { p in
                    Button { switchProvider(p) } label: {
                        Label(p.displayName, systemImage: current == p ? "checkmark" : "gift")
                    }
                }
            }
            Section("上級（従量課金・APIキー必要）") {
                ForEach(AIProvider.allCases.filter { $0.requiresAPIKey }, id: \.self) { p in
                    Button { switchProvider(p) } label: {
                        Label(p.displayName, systemImage: current == p ? "checkmark" : "creditcard")
                    }
                }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: current.isFree ? "gift.fill" : "creditcard.fill")
                    .font(.system(size: 9))
                Text(current.isFree ? "無料モード" : "有料API")
                    .font(.system(size: 10, weight: .semibold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 7))
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background((current.isFree ? Color.green : Color.orange).opacity(0.15))
            .foregroundColor(current.isFree ? .green : .orange)
            .cornerRadius(7)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("AIの種類を切り替え（無料/有料）")
    }

    private func switchProvider(_ p: AIProvider) {
        chatService.settings.provider = p
        chatService.saveSettings()
    }

    // MARK: - API Key Setup

    private var apiKeySetupView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "key.fill")
                .font(.system(size: 32))
                .foregroundColor(.orange)

            Text("これは有料モードです")
                .font(.headline)

            Text("OpenAI / Anthropic は従量課金の上級モードです。\n無料で使うなら「無料モードに戻る」を押してください（キー不要・このMac内で完結）。")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button(action: { switchProvider(.local) }) {
                HStack(spacing: 4) {
                    Image(systemName: "gift.fill")
                    Text("無料モードに戻る")
                        .fontWeight(.semibold)
                }
                .font(.system(size: 12))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Color.green.opacity(0.15))
                .foregroundColor(.green)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)

            // Provider picker
            Picker("プロバイダー", selection: $chatService.settings.provider) {
                ForEach(AIProvider.allCases, id: \.self) { provider in
                    Text(provider.displayName).tag(provider)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 40)

            VStack(alignment: .leading, spacing: 4) {
                Text("API キー")
                    .font(.caption)
                    .foregroundColor(.secondary)
                SecureField("sk-...", text: $chatService.settings.apiKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
            }
            .padding(.horizontal, 24)

            VStack(alignment: .leading, spacing: 2) {
                Text("モデル（空欄でデフォルト）")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField(chatService.settings.provider.defaultModel, text: $chatService.settings.model)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
            }
            .padding(.horizontal, 24)

            Text("推奨: \(chatService.settings.provider.displayName) \(chatService.settings.provider.defaultModel) (\(chatService.settings.provider.costPer1KInput)/1Kトークン)")
                .font(.system(size: 10))
                .foregroundColor(.secondary)

            Button(action: {
                chatService.saveSettings()
            }) {
                Text("保存して開始")
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .padding(.horizontal, 40)
            .disabled(chatService.settings.apiKey.isEmpty)

            Spacer()
        }
    }

    // MARK: - Chat Messages

    private var chatMessages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    if chatService.messages.isEmpty {
                        welcomeMessage
                    }

                    ForEach(chatService.messages) { message in
                        ChatBubble(message: message, onAction: { action in
                            Task { await chatService.performChatAction(action) }
                        })
                        .id(message.id)
                    }

                    if chatService.isLoading {
                        HStack {
                            ProgressView()
                                .controlSize(.small)
                            Text("考え中...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal)
                        .id("loading")
                    }

                    if let error = chatService.errorMessage {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                                .font(.caption)
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                            Spacer()
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical, 8)
            }
            .onChange(of: chatService.messages.count) { _ in
                if let lastId = chatService.messages.last?.id {
                    withAnimation { proxy.scrollTo(lastId, anchor: .bottom) }
                }
            }
        }
    }

    private var welcomeMessage: some View {
        VStack(spacing: 8) {
            Text("診断結果について何でも聞いてください")
                .font(.caption)
                .foregroundColor(.secondary)

            // Suggested questions
            let suggestions = [
                "このMacで容量を食ってるものは？",
                "安全に消せるものを教えて",
                "一番深刻な問題は何？",
            ]
            ForEach(suggestions, id: \.self) { suggestion in
                Button(action: {
                    inputText = suggestion
                    sendMessage()
                }) {
                    Text(suggestion)
                        .font(.system(size: 11))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.purple.opacity(0.1))
                        .cornerRadius(12)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 20)
    }

    // MARK: - Input Area

    private var chatInput: some View {
        HStack(spacing: 8) {
            TextField("質問を入力...", text: $inputText)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
                .focused($isInputFocused)
                .onSubmit { sendMessage() }

            Button(action: sendMessage) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(inputText.isEmpty ? .gray : .purple)
            }
            .buttonStyle(.plain)
            .disabled(inputText.isEmpty || chatService.isLoading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        Task { await chatService.sendMessage(text) }
    }
}

// MARK: - Chat Bubble

struct ChatBubble: View {
    let message: ChatMessage
    var onAction: ((ChatActionDescriptor) -> Void)? = nil

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(attributedContent)
                    .font(.system(size: 12))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(bubbleColor)
                    .foregroundColor(message.role == .user ? .white : .primary)
                    .cornerRadius(12)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)

                // 実行できるアクション（削除提案など）をボタン表示
                if !message.actions.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(message.actions) { action in
                            Button(action: { onAction?(action) }) {
                                HStack(spacing: 5) {
                                    Image(systemName: actionIcon(action))
                                        .font(.system(size: 9))
                                    Text(action.label)
                                        .font(.system(size: 11, weight: .medium))
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(actionColor(action).opacity(0.12))
                                .foregroundColor(actionColor(action))
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Text(message.timestamp, style: .time)
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
            }

            if message.role == .assistant { Spacer(minLength: 40) }
        }
        .padding(.horizontal, 8)
    }

    /// マークダウンの **太字** 等を実際に装飾表示する（改行は保持）
    private var attributedContent: AttributedString {
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace
        if let a = try? AttributedString(markdown: message.content, options: options) {
            return a
        }
        return AttributedString(message.content)
    }

    private var bubbleColor: Color {
        message.role == .user ? .purple : Color.gray.opacity(0.12)
    }

    private func actionIcon(_ a: ChatActionDescriptor) -> String {
        switch a.type {
        case .openURL: return "arrow.up.right.square"
        case .deleteCacheSafe: return "trash.fill"
        case .moveToTrash: return "exclamationmark.triangle.fill"
        }
    }

    private func actionColor(_ a: ChatActionDescriptor) -> Color {
        switch a.type {
        case .openURL: return .green
        case .deleteCacheSafe: return .blue
        case .moveToTrash: return .orange
        }
    }
}
