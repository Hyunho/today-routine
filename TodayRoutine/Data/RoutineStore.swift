import Foundation
import SwiftData
struct StoreSnapshot {
    var todayDocuments: [TodayDocumentRecord] = []
    var routines: [Routine] = []; var steps: [RoutineStep] = []; var groups: [RoutineGroup] = []
    var records: [RoutineDayRecord] = []; var tasks: [TaskItem] = []; var blocks: [TimeBlock] = []; var reminders: [ReminderPreference] = []
}
enum StoreError: LocalizedError { case invalid(String)
    var errorDescription: String? { switch self { case .invalid(let message): message } }
}
enum PersistenceFactory {
    private static func backupBeforeFirstSyncUpgrade(_ url: URL) throws {
        let fm = FileManager.default, destination = url.appendingPathExtension("pre-sync-v1")
        guard fm.fileExists(atPath:url.path), !fm.fileExists(atPath:destination.path) else { return }
        let staging = url.appendingPathExtension("backup-"+UUID().uuidString)
        try fm.createDirectory(at:staging,withIntermediateDirectories:true)
        do {
            // Startup only: no ModelContainer has opened this app's private store yet.
            for suffix in ["","-wal","-shm"] {
                let source = URL(fileURLWithPath:url.path+suffix)
                if fm.fileExists(atPath:source.path) { try fm.copyItem(at:source,to:staging.appendingPathComponent(source.lastPathComponent)) }
            }
            try fm.moveItem(at:staging,to:destination)
        } catch { try? fm.removeItem(at:staging); throw error }
    }
    static func make(url: URL? = nil, inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema([Routine.self, RoutineStep.self, RoutineGroup.self, RoutineDayRecord.self, TaskItem.self, TimeBlock.self, ReminderPreference.self, TodayDocumentRecord.self, SyncJournalEntry.self, SyncDeviceState.self])
        let config: ModelConfiguration
        if let url, !inMemory {
            if FileManager.default.fileExists(atPath: url.path) {
                let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
                let header = try handle.read(upToCount: 16) ?? Data()
                guard header == Data("SQLite format 3\0".utf8) else { throw StoreError.invalid("저장 파일을 읽을 수 없습니다. 기존 파일은 유지됩니다.") }
            }
            config = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        } else { config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none) }
        if !inMemory { try backupBeforeFirstSyncUpgrade(config.url) }
        return try ModelContainer(for: schema, configurations: [config])
    }
}
@MainActor final class RoutineStore {
    let container: ModelContainer; let context: ModelContext
    var syncApplying = false
    var syncDayCommand: (String, DayStatus)?
    var syncDayCommands: [String: DayStatus] = [:]
    var saveOperation: ((ModelContext) throws -> Void)?
    init(container: ModelContainer) { self.container = container; context = ModelContext(container); context.autosaveEnabled = false }
    func save() throws { if let saveOperation { try saveOperation(context) } else { try context.save() } }
    func loadSnapshot() throws -> StoreSnapshot {
        try StoreSnapshot(todayDocuments: context.fetch(FetchDescriptor<TodayDocumentRecord>()), routines: context.fetch(FetchDescriptor<Routine>()), steps: context.fetch(FetchDescriptor<RoutineStep>()), groups: context.fetch(FetchDescriptor<RoutineGroup>()), records: context.fetch(FetchDescriptor<RoutineDayRecord>()), tasks: context.fetch(FetchDescriptor<TaskItem>()), blocks: context.fetch(FetchDescriptor<TimeBlock>()), reminders: context.fetch(FetchDescriptor<ReminderPreference>()))
    }
    func transaction(_ body: () throws -> Void) throws {
        let adapter = StoreSyncAdapter(store: self)
        let before: [String:SyncObject]?
        if !syncApplying, try adapter.configuration() != nil { before = try StoreSyncBridge.objects(loadSnapshot()) } else { before = nil }
        defer { syncDayCommand = nil; syncDayCommands = [:] }
        do { try body(); if let before { try adapter.capture(before: before) }; try save() } catch { context.rollback(); throw error }
    }
}
