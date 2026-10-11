struct OutlineNode {
    let id: String
    var children: [OutlineNode] = []

    func find(_ target: String) -> OutlineNode? {
        if id == target { return self }
        return children.lazy.compactMap { $0.find(target) }.first
    }

    func parent(of target: String) -> String? {
        if children.contains(where: { $0.id == target }) { return id }
        return children.lazy.compactMap { $0.parent(of: target) }.first
    }
}

struct OutlineExpansion {
    private(set) var collapsed: Set<String> = []

    mutating func toggle(_ id: String) {
        if !collapsed.insert(id).inserted { collapsed.remove(id) }
    }

    func visibleIDs(in nodes: [OutlineNode]) -> [String] {
        nodes.flatMap { [$0.id] + (collapsed.contains($0.id) ? [] : visibleIDs(in: $0.children)) }
    }

    mutating func moveHorizontal(expanding: Bool, selection: inout OutlineSelection, in nodes: [OutlineNode]) {
        guard let id = selection.focus,
              let node = nodes.lazy.compactMap({ $0.find(id) }).first else { return }
        if expanding {
            if collapsed.contains(id) { collapsed.remove(id) }
            else if let child = node.children.first { selection.select(child.id) }
        } else if !node.children.isEmpty && !collapsed.contains(id) {
            collapsed.insert(id)
        } else if let parent = nodes.lazy.compactMap({ $0.parent(of: id) }).first {
            selection.select(parent)
        }
        selection.reconcile(with: visibleIDs(in: nodes))
    }
}
