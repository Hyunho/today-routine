import SwiftUI

struct InboxDetailView: View {
    let itemID: String
    let model: AppModel
    var embedded = false
    private var item: InboxItem? { model.inbox?.state.items.first { $0.id == itemID } }
    private var routine: Routine? { model.snapshot.routines.first { $0.id == item?.routineID } }
    var body: some View {
        Group {
            if embedded { article }
            else {
                article
                    .pageStack(["feed", item?.title ?? "글 읽기"])
                    .navigationTitle(item?.kind == .reminder ? "루틴 알림" : "글 읽기").platformInlineTitle()
            }
        }
        .onAppear { model.inbox?.setRead(itemID) }
    }
    private var article: some View {
        Group {
            if let item {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Label(item.sourceTitle, systemImage: item.kind == .feed ? "dot.radiowaves.left.and.right" : "bell").font(.subheadline).foregroundStyle(.teal)
                        Text(item.title).font(.title2.bold()).textSelection(.enabled)
                        Text(item.date, format: .dateTime.year().month().day().hour().minute()).font(.caption).foregroundStyle(.secondary)
                        Divider()
                        if item.kind == .reminder {
                            if let status = model.routineStatus(for: item) { CompletionStatusLabel(status: status) }
                            Text("예정 시각 기준 기록").font(.subheadline).foregroundStyle(.secondary)
                            if routine != nil { Button("루틴 상세 열기") { Task { await model.openTodayRoutine(item) } }.buttonStyle(.bordered) }
                            else { Text("이 루틴은 삭제되었습니다.").foregroundStyle(.secondary) }
                        } else {
                            if (item.richBody ?? item.body).isEmpty {
                                Text("피드에 본문이 없습니다. 원문에서 확인하세요.")
                            } else {
                                FeedBodyView(bodyText: item.richBody ?? item.body, format: item.bodyFormat, baseURL: item.link ?? model.inbox?.state.subscriptions.first { $0.id == item.subscriptionID }?.url)
                            }
                        }
                    }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                }
                .toolbar {
                    if !embedded {
                        ToolbarItem(placement: .automatic) { saveButton(saved: item.isSaved) }
                    }
                }
                .webActionsSidebar(url: item.link, enabled: item.kind == .feed && !embedded)
                .safeAreaInset(edge: .top, spacing: 0) {
                    if embedded {
                        HStack {
                            saveButton(saved: item.isSaved).accessibilityIdentifier("panel-feed-save")
                            Spacer()
                            if let url = item.link, item.kind == .feed,
                               ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host != nil {
                                Link(destination: url) { Label("원문 열기", systemImage: "arrow.up.right.square") }
                                    .accessibilityIdentifier("panel-feed-open-in-browser")
                            }
                        }.buttonStyle(.borderless).padding(12).background(.bar)
                    }
                }
            } else { ContentUnavailableView("항목을 찾을 수 없습니다", systemImage: "doc", description: Text("구독 삭제 또는 보관 기간에 따라 제거된 항목입니다.")) }
        }
    }
    private func saveButton(saved: Bool) -> some View {
        Button { model.inbox?.toggleSaved(itemID) } label: { Image(systemName: saved ? "bookmark.fill" : "bookmark") }
            .accessibilityLabel(saved ? "나중에 읽기 해제" : "나중에 읽기 저장")
    }
}
