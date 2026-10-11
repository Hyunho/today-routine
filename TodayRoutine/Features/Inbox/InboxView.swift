import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct InboxView: View {
    let model: AppModel
    var isActive = true
    var embedded = false
    var presentsErrors = true
    var body: some View {
        if let inbox = model.inbox {
            InboxTimelineView(model: model, inbox: inbox, isActive: isActive, embedded: embedded, presentsErrors: presentsErrors)
        } else if embedded {
            unavailable
        } else {
            NavigationStack { unavailable.navigationTitle("피드") }
        }
    }
    private var unavailable: some View {
        ContentUnavailableView {
            Label("피드를 열 수 없습니다", systemImage: "tray")
        } description: { Text(model.inboxStartupError ?? "피드를 준비하고 있습니다.") }
        actions: { Button("다시 시도") { model.openInbox() } }
    }
}
private struct InboxTimelineView: View {
    let model: AppModel
    @Bindable var inbox: InboxModel
    let isActive: Bool
    let embedded: Bool
    let presentsErrors: Bool
    @State private var filter: InboxFilter = .all
    @State private var savedOnly = false
    @State private var subscriptions = false
    @State private var position: String?
    @State private var path: [String] = []
    @Environment(\.scenePhase) private var phase
    private var key: String { (embedded ? "panel." : "") + filter.positionKey(savedOnly: savedOnly) }
    private var items: [InboxItem] { inbox.items(filter: filter, savedOnly: savedOnly) }
    var body: some View {
        Group {
            if embedded {
                VStack(spacing: 0) {
                    HStack {
                        if !path.isEmpty {
                            Button { path.removeLast() } label: { Label("피드 목록", systemImage: "chevron.left") }
                                .accessibilityIdentifier("panel-feed-back")
                        }
                        Spacer()
                        subscriptionButton
                        refreshButton
                    }.buttonStyle(.borderless).padding(12)
                    Divider()
                    ZStack {
                        listContent
                            .opacity(path.isEmpty ? 1 : 0)
                            .disabled(!path.isEmpty)
                            .accessibilityHidden(!path.isEmpty)
                        if let id = path.last {
                            InboxDetailView(itemID: id, model: model, embedded: true).id(id)
                        }
                    }
                }
            } else {
                NavigationStack(path: $path) {
                    listContent
                        .navigationTitle("피드")
                        .platformInlineTitle()
                        .toolbar {
                            ToolbarItem(placement: .automatic) { subscriptionButton }
                            ToolbarItem(placement: .automatic) { refreshButton }
                        }
                        .navigationDestination(for: String.self) { id in InboxDetailView(itemID: id, model: model) }
                }
            }
        }
        .sheet(isPresented: $subscriptions) {
            FeedSubscriptionsView(inbox: inbox)
                .onAppear { model.presentedInboxSubscriptions += 1 }
                .onDisappear { model.presentedInboxSubscriptions = max(0, model.presentedInboxSubscriptions - 1) }
        }
        .alert("피드를 저장하지 못했습니다", isPresented: Binding(get: { isActive && presentsErrors && model.presentedInboxSubscriptions == 0 && inbox.error != nil && !subscriptions }, set: { if !$0 && isActive && presentsErrors && model.presentedInboxSubscriptions == 0 { inbox.error = nil } })) { Button("확인") { inbox.error = nil } } message: { Text(inbox.error ?? "") }
        .onAppear { position = inbox.state.positions[key]; model.refreshInboxReminders() }
        .onDisappear { persistPosition() }
        .onChange(of: key) { old, new in
            if let position { inbox.savePosition(position, key: old) }
            position = inbox.state.positions[new]
        }
        .onChange(of: phase) { _, phase in if phase != .active { persistPosition() } }
        .task(id: position) {
            do { try await Task.sleep(for: .milliseconds(300)); persistPosition() } catch {}
        }
        .onChange(of: isActive) { _, active in if !active { persistPosition() } }
        .task(id: phase == .active && isActive) {
            guard phase == .active && isActive else { return }
            await inbox.refresh()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
                model.refreshInboxReminders()
            }
        }
    }
    private var subscriptionButton: some View {
        Button { subscriptions = true } label: { Image(systemName: "plus.circle") }
            .accessibilityLabel("구독 관리")
            .accessibilityIdentifier(embedded ? "panel-feed-subscriptions" : "feed-subscriptions")
    }
    private var refreshButton: some View {
        Button { Task { await inbox.refresh(force: true) } } label: {
            if inbox.isRefreshing { ProgressView().controlSize(.small) } else { Image(systemName: "arrow.clockwise") }
        }.disabled(inbox.isRefreshing).accessibilityLabel("새로고침")
    }
    private var listContent: some View {
        VStack(spacing: 0) {
            controls
            if !inbox.feedErrors.isEmpty {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                    Text("일부 구독을 갱신하지 못했습니다.").font(.caption)
                    Spacer()
                    Button("확인") { subscriptions = true }.font(.caption)
                }.padding(12).background(Color.orange.opacity(0.1))
            }
            timeline
        }
    }
    private func openItem(_ item: InboxItem) {
        persistPosition()
        inbox.setRead(item.id)
        Task {
            if !embedded, item.kind == .reminder, await model.openTodayRoutine(item) { return }
            path.append(item.id)
        }
    }
    private var controls: some View {
        VStack(spacing: 10) {
            Picker("항목 종류", selection: $filter) {
                ForEach(InboxFilter.allCases) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented)
            HStack {
                Text("\(items.count)개").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { savedOnly.toggle() } label: {
                    Label("나중에 읽기", systemImage: savedOnly ? "bookmark.fill" : "bookmark").font(.subheadline)
                }.buttonStyle(.borderless).foregroundStyle(savedOnly ? Color.teal : Color.secondary)
                    .accessibilityLabel(savedOnly ? "모든 항목 보기" : "나중에 읽기만 보기")
                if position != nil {
                    Button { position = items.first?.id } label: { Image(systemName: "arrow.up.to.line") }.buttonStyle(.borderless).accessibilityLabel("최신 항목으로 이동")
                }
            }
        }.padding(.horizontal).padding(.vertical, 12)
    }
    private var timeline: some View {
        let timelineItems = items
        return ScrollView {
            LazyVStack(spacing: 0) {
                if timelineItems.isEmpty {
                    ContentUnavailableView(savedOnly ? "저장한 항목이 없습니다" : "아직 도착한 소식이 없습니다", systemImage: savedOnly ? "bookmark" : "tray", description: Text(savedOnly ? "항목을 열어 나중에 읽기에 저장하세요." : "구독을 추가하거나 루틴 알림 시간이 되면 여기에 표시됩니다."))
                }
                ForEach(Array(timelineItems.enumerated()), id: \.element.id) { index, item in
                    VStack(spacing: 0) {
                        if index == 0 || !RoutineRules.calendar.isDate(timelineItems[index - 1].date, inSameDayAs: item.date) {
                            HStack(spacing: 10) {
                                Text(item.date, format: .dateTime.year().month().day().weekday())
                                    .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                                    .accessibilityAddTraits(.isHeader)
                                Rectangle().fill(Color.teal.opacity(0.6)).frame(height: 2)
                            }
                            .padding(.horizontal, 16).padding(.top, index == 0 ? 8 : 20).padding(.bottom, 4)
                        }
                        HStack(alignment: .center, spacing: 0) {
                            if let status = model.routineStatus(for: item) {
                                CompletionCheckButton(title: item.title, status: status) { model.toggleRoutineCompletion(for: item) }
                                    .accessibilityIdentifier("inbox-completion-" + item.id)
                                    .disabled(!model.snapshot.routines.contains { $0.id == item.routineID })
                                    .padding(.leading, 16)
                            }
                        Button { openItem(item) } label: { InboxRow(item: item, status: model.routineStatus(for: item)) }
                            .buttonStyle(.plain).accessibilityIdentifier((embedded ? "inbox-panel-item-" : "inbox-item-") + item.id)
                            .contextMenu {
                                Button(item.kind == .reminder ? "루틴 상세 열기" : "글 열기", systemImage: item.kind == .reminder ? "sun.max" : "doc.text") {
                                    openItem(item)
                                }
                                Divider()
                                Button(item.isRead ? "읽지 않음으로 표시" : "읽음으로 표시", systemImage: item.isRead ? "envelope.badge" : "envelope.open") {
                                    inbox.setRead(item.id, read: !item.isRead)
                                }
                                Button(item.isSaved ? "나중에 읽기 해제" : "나중에 읽기 저장", systemImage: item.isSaved ? "bookmark.slash" : "bookmark") {
                                    inbox.toggleSaved(item.id)
                                }
                                if let url = item.link, ["https", "http"].contains(url.scheme?.lowercased() ?? "") {
                                    Divider()
                                    Link(destination: url) { Label("원문 열기", systemImage: "arrow.up.right.square") }
                                    Button("링크 복사", systemImage: "link") {
                                        #if os(macOS)
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(url.absoluteString, forType: .string)
                                        #else
                                        UIPasteboard.general.string = url.absoluteString
                                        #endif
                                    }
                                }
                            }
                        }
                        Divider().padding(.leading, 44)
                    }.id(item.id)
                }
            }.scrollTargetLayout()
        }
        .scrollPosition(id: $position, anchor: .top)
        .accessibilityIdentifier("피드 목록")
        .scrollBounceBehavior(.always)
        .modifier(MobileSyncRefresh(model: model, includeFeeds: true))
    }
    private func persistPosition() { if let position { inbox.savePosition(position, key: key) } }
}
private struct InboxRow: View {
    let item: InboxItem
    let status: DayStatus?
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if status == nil {
                Image(systemName: item.kind == .feed ? "dot.radiowaves.left.and.right" : "bell")
                    .font(.subheadline).foregroundStyle(item.isRead ? Color.secondary : .teal)
                    .frame(width: 20).padding(.top, 3)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(item.sourceTitle).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(item.date, format: .dateTime.hour().minute()).lineLimit(1)
                }.font(.caption).foregroundStyle(.secondary)
                Text(item.title).font(.body.weight(item.isRead ? .regular : .semibold)).multilineTextAlignment(.leading).foregroundStyle(.primary)
                if !item.body.isEmpty { Text(item.body).font(.subheadline).foregroundStyle(.secondary).lineLimit(2).multilineTextAlignment(.leading) }
            }
            if item.isSaved { Image(systemName: "bookmark.fill").font(.caption).foregroundStyle(.teal) }
            else if !item.isRead { Circle().fill(.teal).frame(width: 6, height: 6).padding(.top, 7) }
        }.padding(.vertical, 16).padding(.trailing, 16).padding(.leading, status == nil ? 16 : 12)
            .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
    }
}
