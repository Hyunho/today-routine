import Foundation
import Darwin
struct SyncDownloadPending: LocalizedError {
    let urls: [URL]
    var errorDescription: String? { "iCloud 다운로드 대기 \(urls.count)개 · 받은 파일은 처리 완료" }
}
struct SyncCSVFile { var document: RoutineCSVDocument; var data: Data; var url: URL }
struct SyncReceipt: Codable { var version = 1; var spaceID: UUID; var deviceID: UUID; var applied: [UUID]; var date: Date }
struct SyncFolderBatch {
    var events: [SyncEvent] = []
    var documents: [SyncCSVFile] = []
    var receipts: [SyncReceipt] = []
    var hasChanges = true
    var documentURLs: Set<URL> = []
    var changedDocumentURLs: [URL] = []
    var waitingDownloads: Set<URL> = []
    fileprivate var eventPaths: [String] = []
    fileprivate var scanID = UUID()
}
// Metadata only: never retain decoded historical baselines between refreshes.
// ctime and inode also detect replacements/edits that preserve size and mtime.
private struct SyncFileStamp: Equatable {
    let device: Int32
    let inode: UInt64
    let size: Int64
    let modifiedSeconds: Int
    let modifiedNanoseconds: Int
    let changedSeconds: Int
    let changedNanoseconds: Int
    init(_ info: stat) {
        device = info.st_dev; inode = info.st_ino; size = info.st_size
        modifiedSeconds = info.st_mtimespec.tv_sec; modifiedNanoseconds = info.st_mtimespec.tv_nsec
        changedSeconds = info.st_ctimespec.tv_sec; changedNanoseconds = info.st_ctimespec.tv_nsec
    }
}
private struct SpaceManifest: Codable { var version = 1; var spaceID: UUID }
private struct FileEnvelope: Codable { var version = 1; var hash: String; var payload: Data }
private struct CSVManifest: Codable { var version = 1; var baselineHash: String }
actor SyncFolderTransport {
    let root: URL
    private var expectedSpace: UUID?
    private var acknowledgedFiles: [String: SyncFileStamp] = [:]
    private var documentContexts: [URL: String] = [:]
    private var pendingScan: (id: UUID, files: [String: SyncFileStamp])?
    // Counters help distinguish actual writes from repeated coordination during hang diagnostics.
    private(set) var writeCoordinationCount = 0
    init(root: URL) { self.root = root.resolvingSymlinksInPath().standardizedFileURL }
    func loadListLayout(migratingFrom localURL: URL) throws -> ListLayoutConfig {
        let url = root.appendingPathComponent("Config/list-layout.json")
        func exists() throws -> Bool {
            _ = try checked(url)
            let placeholder = url.deletingLastPathComponent().appendingPathComponent(".list-layout.json.icloud")
            return FileManager.default.fileExists(atPath: url.path) || FileManager.default.fileExists(atPath: placeholder.path)
        }
        if try coordinated(write: false, { try exists() }) {
            return try coordinated(write: false) { try JSONDecoder().decode(ListLayoutConfig.self, from: read(url)) }
        }
        return try coordinated(write: true) {
            // Another device may have supplied the file since the initial check.
            if try !exists() {
                let config: ListLayoutConfig
                if FileManager.default.fileExists(atPath: localURL.path) {
                    config = try JSONDecoder().decode(ListLayoutConfig.self, from: Data(contentsOf: localURL))
                } else { config = ListLayoutConfig() }
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try write(encoder.encode(config), to: url, immutable: true)
            }
            return try JSONDecoder().decode(ListLayoutConfig.self, from: read(url))
        }
    }
    func saveListLayout(_ config: ListLayoutConfig) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try coordinated(write: true) {
            let url = root.appendingPathComponent("Config/list-layout.json")
            _ = try checked(url)
            let placeholder = url.deletingLastPathComponent().appendingPathComponent(".list-layout.json.icloud")
            // Do not overwrite a cloud copy that has not finished downloading.
            if FileManager.default.fileExists(atPath: url.path) || FileManager.default.fileExists(atPath: placeholder.path) {
                _ = try read(url)
            }
            try write(data, to: url, immutable: false)
        }
    }
    private func coordinated<T>(write: Bool, _ body: () throws -> T) throws -> T {
        var result: Result<T,Error>?, failure: NSError?
        let coordinator = NSFileCoordinator(filePresenter:nil)
        if write { writeCoordinationCount += 1; coordinator.coordinate(writingItemAt:root,options:.forMerging,error:&failure) { _ in result = Result { try body() } } }
        else { coordinator.coordinate(readingItemAt:root,options:[],error:&failure) { _ in result = Result { try body() } } }
        if let failure { throw failure }
        guard let result else { throw SyncError.invalid("폴더 접근 권한을 다시 연결해 주세요.") }
        return try result.get()
    }
    private func checked(_ url: URL) throws -> URL {
        let canonicalRoot = root.resolvingSymlinksInPath().standardizedFileURL.path
        let actual = url.resolvingSymlinksInPath().standardizedFileURL.path
        guard actual == canonicalRoot || actual.hasPrefix(canonicalRoot+"/") else { throw SyncError.invalid("폴더 밖으로 연결된 파일은 사용할 수 없습니다: \(url.lastPathComponent)") }
        var cursor = url.standardizedFileURL
        while cursor.path != root.path && cursor.path.count >= root.path.count {
            if (try? cursor.resourceValues(forKeys:[.isSymbolicLinkKey]).isSymbolicLink) == true { throw SyncError.invalid("동기화 폴더 안의 심볼릭 링크는 사용할 수 없습니다.") }
            cursor.deleteLastPathComponent()
        }
        return url
    }
    private func read(_ url: URL) throws -> Data {
        try Task.checkCancellation()
        _ = try checked(url)
        let placeholder = url.deletingLastPathComponent().appendingPathComponent("." + url.lastPathComponent + ".icloud")
        if FileManager.default.fileExists(atPath: placeholder.path) {
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            throw SyncDownloadPending(urls: [url])
        }
        let values = try url.resourceValues(forKeys:[.isUbiquitousItemKey,.ubiquitousItemDownloadingStatusKey,.fileSizeKey])
        if values.isUbiquitousItem == true && values.ubiquitousItemDownloadingStatus != .current {
            try FileManager.default.startDownloadingUbiquitousItem(at:url)
            throw SyncDownloadPending(urls: [url])
        }
        if NSFileVersion.unresolvedConflictVersionsOfItem(at:url)?.isEmpty == false { throw SyncError.invalid("iCloud에 충돌 사본이 있습니다. 파일 앱 또는 Finder에서 사본을 확인해 주세요: \(url.lastPathComponent)") }
        guard (values.fileSize ?? 0) <= 30_000_000 else { throw SyncError.invalid("파일이 너무 큽니다: \(url.lastPathComponent)") }
        return try Data(contentsOf:url)
    }
    private func write(_ data: Data, to url: URL, immutable: Bool) throws {
        _ = try checked(url)
        try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
        if immutable && FileManager.default.fileExists(atPath:url.path) {
            guard try read(url) == data else { throw SyncError.invalid("기존 동기화 파일과 내용이 다릅니다: \(url.lastPathComponent)") }; return
        }
        try data.write(to:url,options:.atomic)
    }
    private func manifest() throws -> SpaceManifest {
        let m = try SyncCoding.decode(SpaceManifest.self,from:read(root.appendingPathComponent("space.json")))
        guard m.version == 1, expectedSpace == nil || expectedSpace == m.spaceID else { throw SyncError.invalid("동기화 폴더의 버전 또는 공간 ID가 바뀌었습니다.") }
        return m
    }
    // Invoked only by the explicit sync button. Metadata scanning stays off the UI actor.
    func requestCloudTransfer(upload: Bool, deviceID: UUID?) async throws -> CloudTransferReport {
        var report = CloudTransferReport()
        let cloud = try root.resourceValues(forKeys: [.isUbiquitousItemKey]).isUbiquitousItem == true
        report.isCloud = cloud
        guard cloud else { return report }
        if !upload { try FileManager.default.startDownloadingUbiquitousItem(at: root) }
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey, .ubiquitousItemIsUploadedKey]
        let files: [URL] = try coordinated(write: false) {
            var result: [URL] = []
            var scanError: Error?
            guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles], errorHandler: { _, error in scanError = error; return false }) else { throw SyncError.invalid("동기화 파일 목록을 읽지 못했습니다.") }
            for case let url as URL in enumerator {
                _ = try checked(url)
                if try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true { result.append(url) }
                guard result.count <= 100_000 else { throw SyncError.invalid("동기화 파일이 너무 많습니다.") }
            }
            if let scanError { throw scanError }
            return result
        }
        for url in files {
            try Task.checkCancellation()
            do {
                let values = try url.resourceValues(forKeys: keys)
                guard values.isUbiquitousItem == true else { continue }
                report.files += 1
                switch values.ubiquitousItemIsUploaded {
                case true?: report.uploaded += 1
                case false?: report.uploadPending += 1
                case nil: report.uploadUnknown += 1
                }
                if !upload && values.ubiquitousItemDownloadingStatus != .current {
                    try FileManager.default.startDownloadingUbiquitousItem(at: url)
                    report.downloadsRequested += 1
                }
                if #available(macOS 26.0, iOS 26.0, *) {
                    let controls = try url.resourceValues(forKeys: [.ubiquitousItemSupportedSyncControlsKey]).ubiquitousItemSupportedSyncControls
                    if controls?.contains(.pauseSync) == true {
                        report.directUploadSupported = true
                        // Only app-owned immutable change files may use the provider's default
                        // conflict policy. Never directly upload editable CSVs or peer files.
                        let relative = String(url.path.dropFirst(root.path.count + 1))
                        if upload, values.ubiquitousItemIsUploaded == false,
                           let deviceID, relative.hasPrefix("changes/\(deviceID.uuidString)/"), url.pathExtension == "json",
                           report.uploadsRequested < 50 {
                            _ = try checked(url)
                            let envelope = try SyncCoding.decode(FileEnvelope.self, from: read(url))
                            guard SyncCoding.hash(envelope.payload) == envelope.hash else { throw SyncError.invalid("변경 파일의 무결성을 확인하지 못했습니다.") }
                            let event = try SyncCoding.decode(SyncEvent.self, from: envelope.payload)
                            try SyncValidation.validate(event)
                            guard event.deviceID == deviceID, event.spaceID == (try manifest()).spaceID else { throw SyncError.invalid("다른 기기의 변경 파일입니다.") }
                            // Default policy doesn't require pausing sync. Avoid persistent paused
                            // files if the app quits during a manual request.
                            _ = try await FileManager.default.uploadLocalVersionOfUbiquitousItem(at: url, withConflictResolutionPolicy: .conflictPolicyDefault)
                            report.uploadsRequested += 1
                            report.uploadPending -= 1; report.uploaded += 1
                        }
                    }
                }
            } catch is CancellationError { throw CancellationError() }
            catch { report.failures += 1; report.lastError = error.localizedDescription }
        }
        return report
    }
    func open() throws -> UUID {
        let space: UUID = try coordinated(write:true) {
            guard (try root.resourceValues(forKeys:[.isDirectoryKey])).isDirectory == true else { throw SyncError.invalid("전용 동기화 폴더를 선택해 주세요.") }
            let url = root.appendingPathComponent("space.json")
            if !FileManager.default.fileExists(atPath:url.path) {
                let contents = try FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:nil)
                guard contents.allSatisfy({$0.lastPathComponent == ".DS_Store"}) else { throw SyncError.invalid("처음 연결할 때는 비어 있는 전용 폴더를 선택해 주세요.") }
                try write(SyncCoding.encode(SpaceManifest(spaceID:UUID())),to:url,immutable:true)
            }
            return try manifest().spaceID
        }
        expectedSpace = space; return space
    }
    func publish(_ events: [SyncEvent]) throws {
        guard !events.isEmpty else { return }
        try coordinated(write:true) {
            let space = try manifest().spaceID
            for event in events {
                try SyncValidation.validate(event)
                guard event.spaceID == space else { throw SyncError.invalid("다른 공간의 변경 파일입니다.") }
                let payload = try SyncCoding.encode(event)
                let envelope = FileEnvelope(hash:SyncCoding.hash(payload),payload:payload)
                try write(SyncCoding.encode(envelope),to:root.appendingPathComponent("changes/\(event.deviceID)/\(event.id).json"),immutable:true)
            }
        }
    }
    func publishCSV(_ document: RoutineCSVDocument, deviceID: UUID) throws -> URL {
        guard document.revisionID.allSatisfy({ $0.isHexDigit }), document.revisionID.count == 64 else { throw SyncError.invalid("CSV 버전 ID가 잘못되었습니다.") }
        let dir = root.appendingPathComponent("tables/\(deviceID)/\(document.revisionID)/\(document.routineID)")
        let csv = dir.appendingPathComponent("루틴.csv"), marker = dir.appendingPathComponent("manifest.json")
        let baseline = try SyncCoding.encode(document)
        let baselineHash = SyncCoding.hash(baseline)
        func isPublished() throws -> Bool {
            guard document.spaceID == (try manifest()).spaceID else { throw SyncError.invalid("CSV 공간 ID가 잘못되었습니다.") }
            _ = try checked(marker)
            guard FileManager.default.fileExists(atPath: marker.path) else { return false }
            let m = try SyncCoding.decode(CSVManifest.self, from: read(marker))
            guard m.version == 1, m.baselineHash == baselineHash else { throw SyncError.invalid("CSV 기준 정보가 바뀌었습니다.") }
            _ = try checked(csv)
            return true
        }
        // A write coordination notifies file presenters even when the accessor makes no changes.
        // Existing exports must therefore use a read claim, otherwise iCloud can retrigger refresh.
        if try coordinated(write: false, { try isPublished() }) { return csv }
        return try coordinated(write: true) {
            // Recheck under the write claim in case another process finished the export meanwhile.
            if try isPublished() { return csv }
            try write(baseline, to: dir.appendingPathComponent("baseline.json"), immutable: true)
            if !FileManager.default.fileExists(atPath: csv.path) { try write(document.csv, to: csv, immutable: true) }
            try write(SyncCoding.encode(CSVManifest(baselineHash: baselineHash)), to: marker, immutable: true)
            return csv
        }
    }
    // A failed or cancelled refresh must be retried, so reads do not advance the cache.
    func acknowledge(_ batch: SyncFolderBatch) {
        guard let pendingScan, pendingScan.id == batch.scanID else { return }
        guard batch.waitingDownloads.isEmpty else { return }
        acknowledgedFiles = pendingScan.files
        documentContexts = documentContexts.filter { batch.documentURLs.contains($0.key) }
        self.pendingScan = nil
    }
    func acknowledgeEvents(in batch: SyncFolderBatch) {
        guard let scan = pendingScan, scan.id == batch.scanID else { return }
        for path in batch.eventPaths { acknowledgedFiles[path] = scan.files[path] }
    }
    private func documentPaths(_ csv: URL) -> [String] {
        let directory = csv.deletingLastPathComponent().standardizedFileURL.path
        let prefix = String(directory.dropFirst(root.path.count + 1)) + "/"
        return [prefix + "manifest.json", prefix + "baseline.json", prefix + "루틴.csv"]
    }
    func acknowledgeDocument(at csv: URL, in batch: SyncFolderBatch, context: String) {
        guard let scan = pendingScan, scan.id == batch.scanID else { return }
        for path in documentPaths(csv) { acknowledgedFiles[path] = scan.files[path] }
        documentContexts[csv] = context
    }
    func documentsToProcess(in batch: SyncFolderBatch, context: String) -> [URL] {
        guard let scan = pendingScan, scan.id == batch.scanID else { return [] }
        return batch.documentURLs.filter { url in
            if documentContexts[url] != context { return true }
            return documentPaths(url).contains { scan.files[$0] != acknowledgedFiles[$0] }
        }.sorted { $0.path < $1.path }
    }
    func readBatch(incremental: Bool = false, recheckDocuments: Bool = false, deferDocuments: Bool = false, allowPartialDownloads: Bool = false) throws -> SyncFolderBatch {
        pendingScan = nil
        try Task.checkCancellation()
        return try coordinated(write: false) {
            let space = try manifest().spaceID
            var batch = SyncFolderBatch(), count = 0
            var files: [String: SyncFileStamp] = [:]
            var scanError: Error?
            guard let iterator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, options: [], errorHandler: { _, error in
                scanError = error; return false
            }) else { throw SyncError.invalid("폴더를 읽을 수 없습니다.") }
            for case let url as URL in iterator {
                try Task.checkCancellation()
                count += 1
                guard count < 100_000 else { throw SyncError.invalid("동기화 파일 수가 너무 많습니다.") }
                var info = stat()
                guard url.withUnsafeFileSystemRepresentation({ path in path.map { lstat($0, &info) } ?? -1 }) == 0 else {
                    throw CocoaError(.fileReadUnknown)
                }
                guard info.st_mode & S_IFMT != S_IFLNK else { throw SyncError.invalid("동기화 폴더 안의 심볼릭 링크는 사용할 수 없습니다.") }
                guard info.st_mode & S_IFMT == S_IFREG else { continue }
                var relative = String(url.standardizedFileURL.path.dropFirst(root.path.count + 1))
                if url.lastPathComponent.hasSuffix(".icloud") {
                    var name = String(url.lastPathComponent.dropLast(".icloud".count))
                    if name.hasPrefix(".") { name.removeFirst() }
                    let parent = (relative as NSString).deletingLastPathComponent
                    relative = parent.isEmpty ? name : parent + "/" + name
                    let logicalURL = root.appendingPathComponent(relative)
                    try? FileManager.default.startDownloadingUbiquitousItem(at: logicalURL)
                    guard allowPartialDownloads else { throw SyncDownloadPending(urls: [logicalURL]) }
                    batch.waitingDownloads.insert(logicalURL.standardizedFileURL)
                }
                files[relative] = SyncFileStamp(info)
            }
            if let scanError { throw scanError }
            let previous = acknowledgedFiles
            batch.hasChanges = files != previous
            let paths = files.keys.sorted()
            func changed(_ path: String) -> Bool { !incremental || files[path] != previous[path] }
            let eventPaths = paths.filter { $0.hasPrefix("changes/") && $0.hasSuffix(".json") }
            let eventsChanged = eventPaths.contains(where: changed)
            for path in eventPaths where changed(path) {
                try Task.checkCancellation()
                let url = root.appendingPathComponent(path)
                if batch.waitingDownloads.contains(url) { continue }
                do {
                    let envelope = try SyncCoding.decode(FileEnvelope.self, from: read(url))
                    guard envelope.version == 1, envelope.hash == SyncCoding.hash(envelope.payload) else { throw SyncError.invalid("변경 파일의 검증에 실패했습니다.") }
                    let event = try SyncCoding.decode(SyncEvent.self, from: envelope.payload)
                    try SyncValidation.validate(event)
                    guard event.spaceID == space, path == "changes/\(event.deviceID)/\(event.id).json" else { throw SyncError.invalid("변경 파일 경로 또는 공간이 다릅니다.") }
                    batch.events.append(event)
                    batch.eventPaths.append(path)
                } catch let pending as SyncDownloadPending {
                    guard allowPartialDownloads else { throw pending }
                    batch.waitingDownloads.formUnion(pending.urls)
                }
            }
            for path in paths where path.hasPrefix("tables/") && path.hasSuffix("/manifest.json") {
                try Task.checkCancellation()
                let url = root.appendingPathComponent(path), dir = url.deletingLastPathComponent()
                let prefix = String(path.dropLast("manifest.json".count))
                let csv = dir.appendingPathComponent("루틴.csv")
                batch.documentURLs.insert(csv)
                // Recheck historical CSVs when journal state changes: conflict outcomes depend on it.
                guard recheckDocuments || eventsChanged || changed(path) || changed(prefix + "baseline.json") || changed(prefix + "루틴.csv") else { continue }
                batch.changedDocumentURLs.append(csv)
                if !deferDocuments { batch.documents.append(try readDocumentContents(at: csv, space: space)) }
            }
            // Receipts are small and are needed even when no journal/CSV changed.
            for path in paths where path.hasPrefix("receipts/") && path.hasSuffix(".json") {
                try Task.checkCancellation()
                let url = root.appendingPathComponent(path)
                if batch.waitingDownloads.contains(url) { continue }
                do {
                    let receipt = try SyncCoding.decode(SyncReceipt.self, from: read(url))
                    guard receipt.version == 1, receipt.spaceID == space else { throw SyncError.invalid("수신 확인 정보의 버전 또는 공간이 다릅니다.") }
                    batch.receipts.append(receipt)
                } catch let pending as SyncDownloadPending {
                    guard allowPartialDownloads else { throw pending }
                    batch.waitingDownloads.formUnion(pending.urls)
                }
            }
            _ = try SyncReducer.reduce(batch.events)
            try Task.checkCancellation()
            pendingScan = (batch.scanID, files)
            return batch
        }
    }
    // The coordinator consumes one baseline at a time, bounding transient memory by a single document.
    func readDocument(at csv: URL) throws -> SyncCSVFile {
        try Task.checkCancellation()
        return try coordinated(write: false) {
            try readDocumentContents(at: csv, space: manifest().spaceID)
        }
    }
    private func readDocumentContents(at csv: URL, space: UUID) throws -> SyncCSVFile {
        let dir = csv.deletingLastPathComponent()
        let m = try SyncCoding.decode(CSVManifest.self, from: read(dir.appendingPathComponent("manifest.json")))
        let data = try read(dir.appendingPathComponent("baseline.json"))
        guard m.version == 1, m.baselineHash == SyncCoding.hash(data) else { throw SyncError.invalid("CSV 기준 JSON 검증에 실패했습니다.") }
        let document = try SyncCoding.decode(RoutineCSVDocument.self, from: data)
        guard document.version == 1, document.spaceID == space else { throw SyncError.invalid("CSV 형식 버전 또는 공간이 다릅니다.") }
        return SyncCSVFile(document: document, data: try read(csv), url: csv)
    }
    func writeReceipt(_ receipt: SyncReceipt) throws {
        try coordinated(write:true) {
            guard receipt.spaceID == (try manifest()).spaceID else { throw SyncError.invalid("수신 확인 공간이 다릅니다.") }
            try write(SyncCoding.encode(receipt),to:root.appendingPathComponent("receipts/\(receipt.deviceID).json"),immutable:false)
        }
    }
}
