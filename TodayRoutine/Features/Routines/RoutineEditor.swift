import SwiftUI
struct RoutineEditor: View {
    let model: AppModel
    @State var draft: RoutineDraft
    @Environment(\.dismiss) private var dismiss
    @State private var stepToDelete: UUID?
    @State private var converting = false
    @State private var durationEnabled: Bool
    @State private var durationInput: String
    init(model: AppModel, draft: RoutineDraft) {
        self.model = model
        _draft = State(initialValue: draft)
        _durationEnabled = State(initialValue: draft.durationMinutes != nil)
        _durationInput = State(initialValue: draft.durationMinutes.map(String.init) ?? "")
    }
    private var saveDraft: RoutineDraft {
        var result = draft
        if !linked {
            result.durationMinutes = durationEnabled
                ? Int(durationInput.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0 : nil
        }
        return result
    }
    private var linked: Bool { model.snapshot.routines.first(where: { $0.id == draft.id })?.calendarLink != nil }
    private let days = [(2,"월"),(3,"화"),(4,"수"),(5,"목"),(6,"금"),(7,"토"),(1,"일")]
    func move(_ id: UUID, by offset: Int) {
        guard let index = draft.steps.firstIndex(where:{$0.id == id}), draft.steps.indices.contains(index+offset) else { return }
        draft.steps.swapAt(index,index+offset)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("기본 정보") {
                    if linked, case .connected(let event) = model.appleCalendar.routineConnections[draft.id] { Text(event.title).font(.headline) }
                    else { TextField("루틴 이름", text: $draft.name).accessibilityIdentifier("루틴 이름").disabled(linked) }
                    TextField("메모", text: $draft.note, axis: .vertical).lineLimit(2...5)
                    Picker("그룹", selection: $draft.groupID) { Text("그룹 없음").tag(UUID?.none); ForEach(model.snapshot.groups.sorted { $0.sortOrder < $1.sortOrder }) { g in Text(g.name).tag(Optional(g.id)) } }
                }
                if linked {
                    Section("캘린더 루틴") { Text("제목·시간·반복은 Apple 캘린더에서 변경해 주세요. 이 화면에서는 하위 목록과 앱 메모를 관리합니다.").font(.subheadline) }
                } else { Section("반복과 시간") {
                    Picker("반복", selection: $draft.repeatKind) {
                        ForEach(RepeatKind.selectableCases, id: \.self) { Text($0.label).tag($0) }
                        if draft.repeatKind == .weeklyGoal {
                            Text("기존 주간 목표 · 재설정 필요").tag(RepeatKind.weeklyGoal)
                        }
                    }
                    if draft.repeatKind == .weekdays {
                        ForEach(days, id: \.0) { day in Toggle(day.1, isOn: Binding(get: { draft.weekdays.contains(day.0) }, set: { if $0 { draft.weekdays.append(day.0) } else { draft.weekdays.removeAll { $0 == day.0 } } })) }
                    }
                    if draft.repeatKind == .weeklyGoal {
                        Text("기존 주 \(draft.weeklyTarget)회 설정을 보존하고 있습니다. 반복 방식을 매일 또는 요일 선택으로 변경할 수 있습니다.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Toggle("소요시간 지정", isOn: $durationEnabled)
                        .accessibilityIdentifier("routine-duration-enabled")
                    if durationEnabled {
                        HStack {
                            TextField("소요시간 (분)", text: $durationInput)
                                .accessibilityIdentifier("routine-duration-minutes")
                                #if os(iOS)
                                .keyboardType(.numberPad)
                                #endif
                            Text("분").foregroundStyle(.secondary)
                        }
                        Text("1~1,440분 사이로 입력해 주세요.").font(.caption).foregroundStyle(.secondary)
                    } else {
                        LabeledContent("소요시간", value: "미정")
                    }
                    Toggle("시간 지정", isOn: Binding(get: { draft.minute != nil }, set: { draft.minute = $0 ? 540 : nil }))
                    if draft.minute != nil { MinutePicker(title: "실행 시간", minute: Binding(get: { draft.minute ?? 540 }, set: { draft.minute = $0 })) }
                }
                }
                Section { ForEach($draft.steps) { $step in
                    HStack { TextField("단계 이름", text: $step.name); Button(role: .destructive) { stepToDelete = step.id } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless).accessibilityLabel("\(step.name) 단계 삭제") }
                    .contextMenu {
                        Button("위로 이동") { move(step.id,by:-1) }.disabled(draft.steps.first?.id == step.id)
                        Button("아래로 이동") { move(step.id,by:1) }.disabled(draft.steps.last?.id == step.id)
                    }
                }.onMove { from,to in draft.steps.move(fromOffsets: from, toOffset: to) }
                    Button("단계 추가", systemImage: "plus") { draft.steps.append(StepDraft()) }
                } header: { Text("하위 단계") } footer: { Text("단계를 모두 체크하면 루틴이 완료됩니다.") }
                Section { Picker("상태", selection: $draft.status) { ForEach(RoutineStatus.allCases, id: \.self) { Text($0.label).tag($0) } } }
                if !linked, draft.repeatKind != .weeklyGoal, model.snapshot.routines.contains(where: { $0.id == draft.id }) {
                    Section {
                        Button("캘린더 루틴으로 전환", systemImage: "calendar.badge.plus") {
                            if model.perform({ try $0.upsertRoutine(saveDraft) }) { converting = true }
                        }
                    }
                }
            }
            .navigationTitle("루틴 편집").platformInlineTitle()
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("저장") { if model.perform({ try $0.upsertRoutine(saveDraft) }) { dismiss() } }.bold() }; ToolbarItem(placement: .automatic) { PlatformEditButton() } }
            .confirmationDialog("이 단계를 삭제할까요?", isPresented: Binding(get: { stepToDelete != nil }, set: { if !$0 { stepToDelete = nil } })) { Button("단계 삭제", role: .destructive) { draft.steps.removeAll { $0.id == stepToDelete }; stepToDelete = nil } }
        }.modifier(SheetSaveErrors(model: model))
        .sheet(isPresented: $converting) { CalendarRoutineConversionView(model: model, routineID: draft.id) }
    }
}
