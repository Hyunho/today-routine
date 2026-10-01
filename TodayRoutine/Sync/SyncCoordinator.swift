import Foundation
import Observation
struct SyncCSVLink: Identifiable { var id: UUID; var name: String; var url: URL }
@MainActor @Observable final class SyncCoordinator {
    let adapter: StoreSyncAdapter
    var latestCSV: [SyncCSVLink] = []
    var conflicts: [CSVConflict] = []
    var status = "기기에만 저장"
    var folderName: String?
    var lastChecked: Date?
    var pendingCount = 0
    var onChange: (() -> Void)?
    private let automatic: Bool
    private let access: SyncFolderAccess
    private var transport: SyncFolderTransport?
    private var monitor: FileChangeMonitor?
    private var debounce: Task<Void,Never>?
    private var timer: Task<Void,Never>?
    private var active = true
    private var busy = false
    private var rerun = false
    private var generation = 0
    private var retry = 0
    private var receiptIDs: Set<UUID>?
    init(store: RoutineStore, automatic: Bool = true, access: SyncFolderAccess? = nil) {
        adapter = StoreSyncAdapter(store:store); self.automatic = automatic; self.access = access ?? SyncFolderAccess()
    }
    func restore() async {
        do { if (try adapter.configuration())?.enabled == true, let url = try access.restore() { await connect(url:url,persist:false) } }
        catch { status = "폴더를 다시 선택해 주세요: \(error.localizedDescription)" }
    }
    func connect(url: URL, persist: Bool = true) async {
        guard !busy else { status = "현재 확인이 끝난 뒤 폴더를 다시 선택해 주세요."; return }
        do {
            // Open the selected scope before any I/O; a failed connection leaves local records intact.
            if persist { try access.connect(url:url) }
            let candidate = SyncFolderTransport(root:url), space = try await candidate.open()
            try adapter.enable(spaceID:space,deviceID:UUID())
            generation += 1; transport = candidate; folderName = url.lastPathComponent; receiptIDs = nil
            monitor?.stop()
            if automatic { monitor = FileChangeMonitor(url:url) { [weak self] in Task { @MainActor in self?.localDataDidChange() } } }
            await refresh(); setActive(active)
        } catch { status = "연결하지 못했습니다: \(error.localizedDescription)" }
    }
    func localDataDidChange() { schedule(after:0.5) }
    private func schedule(after seconds: Double) {
        guard automatic, active, transport != nil else { return }
        debounce?.cancel()
        debounce = Task { [weak self] in
            do { try await Task.sleep(nanoseconds:UInt64(seconds*1_000_000_000)) } catch { return }
            guard !Task.isCancelled else { return }; await self?.refresh()
        }
    }
    func setActive(_ value: Bool) {
        active = value; timer?.cancel(); timer = nil
        if !value { debounce?.cancel(); return }
        guard automatic, transport != nil else { return }
        schedule(after:0)
        timer = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds:15_000_000_000) } catch { return }
                guard !Task.isCancelled else { return }; await self?.refresh()
            }
        }
    }
    func refresh() async {
        guard let transport else { return }
        if busy { rerun = true; return }
        busy = true; let token = generation
        defer { busy = false; if rerun { rerun = false; schedule(after:0.5) } }
        do {
            status = "변경 확인 중"
            guard let config = try adapter.configuration() else { return }
            let batch = try await transport.readBatch()
            guard token == generation else { return }
            let existing = try adapter.events(), known = Set(existing.map(\.id))
            // Validate even duplicate payloads, then avoid replaying unchanged data into active editors.
            _ = try SyncReducer.reduce(existing+batch.events)
            let incoming = batch.events.filter { !known.contains($0.id) }
            if !incoming.isEmpty { try adapter.ingest(incoming); onChange?() }
            conflicts = []
            var warnings: [String] = []
            for file in batch.documents {
                do {
                    var doc = file.document
                    let events = try adapter.events()
                    let sourceEvents = events.filter { $0.csvDocumentID == doc.documentID }
                    let normalized = try CSVCodec.encode(CSVCodec.decode(file.data))
                    let hash = SyncCoding.hash(normalized)
                    doc.state = try SyncReducer.reduce(sourceEvents,initial:doc.state)
                    doc.dates = Set(doc.dates).union(doc.state.objects.values.filter { $0.kind == .record && $0.fields["routineID"] == doc.routineID.uuidString }.compactMap { $0.fields["dayKey"] }).sorted()
                    let result = try CSVImporter.diff(data:file.data,baseline:doc,current:adapter.exportState())
                    let resolved = Set(events.flatMap { $0.resolvedConflicts ?? [] })
                    func alreadyApplied(_ op: SyncOperation) -> Bool {
                        let fields = Set(op.values.keys.filter { $0.hasPrefix("step/") || $0 == "status" })
                        return !fields.isEmpty && fields.allSatisfy { field in
                            sourceEvents.contains { event in event.csvHash == hash && event.operations.contains { $0.id == op.id && $0.values[field] != nil } }
                        }
                    }
                    let pendingConflicts = result.conflicts.filter { !resolved.contains($0.id) && !alreadyApplied($0.operation) }
                    conflicts.append(contentsOf:pendingConflicts)
                    // Each independently accepted cell has its own canonical identity. A peer's
                    // conflict subset cannot change the bytes stored under another cell's ID.
                    for event in try CSVImporter.cellEvents(result.operations,document:doc,hash:hash) {
                        if !event.operations.allSatisfy(alreadyApplied) { try adapter.appendLocal(event); onChange?() }
                    }
                } catch { warnings.append("\(file.document.name): \(error.localizedDescription)") }
            }
            let pending = try adapter.pendingEvents(); pendingCount = pending.count
            try await transport.publish(pending)
            guard token == generation else { return }
            if !pending.isEmpty { try adapter.markPublished(ids:pending.map(\.id)) }
            pendingCount = try adapter.pendingEvents().count
            let state = try adapter.exportState()
            var links: [SyncCSVLink] = []
            for routine in state.objects.values.filter({$0.kind == .routine}).sorted(by:{$0.id < $1.id}) {
                var doc = try RoutineCSVDocument.make(routineID:UUID(uuidString:routine.id)!,spaceID:config.spaceID,state:state,today:Date())
                doc.documentID = SyncCoding.stableID(doc.documentID.uuidString+config.deviceID.uuidString)
                let url = try await transport.publishCSV(doc,deviceID:config.deviceID)
                guard token == generation else { return }
                links.append(SyncCSVLink(id:doc.routineID,name:doc.name,url:url))
            }
            latestCSV = links
            let ids = Set(try adapter.events().map(\.id))
            if receiptIDs != ids {
                try await transport.writeReceipt(SyncReceipt(spaceID:config.spaceID,deviceID:config.deviceID,applied:ids.sorted{$0.uuidString<$1.uuidString},date:Date()))
                guard token == generation else { return }; receiptIDs = ids
            }
            lastChecked = Date(); retry = 0
            let peers = batch.receipts.filter { $0.deviceID != config.deviceID }
            let acknowledged = !peers.isEmpty && peers.allSatisfy { ids.isSubset(of:Set($0.applied)) }
            if !warnings.isEmpty { status = "CSV 확인 필요: "+warnings.joined(separator:"\n") }
            else if !conflicts.isEmpty { status = "CSV 충돌 \(conflicts.count)개 확인 필요" }
            else { status = acknowledged ? "모든 연결 기기에서 적용 확인":"폴더 저장 완료 · 상대 기기 확인 대기" }
        } catch {
            if token == generation {
                pendingCount = (try? adapter.pendingEvents().count) ?? pendingCount
                status = "동기화 대기: \(error.localizedDescription)"
                let delays = [2.0,5,15,60]; schedule(after:delays[min(retry,3)]); retry += 1
            }
        }
    }
    func resolve(_ conflict: CSVConflict, useCSV: Bool) async {
        do {
            guard let config = try adapter.configuration() else { return }
            let state = try adapter.exportState(); var op = conflict.operation
            if !useCSV { for key in op.values.keys { op.values[key] = state.objects[op.key]?.fields[key] ?? (key == "status" ? "pending":"false") } }
            var event = SyncEvent(spaceID:config.spaceID,id:UUID(),deviceID:config.deviceID,counter:state.counter+1,createdAt:Date(),operations:[op])
            event.resolvedConflicts = [conflict.id]
            try adapter.appendLocal(event); onChange?(); await refresh()
        } catch { status = "충돌 선택을 저장하지 못했습니다: \(error.localizedDescription)" }
    }
    func disconnect() {
        do { try adapter.disconnect() } catch { status = error.localizedDescription; return }
        generation += 1; debounce?.cancel(); timer?.cancel(); monitor?.stop(); monitor = nil
        transport = nil; access.disconnect(); folderName = nil; latestCSV = []; conflicts = []; status = "기기에만 저장"
    }
}
