import Foundation
import Observation
import OSLog
struct SyncCSVLink: Identifiable { var id: UUID; var name: String; var url: URL }
@MainActor @Observable final class SyncCoordinator {
    let adapter: StoreSyncAdapter
    var latestCSV: [SyncCSVLink] = []
    var conflicts: [CSVConflict] = []
    var status = "기기에만 저장"
    var folderName: String?
    var lastChecked: Date?
    var pendingCount = 0
    private(set) var isRequestingCloudSync = false
    private(set) var cloudTransferStatus: String?
    var onChange: (() -> Void)?
    private(set) var listLayout = ListLayoutConfig()
    private(set) var listLayoutStatus = ""
    var listLayoutFileURL: URL? { transport?.root.appendingPathComponent("Config/list-layout.json") }
    private var layoutRevision = 0
    private var savingLayout = false
    func saveListLayout(_ value: ListLayoutConfig) async throws {
        guard let transport else { throw SyncError.invalid("동기화 폴더가 연결되어 있지 않습니다.") }
        guard !savingLayout else { throw SyncError.invalid("설정을 저장 중입니다. 잠시 후 다시 시도해 주세요.") }
        savingLayout = true
        layoutRevision += 1
        let token = generation
        defer { savingLayout = false }
        try await transport.saveListLayout(value)
        guard token == generation else { throw CancellationError() }
        listLayout = value
        listLayoutStatus = "설정을 저장하고 타임라인에 적용했습니다."
    }
    func reloadListLayout() async {
        guard let transport, !savingLayout else { return }
        let token = generation
        let revision = layoutRevision
        do {
            let value = try await transport.loadListLayout(migratingFrom: ListLayoutConfig.fileURL)
            guard token == generation, revision == layoutRevision else { return }
            if listLayout != value { listLayout = value }
            listLayoutStatus = "동기화 폴더의 설정을 불러왔습니다. 누락되거나 잘못된 값은 기본값을 사용합니다."
        } catch is CancellationError {
            return
        } catch is SyncDownloadPending {
            guard token == generation, revision == layoutRevision else { return }
            listLayoutStatus = "설정 파일 다운로드를 기다리고 있습니다. 현재 설정을 유지합니다."
        } catch {
            guard token == generation, revision == layoutRevision else { return }
            listLayoutStatus = "설정 파일을 읽을 수 없어 마지막 정상 설정을 유지합니다. \(error.localizedDescription)"
        }
    }
    private let automatic: Bool
    private let access: SyncFolderAccess
    private var transport: SyncFolderTransport?
    private var monitor: FileChangeMonitor?
    private var debounce: Task<Void,Never>?
    private var timer: Task<Void,Never>?
    private var active = true
    private var busy = false
    private var rerun = false
    private var retryDelay: Double?
    private var retryNotBefore = Date.distantPast
    private var generation = 0
    private var retry = 0
    private var receiptIDs: Set<UUID>?
    private var processedIDs: Set<UUID>?
    private var lastExportDay: String?
    private var csvConflicts: [URL: [CSVConflict]] = [:]
    private var csvWarnings: [URL: String] = [:]
    private var refreshTask: Task<Void, Never>?
    private var idlePollInterval: Double = 15
    private let logger = Logger(subsystem: "com.hyunho.TodayRoutine", category: "Sync")
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
            listLayout = ListLayoutConfig(); listLayoutStatus = ""
            processedIDs = nil; lastExportDay = nil; csvConflicts = [:]; csvWarnings = [:]; retryNotBefore = .distantPast
            monitor?.stop()
            if automatic { monitor = FileChangeMonitor(url:url) { [weak self] in Task { @MainActor in self?.localDataDidChange() } } }
            await refresh(); setActive(active)
        } catch { status = "연결하지 못했습니다: \(error.localizedDescription)" }
    }
    func localDataDidChange() { idlePollInterval = 15; schedule(after: 0.5) }
    private func schedule(after seconds: Double) {
        guard automatic, active, !isRequestingCloudSync, transport != nil else { return }
        // Coalesce notifications without postponing indefinitely or cancelling an active read.
        if busy { rerun = true; return }
        guard debounce == nil else { return }
        let delay = max(seconds, retryNotBefore.timeIntervalSinceNow)
        debounce = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard !Task.isCancelled else { return }
            self?.debounce = nil
            await self?.refresh()
        }
    }
    func setActive(_ value: Bool) {
        active = value; timer?.cancel(); timer = nil
        if !value {
            debounce?.cancel(); debounce = nil; refreshTask?.cancel(); rerun = false; retryDelay = nil
            return
        }
        idlePollInterval = 15
        guard automatic, transport != nil else { return }
        schedule(after:0)
        timer = Task { [weak self] in
            while !Task.isCancelled {
                let delay = self?.idlePollInterval ?? 120
                do { try await Task.sleep(for: .seconds(delay)) } catch { return }
                guard !Task.isCancelled else { return }; await self?.refresh()
            }
        }
    }
    func refresh(manual: Bool = false) async {
        guard !isRequestingCloudSync || manual else { return }
        guard let transport else { return }
        if automatic && !manual && Date() < retryNotBefore {
            schedule(after: retryNotBefore.timeIntervalSinceNow)
            return
        }
        if busy { rerun = true; return }
        busy = true
        let task = Task { await self.performRefresh(transport: transport, manual: manual) }
        refreshTask = task
        await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
        refreshTask = nil; busy = false
        if let delay = retryDelay {
            retryDelay = nil; rerun = false; schedule(after: delay)
        } else if rerun { rerun = false; schedule(after: 0.5) }
    }
    private func performRefresh(transport: SyncFolderTransport, manual: Bool) async {
        let token = generation
        do {
            try Task.checkCancellation()
            await reloadListLayout()
            guard token == generation else { return }
            try Task.checkCancellation()
            guard let config = try adapter.configuration() else { return }
            let localIDs = Set(try adapter.entries().map(\.id))
            let today = Date(), day = RoutineRules.dayKey(today)
            let batch = try await transport.readBatch(incremental: !manual, deferDocuments: true, allowPartialDownloads: true)
            let context = journalContext(localIDs.union(batch.events.map(\.id)))
            let documentURLs = manual ? batch.documentURLs.sorted { $0.path < $1.path } : await transport.documentsToProcess(in: batch, context: context)
            var waitingDownloads = batch.waitingDownloads
            logger.info("Sync scan: documents \(documentURLs.count)/\(batch.documentURLs.count), events \(batch.events.count), waiting \(waitingDownloads.count)")
            try Task.checkCancellation()
            guard token == generation else { return }
            if waitingDownloads.isEmpty && !batch.hasChanges && batch.events.isEmpty && documentURLs.isEmpty,
               processedIDs == localIDs, lastExportDay == day {
                idlePollInterval = min(idlePollInterval * 2, 120)
                finishRefresh(batch: batch, ids: localIDs, deviceID: config.deviceID)
                await transport.acknowledge(batch)
                return
            }
            idlePollInterval = 15
            status = "변경 확인 중"
            let existing = try adapter.events(), known = Set(existing.map(\.id))
            // Validate even duplicate payloads, then avoid replaying unchanged data into active editors.
            _ = try SyncReducer.reduce(existing+batch.events)
            let incoming = batch.events.filter { !known.contains($0.id) }
            if !incoming.isEmpty { try adapter.ingest(incoming); onChange?() }
            await transport.acknowledgeEvents(in: batch)
            // Do not interpret CSV edits against a journal that is still downloading.
            if waitingDownloads.contains(where: { $0.path.hasPrefix(transport.root.path + "/changes/") }) {
                throw SyncDownloadPending(urls: Array(waitingDownloads))
            }
            csvConflicts = csvConflicts.filter { batch.documentURLs.contains($0.key) }
            csvWarnings = csvWarnings.filter { batch.documentURLs.contains($0.key) }
            var events = try adapter.events()
            var currentState = try SyncReducer.reduce(events)
            for url in documentURLs {
                try Task.checkCancellation()
                let file: SyncCSVFile
                do { file = try await transport.readDocument(at: url) }
                catch let pending as SyncDownloadPending {
                    waitingDownloads.formUnion(pending.urls)
                    continue
                }
                try Task.checkCancellation()
                guard token == generation else { return }
                // A local edit can arrive while file I/O is suspended.
                if Set(try adapter.entries().map(\.id)) != Set(events.map(\.id)) {
                    events = try adapter.events()
                    currentState = try SyncReducer.reduce(events)
                }
                var completed = false
                do {
                    var doc = file.document
                    let sourceEvents = events.filter { $0.csvDocumentID == doc.documentID }
                    let normalized = try CSVCodec.encode(CSVCodec.decode(file.data))
                    let hash = SyncCoding.hash(normalized)
                    doc.state = try SyncReducer.reduce(sourceEvents,initial:doc.state)
                    doc.dates = Set(doc.dates).union(doc.state.objects.values.filter { $0.kind == .record && $0.fields["routineID"] == doc.routineID.uuidString }.compactMap { $0.fields["dayKey"] }).sorted()
                    let result = try CSVImporter.diff(data:file.data,baseline:doc,current:currentState)
                    let resolved = Set(events.flatMap { $0.resolvedConflicts ?? [] })
                    func alreadyApplied(_ op: SyncOperation) -> Bool {
                        let fields = Set(op.values.keys.filter { $0.hasPrefix("step/") || $0 == "status" })
                        return !fields.isEmpty && fields.allSatisfy { field in
                            sourceEvents.contains { event in event.csvHash == hash && event.operations.contains { $0.id == op.id && $0.values[field] != nil } }
                        }
                    }
                    let pendingConflicts = result.conflicts.filter { !resolved.contains($0.id) && !alreadyApplied($0.operation) }
                    csvConflicts[file.url] = pendingConflicts
                    csvWarnings.removeValue(forKey: file.url)
                    // Each independently accepted cell has its own canonical identity. A peer's
                    // conflict subset cannot change the bytes stored under another cell's ID.
                    for event in try CSVImporter.cellEvents(result.operations,document:doc,hash:hash) {
                        if !event.operations.allSatisfy(alreadyApplied) {
                            try adapter.appendLocal(event)
                            events = try adapter.events()
                            currentState = try SyncReducer.reduce(events)
                            onChange?()
                        }
                    }
                    completed = true
                } catch is CancellationError { throw CancellationError() }
                catch {
                    csvConflicts.removeValue(forKey: file.url)
                    csvWarnings[file.url] = "\(file.document.name): \(error.localizedDescription)"
                }
                if completed {
                    await transport.acknowledgeDocument(at: url, in: batch, context: journalContext(Set(events.map(\.id))))
                }
            }
            conflicts = csvConflicts.keys.sorted { $0.path < $1.path }.flatMap { csvConflicts[$0] ?? [] }
            try Task.checkCancellation()
            let pending = try adapter.pendingEvents(); pendingCount = pending.count
            try await transport.publish(pending)
            guard token == generation else { return }
            if !pending.isEmpty { try adapter.markPublished(ids:pending.map(\.id)) }
            pendingCount = try adapter.pendingEvents().count
            let ids = Set(try adapter.entries().map(\.id))
            if processedIDs != ids || lastExportDay != day || latestCSV.contains(where: { !batch.documentURLs.contains($0.url) }) {
                let state = try adapter.exportState()
                let spaceID = config.spaceID
                let export = Task.detached(priority: .utility) {
                    try RoutineCSVDocument.makeAll(spaceID: spaceID, state: state, today: today)
                }
                let documents = try await withTaskCancellationHandler { try await export.value } onCancel: { export.cancel() }
                try Task.checkCancellation()
                guard token == generation else { return }
                var links: [SyncCSVLink] = []
                for var doc in documents {
                    try Task.checkCancellation()
                    doc.documentID = SyncCoding.stableID(doc.documentID.uuidString + config.deviceID.uuidString)
                    let url = try await transport.publishCSV(doc, deviceID: config.deviceID)
                    guard token == generation else { return }
                    links.append(SyncCSVLink(id: doc.routineID, name: doc.name, url: url))
                }
                latestCSV = links
                lastExportDay = day
            }
            if receiptIDs != ids {
                try await transport.writeReceipt(SyncReceipt(spaceID:config.spaceID,deviceID:config.deviceID,applied:ids.sorted{$0.uuidString<$1.uuidString},date:Date()))
                guard token == generation else { return }; receiptIDs = ids
            }
            try Task.checkCancellation()
            processedIDs = ids
            if !waitingDownloads.isEmpty { throw SyncDownloadPending(urls: Array(waitingDownloads)) }
            finishRefresh(batch: batch, ids: ids, deviceID: config.deviceID)
            await transport.acknowledge(batch)
        } catch is CancellationError {
            if token == generation { status = "동기화 일시 중지" }
        } catch {
            if token == generation {
                logger.error("Sync refresh failed: \(error.localizedDescription, privacy: .public)")
                pendingCount = (try? adapter.pendingEvents().count) ?? pendingCount
                status = "동기화 대기: \(error.localizedDescription)"
                let delays = [2.0,5,15,60]
                let delay = delays[min(retry,3)]
                retryDelay = delay; retryNotBefore = Date().addingTimeInterval(delay); retry += 1
            }
        }
    }
    private func journalContext(_ ids: Set<UUID>) -> String {
        SyncCoding.hash(Data(ids.map(\.uuidString).sorted().joined(separator: ",").utf8))
    }
    private func finishRefresh(batch: SyncFolderBatch, ids: Set<UUID>, deviceID: UUID) {
        lastChecked = Date(); retry = 0; retryNotBefore = .distantPast
        let peers = batch.receipts.filter { $0.deviceID != deviceID }
        let acknowledged = !peers.isEmpty && peers.allSatisfy { ids.isSubset(of: Set($0.applied)) }
        let warnings = csvWarnings.keys.sorted { $0.path < $1.path }.compactMap { csvWarnings[$0] }
        if !warnings.isEmpty { status = "CSV 확인 필요: " + warnings.joined(separator: "\n") }
        else if !conflicts.isEmpty { status = "CSV 충돌 \(conflicts.count)개 확인 필요" }
        else { status = acknowledged ? "모든 연결 기기에서 적용 확인" : "폴더 저장 완료 · 상대 기기 확인 대기" }
    }
    func syncNow() async {
        guard !isRequestingCloudSync, let transport else { return }
        guard !busy else { cloudTransferStatus = "현재 확인이 끝난 뒤 다시 눌러 주세요."; return }
        isRequestingCloudSync = true
        debounce?.cancel(); debounce = nil
        let token = generation
        defer { isRequestingCloudSync = false; if token == generation { schedule(after: 2) } }
        do {
            cloudTransferStatus = "iCloud에서 최신 파일 다운로드를 요청하는 중"
            let deviceID = try adapter.configuration()?.deviceID
            let download = try await transport.requestCloudTransfer(upload: false, deviceID: deviceID)
            guard token == generation else { return }
            cloudTransferStatus = "다운로드 요청 완료 · 변경 파일을 확인하고 저장하는 중"
            await refresh(manual: true)
            guard token == generation else { return }
            cloudTransferStatus = "iCloud 업로드 상태를 확인하는 중"
            var report = try await transport.requestCloudTransfer(upload: true, deviceID: deviceID)
            guard token == generation else { return }
            report.downloadsRequested = download.downloadsRequested
            report.failures += download.failures
            if report.lastError == nil { report.lastError = download.lastError }
            cloudTransferStatus = report.summary
        } catch {
            if token == generation { cloudTransferStatus = "전송 요청을 완료하지 못했습니다: \(error.localizedDescription)" }
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
        generation += 1; debounce?.cancel(); debounce = nil; timer?.cancel(); refreshTask?.cancel(); monitor?.stop(); monitor = nil
        processedIDs = nil; lastExportDay = nil; csvConflicts = [:]; csvWarnings = [:]; retryNotBefore = .distantPast; rerun = false; retryDelay = nil
        cloudTransferStatus = nil; transport = nil; access.disconnect(); folderName = nil; latestCSV = []; conflicts = []; status = "기기에만 저장"
    }
}
