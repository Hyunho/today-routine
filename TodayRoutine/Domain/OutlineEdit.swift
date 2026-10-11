import Foundation

struct OutlineEdit {
    let status: DayStatus?
    let minute: Int?
    let title: String

    init(line: String, expectsStatus: Bool) throws {
        guard !line.contains(where: { $0.isNewline }) else { throw StoreError.invalid("항목은 한 줄로 입력해 주세요.") }
        var parts = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        if expectsStatus {
            guard let first = parts.first, ["TODO", "DONE", "SKIPPED"].contains(first) else {
                throw StoreError.invalid("TODO, DONE 또는 SKIPPED로 시작해 주세요.")
            }
            let token = parts.removeFirst()
            status = token == "TODO" ? .pending : token == "DONE" ? .completed : .skipped
        } else { status = nil }
        if let first = parts.first, first.contains(":"), first.first?.isNumber == true {
            let pieces = first.split(separator: ":", omittingEmptySubsequences: false)
            guard pieces.count == 2, pieces[0].count == 2, pieces[1].count == 2,
                  let h = Int(pieces[0]), let m = Int(pieces[1]), (0..<24).contains(h), (0..<60).contains(m) else {
                throw StoreError.invalid("시간은 14:00처럼 00:00~23:59 범위로 입력해 주세요.")
            }
            minute = h * 60 + m; parts.removeFirst()
        } else { minute = nil }
        title = parts.joined(separator: " ")
        guard !title.isEmpty else { throw StoreError.invalid("제목을 입력해 주세요.") }
    }

    static func line(title: String, minute: Int?, status: DayStatus?) -> String {
        let state = status.map { $0 == .pending ? "TODO" : $0 == .completed ? "DONE" : "SKIPPED" } ?? ""
        return [state, minute.map { RoutineRules.timeLabel($0) } ?? "", title]
            .filter { !$0.isEmpty }.joined(separator: " ").components(separatedBy: .newlines).joined(separator: " ")
    }
}
