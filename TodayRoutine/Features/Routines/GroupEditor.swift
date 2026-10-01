import SwiftUI
struct GroupEditor: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var editID: UUID?
    @State private var deleteID: UUID?
    var body: some View {
        NavigationStack { Form {
            Section(editID == nil ? "새 그룹" : "그룹 수정") { TextField("그룹 이름", text: $name); Button(editID == nil ? "추가" : "이름 저장") { if model.perform({ try $0.saveGroup(id: editID, name: name) }) { name = ""; editID = nil } } }
            Section { ForEach(model.snapshot.groups.sorted { $0.sortOrder < $1.sortOrder }) { g in
                HStack { Button(g.name) { editID = g.id; name = g.name }; Spacer(); Button(role: .destructive) { deleteID = g.id } label: { Image(systemName: "trash") }.buttonStyle(.borderless).accessibilityLabel("\(g.name) 그룹 삭제") }
            } } footer: { Text("그룹을 삭제해도 루틴과 기록은 유지됩니다.") }
        }.navigationTitle("그룹 관리").toolbar { ToolbarItem(placement: .confirmationAction) { Button("완료") { dismiss() } } }
        .confirmationDialog("그룹을 삭제하고 루틴 연결을 해제할까요?", isPresented: Binding(get: { deleteID != nil }, set: { if !$0 { deleteID = nil } })) { Button("그룹 삭제", role: .destructive) { if let id = deleteID { model.perform { try $0.deleteGroup(id: id) } }; deleteID = nil } }
        }.modifier(SheetSaveErrors(model: model))
    }
}
