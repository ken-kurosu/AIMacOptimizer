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

    // MARK: - API Key Setup

    private var apiKeySetupView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "key.fill")
                .font(.system(size: 32))
                .foregroundColor(.orange)

            Text("APIキーを設定")
                .font(.headline)

            Text("AIチャットにはOpenAIまたはAnthropicのAPIキーが必要です。\nキーはお使いのMacのKeychain内に安全に保存されます。")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

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
                        ChatBubble(message: message)
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
                "一番深刻な問題は何？",
                "メモリを節約するには？",
                "ディスクの空きを増やすには？",
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

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 2) {
                Text(message.content)
                    .font(.system(size: 12))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(bubbleColor)
                    .foregroundColor(message.role == .user ? .white : .primary)
                    .cornerRadius(12)
                    .textSelection(.enabled)

                Text(message.timestamp, style: .time)
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
            }

            if message.role == .assistant { Spacer(minLength: 40) }
        }
        .padding(.horizontal, 8)
    }

    private var bubbleColor: Color {
        message.role == .user ? .purple : Color.gray.opacity(0.12)
    }
}
