import SwiftUI
import SwiftData

@main struct TodayRoutineApp: App {
    @State private var model = AppModel()
    var body: some Scene { WindowGroup { RootView(model: model).tint(.teal).environment(\.locale, Locale(identifier: "ko_KR")).environment(\.calendar, RoutineRules.calendar).environment(\.timeZone, RoutineRules.calendar.timeZone) } }
}
@MainActor @Observable final class AppModel {
    var store: RoutineStore?
    var snapshot = StoreSnapshot()
    var sync: SyncCoordinator?
    var presentedSheets = 0
    var error: String?
    var startupError: String?
    var revision = 0
    let notifications = NotificationService()
    init() { open() }
    func open() {
        do {
            var url: URL?
            #if DEBUG
            if let index = ProcessInfo.processInfo.arguments.firstIndex(of: "--uitest-store"), ProcessInfo.processInfo.arguments.count > index+1, let id = UUID(uuidString: ProcessInfo.processInfo.arguments[index+1]) {
                url = URL.applicationSupportDirectory.appendingPathComponent("UITest-\(id.uuidString).store")
            }
            #endif
            store = RoutineStore(container: try PersistenceFactory.make(url: url))
            #if DEBUG
            if url != nil && ProcessInfo.processInfo.arguments.contains("--uitest-fail-save-once") {
                var fail = true
                store?.saveOperation = { context in
                    if fail { fail = false; throw CocoaError(.fileWriteOutOfSpace) }
                    try context.save()
                }
            }
            #endif
            startupError = nil; try reload()
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
    func reload() throws { if let store { snapshot = try store.loadSnapshot(); revision += 1 } }
    @discardableResult func perform(_ action: (RoutineStore) throws -> Void) -> Bool {
        guard let store else { return false }
        do { try action(store); try reload(); refreshNotifications(); sync?.localDataDidChange(); return true }
        catch { self.error = error.localizedDescription; try? reload(); return false }
    }
    func refreshNotifications() { notifications.enqueue(snapshot: snapshot) }
    func steps(for r: Routine) -> [RoutineStep] { snapshot.steps.filter { $0.routineID == r.id }.sorted { $0.sortOrder < $1.sortOrder } }
    func record(_ r: Routine, date: Date) -> RoutineDayRecord? { snapshot.records.first { $0.routineID == r.id && $0.dayKey == RoutineRules.dayKey(date) } }
}
