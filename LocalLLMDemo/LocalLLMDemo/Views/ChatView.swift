import SwiftUI

struct ChatView: View {
    @StateObject private var vm = ChatViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(vm.messages) { m in
                                MessageBubble(message: m).id(m.id)
                            }
                        }
                        .padding()
                    }
                    .onChange(of: vm.messages.count) { _ in
                        if let last = vm.messages.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }

                Divider()
                HStack(alignment: .bottom) {
                    TextField("说点什么…", text: $vm.inputText, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .disabled(vm.isGenerating)
                    if vm.isGenerating {
                        Button("停止", action: vm.stop)
                            .foregroundStyle(.red)
                    } else {
                        Button("发送", action: vm.send)
                            .disabled(vm.inputText.trimmingCharacters(in: .whitespaces).isEmpty
                                      || vm.loadedItemID == nil)
                    }
                }
                .padding(8)
            }
            .navigationTitle("本地聊天")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink("模型库", destination: ModelLibraryView(vm: vm))
                }
            }
            .safeAreaInset(edge: .top) {
                Text(vm.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial)
            }
        }
    }
}

struct MessageBubble: View {
    let message: ChatMessage
    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }
            Text(message.text.isEmpty ? "…" : message.text)
                .padding(10)
                .background(message.role == .user
                            ? Color.accentColor.opacity(0.2)
                            : Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .textSelection(.enabled)
            if message.role == .assistant { Spacer(minLength: 40) }
        }
    }
}
