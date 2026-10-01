import SwiftUI
struct PlanningView: View {
    let model: AppModel
    @State private var mode = 0
    @State private var date = Date()
    @State private var task: TaskDraft?
    @State private var block: BlockDraft?
    @State private var deleteTask: UUID?
    @State private var deleteBlock: UUID?
    var body: some View {
        NavigationStack { List {
            Section { Picker("계획 종류", selection: $mode) { Text("일감").tag(0); Text("타임블록").tag(1) }.pickerStyle(.segmented) }
            if mode == 0 {
                if model.snapshot.tasks.isEmpty { EmptyHint(title: "마음을 비우는 작업함", message: "해야 할 일을 적고 알맞은 날에 배치해 보세요.", symbol: "tray") }
                ForEach([false,true], id: \.self) { done in
                    Section(done ? "완료한 일감" : "할 일") { ForEach(model.snapshot.tasks.filter { ($0.completedAt != nil) == done }.sorted { ($0.dayKey ?? "9999", $0.minute ?? Int.max, $0.createdAt) < ($1.dayKey ?? "9999", $1.minute ?? Int.max, $1.createdAt) }) { t in
                        HStack(spacing: 14) { Button { model.perform { try $0.setTaskCompleted(id: t.id, completed: !done) } } label: { Image(systemName: done ? "checkmark.circle.fill" : "circle").font(.title2) }.buttonStyle(.borderless).accessibilityLabel("\(t.title) 완료 전환")
                            Button { task = TaskDraft(t) } label: { VStack(alignment: .leading, spacing: 5) { Text(t.title).font(.headline); Text(t.dayKey.map { "\($0) · \(RoutineRules.timeLabel(t.minute))" } ?? "날짜 미정").font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(.plain)
                        }.padding(.vertical,5).swipeActions { Button("삭제", role: .destructive) { deleteTask = t.id } }
                    } }
                }
            } else {
                Section { DatePicker("날짜", selection: $date, displayedComponents: .date) }
                let blocks = model.snapshot.blocks.filter { $0.dayKey == RoutineRules.dayKey(date) }.sorted { $0.startMinute < $1.startMinute }
                if blocks.isEmpty { EmptyHint(title: "시간에 자리를 만들어 주세요", message: "집중할 시간을 블록으로 정해 보세요.", symbol: "calendar.badge.plus") }
                ForEach(blocks) { b in
                    Button { block = BlockDraft(b) } label: { HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading) { Text(RoutineRules.timeLabel(b.startMinute)).font(.headline); Text(RoutineRules.timeLabel(b.endMinute)).font(.caption).foregroundStyle(.secondary) }.monospacedDigit()
                        RoundedRectangle(cornerRadius: 2).fill(.teal).frame(width: 3)
                        VStack(alignment: .leading, spacing: 5) { Text(b.title).font(.headline); Text("\(b.endMinute-b.startMinute)분").font(.caption).foregroundStyle(.secondary); if b.linkedID != nil { Label("연결된 \(b.linkedKind == "task" ? "일감" : "루틴")", systemImage: "link").font(.caption).foregroundStyle(.secondary) } }
                    }.padding(.vertical,6) }.buttonStyle(.plain).swipeActions { Button("삭제", role: .destructive) { deleteBlock = b.id } }
                }
            }
        }.navigationTitle("계획")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { if mode == 0 { task = TaskDraft() } else { var d = BlockDraft(); d.dayKey = RoutineRules.dayKey(date); block = d } } label: { Image(systemName: "plus") }.accessibilityLabel(mode == 0 ? "일감 추가" : "타임블록 추가") } }
        .sheet(item: $task) { TaskEditor(model: model, draft: $0) }
        .sheet(item: $block) { TimeBlockEditor(model: model, draft: $0) }
        .confirmationDialog("이 일감을 삭제할까요?", isPresented: Binding(get: { deleteTask != nil }, set: { if !$0 { deleteTask = nil } })) { Button("일감 삭제", role: .destructive) { if let id = deleteTask { model.perform { try $0.deleteTask(id: id) } }; deleteTask = nil } }
        .confirmationDialog("이 타임블록을 삭제할까요?", isPresented: Binding(get: { deleteBlock != nil }, set: { if !$0 { deleteBlock = nil } })) { Button("타임블록 삭제", role: .destructive) { if let id = deleteBlock { model.perform { try $0.deleteBlock(id: id) } }; deleteBlock = nil } }
        }
    }
}
