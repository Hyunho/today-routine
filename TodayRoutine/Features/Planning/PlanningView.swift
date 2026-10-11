import SwiftUI
private struct TimelineEntry: Identifiable {
    let routine: Routine?
    let block: TimeBlock?
    var id: String { routine.map { "routine-\($0.id)" } ?? "block-\(block!.id)" }
    var minute: Int { routine?.minute ?? block?.startMinute ?? Int.max }
}
struct PlanningView: View {
    let model: AppModel
    let mode: Int
    @AppStorage("planning.taskView") private var taskView = "목록"
    @State private var date = Date()
    @State private var reminderConnection = false
    @State private var reminderDraft: AppleReminderDraft?
    @State private var block: BlockDraft?
    @State private var deleteBlock: UUID?
    @State private var expanded: Set<UUID> = []
    private var routines: [Routine] {
        RoutineRules.timeSorted(model.snapshot.routines.filter {
            RoutineRules.visible($0, records: model.snapshot.records, on: date, now: Date())
        })
    }
    private var timeline: [TimelineEntry] {
        let scheduled = routines.filter { $0.repeatKind != .weeklyGoal && $0.minute != nil }
            .map { TimelineEntry(routine: $0, block: nil) }
        let blocks = model.snapshot.blocks.filter { $0.dayKey == RoutineRules.dayKey(date) }
            .map { TimelineEntry(routine: nil, block: $0) }
        return (scheduled + blocks).sorted { $0.minute == $1.minute ? $0.id < $1.id : $0.minute < $1.minute }
    }
    private var isLogseqReading: Bool { mode == 0 && taskView == "Logseq 읽기" }
    private var reminderOutline: [TodayOutlineSection] {
        let grouped = Dictionary(grouping: model.appleReminders.items) { $0.dayKey ?? "날짜 미정" }
        return grouped.keys.sorted().map { day in
            let items = grouped[day, default: []].sorted {
                if $0.completed != $1.completed { return !$0.completed }
                if $0.minute != $1.minute { return ($0.minute ?? Int.max) < ($1.minute ?? Int.max) }
                if $0.title != $1.title { return $0.title < $1.title }
                return $0.id < $1.id
            }
            return TodayOutlineSection(title: day, rows: items.map { item in
                TodayOutlineRow(id: "reminder-" + item.id, title: item.title,
                                status: item.completed ? .completed : .pending,
                                detail: [item.listTitle, item.note].filter { !$0.isEmpty }.joined(separator: " · "),
                                time: item.minute.map { RoutineRules.timeLabel($0) } ?? "")
            })
        }
    }
    private var reminderEmptyMessage: String {
        if !model.appleReminders.hasAccess { return "일감을 사용하려면 Apple 미리 알림 접근을 허용해 주세요." }
        if model.appleReminders.selectedIDs.isEmpty { return "표시할 미리 알림 목록을 연결해 주세요." }
        if model.appleReminders.loading { return "미리 알림을 불러오고 있습니다." }
        return "연결한 목록에 표시할 일감이 없습니다."
    }
    var body: some View {
        NavigationStack {
        VStack(spacing: 0) {
            if mode == 0 {
                Picker("일감 보기", selection: $taskView) {
                    Text("목록").tag("목록")
                    Text("Logseq 읽기").tag("Logseq 읽기")
                }.pickerStyle(.segmented).padding()
            }
            if isLogseqReading {
                ScrollViewReader { scroll in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Button("미리 알림 연결 관리") { reminderConnection = true }
                                Spacer()
                                if model.appleReminders.loading { ProgressView().controlSize(.small) }
                                Button("새로고침", systemImage: "arrow.clockwise") {
                                    Task { await model.appleReminders.refresh() }
                                }.disabled(model.appleReminders.loading)
                            }.font(.caption)
                            LogseqReadingView(heading: "일감", sections: reminderOutline,
                                              isActive: model.selectedTab == "일감",
                                              emptyMessage: reminderEmptyMessage) { id in
                                scroll.scrollTo("today-outline-" + id, anchor: .center)
                            }
                        }.padding()
                    }
                }
            } else {
            List {
            if mode == 0 {
                Section("Apple 미리 알림") {
                    Button { reminderConnection = true } label: {
                        Label(model.appleReminders.selectedIDs.isEmpty ? "미리 알림 연결" : "연결 목록 관리 (\(model.appleReminders.selectedIDs.count)개)", systemImage: "checklist")
                    }
                    if !model.appleReminders.hasAccess {
                        Text("일감을 사용하려면 Apple 미리 알림 접근을 허용해 주세요.").font(.caption).foregroundStyle(.secondary)
                    } else if model.appleReminders.selectedIDs.isEmpty {
                        Text("표시할 미리 알림 목록을 선택해 주세요.").font(.caption).foregroundStyle(.secondary)
                    } else if model.appleReminders.writableLists.isEmpty {
                        Text("새 일감을 추가하려면 쓰기 가능한 목록을 연결해 주세요.").font(.caption).foregroundStyle(.secondary)
                    }
                    if model.appleReminders.loading { ProgressView("미리 알림 불러오는 중") }
                    if model.appleReminders.hasAccess && !model.appleReminders.writableLists.isEmpty {
                        Button("미리 알림 추가", systemImage: "plus") { addReminder() }
                    }
                    if model.appleReminders.hasAccess && !model.appleReminders.selectedIDs.isEmpty {
                        Button("미리 알림 새로고침") { Task { await model.appleReminders.refresh() } }
                    }
                }
                ForEach([false, true], id: \.self) { done in
                    let reminders = model.appleReminders.items.filter { $0.completed == done }
                    if !reminders.isEmpty {
                        Section(done ? "완료한 미리 알림" : "미리 알림 할 일") {
                            ForEach(reminders) { item in AppleReminderRow(item: item, reminders: model.appleReminders) { reminderDraft = AppleReminderDraft(item) } }
                        }
                    }
                }
                if model.appleReminders.items.isEmpty && model.appleReminders.hasAccess && !model.appleReminders.selectedIDs.isEmpty && !model.appleReminders.loading {
                    EmptyHint(title: "미리 알림이 없습니다", message: "선택한 목록에 할 일을 추가해 보세요.", symbol: "tray")
                }
            } else {
                Section { DatePicker("날짜", selection: $date, displayedComponents: .date) }
                if timeline.isEmpty && routines.isEmpty {
                    EmptyHint(title: "시간에 자리를 만들어 주세요", message: "루틴을 추가하거나 집중할 시간을 블록으로 정해 보세요.", symbol: "calendar.badge.plus")
                }
                if !timeline.isEmpty {
                    Section("시간순") {
                        ForEach(timeline) { entry in
                            if let r = entry.routine { routineRow(r) }
                            else if let b = entry.block { blockRow(b) }
                        }
                    }
                }
                let untimed = routines.filter { $0.minute == nil && $0.repeatKind != .weeklyGoal }
                if !untimed.isEmpty { Section("시간 미정") { ForEach(untimed) { routineRow($0) } } }
                let weekly = routines.filter { $0.repeatKind == .weeklyGoal }
                if !weekly.isEmpty { Section("이번 주 목표") { ForEach(weekly) { routineRow($0) } } }
            }
            }
            }
        }.modifier(MobileSyncRefresh(model: model)).navigationTitle(mode == 0 ? "일감" : "타임블록")
        .toolbar { if !isLogseqReading { ToolbarItem(placement: .primaryAction) { Button { if mode == 0 { addReminder() } else { var d = BlockDraft(); d.dayKey = RoutineRules.dayKey(date); block = d } } label: { Image(systemName: "plus") }.accessibilityLabel(mode == 0 ? "일감 추가" : "타임블록 추가") } } }
        .sheet(isPresented: $reminderConnection) { AppleRemindersConnectionView(reminders: model.appleReminders) }
        .sheet(item: $reminderDraft) { AppleReminderEditor(reminders: model.appleReminders, draft: $0) }
        .modifier(AppleRemindersErrors(reminders: model.appleReminders, enabled: !reminderConnection && reminderDraft == nil))
        .sheet(item: $block) { TimeBlockEditor(model: model, draft: $0) }
        .confirmationDialog("이 타임블록을 삭제할까요?", isPresented: Binding(get: { deleteBlock != nil }, set: { if !$0 { deleteBlock = nil } })) { Button("타임블록 삭제", role: .destructive) { if let id = deleteBlock { model.perform { try $0.deleteBlock(id: id) } }; deleteBlock = nil } }
        }
    }
    private func addReminder() {
        if model.appleReminders.hasAccess, let list = model.appleReminders.writableLists.first {
            reminderDraft = AppleReminderDraft(listID: list.id)
        } else { reminderConnection = true }
    }
    private func blockRow(_ b: TimeBlock) -> some View {
                    Button { block = BlockDraft(b) } label: { HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading) { Text(RoutineRules.timeLabel(b.startMinute)).font(.headline); Text(RoutineRules.timeLabel(b.endMinute)).font(.caption).foregroundStyle(.secondary) }.monospacedDigit()
                        RoundedRectangle(cornerRadius: 2).fill(.teal).frame(width: 3)
                        VStack(alignment: .leading, spacing: 5) { Text(b.title).font(.headline); Text("\(b.endMinute-b.startMinute)분").font(.caption).foregroundStyle(.secondary); if b.linkedID != nil { Label("연결된 \(b.linkedKind == "task" ? "일감" : "루틴")", systemImage: "link").font(.caption).foregroundStyle(.secondary) } }
                    }.padding(.vertical,6) }.buttonStyle(.plain).swipeActions { Button("삭제", role: .destructive) { deleteBlock = b.id } }.contextMenu { Button("타임블록 삭제",role:.destructive) { deleteBlock = b.id } }
    }
    private func routineRow(_ r: Routine) -> some View {
        let record = model.record(r, date: date)
        let isPast = RoutineRules.dayKey(date) < RoutineRules.dayKey(Date())
        return VStack(alignment: .leading, spacing: 10) {
            Button {
                if expanded.contains(r.id) { expanded.remove(r.id) } else { expanded.insert(r.id) }
            } label: {
                HStack(alignment: .top, spacing: 16) {
                    Text(r.repeatKind == .weeklyGoal ? "주간 목표" : RoutineRules.timeLabel(r.minute)).font(.headline).monospacedDigit()
                    RoundedRectangle(cornerRadius: 2).fill(.orange).frame(width: 3)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(isPast ? (record?.nameSnapshot ?? r.name) : r.name).font(.headline)
                        Text(record?.status == .completed ? "루틴 · 완료" : record?.status == .skipped ? "루틴 · 건너뜀" : "루틴").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: expanded.contains(r.id) ? "chevron.up" : "chevron.down")
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("\(r.name) 세부 작업 보기")
            if expanded.contains(r.id) {
                if !r.note.isEmpty { Text(r.note).font(.subheadline).foregroundStyle(.secondary) }
                if !isPast {
                    ForEach(model.steps(for: r)) { step in
                        Button { model.perform { try $0.toggleStep(routineID: r.id, stepID: step.id, date: date) } } label: {
                            Label(step.name, systemImage: record?.completedStepIDs.contains(step.id) == true ? "checkmark.square.fill" : "square")
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
                        }.buttonStyle(.borderless)
                    }
                }
            }
        }.padding(.vertical, 6)
    }

}
