import SwiftUI
struct RoutinesView: View {
    let model: AppModel
    @State private var mode = "내 순서"
    @State private var selectedStatus = RoutineStatus.active
    @State private var draft: RoutineDraft?
    @State private var groups = false
    @State private var settings = false
    var routines: [Routine] { model.snapshot.routines.filter { $0.status == selectedStatus }.sorted { $0.sortOrder < $1.sortOrder } }
    var body: some View {
        NavigationStack {
            List {
                Section { Picker("보기", selection: $mode) { ForEach(["내 순서","그룹별","시간순"], id: \.self) { Text($0) } }.pickerStyle(.segmented)
                    Picker("상태", selection: $selectedStatus) { ForEach(RoutineStatus.allCases, id: \.self) { Text($0.label).tag($0) } }
                }
                if routines.isEmpty { EmptyHint(title: "나만의 리듬을 만들어 보세요", message: "작은 루틴 하나부터 시작해요.", symbol: "leaf") }
                if mode == "그룹별" {
                    ForEach(model.snapshot.groups.sorted { $0.sortOrder < $1.sortOrder }) { group in
                        let items = routines.filter { $0.groupID == group.id }
                        if !items.isEmpty { Section(group.name) { ForEach(RoutineRules.timeSorted(items)) { row($0) } } }
                    }
                    let others = routines.filter { r in r.groupID == nil || !model.snapshot.groups.contains(where: { $0.id == r.groupID }) }
                    Section("그룹 없음") { ForEach(RoutineRules.timeSorted(others)) { row($0) } }
                } else {
                    Section { ForEach(mode == "시간순" ? RoutineRules.timeSorted(routines) : routines) { row($0) }.onMove { indices, destination in
                        var ids = routines.map(\.id); ids.move(fromOffsets: indices, toOffset: destination)
                        // Reorder this section while preserving the other statuses after it.
                        ids += model.snapshot.routines.filter { $0.status != selectedStatus }.sorted { $0.sortOrder < $1.sortOrder }.map(\.id)
                        model.perform { try $0.reorder(ids) }
                    }.moveDisabled(mode != "내 순서") }
                }
            }.navigationTitle("나의 루틴")
            .toolbar { ToolbarItem(placement: .topBarLeading) { Menu { Button("그룹 관리") { groups = true }; Button("설정") { settings = true } } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("루틴 메뉴") }; ToolbarItemGroup(placement: .topBarTrailing) { if mode == "내 순서" { EditButton() }; Button { draft = RoutineDraft() } label: { Image(systemName: "plus") }.accessibilityLabel("루틴 추가") } }
            .sheet(item: $draft) { RoutineEditor(model: model, draft: $0) }
            .sheet(isPresented: $groups) { GroupEditor(model: model) }
            .sheet(isPresented: $settings) { SettingsView(model: model) }
        }
    }
    func row(_ r: Routine) -> some View {
        Button { draft = RoutineDraft(r, steps: model.snapshot.steps) } label: {
            HStack(alignment: .top) { Image(systemName: r.status == .active ? "circle.dotted" : "archivebox").foregroundStyle(.teal).font(.title2)
                VStack(alignment: .leading, spacing: 6) { Text(r.name).font(.headline).foregroundStyle(.primary); Text("\(r.repeatKind == .weeklyGoal ? "주 \(r.weeklyTarget)회" : r.repeatKind.label) · \(RoutineRules.timeLabel(r.minute))").font(.caption).foregroundStyle(.secondary); if !model.steps(for: r).isEmpty { Text("\(model.steps(for: r).count)단계").font(.caption).foregroundStyle(.secondary) } }; Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary) }
            .padding(.vertical, 5)
        }.buttonStyle(.plain)
    }
}
