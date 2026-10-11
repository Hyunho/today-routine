/// Selection follows stable row IDs while a live, read-only outline refreshes.
struct OutlineSelection: Equatable {
    private(set) var anchor: String?
    private(set) var focus: String?

    mutating func select(_ id: String, extending: Bool = false) {
        if !extending || anchor == nil { anchor = id }
        focus = id
    }

    mutating func move(by offset: Int, extending: Bool, in ids: [String]) {
        guard !ids.isEmpty else { clear(); return }
        reconcile(with: ids)
        let index = focus.flatMap { ids.firstIndex(of: $0) }
        let target = index.map { min(ids.count - 1, max(0, $0 + offset)) } ?? (offset < 0 ? ids.count - 1 : 0)
        select(ids[target], extending: extending)
    }

    mutating func selectAll(in ids: [String]) {
        anchor = ids.first
        focus = ids.last
    }

    mutating func clear() { anchor = nil; focus = nil }

    mutating func reconcile(with ids: [String]) {
        guard let focus, ids.contains(focus) else { clear(); return }
        if anchor.map({ ids.contains($0) }) != true { anchor = focus }
    }

    func selectedIDs(in ids: [String]) -> [String] {
        guard let anchor, let focus,
              let start = ids.firstIndex(of: anchor), let end = ids.firstIndex(of: focus) else { return [] }
        return Array(ids[min(start, end)...max(start, end)])
    }
}
