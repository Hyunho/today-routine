import SwiftUI
struct TimeBlockEditor: View {
    let model: AppModel
    @State var draft: BlockDraft
    @Environment(\.dismiss) private var dismiss
    @State private var overlapConfirmation = false
    var linkSelection: Binding<String> { Binding(get: { if let id = draft.linkedID, let kind = draft.linkedKind { return "\(kind)/\(id.uuidString)" }; return "" }, set: { value in let parts = value.split(separator: "/"); if parts.count == 2, let id = UUID(uuidString: String(parts[1])) { draft.linkedKind = String(parts[0]); draft.linkedID = id } else { draft.linkedID = nil; draft.linkedKind = nil } }) }
    var body: some View {
        NavigationStack { Form {
            TextField("블록 제목", text: $draft.title)
            DatePicker("날짜", selection: Binding(get: { RoutineRules.date(for: draft.dayKey) ?? Date() }, set: { draft.dayKey = RoutineRules.dayKey($0) }), displayedComponents: .date)
            MinutePicker(title: "시작", minute: $draft.startMinute); MinutePicker(title: "종료", minute: $draft.endMinute)
            Section { Picker("연결 항목", selection: linkSelection) {
                Text("연결 없음").tag("")
                ForEach(model.snapshot.tasks) { Text("일감 · \($0.title)").tag("task/\($0.id.uuidString)") }
                ForEach(model.snapshot.routines.filter { $0.status == .active }) { Text("루틴 · \($0.name)").tag("routine/\($0.id.uuidString)") }
            } } footer: { Text("시간 배치는 연결 항목의 완료 상태를 바꾸지 않습니다.") }
        }.navigationTitle("타임블록 편집").platformInlineTitle()
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("저장") {
            do { if try model.store?.overlaps(draft) == true { overlapConfirmation = true } else { save() } } catch { model.error = error.localizedDescription }
        }.bold() } }
        .alert("겹치는 시간이 있습니다", isPresented: $overlapConfirmation) { Button("계속 저장") { save() }; Button("시간 수정", role: .cancel) {} } message: { Text("다른 타임블록과 겹쳐도 저장할 수 있습니다.") }
        }.modifier(SheetSaveErrors(model: model))
    }
    func save() { if model.perform({ try $0.upsertBlock(draft) }) { dismiss() } }
}
