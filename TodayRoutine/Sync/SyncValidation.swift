import Foundation
enum SyncValidation {
    static let common: Set<String> = ["createdAt","updatedAt"]
    static let fields: [SyncKind:Set<String>] = [
        .routine:["name","note","repeatRaw","weekdays","weeklyTarget","minute","groupID","sortOrder","statusRaw"],
        .step:["routineID","name","sortOrder"], .group:["name","sortOrder"],
        .record:["routineID","dayKey","status","stepIDs","nameSnapshot","completedAt","stepNames","command"],
        .task:["title","note","dayKey","minute","completedAt"],
        .block:["title","dayKey","startMinute","endMinute","linkedID","linkedKind"]]
    static func validate(_ event: SyncEvent) throws {
        guard event.version == 1 else { throw SyncError.invalid("새 동기화 형식입니다. 앱 업데이트가 필요합니다.") }
        guard event.counter >= 0, event.counter < Int64.max, !event.operations.isEmpty, event.operations.count <= 10000 else { throw SyncError.invalid("잘못된 변경 기록입니다.") }
        for op in event.operations {
            if op.kind == .record {
                let p = op.id.split(separator:"/"); guard p.count == 2, UUID(uuidString:String(p[0])) != nil, RoutineRules.date(for:String(p[1])) != nil else { throw SyncError.invalid("잘못된 날짜 기록 ID입니다.") }
            } else { guard UUID(uuidString:op.id) != nil else { throw SyncError.invalid("잘못된 항목 ID입니다.") } }
            for (key,value) in op.values {
                if key.hasPrefix("step/") && op.kind == .record {
                    guard UUID(uuidString:String(key.dropFirst(5))) != nil, ["true","false"].contains(value) else { throw SyncError.invalid("잘못된 단계 완료 값입니다.") }; continue
                }
                guard common.contains(key) || fields[op.kind]!.contains(key), value.utf8.count <= 1_000_000 else { throw SyncError.invalid("지원하지 않는 필드: \(key)") }
                if ["routineID","groupID","linkedID"].contains(key), !value.isEmpty, UUID(uuidString:value) == nil { throw SyncError.invalid("잘못된 연결 ID입니다.") }
                if key == "dayKey", !value.isEmpty, RoutineRules.date(for:value) == nil { throw SyncError.invalid("날짜 형식을 확인해 주세요.") }
                if ["minute","startMinute","endMinute"].contains(key), !value.isEmpty { guard let n = Int(value), (0..<1440).contains(n) else { throw SyncError.invalid("시간 범위를 확인해 주세요.") } }
                if key == "sortOrder" { guard let n = Int(value), abs(Double(n)) < 1e9 else { throw SyncError.invalid("순서 범위를 확인해 주세요.") } }
                if key == "weeklyTarget" { guard let n = Int(value), (1...7).contains(n) else { throw SyncError.invalid("주간 목표를 확인해 주세요.") } }
                if key == "repeatRaw", RepeatKind(rawValue:value) == nil { throw SyncError.invalid("반복 형식 오류") }
                if key == "statusRaw", RoutineStatus(rawValue:value) == nil { throw SyncError.invalid("루틴 상태 오류") }
                if ["status","command"].contains(key), DayStatus(rawValue:value) == nil { throw SyncError.invalid("완료 상태 오류") }
                if key == "weekdays", value.split(separator:",").contains(where:{ Int($0).map { !(1...7).contains($0) } ?? true }) { throw SyncError.invalid("요일 오류") }
                if key == "stepIDs", value.split(separator:",").contains(where:{ UUID(uuidString:String($0)) == nil }) { throw SyncError.invalid("단계 ID 오류") }
                if ["createdAt","updatedAt","completedAt"].contains(key), !value.isEmpty { guard let d = Double(value), d.isFinite, abs(d) < 1e12 else { throw SyncError.invalid("시각 오류") } }
                if key == "stepNames" { guard let d = value.data(using:.utf8), (try? JSONDecoder().decode([String:String].self,from:d)) != nil else { throw SyncError.invalid("과거 단계 정보 오류") } }
                if key == "linkedKind", !["","routine","task"].contains(value) { throw SyncError.invalid("연결 종류 오류") }
            }
        }
    }
}
