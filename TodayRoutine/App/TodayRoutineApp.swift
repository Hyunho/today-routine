import SwiftUI
import SwiftData

@main struct TodayRoutineApp: App {
    @State private var model = AppModel()
    #if os(macOS)
    @NSApplicationDelegateAdaptor(TodayRoutineMacDelegate.self) private var delegate
    #endif
    var body: some Scene { WindowGroup { RootView(model: model)
        .onAppear {
            #if os(macOS)
            delegate.closeCoordinator = model.logseqClose
            #endif
        }.tint(.teal).environment(\.locale, Locale(identifier: "ko_KR")).environment(\.calendar, RoutineRules.calendar).environment(\.timeZone, RoutineRules.calendar.timeZone) }
        #if os(macOS)
        .defaultSize(width:440,height:760)
        .windowResizability(.contentSize)
        .commands { TodayDocumentCommands() }
        #endif
    }
}
struct TodayRoutineRoute: Identifiable {
    let id = UUID()
    let routineID: UUID
    let date: Date
    let returnTab: String
}
@MainActor @Observable final class AppModel {
    #if os(macOS)
    let logseq = LogseqHost()
    @ObservationIgnored var todayDocumentHosts: [UUID: TodayDocumentHost] = [:]
    @ObservationIgnored lazy var logseqClose = LogseqCloseCoordinator(host: logseq, prepareAdditional: { [weak self] in
        guard let self else { return true }
        for host in todayDocumentHosts.values { if !(await host.flushDraft()) { return false } }
        return true
    })
    #endif
    var selectedTab = "오늘"
    var todayRoutineRoute: TodayRoutineRoute?
    @discardableResult func openTodayRoutine(_ item: InboxItem) async -> Bool {
        guard let id = item.routineID, snapshot.routines.contains(where: { $0.id == id }) else { return false }
        let returnTab = selectedTab
        guard await selectTab("오늘") else { return false }
        todayRoutineRoute = TodayRoutineRoute(routineID: id, date: item.dayKey.flatMap { RoutineRules.date(for: $0) } ?? item.date, returnTab: returnTab)
        return true
    }
    func routineStatus(for item: InboxItem) -> DayStatus? {
        guard item.kind == .reminder, let id = item.routineID else { return nil }
        let day = item.dayKey ?? RoutineRules.dayKey(item.date)
        if let record = snapshot.records.first(where: { $0.routineID == id && $0.dayKey == day }) { return record.status }
        return snapshot.routines.contains(where: { $0.id == id }) ? .pending : nil
    }
    func toggleRoutineCompletion(for item: InboxItem) {
        guard let status = routineStatus(for: item), let id = item.routineID,
              snapshot.routines.contains(where: { $0.id == id }) else { return }
        let date = item.dayKey.flatMap { RoutineRules.date(for: $0) } ?? item.date
        perform { try $0.setStatus(routineID: id, date: date, status: status == .pending ? .completed : .pending) }
    }
    var store: RoutineStore?
    var snapshot = StoreSnapshot()
    var sync: SyncCoordinator?
    var inbox: InboxModel?
    var inboxStartupError: String?
    private var inboxURL = URL.applicationSupportDirectory.appendingPathComponent("TodayRoutineInbox/inbox.json")
    var reminderDefaults = ReminderDefaults()
    private var localListLayout = ListLayoutConfig()
    private var localListLayoutStatus = ""
    var listLayoutFileURL: URL { sync?.listLayoutFileURL ?? ListLayoutConfig.fileURL }
    var listLayout: ListLayoutConfig { sync?.listLayoutFileURL != nil ? sync!.listLayout : localListLayout }
    var listLayoutStatus: String { sync?.listLayoutFileURL != nil ? sync!.listLayoutStatus : localListLayoutStatus }
    private(set) var isSavingListLayout = false
    func saveListLayout(_ value: ListLayoutConfig) async {
        guard !isSavingListLayout else { return }
        isSavingListLayout = true
        defer { isSavingListLayout = false }
        do {
            if let sync, sync.listLayoutFileURL != nil {
                try await sync.saveListLayout(value)
            } else {
                try value.save(at: ListLayoutConfig.fileURL)
                localListLayout = value
                localListLayoutStatus = "설정을 저장하고 타임라인에 적용했습니다."
            }
        } catch is CancellationError {
            return
        } catch { self.error = "타임라인 간격을 저장하지 못했습니다. \(error.localizedDescription)" }
    }
    func reloadListLayout() async {
        guard !isSavingListLayout else { return }
        if let sync, sync.listLayoutFileURL != nil { await sync.reloadListLayout() }
        else { reloadLocalListLayout() }
    }
    // The view owns cancellation and restarts this when the app becomes active.
    // Read only the small layout file, without triggering a full data sync.
    func monitorListLayoutChanges() async {
        while !Task.isCancelled {
            await reloadListLayout()
            do { try await Task.sleep(for: .seconds(2)) }
            catch { return }
        }
    }
    private func reloadLocalListLayout() {
        do {
            let value = try ListLayoutConfig.loadOrCreate(at: ListLayoutConfig.fileURL)
            if localListLayout != value { localListLayout = value }
            localListLayoutStatus = "설정을 불러왔습니다. 누락되거나 허용 범위를 벗어난 값은 기본값을 사용합니다."
        } catch {
            localListLayoutStatus = "설정 파일을 읽을 수 없어 마지막 정상 설정을 유지합니다. \(error.localizedDescription)"
        }
    }
    private var reminderSettingsStore = UserDefaults.standard
    var focusSession: FocusSession?
    var presentedSheets = 0
    var presentedInboxSubscriptions = 0
    var error: String?
    var startupError: String?
    private(set) var isRefreshingLists = false
    var revision = 0
    let appleReminders: AppleRemindersModel
    let notifications = NotificationService()
    let appleCalendar = AppleCalendarModel()
    init() {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "--uitest-store"), args.count > index + 1 {
            let id = args[index + 1]
            let defaults = UserDefaults(suiteName: "reminders-uitest-" + id)!
            if args.contains("--uitest-reminders") {
                appleReminders = AppleRemindersModel(client: AppleRemindersFixture(id: id, denied: args.contains("--uitest-reminders-denied")), defaults: defaults)
            } else { appleReminders = AppleRemindersModel(client: EventKitRemindersAccess(), defaults: defaults) }
        } else { appleReminders = AppleRemindersModel(client: EventKitRemindersAccess()) }
        #else
        appleReminders = AppleRemindersModel(client: EventKitRemindersAccess())
        #endif
        #if DEBUG
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil,
           !ProcessInfo.processInfo.arguments.contains("--uitest-store") { return }
        #endif
        reloadLocalListLayout()
        open()
        configureCalendarRoutineCompletion()
    }
    func open() {
        do {
            var url: URL?
            #if DEBUG
            if let index = ProcessInfo.processInfo.arguments.firstIndex(of: "--uitest-store"), ProcessInfo.processInfo.arguments.count > index+1, let id = UUID(uuidString: ProcessInfo.processInfo.arguments[index+1]) {
                url = URL.applicationSupportDirectory.appendingPathComponent("UITest-\(id.uuidString).store")
            }
            #endif
            reminderSettingsStore = url.map { UserDefaults(suiteName: "reminder-defaults-" + $0.lastPathComponent)! } ?? .standard
            if let data = reminderSettingsStore.data(forKey: "routine.reminderDefaults"), let saved = try? JSONDecoder().decode(ReminderDefaults.self, from: data) { reminderDefaults = saved }
            store = RoutineStore(container: try PersistenceFactory.make(url: url))
            #if DEBUG
            if url != nil && ProcessInfo.processInfo.arguments.contains("--uitest-pending-stack"), let store, try store.loadSnapshot().routines.isEmpty {
                for index in 0..<24 {
                    var routine = RoutineDraft()
                    routine.name = "스택 작업 \(index)"; routine.minute = 360 + index * 20
                    try store.upsertRoutine(routine)
                    if index == 1 { try store.setStatus(routineID: routine.id, date: Date(), status: .completed) }
                }
            }
            if url != nil && ProcessInfo.processInfo.arguments.contains("--uitest-legacy-tasks"), let store, try store.loadSnapshot().blocks.isEmpty {
                let task = TaskItem(title: "삭제할 내부 일감", dayKey: RoutineRules.dayKey(Date()), minute: 540)
                let done = TaskItem(title: "삭제할 완료 일감", dayKey: RoutineRules.dayKey(Date()))
                done.completedAt = Date()
                let block = TimeBlock(title: "보존할 집중 시간", dayKey: RoutineRules.dayKey(Date()), start: 540, end: 600)
                block.linkedID = task.id; block.linkedKind = "task"
                store.context.insert(task); store.context.insert(done); store.context.insert(block); try store.save()
            }
            if url != nil && ProcessInfo.processInfo.arguments.contains("--uitest-fail-save-once") {
                var fail = true
                store?.saveOperation = { context in
                    if fail { fail = false; throw CocoaError(.fileWriteOutOfSpace) }
                    try context.save()
                }
            }
            #endif
            inboxURL = url.map { $0.deletingPathExtension().appendingPathExtension("inbox.json") } ?? URL.applicationSupportDirectory.appendingPathComponent("TodayRoutineInbox/inbox.json")
            try store?.removeLegacyTasks()
            startupError = nil; try reload()
            openInbox()
            if let store {
                let access = SyncFolderAccess(key:url == nil ? "routine.sync.bookmark":"routine.sync.test.\(url!.lastPathComponent)")
                sync = SyncCoordinator(store:store,access:access)
                sync?.onChange = { [weak self] in try? self?.reload(); self?.refreshNotifications() }
                Task {
                    #if DEBUG
                    if let url, ProcessInfo.processInfo.arguments.contains("--uitest-sync") {
                        let folder = url.deletingPathExtension().appendingPathExtension("sync")
                        do { try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true); await sync?.connect(url:folder,persist:false) } catch { self.error = error.localizedDescription }
                        return
                    }
                    #endif
                    await sync?.restore()
                }
            }
        } catch { startupError = error.localizedDescription }
    }
    func reload() throws {
        if let store {
            snapshot = try store.loadSnapshot()
            if let session = focusSession, case .task = session.target { focusSession = nil }
            revision += 1
        }
    }
    @discardableResult func perform(_ action: (RoutineStore) throws -> Void) -> Bool {
        guard let store else { return false }
        do { try action(store); try reload(); refreshNotifications(); sync?.localDataDidChange(); return true }
        catch { self.error = error.localizedDescription; try? reload(); return false }
    }
    func openInbox() {
        do {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--uitest-inbox-corrupt"), !FileManager.default.fileExists(atPath: inboxURL.path) {
                try FileManager.default.createDirectory(at: inboxURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data("corrupt fixture".utf8).write(to: inboxURL)
            }
            #endif
            let store = try InboxStore(url: inboxURL)
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--uitest-inbox") {
                var linkedRoutineID: UUID?
                if ProcessInfo.processInfo.arguments.contains("--uitest-inbox-routine") {
                    var draft = RoutineDraft()
                    draft.name = "알림 연결 확인"
                    try self.store?.upsertRoutine(draft)
                    if let snapshot = try self.store?.loadSnapshot() { self.snapshot = snapshot }
                    linkedRoutineID = draft.id
                }
                try InboxFixture.seed(store, routineID: linkedRoutineID)
                inbox = InboxModel(store: store, client: InboxFixtureClient())
            } else {
                try store.seed(); inbox = InboxModel(store: store)
            }
            #else
            try store.seed(); inbox = InboxModel(store: store)
            #endif
            inboxStartupError = nil
            refreshInboxReminders()
        } catch { inbox = nil; inboxStartupError = error.localizedDescription }
    }
    func refreshLists(includeFeeds: Bool = false) async {
        guard !isRefreshingLists else { return }
        isRefreshingLists = true
        defer { isRefreshingLists = false }
        await sync?.syncNow()
        await appleReminders.refresh()
        appleCalendar.refreshRevision += 1
        do { try reload() } catch { self.error = error.localizedDescription }
        refreshInboxReminders()
        if includeFeeds { await inbox?.refresh(force: true) }
    }
    func refreshInboxReminders() {
        let now = Date()
        inbox?.reconcileReminders(ReminderPlanner.requests(snapshot: snapshot, now: now, defaults: reminderDefaults), now: now)
    }
    func saveReminderDefaults(_ value: ReminderDefaults) {
        do {
            let data = try JSONEncoder().encode(value)
            reminderSettingsStore.set(data, forKey: "routine.reminderDefaults")
            reminderDefaults = value
            refreshNotifications()
        } catch { self.error = error.localizedDescription }
    }
    func refreshNotifications() { refreshInboxReminders(); notifications.enqueue(snapshot: snapshot, defaults: reminderDefaults) }
    func steps(for r: Routine) -> [RoutineStep] { snapshot.steps.filter { $0.routineID == r.id }.sorted { $0.sortOrder < $1.sortOrder } }
    func record(_ r: Routine, date: Date) -> RoutineDayRecord? { snapshot.records.first { $0.routineID == r.id && $0.dayKey == RoutineRules.dayKey(date) } }
}
