import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct TodayOutlineSection: Identifiable {
    let title: String
    let rows: [TodayOutlineRow]
    var id: String { title }
}

struct TodayOutlineRow: Identifiable {
    let id: String
    let title: String
    let status: DayStatus?
    let detail: String
    var time = ""
    var children: [TodayOutlineRow] = []
    var editable = false

    var line: String {
        let state: String
        switch status {
        case .pending: state = "TODO"
        case .completed: state = "DONE"
        case .skipped: state = "SKIPPED"
        case nil: state = ""
        }
        return [state, time, title].filter { !$0.isEmpty }.joined(separator: " ")
            .components(separatedBy: .newlines).joined(separator: " ")
    }
}

/// Editing is opt-in; the host saves changes to the same store used by its other views.
struct LogseqReadingView: View {
    let heading: String
    let sections: [TodayOutlineSection]
    var isActive = true
    var emptyMessage = "이 날짜에 표시할 작업이 없습니다."
    var editRow: ((TodayOutlineRow, String, String) -> String?)? = nil
    var revealRow: (String) -> Void = { _ in }
    @State private var selection = OutlineSelection()
    @State private var expansion = OutlineExpansion()
    @FocusState private var keyboardFocused: Bool
    @FocusState private var editorFocused: Bool
    @State private var editing: TodayOutlineRow?
    @State private var editingHeading = ""
    @State private var editedLine = ""
    @State private var editError: String?

    private func sectionRow(_ section: TodayOutlineSection) -> TodayOutlineRow {
        TodayOutlineRow(id: "section-" + section.id, title: "\(section.title) · \(section.rows.count)개", status: nil,
                        detail: "", children: section.rows)
    }
    private var nodes: [OutlineNode] {
        sections.map { section in
            OutlineNode(id: sectionRow(section).id, children: section.rows.map {
                OutlineNode(id: $0.id, children: $0.children.map { OutlineNode(id: $0.id) })
            })
        }
    }
    private var rows: [TodayOutlineRow] { sections.flatMap { [sectionRow($0)] + $0.rows.flatMap { [$0] + $0.children } } }
    private var rowIDs: [String] { expansion.visibleIDs(in: nodes) }
    private var selectedIDs: Set<String> { Set(selection.selectedIDs(in: rowIDs)) }
    private var copiedText: String {
        rows.filter { selectedIDs.contains($0.id) }.map { row in
            "- \(row.line)"
        }.joined(separator: "\n")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(heading).font(.title2.bold()).monospacedDigit()
                Label(editRow == nil ? "읽기 전용" : "Enter 또는 연필 버튼으로 편집 · Enter 저장 · Esc 취소",
                      systemImage: editRow == nil ? "lock" : "pencil").font(.caption).foregroundStyle(.secondary)
                Text("↑↓ 이동 · ←→ 접기/펼치기 · Shift+↑↓ 범위 선택 · ⌘A 전체 선택 · ⌘C 복사 · Esc 해제")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if let editing {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(editingHeading) · 항목 편집").font(.caption).foregroundStyle(.secondary)
                    TextField("TODO 14:00 제목", text: $editedLine)
                        .textFieldStyle(.roundedBorder).focused($editorFocused)
                        .onSubmit { saveEditing() }
                        .onKeyPress(.escape) { cancelEditing(); return .handled }
                    if let editError { Text(editError).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
                    HStack {
                        Button("저장") { saveEditing() }
                        Button("취소") { cancelEditing() }
                    }
                    Text(editing.status == nil ? "시간 블록의 길이는 유지됩니다." : "시간·상태는 선택한 날짜에, 제목은 루틴 이름에 반영됩니다.")
                        .font(.caption2).foregroundStyle(.secondary)
                }.id("today-outline-editor")
            }
            if sections.isEmpty {
                Text(emptyMessage).foregroundStyle(.secondary)
            }
            ForEach(sections) { section in
                VStack(alignment: .leading, spacing: 12) {
                    outlineRow(sectionRow(section)).font(.headline)
                    if !expansion.collapsed.contains(sectionRow(section).id) {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(section.rows) { row in
                            VStack(alignment: .leading, spacing: 10) {
                                outlineRow(row)
                                if !row.children.isEmpty && !expansion.collapsed.contains(row.id) {
                                    VStack(alignment: .leading, spacing: 10) {
                                        ForEach(row.children) { outlineRow($0) }
                                    }
                                    .padding(.leading, 20)
                                }
                            }
                        }
                    }
                    .padding(.leading, 20)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(.secondary.opacity(0.18)).frame(width: 1).padding(.leading, 3)
                    }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
        .focusable()
        .focused($keyboardFocused)
        .onKeyPress(keys: [.return, .upArrow, .downArrow, .leftArrow, .rightArrow, .home, .end, .escape], phases: [.down, .repeat]) { key in
            guard isActive, editing == nil else { return .ignored }
            if key.key == .return {
                guard let row = rows.first(where: { $0.id == selection.focus }), row.editable, editRow != nil else { return .ignored }
                beginEditing(row); return .handled
            }
            if key.key == .escape { selection.clear(); return .handled }
            guard !rowIDs.isEmpty else { return .ignored }
            if key.key == .leftArrow || key.key == .rightArrow {
                if selection.focus == nil { selection.select(rowIDs[0]) }
                expansion.moveHorizontal(expanding: key.key == .rightArrow, selection: &selection, in: nodes)
                if let id = selection.focus { revealRow(id) }
                return .handled
            }
            let extending = key.modifiers.contains(.shift)
            if key.key == .home || (key.key == .upArrow && key.modifiers.contains(.command)) {
                selection.select(rowIDs[0], extending: extending)
            } else if key.key == .end || (key.key == .downArrow && key.modifiers.contains(.command)) {
                selection.select(rowIDs[rowIDs.count - 1], extending: extending)
            } else {
                selection.move(by: key.key == .upArrow ? -1 : 1, extending: extending, in: rowIDs)
            }
            if let id = selection.focus { revealRow(id) }
            return .handled
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "ac")) { key in
            guard isActive, editing == nil, key.modifiers == .command else { return .ignored }
            if key.characters == "a" {
                selection.selectAll(in: rowIDs)
            } else {
                guard !selectedIDs.isEmpty else { return .ignored }
                #if os(macOS)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(copiedText, forType: .string)
                #else
                UIPasteboard.general.string = copiedText
                #endif
            }
            return .handled
        }
        #if os(macOS)
        .onCopyCommand(perform: isActive && editing == nil && keyboardFocused && !selectedIDs.isEmpty
                       ? { [NSItemProvider(object: copiedText as NSString)] } : nil)
        #endif
        .onAppear { keyboardFocused = isActive }
        .onChange(of: isActive) { _, active in
            keyboardFocused = active && editing == nil
            editorFocused = active && editing != nil
        }
        .onChange(of: heading) { _, _ in selection.clear(); expansion = OutlineExpansion() }
        .onChange(of: rowIDs) { _, ids in selection.reconcile(with: ids) }
        .accessibilityIdentifier("today-logseq-reading")
    }

