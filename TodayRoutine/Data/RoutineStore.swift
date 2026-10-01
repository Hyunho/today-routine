import Foundation
import SwiftData
struct StoreSnapshot {
    var routines: [Routine] = []; var steps: [RoutineStep] = []; var groups: [RoutineGroup] = []
    var records: [RoutineDayRecord] = []; var tasks: [TaskItem] = []; var blocks: [TimeBlock] = []; var reminders: [ReminderPreference] = []
}
enum StoreError: LocalizedError { case invalid(String)
    var errorDescription: String? { switch self { case .invalid(let message): message } }
}
enum PersistenceFactory {
    static func make(url: URL? = nil, inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema([Routine.self, RoutineStep.self, RoutineGroup.self, RoutineDayRecord.self, TaskItem.self, TimeBlock.self, ReminderPreference.self])
        let config: ModelConfiguration
        if let url, !inMemory {
            if FileManager.default.fileExists(atPath: url.path) {
                let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
                let header = try handle.read(upToCount: 16) ?? Data()
                guard header == Data("SQLite format 3\0".utf8) else { throw StoreError.invalid("저장 파일을 읽을 수 없습니다. 기존 파일은 유지됩니다.") }
            }
            config = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        } else { config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none) }
        return try ModelContainer(for: schema, configurations: [config])
    }
}
@MainActor final class RoutineStore {
    let container: ModelContainer; let context: ModelContext
    init(container: ModelContainer) { self.container = container; context = ModelContext(container); context.autosaveEnabled = false }
    func save() throws { try context.save() }
    func loadSnapshot() throws -> StoreSnapshot {
        try StoreSnapshot(routines: context.fetch(FetchDescriptor<Routine>()), steps: context.fetch(FetchDescriptor<RoutineStep>()), groups: context.fetch(FetchDescriptor<RoutineGroup>()), records: context.fetch(FetchDescriptor<RoutineDayRecord>()), tasks: context.fetch(FetchDescriptor<TaskItem>()), blocks: context.fetch(FetchDescriptor<TimeBlock>()), reminders: context.fetch(FetchDescriptor<ReminderPreference>()))
    }
    func transaction(_ body: () throws -> Void) throws {
        do { try body(); try save() } catch { context.rollback(); throw error }
    }
}
