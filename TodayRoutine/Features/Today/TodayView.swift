import SwiftUI
import Combine
private struct TodayEntry: Identifiable {
    let routine: Routine?; let task: TaskItem?
    var id: UUID { routine?.id ?? task!.id }
    var minute: Int? { routine?.minute ?? task?.minute }
}
struct TodayView: View {
    let model: AppModel
    @State private var date = Date()
    @State private var lastToday = Date()
    @Environment(\.scenePhase) private var scenePhase
    private var isPast: Bool { RoutineRules.dayKey(date) < RoutineRules.dayKey(Date()) }
    private func refreshDay() { let now = Date(); date = RoutineRules.refreshedSelection(date, previousToday: lastToday, now: now); lastToday = now }
    private func displayName(_ r: Routine) -> String { isPast ? (model.record(r, date: date)?.nameSnapshot ?? r.name) : r.name }
    @State private var expanded: Set<UUID> = []
    @State private var settings = false
    @State private var draft: RoutineDraft?
    private var routines: [Routine] { model.snapshot.routines.filter { RoutineRules.visible($0, records: model.snapshot.records, on: date, now: Date()) } }
    private var tasks: [TaskItem] { model.snapshot.tasks.filter { $0.dayKey == RoutineRules.dayKey(date) } }
    private func status(_ r: Routine) -> DayStatus { model.record(r, date: date)?.status ?? .pending }
    private var completed: Int { routines.filter { status($0) == .completed }.count + tasks.filter { $0.completedAt != nil }.count }
    private var entries: [TodayEntry] {
        let r = routines.filter { $0.repeatKind != .weeklyGoal && status($0) == .pending }.map { TodayEntry(routine: $0, task: nil) }
        let t = tasks.filter { $0.completedAt == nil }.map { TodayEntry(routine: nil, task: $0) }
        return (r+t).sorted { if ($0.minute ?? Int.max) != ($1.minute ?? Int.max) { return ($0.minute ?? Int.max) < ($1.minute ?? Int.max) }; return $0.id.uuidString < $1.id.uuidString }
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    DatePicker("날짜", selection: $date, displayedComponents: .date)
                    HStack { VStack(alignment: .leading, spacing: 8) { Text("작은 실천이 만드는 하루").font(.subheadline).foregroundStyle(.secondary); Text("완료 \(completed)개").font(.title2.bold()); Text("남은 항목 \(routines.filter { status($0) == .pending }.count + tasks.filter { $0.completedAt == nil }.count)개").font(.subheadline) }; Spacer(); Image(systemName: "sun.max.fill").font(.largeTitle).foregroundStyle(.orange) }.padding(.vertical,8)
                }
                if routines.isEmpty && tasks.isEmpty { EmptyHint(title: "오늘의 리듬을 시작해요", message: "루틴을 추가하면 이곳에 오늘 할 일이 모입니다.", symbol: "sun.horizon"); Button("첫 루틴 추가", systemImage: "plus") { draft = RoutineDraft() } }
                let timed = entries.filter { $0.minute != nil }, untimed = entries.filter { $0.minute == nil }
                if !timed.isEmpty { Section("시간순 · \(timed.count)") { ForEach(timed) { entry($0) } } }
                if !untimed.isEmpty { Section("시간 미정 · \(untimed.count)") { ForEach(untimed) { entry($0) } } }
                let weekly = routines.filter { $0.repeatKind == .weeklyGoal && status($0) == .pending }
                if !weekly.isEmpty { Section("이번 주 목표") { ForEach(RoutineRules.timeSorted(weekly)) { r in
                    routineRow(r)
                } } }
                if completed > 0 { Section("완료") { ForEach(routines.filter { status($0) == .completed }) { routineRow($0) }; ForEach(tasks.filter { $0.completedAt != nil }) { taskRow($0) } } }
                let skipped = routines.filter { status($0) == .skipped }
                if !skipped.isEmpty { Section("건너뜀") { ForEach(skipped) { routineRow($0) } } }
            }.navigationTitle("오늘")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { settings = true } label: { Image(systemName: "gearshape") }.accessibilityLabel("설정") } }
            .onChange(of: scenePhase) { _, phase in if phase == .active { refreshDay() } }
            .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in refreshDay() }
            .sheet(isPresented: $settings) { SettingsView(model: model) }
            .sheet(item: $draft) { RoutineEditor(model: model, draft: $0) }
        }
    }
    @ViewBuilder private func entry(_ e: TodayEntry) -> some View { if let r = e.routine { routineRow(r) } else if let t = e.task { taskRow(t) } }
    private func routineRow(_ r: Routine) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                Button { model.perform { try $0.setStatus(routineID: r.id, date: date, status: status(r) == .completed ? .pending : .completed) } } label: { Image(systemName: status(r) == .completed ? "checkmark.circle.fill" : "circle").font(.title2).foregroundStyle(status(r) == .completed ? Color.teal : Color.secondary) }.buttonStyle(.borderless).accessibilityLabel("\(r.name) \(status(r) == .completed ? "완료 취소" : "완료")")
                Button { if expanded.contains(r.id) { expanded.remove(r.id) } else { expanded.insert(r.id) } } label: {
                    VStack(alignment: .leading, spacing: 5) { Text(displayName(r)).font(.headline).foregroundStyle(.primary); Text(r.repeatKind == .weeklyGoal ? "이번 주 \(RoutineRules.completedCount(routineID: r.id, records: model.snapshot.records, week: date))/\(r.weeklyTarget)회" : RoutineRules.timeLabel(r.minute)).font(.caption).foregroundStyle(.secondary)
                        if !isPast && !model.steps(for: r).isEmpty { Text("\(model.record(r, date: date)?.completedStepIDs.count ?? 0)/\(model.steps(for: r).count)단계").font(.caption).foregroundStyle(.secondary) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain).accessibilityLabel("\(r.name) 단계 보기")
                Menu { Button(status(r) == .skipped ? "되돌리기" : "오늘 건너뛰기") { model.perform { try $0.setStatus(routineID: r.id, date: date, status: status(r) == .skipped ? .pending : .skipped) } }; Button("루틴 수정") { draft = RoutineDraft(r, steps: model.snapshot.steps) } } label: { Image(systemName: "ellipsis") }.accessibilityLabel("\(r.name) 더 보기")
            }
            if expanded.contains(r.id) && !isPast {
                if !r.note.isEmpty { Text(r.note).font(.subheadline).foregroundStyle(.secondary) }
                ForEach(model.steps(for: r)) { step in
                    Button { model.perform { try $0.toggleStep(routineID: r.id, stepID: step.id, date: date) } } label: { Label(step.name, systemImage: model.record(r, date: date)?.completedStepIDs.contains(step.id) == true ? "checkmark.square.fill" : "square").frame(maxWidth: .infinity, alignment: .leading).padding(.vertical,6) }.buttonStyle(.borderless)
                }
            }
        }.padding(.vertical,5)
    }
    private func taskRow(_ t: TaskItem) -> some View {
        HStack { Button { model.perform { try $0.setTaskCompleted(id: t.id, completed: t.completedAt == nil) } } label: { Image(systemName: t.completedAt == nil ? "circle" : "checkmark.circle.fill").font(.title2) }.buttonStyle(.borderless).accessibilityLabel("\(t.title) 완료 전환"); VStack(alignment: .leading) { Text(t.title).font(.headline); Text("일감 · \(RoutineRules.timeLabel(t.minute))").font(.caption).foregroundStyle(.secondary) } }.padding(.vertical,5)
    }
}
