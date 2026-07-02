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

            // すべて無料プロバイダ（ローカル/オンデバイス）なので設定不要で常にチャット可能
            chatMessages
            Divider()
            chatInput
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

            Text(L10n.aiChat)
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
            .help(L10n.clearConversation)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    /// AIの種類（ローカル解析 / オンデバイスAI、いずれも無料）を切り替えるメニュー
    private var providerMenu: some View {
        let current = chatService.settings.provider
        return Menu {
            ForEach(AIProvider.allCases, id: \.self) { p in
                Button { switchProvider(p) } label: {
                    Label(p.displayName, systemImage: current == p ? "checkmark" : "gift")
                }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "gift.fill")
                    .font(.system(size: 9))
                Text(L10n.freeMode)
                    .font(.system(size: 10, weight: .semibold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 7))
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.green.opacity(0.15))
            .foregroundColor(.green)
            .cornerRadius(7)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(L10n.switchAIType)
    }

    private func switchProvider(_ p: AIProvider) {
        chatService.settings.provider = p
        chatService.saveSettings()
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
                            Text(L10n.thinking)
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
            Text(L10n.askAnythingDiagnosis)
                .font(.caption)
                .foregroundColor(.secondary)

            // Suggested questions
            let suggestions = [
                L10n.suggestedQ1,
                L10n.suggestedQ2,
                L10n.suggestedQ3,
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
            TextField(L10n.enterQuestion, text: $inputText)
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
