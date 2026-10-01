import Foundation
struct CSVConflict: Identifiable, Equatable { var id: String; var date: String; var column: String; var appValue: Bool; var csvValue: Bool; var operation: SyncOperation }
struct CSVImportResult { var operations: [SyncOperation] = []; var conflicts: [CSVConflict] = [] }
enum CSVImporter {
    static func diff(data: Data, baseline: RoutineCSVDocument, current: SyncState) throws -> CSVImportResult {
        guard baseline.version == 1 else { throw SyncError.invalid("CSV 기준 정보의 버전이 다릅니다.") }
        let rows = try CSVCodec.decode(data)
        guard let header = rows.first, header.first == "날짜", Set(header).count == header.count else { throw SyncError.invalid("CSV 첫 열은 날짜이고 열 이름은 중복될 수 없습니다.") }
        let mapping = Dictionary(uniqueKeysWithValues:baseline.columns.map { ($0.title,$0.stepID) })
        guard header.dropFirst().allSatisfy({ mapping[$0] != nil }) else { throw SyncError.invalid("알 수 없는 세부작업 열입니다. 열 이름 변경은 앱에서 해주세요.") }
        var dates: Set<String> = [], result = CSVImportResult()
        for (index,row) in rows.dropFirst().enumerated() {
            if row.allSatisfy(\.isEmpty) { continue }
            guard row.count == header.count, let date = row.first, RoutineRules.date(for:date) != nil, dates.insert(date).inserted else { throw SyncError.invalid("CSV \(index+2)행: 날짜 중복 또는 잘못된 열/날짜입니다.") }
            let id = baseline.routineID.uuidString+"/"+date, key = "record/"+id
            var values: [String:String] = [:]
            for n in 1..<row.count {
                let raw = row[n].trimmingCharacters(in:.whitespacesAndNewlines).uppercased()
                if raw.isEmpty { continue }; guard ["TRUE","FALSE"].contains(raw) else { throw SyncError.invalid("CSV \(index+2)행 \(header[n]): TRUE 또는 FALSE를 입력해 주세요.") }
                let step = mapping[header[n]]!, edited = raw == "TRUE"
                let old = baseline.value(date:date,stepID:step,state:baseline.state)
                // A previously inapplicable historical step cannot silently become part of that day's schema.
                if old == nil { throw SyncError.invalid("CSV \(index+2)행: 해당 날짜에 없는 단계입니다.") }
                guard edited != old || !baseline.dates.contains(date) else { continue }
                let actual = baseline.value(date:date,stepID:step,state:current) ?? false
                let field = step == "_complete" ? "status" : "step/"+step
                let newValue = step == "_complete" ? (edited ? "completed":"pending") : (edited ? "true":"false")
                let operation = SyncOperation(kind:.record,id:id,values:[field:newValue])
                if current.version(key,field) != baseline.state.version(key,field) && actual != edited {
                    result.conflicts.append(CSVConflict(id:SyncCoding.hash(Data((baseline.documentID.uuidString+id+field+raw).utf8)),date:date,column:header[n],appValue:actual,csvValue:edited,operation:operation))
                } else { values[field] = newValue }
            }
            if !values.isEmpty {
                if current.objects[key] == nil {
                    values["routineID"] = baseline.routineID.uuidString; values["dayKey"] = date; values["nameSnapshot"] = baseline.name
                    let ids = baseline.columns.filter { $0.stepID != "_complete" }.map(\.stepID)
                    values["stepIDs"] = ids.joined(separator:",")
                    values["stepNames"] = String(data:try SyncCoding.encode(Dictionary(uniqueKeysWithValues:baseline.columns.map { ($0.stepID,$0.title) })),encoding:.utf8)
                }
                result.operations.append(SyncOperation(kind:.record,id:id,values:values))
            }
        }
        return result
    }
    static func event(_ operations: [SyncOperation], document: RoutineCSVDocument) throws -> SyncEvent {
        let bytes = try SyncCoding.encode(operations)
        return SyncEvent(spaceID:document.spaceID,id:SyncCoding.stableID(document.documentID.uuidString+SyncCoding.hash(bytes)),deviceID:document.documentID,counter:document.state.counter+1,createdAt:document.createdAt,operations:operations)
    }
}
