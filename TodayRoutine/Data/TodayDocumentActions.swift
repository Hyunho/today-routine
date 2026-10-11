import Foundation
import SwiftData

extension RoutineStore {
    private func documentRecord(_ day: String) throws -> TodayDocumentRecord? {
        try context.fetch(FetchDescriptor<TodayDocumentRecord>()).first { $0.dayKey == day }
    }

    private func documentSources(day: String) throws -> [TodayDocumentSource] {
        guard let date = RoutineRules.date(for: day) else { throw StoreError.invalid("날짜가 올바르지 않습니다.") }
        let snapshot = try loadSnapshot()
        var result: [TodayDocumentSource] = []
        for routine in snapshot.routines where routine.calendarLink == nil && RoutineRules.visible(routine, records: snapshot.records, on: date, now: Date()) {
            let record = snapshot.records.first { $0.routineID == routine.id && $0.dayKey == day }
            result.append(TodayDocumentSource(id: routine.id, kind: .routine,
                text: OutlineEdit.line(title: routine.name, minute: RoutineRules.minute(routine, records: snapshot.records, on: date), status: record?.status ?? .pending), sortOrder: routine.sortOrder))
            for step in snapshot.steps.filter({ $0.routineID == routine.id }).sorted(by: { $0.sortOrder < $1.sortOrder }) {
                result.append(TodayDocumentSource(id: step.id, kind: .step, parentID: routine.id,
                    text: OutlineEdit.line(title: step.name, minute: nil, status: record?.completedStepIDs.contains(step.id) == true ? .completed : .pending), sortOrder: step.sortOrder))
            }
        }
        for block in snapshot.blocks where block.dayKey == day {
            result.append(TodayDocumentSource(id: block.id, kind: .block,
                text: OutlineEdit.line(title: block.title, minute: block.startMinute, status: nil), duration: block.endMinute - block.startMinute))
        }
        return result.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    func openTodayDocument(day: String) throws -> (TodayDocument, Int) {
        let sources = try documentSources(day: day)
        let record = try documentRecord(day)
        let savedDocument = try record.map { try JSONDecoder().decode(TodayDocument.self, from: $0.payload) }
        var document = savedDocument ?? TodayDocument(dayKey: day)
        if !document.needsApply {
            let previous = Set(document.baseline.map(\.id)), current = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0) })
            func refresh(_ nodes: [TodayDocumentBlock]) -> [TodayDocumentBlock] {
                nodes.flatMap { node -> [TodayDocumentBlock] in
                    if previous.contains(node.id) && current[node.id] == nil {
                        let children = refresh(node.children)
                        let notes = node.text.split(separator: "\n", omittingEmptySubsequences: false).dropFirst().joined(separator: "\n")
                        return notes.isEmpty ? children : [TodayDocumentBlock(text: notes, children: children)]
                    }
                    var node = node
                    if let source = current[node.id] {
                        let extra = node.text.split(separator: "\n", omittingEmptySubsequences: false).dropFirst().joined(separator: "\n")
                        let marker = source.kind == .block ? self.documentMarker(node.text) : ""
                        node.text = marker + source.text + (extra.isEmpty ? "" : "\n" + extra)
                    }
                    node.children = refresh(node.children)
                    return [node]
                }
            }
            document.blocks = refresh(document.blocks)
            document.links.removeAll { previous.contains($0.id) && current[$0.id] == nil }
            var present = Set(document.blocks.flatMap(\.flattened).map(\.id))
            let ordered = sources.sorted { $0.sortOrder == $1.sortOrder ? $0.id.uuidString < $1.id.uuidString : $0.sortOrder < $1.sortOrder }
            for source in ordered where source.kind != .step && !present.contains(source.id) && !document.hiddenRoutineIDs.contains(source.id) {
                let children = ordered.filter { $0.parentID == source.id && !present.contains($0.id) }.map { TodayDocumentBlock(id: $0.id, text: $0.text) }
                document.blocks.append(TodayDocumentBlock(id: source.id, text: source.text, children: children))
                present.formUnion([source.id] + children.map(\.id))
            }
            // Newly added steps join their existing routine without flattening user nesting.
            func addSteps(_ nodes: [TodayDocumentBlock]) -> [TodayDocumentBlock] {
                nodes.map { node in
                    var node = node; node.children = addSteps(node.children)
                    node.children += ordered.filter { $0.parentID == node.id && !present.contains($0.id) }.map { TodayDocumentBlock(id: $0.id, text: $0.text) }
                    return node
                }
            }
            document.blocks = addSteps(document.blocks)
            if document.blocks.isEmpty { document.blocks = [TodayDocumentBlock(text: "")] }
            document.baseline = sources; document.appliedBlocks = document.blocks
            for source in sources {
                if let i = document.links.firstIndex(where: { $0.id == source.id }) { document.links[i] = source }
                else { document.links.append(source) }
            }
        }
        let payload = try JSONEncoder().encode(document)
        if let record {
            if savedDocument != document { try transaction { record.payload = payload; record.revision += 1 } }
            return (document, record.revision)
        }
        let created = TodayDocumentRecord(dayKey: day, payload: payload)
        try transaction { context.insert(created) }
        return (document, created.revision)
    }

    private func documentMarker(_ text: String) -> String {
        let token = text.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? ""
        return ["TODO", "DONE", "SKIPPED", "DOING", "NOW", "LATER", "WAITING", "CANCELED", "CANCELLED"].contains(token) ? token + " " : ""
    }

    func discardTodayDocumentDraft(day: String, expectedRevision: Int) throws {
        guard let record = try documentRecord(day), record.revision == expectedRevision else { return }
        var document = try JSONDecoder().decode(TodayDocument.self, from: record.payload)
        document.blocks = document.appliedBlocks
        let payload = try JSONEncoder().encode(document)
        try transaction { record.payload = payload; record.revision += 1 }
    }

    func saveTodayDocumentDraft(_ draft: TodayDocument, expectedRevision: Int) throws -> Int {
        guard let record = try documentRecord(draft.dayKey), record.revision == expectedRevision else { throw StoreError.invalid("다른 창에서 문서가 변경되었습니다. 편집 내용을 사본으로 보관해 주세요.") }
        let flat = draft.blocks.flatMap(\.flattened)
        guard !draft.blocks.isEmpty, Set(flat.map(\.id)).count == flat.count else { throw StoreError.invalid("문서 블록 ID가 중복되거나 문서가 비어 있습니다.") }
        var document = try JSONDecoder().decode(TodayDocument.self, from: record.payload)
        document.blocks = draft.blocks
        let bytes = try JSONEncoder().encode(document)
        try transaction { record.payload = bytes; record.revision += 1 }
        return record.revision
    }

    private func parseDocumentLine(_ text: String) throws -> OutlineEdit {
        var line = String(text.split(separator: "\n", omittingEmptySubsequences: false).first ?? "")
        let markers = ["TODO", "DONE", "SKIPPED", "DOING", "NOW", "LATER", "WAITING", "CANCELED", "CANCELLED"]
        let first = line.split(separator: " ").first.map(String.init) ?? ""
        if markers.contains(first) {
            let status = first == "DONE" ? "DONE" : ["SKIPPED", "CANCELED", "CANCELLED"].contains(first) ? "SKIPPED" : "TODO"
            line = status + line.dropFirst(first.count)
        } else { line = "TODO " + line }
        return try OutlineEdit(line: line, expectsStatus: true)
    }

    func applyTodayDocument(day: String, expectedRevision: Int) throws -> (TodayDocument, Int) {
        guard let record = try documentRecord(day), record.revision == expectedRevision,
              let date = RoutineRules.date(for: day) else { throw StoreError.invalid("문서가 다른 곳에서 변경되었습니다.") }
        var document = try JSONDecoder().decode(TodayDocument.self, from: record.payload)
        if !document.needsApply { return (document, record.revision) }
        guard day >= RoutineRules.dayKey(Date()) else { throw StoreError.invalid("지난 날짜 문서의 원본 반영은 지원하지 않습니다. 초안은 보관됩니다.") }
        guard try documentSources(day: day) == document.baseline else { throw StoreError.invalid("목록이나 타임라인의 원본이 변경되었습니다. 문서를 사본으로 보관한 뒤 원본을 다시 불러와 주세요.") }
        let snapshot = try loadSnapshot(), nodes = document.blocks.flatMap(\.flattened)
        let ids = Set(nodes.map(\.id)), links = Dictionary(uniqueKeysWithValues: document.links.map { ($0.id, $0) })
        var parsed: [UUID: OutlineEdit] = [:]
        for node in nodes where !node.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            do { parsed[node.id] = try parseDocumentLine(node.text) }
            catch { throw StoreError.invalid("\(node.text.prefix(60)): \(error.localizedDescription)") }
        }
        document.hiddenRoutineIDs = document.links.filter { $0.kind == .routine && !ids.contains($0.id) }.map(\.id)
        var normalizedText: [UUID: String] = [:]
        // A parent status change propagates only to steps the user has not edited explicitly.
        let baseline = Dictionary(uniqueKeysWithValues: document.baseline.map { ($0.id, $0) })
        for node in nodes where links[node.id]?.kind == .step {
            if let parent = links[node.id]?.parentID, let parentEdit = parsed[parent],
               let oldParent = baseline[parent], let oldStep = baseline[node.id],
               String(node.text.split(separator: "\n", omittingEmptySubsequences: false).first ?? "") == oldStep.text,
               parentEdit.status != (try? parseDocumentLine(oldParent.text).status) {
                let stepTitle = parsed[node.id]?.title ?? oldStep.text
                let text = OutlineEdit.line(title: stepTitle, minute: nil, status: parentEdit.status == .completed ? .completed : .pending)
                parsed[node.id] = try parseDocumentLine(text); normalizedText[node.id] = text
            }
        }
        try transaction {
            var records = snapshot.records
            func dayRecord(_ routine: Routine) -> RoutineDayRecord {
                if let existing = records.first(where: { $0.routineID == routine.id && $0.dayKey == day }) { return existing }
                let created = RoutineDayRecord(routineID: routine.id, dayKey: day, name: routine.name)
                context.insert(created); records.append(created); return created
            }
            for node in nodes {
                guard let edit = parsed[node.id] else {
                    if links[node.id]?.kind == .routine || links[node.id]?.kind == .step { throw StoreError.invalid("루틴·단계의 제목은 비울 수 없습니다. 삭제하려면 블록 자체를 삭제해 주세요.") }
                    continue
                }
                switch links[node.id]?.kind {
                case .routine:
                    guard let routine = snapshot.routines.first(where: { $0.id == node.id }), routine.calendarLink == nil else { throw StoreError.invalid("연결된 루틴을 찾지 못했습니다.") }
                    guard edit.minute != nil || routine.minute == nil else { throw StoreError.invalid("\(edit.title): 기본 시간이 있는 루틴은 시간을 입력해 주세요.") }
                    routine.name = edit.title; routine.updatedAt = Date()
                    let dayRecord = dayRecord(routine)
                    dayRecord.nameSnapshot = edit.title; dayRecord.minuteOverride = edit.minute
                    if dayRecord.status != edit.status! {
                        dayRecord.status = edit.status!; dayRecord.completedAt = edit.status == .completed ? Date() : nil
                        dayRecord.completedStepIDs = edit.status == .completed ? snapshot.steps.filter { $0.routineID == routine.id }.map(\.id) : []
                    }
                    dayRecord.updatedAt = Date()
                case .step:
                    guard let parent = links[node.id]?.parentID, let routine = snapshot.routines.first(where: { $0.id == parent }) else { throw StoreError.invalid("단계의 루틴을 찾지 못했습니다.") }
                    let step = snapshot.steps.first { $0.id == node.id } ?? RoutineStep(id: node.id, routineID: parent, name: edit.title)
                    if step.modelContext == nil { context.insert(step) }
                    step.name = edit.title; step.sortOrder = nodes.firstIndex(where: { $0.id == node.id })!; step.updatedAt = Date()
                    let dayRecord = dayRecord(routine)
                    dayRecord.completedStepIDs.removeAll { $0 == step.id }
                    if edit.status == .completed { dayRecord.completedStepIDs.append(step.id) }
                    dayRecord.updatedAt = Date()
                case .block, nil:
                    if let start = edit.minute {
                        let duration = links[node.id]?.duration ?? 30
                        guard start + duration < 1440 else { throw StoreError.invalid("\(edit.title): 블록 종료 시간이 자정을 넘습니다.") }
                        let block = snapshot.blocks.first { $0.id == node.id } ?? TimeBlock(id: node.id, title: edit.title, dayKey: day, start: start, end: start + duration)
                        if block.modelContext == nil { context.insert(block) }
                        block.title = edit.title; block.startMinute = start; block.endMinute = start + duration; block.updatedAt = Date()
                        if links[node.id] == nil { document.links.append(TodayDocumentSource(id: node.id, kind: .block, text: node.text, duration: duration)) }
                    }
                }
            }
            for block in snapshot.blocks where block.dayKey == day && document.baseline.contains(where: { $0.id == block.id && $0.kind == .block }) {
                if !ids.contains(block.id) || parsed[block.id]?.minute == nil { context.delete(block) }
            }
            for step in snapshot.steps where document.baseline.contains(where: { $0.id == step.id && $0.kind == .step }) && !ids.contains(step.id) {
                // Deleting a whole routine hides the day; it must not delete its reusable steps.
                if !document.hiddenRoutineIDs.contains(step.routineID) {
                    context.delete(step)
                    for dayRecord in records where dayRecord.routineID == step.routineID && dayRecord.dayKey == day { dayRecord.completedStepIDs.removeAll { $0 == step.id } }
                }
            }
            // Explicit step edits derive the parent completion just like the list controls.
            let remainingSteps = try loadSnapshot().steps
            for routine in snapshot.routines where ids.contains(routine.id) && routine.calendarLink == nil {
                let stepIDs = Set(remainingSteps.filter { $0.routineID == routine.id }.map(\.id))
                guard !stepIDs.isEmpty, let current = records.first(where: { $0.routineID == routine.id && $0.dayKey == day }), current.status != .skipped else { continue }
                current.status = stepIDs.isSubset(of: Set(current.completedStepIDs)) ? .completed : .pending
                current.completedAt = current.status == .completed ? (current.completedAt ?? Date()) : nil
                if let edit = parsed[routine.id], edit.status != current.status {
                    normalizedText[routine.id] = OutlineEdit.line(title: edit.title, minute: edit.minute, status: current.status)
                }
            }
            func normalize(_ nodes: [TodayDocumentBlock]) -> [TodayDocumentBlock] {
                nodes.map { node in
                    var node = node
                    if let text = normalizedText[node.id] {
                        let notes = node.text.split(separator: "\n", omittingEmptySubsequences: false).dropFirst().joined(separator: "\n")
                        node.text = text + (notes.isEmpty ? "" : "\n" + notes)
                    }
                    node.children = normalize(node.children); return node
                }
            }
            document.blocks = normalize(document.blocks)
            for current in records where current.dayKey == day {
                if let edit = parsed[current.routineID], let old = baseline[current.routineID],
                   current.status == edit.status,
                   edit.status != (try? parseDocumentLine(old.text).status) {
                    syncDayCommands[current.key] = current.status
                }
            }
            document.baseline = try documentSources(day: day)
            for source in document.baseline {
                if let index = document.links.firstIndex(where: { $0.id == source.id }) { document.links[index] = source }
                else { document.links.append(source) }
            }
            document.appliedBlocks = document.blocks
            record.payload = try JSONEncoder().encode(document); record.revision += 1
        }
        return (document, record.revision)
    }
}
