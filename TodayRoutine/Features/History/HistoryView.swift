import SwiftUI
struct HistoryView: View {
    let model: AppModel
    @State private var date = Date()
    var start: Date { RoutineRules.weekStart(date) }
    var records: [RoutineDayRecord] { let first = RoutineRules.dayKey(start), end = RoutineRules.dayKey(RoutineRules.calendar.date(byAdding: .day, value: 7, to: start)!); return model.snapshot.records.filter { $0.dayKey >= first && $0.dayKey < end && $0.status == .completed } }
    var body: some View {
        NavigationStack { List {
            Section {
                DatePicker("주간 기준일", selection: $date, displayedComponents: .date)
                Text("이번 주 \(records.count)회 완료").font(.title2.bold()).padding(.vertical,8)
                Text("\(RoutineRules.dayKey(start))부터 · 한국 시간").font(.caption).foregroundStyle(.secondary)
            }
            Section("하루의 기록") { ForEach(0..<7, id: \.self) { offset in
                let d = RoutineRules.calendar.date(byAdding: .day, value: offset, to: start)!, key = RoutineRules.dayKey(d)
                HStack { Text(d, format: .dateTime.weekday(.wide).month().day()); Spacer(); Text("\(records.filter { $0.dayKey == key }.count)회").monospacedDigit().foregroundStyle(.teal) }
            } }
            Section("루틴별 완료") { ForEach(model.snapshot.routines.sorted { $0.sortOrder < $1.sortOrder }) { r in
                let count = RoutineRules.completedCount(routineID: r.id, records: records, week: date)
                VStack(alignment: .leading, spacing: 8) { HStack { Text(r.name); Spacer(); Text(r.repeatKind == .weeklyGoal ? "\(count)/\(r.weeklyTarget)회" : "\(count)회").foregroundStyle(.secondary) }; if r.repeatKind == .weeklyGoal { ProgressView(value: Double(min(count,r.weeklyTarget)), total: Double(r.weeklyTarget)) } }
            } }
            if records.isEmpty { EmptyHint(title: "기록이 쌓이는 중이에요", message: "루틴을 완료하면 주간 기록에서 확인할 수 있어요.", symbol: "chart.bar") }
        }.navigationTitle("주간 기록") }
    }
}
