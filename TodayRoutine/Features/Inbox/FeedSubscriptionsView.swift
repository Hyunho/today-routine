import SwiftUI

struct FeedSubscriptionsView: View {
    @Bindable var inbox: InboxModel
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var adding = false
    @State private var deleting: InboxSubscription?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://example.com/feed.xml", text: $address).accessibilityLabel("RSS 주소")
                        #if os(iOS)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                        #endif
                    Button {
                        guard let url = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)) else { inbox.error = "HTTPS 피드 주소를 입력해 주세요."; return }
                        adding = true
                        Task { await inbox.addSubscription(url); if inbox.error == nil { address = "" }; adding = false }
                    } label: { HStack { Text("구독 추가"); if adding { ProgressView().controlSize(.small) } } }
                    .disabled(adding || address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } header: { Text("RSS·Atom 주소") } footer: { Text("HTTPS 피드 주소를 입력하세요. 구독은 이 기기에 저장됩니다.") }
                Section("구독 중 · \(inbox.state.subscriptions.count)") {
                    ForEach(inbox.state.subscriptions) { feed in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(feed.title).font(.headline)
                                Spacer()
                                Button(role: .destructive) { deleting = feed } label: { Image(systemName: "trash") }
                                    .buttonStyle(.borderless).accessibilityLabel("\(feed.title) 구독 삭제")
                            }
                            Text(feed.url.absoluteString).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                            if let error = inbox.feedErrors[feed.id] { Text(error).font(.caption).foregroundStyle(.orange) }
                            if let date = feed.lastRefreshAt { Text("갱신 \(date.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary) }
                        }.padding(.vertical, 4)
                    }
                    if inbox.state.subscriptions.isEmpty { Text("구독한 피드가 없습니다.").foregroundStyle(.secondary) }
                    Button("구독 새로고침") { Task { await inbox.refresh(force: true) } }.disabled(inbox.isRefreshing)
                }
            }.formStyle(.grouped)
            .navigationTitle("구독 관리").platformInlineTitle()
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("닫기") { dismiss() } } }
            .confirmationDialog("구독을 삭제할까요?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                if let selected = deleting {
                    Button("구독 삭제", role: .destructive) { inbox.removeSubscription(selected.id); deleting = nil }
                }
            } message: { Text("구독의 일반 글은 삭제하고, 나중에 읽기에 저장한 글은 유지합니다.") }
            .alert("구독을 변경하지 못했습니다", isPresented: Binding(get: { inbox.error != nil }, set: { if !$0 { inbox.error = nil } })) { Button("확인") { inbox.error = nil } } message: { Text(inbox.error ?? "") }
        }.platformSheetSize()
    }
}
