import SwiftUI
import SwiftData

/// Android Chats 的 iOS 原生对应页。记一记是固定会话，普通会话支持搜索、
/// 加星和删除；会话内容仍保存在 SwiftData，密钥不进入其中。
struct AIChatsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \AIChatSession.updatedAt, order: .reverse)
    private var sessions: [AIChatSession]

    @State private var searchText = ""
    @State private var sessionToOpen: AIChatSession?
    @State private var errorMessage: String?

    private var visibleSessions: [AIChatSession] {
        let ordinary = sessions.filter { !$0.isRecord }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return ordinary }
        return ordinary.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        List {
            Section {
                NavigationLink {
                    MeowAssistantView()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "cat.fill")
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 32, height: 32)
                            .background(Color.accentColor.opacity(0.12), in: .circle)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("记一记")
                                .font(.body.weight(.medium))
                            Text("固定会话 · 用于快速记账")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 3)
                }
            }

            Section("其他会话") {
                if visibleSessions.isEmpty {
                    ContentUnavailableView(
                        searchText.isEmpty ? "还没有其他会话" : "没有匹配的会话",
                        systemImage: searchText.isEmpty ? "bubble.left.and.bubble.right" : "magnifyingglass",
                        description: Text(searchText.isEmpty ? "点击右上角加号开始一次新对话。" : "换一个关键词试试。")
                    )
                } else {
                    ForEach(visibleSessions) { session in
                        Button {
                            sessionToOpen = session
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: session.isStarred ? "star.fill" : "bubble.left")
                                    .foregroundStyle(session.isStarred ? .orange : Color.accentColor)
                                    .frame(width: 30)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(session.title)
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text(session.updatedAt, format: .dateTime.month().day().hour().minute())
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 8)
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button {
                                session.isStarred.toggle()
                                session.updatedAt = Date()
                                save()
                            } label: {
                                Label(session.isStarred ? "取消加星" : "加星", systemImage: session.isStarred ? "star.slash" : "star")
                            }
                            .tint(.orange)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                delete(session)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Chats")
        .searchable(text: $searchText, prompt: "搜索会话")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    createConversation()
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("新建会话")
            }
        }
        .sheet(item: $sessionToOpen) { session in
            MeowAssistantView(sessionID: session.stableID, title: session.title)
        }
        .alert("Chats", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func createConversation() {
        let session = AIChatSession(title: "新对话")
        context.insert(session)
        do {
            try context.save()
            sessionToOpen = session
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(_ session: AIChatSession) {
        let messages = (try? context.fetch(FetchDescriptor<AIChatMessage>())) ?? []
        for message in messages where message.sessionID == session.stableID {
            context.delete(message)
        }
        context.delete(session)
        save()
    }

    private func save() {
        do {
            try context.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    AIChatsView()
        .modelContainer(AppModelContainer.shared)
        .environment(AppRouter())
        .environment(AIProviderStore())
}
