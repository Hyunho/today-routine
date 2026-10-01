import Foundation
struct CSVColumn: Codable, Equatable { var title: String; var stepID: String }
struct RoutineCSVDocument: Codable, Equatable {
    var version = 1; var spaceID: UUID; var documentID: UUID; var revisionID: String; var routineID: UUID; var name: String
    var columns: [CSVColumn]; var state: SyncState; var dates: [String]; var createdAt: Date
    var csv: Data { CSVCodec.encode([["날짜"]+columns.map(\.title)] + dates.sorted().map { date in
        [date] + columns.map { c in value(date:date,stepID:c.stepID,state:state).map { $0 ? "TRUE":"FALSE" } ?? "" }
    }) }
    func value(date: String, stepID: String, state: SyncState) -> Bool? {
        let record = state.objects["record/"+routineID.uuidString+"/"+date]
        if stepID == "_complete" {
            if let ids = record?.fields["stepIDs"], !ids.isEmpty { return nil }
            if record == nil && state.objects.values.contains(where: { $0.kind == .step && $0.fields["routineID"] == routineID.uuidString }) { return nil }
            return record?.fields["status"] == "completed"
        }
        let applicable = record?.fields["stepIDs"].map { $0.split(separator:",").map(String.init) }
        if let applicable, !applicable.contains(stepID) { return nil }
        if applicable == nil && state.objects["step/"+stepID] == nil { return nil }
        return record?.fields["step/"+stepID] == "true"
    }
    static func make(routineID: UUID, spaceID: UUID, state: SyncState, today: Date) throws -> RoutineCSVDocument {
        guard let routine = state.objects["routine/"+routineID.uuidString] else { throw SyncError.invalid("CSV 루틴을 찾을 수 없습니다.") }
        let records = state.objects.values.filter { $0.kind == .record && $0.fields["routineID"] == routineID.uuidString }
        let steps = state.objects.values.filter { $0.kind == .step && $0.fields["routineID"] == routineID.uuidString }.sorted { (Int($0.fields["sortOrder"] ?? "") ?? 0,$0.id) < (Int($1.fields["sortOrder"] ?? "") ?? 0,$1.id) }
        var names: [String:String] = [:], ids = steps.map(\.id)
        for step in steps { names[step.id] = step.fields["name"] ?? "단계" }
        for record in records.sorted(by:{$0.id < $1.id}) {
            let oldNames = (record.fields["stepNames"].flatMap { try? SyncCoding.decode([String:String].self,from:Data($0.utf8)) }) ?? [:]
            for id in (record.fields["stepIDs"] ?? "").split(separator:",").map(String.init) where !ids.contains(id) { ids.append(id); names[id] = oldNames[id] ?? "과거 단계" }
        }
        var used: Set<String> = ["날짜"], columns: [CSVColumn] = []
        for id in ids { let base = CSVCodec.safeTitle(names[id] ?? "단계"); var title = base; var n = 2
            while used.contains(title) { title = "\(base) (\(n))"; n += 1 }; used.insert(title); columns.append(CSVColumn(title:title,stepID:id))
        }
        if steps.isEmpty || records.contains(where: { ($0.fields["stepIDs"] ?? "").isEmpty }) {
            var title = "완료"; while used.contains(title) { title += " (전체)" }
            columns.append(CSVColumn(title:title,stepID:"_complete"))
        }
        let dates = Set(records.compactMap { $0.fields["dayKey"] }).union([RoutineRules.dayKey(today)]).sorted()
        let revision = SyncCoding.hash(try SyncCoding.encode(state)+Data(RoutineRules.dayKey(today).utf8))
        return RoutineCSVDocument(spaceID:spaceID,documentID:SyncCoding.stableID(spaceID.uuidString+routineID.uuidString+revision),revisionID:revision,routineID:routineID,name:routine.fields["name"] ?? "루틴",columns:columns,state:state,dates:dates,createdAt:Date(timeIntervalSince1970:0))
    }
}
