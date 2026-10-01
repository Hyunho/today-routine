import SwiftUI
struct TaskEditor: View {
    let model: AppModel
    @State var draft: TaskDraft
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack { Form {
            Section("일감") { TextField("일감 제목", text: $draft.title); TextField("메모", text: $draft.note, axis: .vertical).lineLimit(2...5) }
            Section("예정일") {
                Toggle("날짜 지정", isOn: Binding(get: { draft.dayKey != nil }, set: { draft.dayKey = $0 ? RoutineRules.dayKey(Date()) : nil; if !$0 { draft.minute = nil } }))
                if draft.dayKey != nil {
                    DatePicker("날짜", selection: Binding(get: { RoutineRules.date(for: draft.dayKey ?? "") ?? Date() }, set: { draft.dayKey = RoutineRules.dayKey($0) }), displayedComponents: .date)
                    Toggle("시간 지정", isOn: Binding(get: { draft.minute != nil }, set: { draft.minute = $0 ? 540 : nil }))
                    if draft.minute != nil { MinutePicker(title: "시간", minute: Binding(get: { draft.minute ?? 540 }, set: { draft.minute = $0 })) }
                }
            }
        }.navigationTitle("일감 편집").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("저장") { if model.perform({ try $0.upsertTask(draft) }) { dismiss() } }.bold() } }
        }
    }
}
