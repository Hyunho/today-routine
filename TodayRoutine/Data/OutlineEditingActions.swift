import Foundation

extension RoutineStore {
    func editOutlineRoutine(id: UUID, date: Date, original: String, line: String) throws {
        let edit = try OutlineEdit(line: line, expectsStatus: true)
        let snapshot = try loadSnapshot()
        guard let routine = snapshot.routines.first(where: { $0.id == id }), routine.calendarLink == nil else {
            throw StoreError.invalid("편집할 루틴을 찾지 못했거나 외부 캘린더에서 관리하는 항목입니다.")
        }
        let day = RoutineRules.dayKey(date)
        guard day >= RoutineRules.dayKey(Date()) else { throw StoreError.invalid("지난 날짜의 기록은 이 편집기에서 변경할 수 없습니다.") }
        let existing = snapshot.records.first { $0.routineID == id && $0.dayKey == day }
        let minute = RoutineRules.minute(routine, records: snapshot.records, on: date)
        guard original == OutlineEdit.line(title: routine.name, minute: minute, status: existing?.status ?? .pending) else {
            throw StoreError.invalid("원본이 변경되었습니다. 입력 내용을 복사한 뒤 편집을 다시 열어 주세요.")
        }
        guard edit.minute != nil || routine.minute == nil else {
            throw StoreError.invalid("기본 시간이 있는 루틴입니다. 시간을 HH:mm 형식으로 입력해 주세요.")
        }
        try transaction {
            let record = existing ?? RoutineDayRecord(routineID: id, dayKey: day, name: routine.name)
            if record.modelContext == nil { context.insert(record) }
            routine.name = edit.title; routine.updatedAt = Date()
            record.nameSnapshot = edit.title; record.minuteOverride = edit.minute
            let status = edit.status!
            if record.status != status {
                syncDayCommand = (record.key, status)
                record.status = status; record.completedAt = status == .completed ? Date() : nil
                record.completedStepIDs = status == .completed ? snapshot.steps.filter { $0.routineID == id }.map(\.id) : []
            }
            record.updatedAt = Date()
        }
    }

    func editOutlineBlock(id: UUID, original: String, line: String) throws {
        let edit = try OutlineEdit(line: line, expectsStatus: false)
        guard let block = try loadSnapshot().blocks.first(where: { $0.id == id }) else { throw StoreError.invalid("시간 블록을 찾지 못했습니다.") }
        guard original == OutlineEdit.line(title: block.title, minute: block.startMinute, status: nil) else {
            throw StoreError.invalid("원본이 변경되었습니다. 입력 내용을 복사한 뒤 편집을 다시 열어 주세요.")
        }
        let duration = block.endMinute - block.startMinute
        guard let start = edit.minute, start + duration < 1440 else {
            throw StoreError.invalid("시작 시간을 입력하고 블록의 끝이 같은 날 안에 오도록 해 주세요.")
        }
        try transaction {
            block.title = edit.title; block.startMinute = start; block.endMinute = start + duration; block.updatedAt = Date()
        }
    }
}
