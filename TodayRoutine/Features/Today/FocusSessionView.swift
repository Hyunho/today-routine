import SwiftUI

struct FocusSessionView: View {
    let model: AppModel
    let session: FocusSession
    private var routine: Routine? {
        guard case .routine(let id) = session.target else { return nil }
        return model.snapshot.routines.first { $0.id == id }
    }
    private var targetExists: Bool {
        switch session.target {
        case .routine: return routine != nil
        case .task: return false
        case .block(let id): return model.snapshot.blocks.contains { $0.id == id }
        }
    }
    private var isBlock: Bool { if case .block = session.target { return true }; return false }
    private var title: String { routine?.name ?? session.title }
    private var note: String { routine?.note ?? "" }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("집중 중", systemImage: "scope").foregroundStyle(.teal)
                Spacer()
                Button("집중 종료") { model.focusSession = nil }
            }.padding()
            ScrollView {
                VStack(alignment: .center, spacing: 28) {
                    Text(title).font(.largeTitle.bold()).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        VStack(spacing: 8) {
                            Text(session.timeLabel(at: context.date))
                                .font(.system(size: 48, weight: .medium, design: .rounded))
                                .monospacedDigit().minimumScaleFactor(0.6).lineLimit(1)
                                .accessibilityIdentifier("focus-elapsed")
                            Text("집중한 시간").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if !targetExists { Text("이 작업이 삭제되었습니다. 집중을 종료해 주세요.").foregroundStyle(.secondary) }
                    if !note.isEmpty { Text(note).frame(maxWidth: .infinity, alignment: .leading) }
                    if let routine, RoutineRules.dayKey(session.day) >= RoutineRules.dayKey(Date()) {
                        VStack(spacing: 12) {
                            ForEach(model.steps(for: routine)) { step in
                                Button {
                                    model.perform { try $0.toggleStep(routineID: routine.id, stepID: step.id, date: session.day) }
                                } label: {
                                    Label(step.name, systemImage: model.record(routine, date: session.day)?.completedStepIDs.contains(step.id) == true ? "checkmark.square.fill" : "square")
                                        .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                                }.buttonStyle(.bordered)
                            }
                        }
                    }
                }.padding(24).frame(maxWidth: 560).frame(maxWidth: .infinity)
            }
            if !isBlock {
                Button("작업 완료하고 종료", systemImage: "checkmark.circle.fill") { complete() }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(!targetExists).padding(24)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func complete() {
        let saved: Bool
        switch session.target {
        case .routine(let id):
            saved = model.perform { try $0.setStatus(routineID: id, date: session.day, status: .completed) }
        case .task:
            saved = true // Legacy sessions may only be closed, never written back.
        case .block: saved = true
        }
        if saved { model.focusSession = nil }
    }
}
