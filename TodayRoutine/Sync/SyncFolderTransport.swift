import Foundation
struct SyncCSVFile { var document: RoutineCSVDocument; var data: Data; var url: URL }
struct SyncReceipt: Codable { var version = 1; var spaceID: UUID; var deviceID: UUID; var applied: [UUID]; var date: Date }
struct SyncFolderBatch { var events: [SyncEvent] = []; var documents: [SyncCSVFile] = []; var receipts: [SyncReceipt] = [] }
private struct SpaceManifest: Codable { var version = 1; var spaceID: UUID }
private struct FileEnvelope: Codable { var version = 1; var hash: String; var payload: Data }
private struct CSVManifest: Codable { var version = 1; var baselineHash: String }
actor SyncFolderTransport {
    let root: URL
    private var expectedSpace: UUID?
    init(root: URL) { self.root = root.resolvingSymlinksInPath().standardizedFileURL }
    private func coordinated<T>(write: Bool, _ body: () throws -> T) throws -> T {
        var result: Result<T,Error>?, failure: NSError?
        let coordinator = NSFileCoordinator(filePresenter:nil)
        if write { coordinator.coordinate(writingItemAt:root,options:.forMerging,error:&failure) { _ in result = Result { try body() } } }
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
        _ = try checked(url)
        let values = try url.resourceValues(forKeys:[.isUbiquitousItemKey,.ubiquitousItemDownloadingStatusKey,.fileSizeKey])
        if values.isUbiquitousItem == true && values.ubiquitousItemDownloadingStatus != .current {
            try FileManager.default.startDownloadingUbiquitousItem(at:url)
            throw SyncError.invalid("iCloud 파일 다운로드를 기다리는 중입니다: \(url.lastPathComponent)")
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
        try coordinated(write:true) {
            guard document.spaceID == (try manifest()).spaceID, document.revisionID.allSatisfy({$0.isHexDigit}), document.revisionID.count == 64 else { throw SyncError.invalid("CSV 공간 또는 버전 ID가 잘못되었습니다.") }
            let dir = root.appendingPathComponent("tables/\(deviceID)/\(document.revisionID)/\(document.routineID)")
            let csv = dir.appendingPathComponent("루틴.csv"), marker = dir.appendingPathComponent("manifest.json")
            let baseline = try SyncCoding.encode(document)
            if FileManager.default.fileExists(atPath:marker.path) {
                let m = try SyncCoding.decode(CSVManifest.self,from:read(marker))
                guard m.version == 1, m.baselineHash == SyncCoding.hash(baseline) else { throw SyncError.invalid("CSV 기준 정보가 바뀌었습니다.") }
                return try checked(csv)
            }
            try write(baseline,to:dir.appendingPathComponent("baseline.json"),immutable:true)
            // Interrupted export retries must also preserve a CSV the user may already have opened.
            if !FileManager.default.fileExists(atPath:csv.path) { try write(document.csv,to:csv,immutable:true) }
            try write(SyncCoding.encode(CSVManifest(baselineHash:SyncCoding.hash(baseline))),to:marker,immutable:true)
            return csv
        }
    }
    func readBatch() throws -> SyncFolderBatch {
        try coordinated(write:false) {
            let space = try manifest().spaceID
            var batch = SyncFolderBatch(), count = 0
            guard let iterator = FileManager.default.enumerator(at:root,includingPropertiesForKeys:[.isRegularFileKey,.isSymbolicLinkKey],options:[]) else { throw SyncError.invalid("폴더를 읽을 수 없습니다.") }
            for case let url as URL in iterator {
                _ = try checked(url); count += 1
                guard count < 100_000 else { throw SyncError.invalid("동기화 파일 수가 너무 많습니다.") }
                if url.lastPathComponent.hasSuffix(".icloud") { try? FileManager.default.startDownloadingUbiquitousItem(at:url); throw SyncError.invalid("iCloud 파일 다운로드를 기다리는 중입니다.") }
                guard url.pathExtension == "json" else { continue }
                let relative = String(url.standardizedFileURL.path.dropFirst(root.path.count+1))
                if relative.hasPrefix("changes/") {
                    let envelope = try SyncCoding.decode(FileEnvelope.self,from:read(url))
                    guard envelope.version == 1, envelope.hash == SyncCoding.hash(envelope.payload) else { throw SyncError.invalid("변경 파일의 검증에 실패했습니다.") }
                    let event = try SyncCoding.decode(SyncEvent.self,from:envelope.payload)
                    try SyncValidation.validate(event)
                    guard event.spaceID == space, relative == "changes/\(event.deviceID)/\(event.id).json" else { throw SyncError.invalid("변경 파일 경로 또는 공간이 다릅니다.") }
                    batch.events.append(event)
                } else if relative.hasPrefix("tables/") && url.lastPathComponent == "manifest.json" {
                    let dir = url.deletingLastPathComponent(), m = try SyncCoding.decode(CSVManifest.self,from:read(url))
                    let data = try read(dir.appendingPathComponent("baseline.json"))
                    guard m.version == 1, m.baselineHash == SyncCoding.hash(data) else { throw SyncError.invalid("CSV 기준 JSON 검증에 실패했습니다.") }
                    let document = try SyncCoding.decode(RoutineCSVDocument.self,from:data)
                    guard document.version == 1, document.spaceID == space else { throw SyncError.invalid("CSV 형식 버전 또는 공간이 다릅니다.") }
                    let csv = dir.appendingPathComponent("루틴.csv")
                    batch.documents.append(SyncCSVFile(document:document,data:try read(csv),url:csv))
                } else if relative.hasPrefix("receipts/") {
                    let receipt = try SyncCoding.decode(SyncReceipt.self,from:read(url))
                    guard receipt.version == 1, receipt.spaceID == space else { throw SyncError.invalid("수신 확인 정보의 버전 또는 공간이 다릅니다.") }
                    batch.receipts.append(receipt)
                }
            }
            _ = try SyncReducer.reduce(batch.events)
            batch.documents.sort { $0.url.path < $1.url.path }
            return batch
        }
    }
    func writeReceipt(_ receipt: SyncReceipt) throws {
        try coordinated(write:true) {
            guard receipt.spaceID == (try manifest()).spaceID else { throw SyncError.invalid("수신 확인 공간이 다릅니다.") }
            try write(SyncCoding.encode(receipt),to:root.appendingPathComponent("receipts/\(receipt.deviceID).json"),immutable:false)
        }
    }
}
