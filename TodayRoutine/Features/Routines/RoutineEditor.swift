import SwiftUI
struct RoutineEditor: View {
    let model: AppModel
    @State var draft: RoutineDraft
    @Environment(\.dismiss) private var dismiss
    @State private var stepToDelete: UUID?
    private let days = [(2,"월"),(3,"화"),(4,"수"),(5,"목"),(6,"금"),(7,"토"),(1,"일")]
    var body: some View {
        NavigationStack {
            Form {
                Section("기본 정보") {
                    TextField("루틴 이름", text: $draft.name).accessibilityIdentifier("루틴 이름")
                    TextField("메모", text: $draft.note, axis: .vertical).lineLimit(2...5)
                    Picker("그룹", selection: $draft.groupID) { Text("그룹 없음").tag(UUID?.none); ForEach(model.snapshot.groups.sorted { $0.sortOrder < $1.sortOrder }) { g in Text(g.name).tag(Optional(g.id)) } }
                }
                Section("반복과 시간") {
                    Picker("반복", selection: $draft.repeatKind) { ForEach(RepeatKind.allCases, id: \.self) { Text($0.label).tag($0) } }
                    if draft.repeatKind == .weekdays {
                        ForEach(days, id: \.0) { day in Toggle(day.1, isOn: Binding(get: { draft.weekdays.contains(day.0) }, set: { if $0 { draft.weekdays.append(day.0) } else { draft.weekdays.removeAll { $0 == day.0 } } })) }
                    }
                    if draft.repeatKind == .weeklyGoal { Stepper("주 \(draft.weeklyTarget)회", value: $draft.weeklyTarget, in: 1...7) }
                    Toggle("시간 지정", isOn: Binding(get: { draft.minute != nil }, set: { draft.minute = $0 ? 540 : nil }))
                    if draft.minute != nil { MinutePicker(title: "실행 시간", minute: Binding(get: { draft.minute ?? 540 }, set: { draft.minute = $0 })) }
                }
                Section { ForEach($draft.steps) { $step in
                    HStack { TextField("단계 이름", text: $step.name); Button(role: .destructive) { stepToDelete = step.id } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless).accessibilityLabel("\(step.name) 단계 삭제") }
                }.onMove { from,to in draft.steps.move(fromOffsets: from, toOffset: to) }
                    Button("단계 추가", systemImage: "plus") { draft.steps.append(StepDraft()) }
                } header: { Text("하위 단계") } footer: { Text("단계를 모두 체크하면 루틴이 완료됩니다.") }
                Section { Picker("상태", selection: $draft.status) { ForEach(RoutineStatus.allCases, id: \.self) { Text($0.label).tag($0) } } }
            }
            .navigationTitle("루틴 편집").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("저장") { if model.perform({ try $0.upsertRoutine(draft) }) { dismiss() } }.bold() }; ToolbarItem(placement: .bottomBar) { EditButton() } }
            .confirmationDialog("이 단계를 삭제할까요?", isPresented: Binding(get: { stepToDelete != nil }, set: { if !$0 { stepToDelete = nil } })) { Button("단계 삭제", role: .destructive) { draft.steps.removeAll { $0.id == stepToDelete }; stepToDelete = nil } }
        }
    }
}
