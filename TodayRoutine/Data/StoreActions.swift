import Foundation
extension RoutineStore {
    func upsertRoutine(_ d: RoutineDraft) throws {
        let name = d.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw StoreError.invalid("루틴 이름을 입력해 주세요.") }
        guard d.repeatKind != .weekdays || (!d.weekdays.isEmpty && d.weekdays.allSatisfy { (1...7).contains($0) }) else { throw StoreError.invalid("반복할 요일을 선택해 주세요.") }
        guard (1...7).contains(d.weeklyTarget), d.minute == nil || (0..<1440).contains(d.minute!) else { throw StoreError.invalid("시간과 주간 목표를 확인해 주세요.") }
        guard d.durationMinutes == nil || (1...1440).contains(d.durationMinutes!) else { throw StoreError.invalid("소요시간은 1~1440분으로 입력해 주세요.") }
        guard d.steps.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { throw StoreError.invalid("단계 이름을 입력하거나 빈 단계를 삭제해 주세요.") }
        let snapshot = try loadSnapshot()
        if d.repeatKind == .weeklyGoal {
            guard let existing = snapshot.routines.first(where: { $0.id == d.id }),
                  existing.repeatKind == .weeklyGoal, existing.weeklyTarget == d.weeklyTarget else {
                throw StoreError.invalid("주간 목표 방식은 더 이상 사용할 수 없습니다. 매일 또는 요일 선택을 사용해 주세요.")
            }
        }
        try transaction {
            let r = snapshot.routines.first { $0.id == d.id } ?? Routine(id: d.id, name: name, sortOrder: (snapshot.routines.map(\.sortOrder).max() ?? -1) + 1)
            if r.modelContext == nil { context.insert(r) }
            if r.calendarLink == nil {
                r.name = name; r.repeatKind = d.repeatKind; r.weekdays = d.weekdays; r.weeklyTarget = d.weeklyTarget; r.minute = d.minute; r.durationMinutes = d.durationMinutes
            }
            r.note = d.note; r.groupID = d.groupID; r.status = d.status; r.updatedAt = Date()
            let previous = snapshot.steps.filter { $0.routineID == r.id }
            for step in previous where !d.steps.contains(where: { $0.id == step.id }) { context.delete(step) }
            for (index, step) in d.steps.enumerated() {
                let model = previous.first { $0.id == step.id } ?? RoutineStep(id: step.id, routineID: r.id, name: step.name)
                if model.modelContext == nil { context.insert(model) }
                model.name = step.name.trimmingCharacters(in: .whitespacesAndNewlines); model.sortOrder = index; model.updatedAt = Date()
            }
            // Only today's derived step state changes; history snapshots are immutable.
            if let record = snapshot.records.first(where: { $0.routineID == r.id && $0.dayKey == RoutineRules.dayKey(Date()) }), record.status != .skipped, !d.steps.isEmpty {
                let valid = Set(d.steps.map(\.id)); record.completedStepIDs = record.completedStepIDs.filter { valid.contains($0) }
                record.status = valid.isSubset(of: Set(record.completedStepIDs)) ? .completed : .pending
                if record.status != .completed { record.completedAt = nil }; record.updatedAt = Date()
            }
        }
    }
    private func record(routineID: UUID, date: Date, snapshot: StoreSnapshot) throws -> RoutineDayRecord {
        let key = RoutineRules.dayKey(date)
        if let record = snapshot.records.first(where: { $0.routineID == routineID && $0.dayKey == key }) { return record }
        guard let r = snapshot.routines.first(where: { $0.id == routineID }) else { throw StoreError.invalid("루틴을 찾지 못했습니다.") }
        let record = RoutineDayRecord(routineID: routineID, dayKey: key, name: r.name); context.insert(record); return record
    }
    func setDayMinute(routineID: UUID, date: Date, minute: Int?) throws {
        guard minute == nil || (0..<1440).contains(minute!) else { throw StoreError.invalid("시간 범위를 확인해 주세요.") }
        let snapshot = try loadSnapshot()
        guard snapshot.routines.first(where: { $0.id == routineID })?.calendarLink == nil else { throw StoreError.invalid("캘린더 루틴의 시간은 Apple 캘린더에서 변경해 주세요.") }
        try transaction {
            let r = try record(routineID: routineID, date: date, snapshot: snapshot)
            r.minuteOverride = minute; r.updatedAt = Date()
        }
    }
    func linkCalendarRoutine(id: UUID, link: CalendarRoutineLink) throws {
        guard let routine = try loadSnapshot().routines.first(where: { $0.id == id }) else { throw StoreError.invalid("루틴을 찾을 수 없습니다.") }
        guard routine.calendarLink == nil || routine.calendarLink == link else { throw StoreError.invalid("이미 다른 캘린더 일정에 연결된 루틴입니다.") }
        try transaction { routine.calendarLink = link; routine.updatedAt = Date() }
    }
    func setStatus(routineID: UUID, date: Date, status: DayStatus) throws {
        let snapshot = try loadSnapshot()
        try transaction {
            let r = try record(routineID: routineID, date: date, snapshot: snapshot)
            syncDayCommand = (r.key, status)
            r.status = status; r.completedAt = status == .completed ? Date() : nil; r.updatedAt = Date()
            r.completedStepIDs = status == .completed ? snapshot.steps.filter { $0.routineID == routineID }.map(\.id) : []
        }
    }
    func toggleStep(routineID: UUID, stepID: UUID, date: Date) throws {
        let snapshot = try loadSnapshot(), valid = Set(try loadSnapshot().steps.filter { $0.routineID == routineID }.map(\.id))
        guard valid.contains(stepID) else { throw StoreError.invalid("단계를 찾지 못했습니다.") }
        try transaction {
            let r = try record(routineID: routineID, date: date, snapshot: snapshot)
            var ids = Set(r.completedStepIDs).intersection(valid)
            if ids.contains(stepID) { ids.remove(stepID) } else { ids.insert(stepID) }
            r.completedStepIDs = Array(ids); r.status = ids == valid ? .completed : .pending; r.completedAt = r.status == .completed ? Date() : nil; r.updatedAt = Date()
        }
    }
    func deleteGroup(id: UUID) throws {
        let s = try loadSnapshot(); try transaction {
            for r in s.routines where r.groupID == id { r.groupID = nil; r.updatedAt = Date() }
            for g in s.groups where g.id == id { context.delete(g) }
        }
    }
    func saveGroup(id: UUID?, name: String) throws {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines); guard !clean.isEmpty else { throw StoreError.invalid("그룹 이름을 입력해 주세요.") }
        let s = try loadSnapshot(); try transaction {
            let g = s.groups.first { $0.id == id } ?? RoutineGroup(name: clean, sortOrder: s.groups.count)
            if g.modelContext == nil { context.insert(g) }; g.name = clean; g.updatedAt = Date()
        }
    }
    func reorder(_ orderedIDs: [UUID]) throws {
        let s = try loadSnapshot(); try transaction { for (i,id) in orderedIDs.enumerated() { if let r = s.routines.first(where: { $0.id == id }) { r.sortOrder = i; r.updatedAt = Date() } } }
    }
    func useDefaultReminder(routineID: UUID? = nil) throws {
        let preferences = try loadSnapshot().reminders
        try transaction {
            for preference in preferences where routineID == nil || preference.routineID == routineID {
                context.delete(preference)
            }
        }
    }
    func saveReminder(routineID: UUID, enabled: Bool, minute: Int) throws {
        guard (0..<1440).contains(minute) else { throw StoreError.invalid("알림 시간을 확인해 주세요.") }
        let s = try loadSnapshot(); try transaction {
            let p = s.reminders.first { $0.routineID == routineID } ?? ReminderPreference(routineID: routineID)
            if p.modelContext == nil { context.insert(p) }; p.enabled = enabled; p.minute = minute; p.updatedAt = Date()
        }
    }
}