    private func outlineRow(_ row: TodayOutlineRow) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if row.children.isEmpty {
                Text("•").foregroundStyle(.secondary).frame(width: 20)
            } else {
                Button {
                    selection.select(row.id)
                    expansion.toggle(row.id)
                    keyboardFocused = true
                } label: {
                    Image(systemName: expansion.collapsed.contains(row.id) ? "chevron.right" : "chevron.down")
                        .font(.caption.bold()).frame(width: 20, height: 24).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(row.title) \(expansion.collapsed.contains(row.id) ? "펼치기" : "접기")")
                .accessibilityValue(expansion.collapsed.contains(row.id) ? "접힘" : "펼침")
            }
            (statusText(row.status)
             + Text(row.time.isEmpty ? "" : row.time + " ").foregroundColor(.secondary)
             + Text(row.title.components(separatedBy: .newlines).joined(separator: " ")))
                .lineLimit(1)
                .truncationMode(.tail)
                .accessibilityLabel(row.line)
                .help(row.line + (row.detail.isEmpty ? "" : "\n" + row.detail))
            if row.editable && editRow != nil {
                Spacer(minLength: 0)
                Button { beginEditing(row) } label: { Image(systemName: "pencil").frame(width: 24, height: 24) }
                    .buttonStyle(.plain).accessibilityLabel("\(row.title) 편집")
                    .disabled(editing != nil)
            }
        }
        .padding(5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selectedIDs.contains(row.id) ? Color.accentColor.opacity(keyboardFocused ? 0.18 : 0.08) : .clear, in: RoundedRectangle(cornerRadius: 5))
        .overlay {
            RoundedRectangle(cornerRadius: 5)
                .stroke(selection.focus == row.id && keyboardFocused ? Color.accentColor : .clear, lineWidth: 1)
        }
        .contentShape(Rectangle())
        .onTapGesture { selection.select(row.id); keyboardFocused = true }
        .accessibilityAddTraits(selectedIDs.contains(row.id) ? .isSelected : [])
        .id("today-outline-" + row.id)
    }

    private func beginEditing(_ row: TodayOutlineRow) {
        guard editing == nil else { return }
        editing = row; editingHeading = heading; editedLine = row.line; editError = nil
        selection.select(row.id); keyboardFocused = false
        Task { @MainActor in
            await Task.yield()
            editorFocused = true
            revealRow("editor")
        }
    }

    private func saveEditing() {
        guard let editing, let editRow else { return }
        if let error = editRow(editing, editingHeading, editedLine) {
            editError = error; editorFocused = true
        } else { cancelEditing() }
    }

    private func cancelEditing() {
        editing = nil; editError = nil; editorFocused = false; keyboardFocused = true
    }

    private func statusText(_ status: DayStatus?) -> Text {
        switch status {
        case .pending: return Text("TODO ").font(.system(.caption, design: .monospaced).bold()).foregroundColor(.orange)
        case .completed: return Text("DONE ").font(.system(.caption, design: .monospaced).bold()).foregroundColor(.secondary)
        case .skipped: return Text("SKIPPED ").font(.system(.caption, design: .monospaced).bold()).foregroundColor(.secondary)
        case nil: return Text("")
        }
    }
}
