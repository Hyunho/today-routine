import XCTest
@testable import RoutineCore
final class SyncTransportTests: XCTestCase {
    func testImmutableEventsAndCSVAndInterruptedFiles() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:root) }
        let transport = SyncFolderTransport(root:root)
        let space = try await transport.open()
        let e = SyncEvent(spaceID:space,id:UUID(),deviceID:UUID(),counter:1,createdAt:Date(timeIntervalSince1970:0),operations:[SyncOperation(kind:.routine,id:UUID().uuidString,values:["name":"아침"])])
        try await transport.publish([e]); try await transport.publish([e])
        try Data("partial".utf8).write(to:root.appendingPathComponent("incomplete.tmp"))
        let batch = try await transport.readBatch()
        XCTAssertEqual(batch.events,[e])
        var bad = e; bad.operations[0].values["name"] = "다른 내용"
        do { try await transport.publish([bad]); XCTFail("must reject different contents") } catch {}
        let state = try SyncReducer.reduce([e])
        let doc = try RoutineCSVDocument.make(routineID:UUID(uuidString:e.operations[0].id)!,spaceID:space,state:state,today:Date())
        let url = try await transport.publishCSV(doc,deviceID:e.deviceID)
        try Data("날짜,완료\n2026-10-02,TRUE\n".utf8).write(to:url)
        _ = try await transport.publishCSV(doc,deviceID:e.deviceID)
        XCTAssertTrue(try String(contentsOf:url).contains("TRUE"))
        let after = try await transport.readBatch()
        XCTAssertEqual(after.documents.count,1)
    }
    func testUnknownVersionAndEscapingSymlinkRejected() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:root) }
        try Data("{\"version\":99,\"spaceID\":\"\(UUID())\"}".utf8).write(to:root.appendingPathComponent("space.json"))
        do { _ = try await SyncFolderTransport(root:root).open(); XCTFail() } catch {}
        try FileManager.default.removeItem(at:root.appendingPathComponent("space.json"))
        let transport = SyncFolderTransport(root:root); let space = try await transport.open()
        try FileManager.default.createSymbolicLink(at:root.appendingPathComponent("changes"),withDestinationURL:FileManager.default.temporaryDirectory)
        let e = SyncEvent(spaceID:space,id:UUID(),deviceID:UUID(),counter:1,createdAt:Date(),operations:[SyncOperation(kind:.routine,id:UUID().uuidString,values:["name":"x"])])
        do { try await transport.publish([e]); XCTFail() } catch {}
    }
}

extension SyncTransportTests {
    func testUnchangedExportDoesNotAcquireWriteCoordination() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = SyncFolderTransport(root: root)
        let space = try await transport.open()
        let routine = UUID(), device = UUID()
        let event = SyncEvent(spaceID: space, id: UUID(), deviceID: device, counter: 1, createdAt: Date(), operations: [SyncOperation(kind: .routine, id: routine.uuidString, values: ["name": "루틴"])])
        let document = try RoutineCSVDocument.make(routineID: routine, spaceID: space, state: SyncReducer.reduce([event]), today: Date())
        let csv = try await transport.publishCSV(document, deviceID: device)
        let userEdit = Data("사용자 CSV 수정".utf8)
        try userEdit.write(to: csv)
        let before = await transport.writeCoordinationCount
        try await transport.publish([])
        _ = try await transport.publishCSV(document, deviceID: device)
        let after = await transport.writeCoordinationCount
        XCTAssertEqual(after, before, "변경 없는 동기화는 쓰기 잠금을 요청하지 않아야 합니다")
        XCTAssertEqual(try Data(contentsOf: csv), userEdit)
    }
}

extension SyncTransportTests {
    func testBatchCSVMatchesExistingFormatAcrossRoutinesAndDays() throws {
        let space = UUID(), device = UUID()
        let ids = (0..<3).map { _ in UUID() }
        let event = SyncEvent(spaceID: space, id: UUID(), deviceID: device, counter: 1, createdAt: Date(), operations: ids.map { SyncOperation(kind: .routine, id: $0.uuidString, values: ["name": "루틴 \($0)"]) })
        let state = try SyncReducer.reduce([event])
        let day = RoutineRules.date(for: "2026-10-06")!
        let batch = try RoutineCSVDocument.makeAll(spaceID: space, state: state, today: day)
        XCTAssertEqual(batch.count, ids.count)
        for document in batch {
            let existing = try RoutineCSVDocument.make(routineID: document.routineID, spaceID: space, state: state, today: day)
            XCTAssertEqual(try SyncCoding.encode(document), try SyncCoding.encode(existing))
            XCTAssertEqual(document.csv, existing.csv)
        }
        let next = try RoutineCSVDocument.makeAll(spaceID: space, state: state, today: RoutineRules.date(for: "2026-10-07")!)
        XCTAssertNotEqual(batch.first?.revisionID, next.first?.revisionID)
    }
}


extension SyncTransportTests {
    func testIncrementalBatchAcknowledgesOnlySuccessfulProcessing() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = SyncFolderTransport(root: root)
        let space = try await transport.open()
        let event = SyncEvent(spaceID: space, id: UUID(), deviceID: UUID(), counter: 1, createdAt: Date(timeIntervalSince1970: 1), operations: [SyncOperation(kind: .routine, id: UUID().uuidString, values: ["name": "캐시"])])
        try await transport.publish([event])
        let document = try RoutineCSVDocument.make(routineID: UUID(uuidString: event.operations[0].id)!, spaceID: space, state: SyncReducer.reduce([event]), today: Date())
        let csv = try await transport.publishCSV(document, deviceID: event.deviceID)
        let first = try await transport.readBatch(incremental: true)
        XCTAssertEqual(first.events, [event])
        XCTAssertEqual(first.documents.count, 1)
        let retry = try await transport.readBatch(incremental: true)
        XCTAssertEqual(retry.events, [event], "A read alone must not acknowledge data")
        await transport.acknowledge(retry)
        let idle = try await transport.readBatch(incremental: true)
        XCTAssertTrue(idle.events.isEmpty)
        XCTAssertTrue(idle.documents.isEmpty)
        XCTAssertFalse(idle.hasChanges)
        try Data("외부 CSV 수정".utf8).write(to: csv)
        let edited = try await transport.readBatch(incremental: true)
        XCTAssertEqual(edited.documents.count, 1)
        XCTAssertEqual(edited.documents.first?.data, Data("외부 CSV 수정".utf8))
        await transport.acknowledge(edited)
        let full = try await transport.readBatch()
        XCTAssertEqual(full.events, [event], "Manual/full reads still validate all files")
        XCTAssertEqual(full.documents.count, 1)
    }

    func testIncrementalReadDetectsTamperingWithPreservedSizeAndModificationDate() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = SyncFolderTransport(root: root)
        let space = try await transport.open()
        let event = SyncEvent(spaceID: space, id: UUID(), deviceID: UUID(), counter: 1, createdAt: Date(timeIntervalSince1970: 1), operations: [SyncOperation(kind: .routine, id: UUID().uuidString, values: ["name": "valid"])])
        try await transport.publish([event])
        let first = try await transport.readBatch(incremental: true)
        await transport.acknowledge(first)
        let url = root.appendingPathComponent("changes/\(event.deviceID)/\(event.id).json")
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let bytes = try Data(contentsOf: url)
        try Data(repeating: 32, count: bytes.count).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: try XCTUnwrap(attributes[.modificationDate])], ofItemAtPath: url.path)
        do { _ = try await transport.readBatch(incremental: true); XCTFail("Changed files must be revalidated") } catch {}
    }

    func testIncrementalBatchRetriesAfterFailureAndDetectsDeletion() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = SyncFolderTransport(root: root)
        let space = try await transport.open()
        let event = SyncEvent(spaceID: space, id: UUID(), deviceID: UUID(), counter: 1, createdAt: Date(timeIntervalSince1970: 1), operations: [SyncOperation(kind: .routine, id: UUID().uuidString, values: ["name": "재시도"])])
        try await transport.publish([event])
        let bad = root.appendingPathComponent("receipts/broken.json")
        try FileManager.default.createDirectory(at: bad.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("broken".utf8).write(to: bad)
        do { _ = try await transport.readBatch(incremental: true); XCTFail() } catch {}
        try FileManager.default.removeItem(at: bad)
        let recovered = try await transport.readBatch(incremental: true)
        XCTAssertEqual(recovered.events, [event])
        await transport.acknowledge(recovered)
        try FileManager.default.removeItem(at: root.appendingPathComponent("changes/\(event.deviceID)/\(event.id).json"))
        let deleted = try await transport.readBatch(incremental: true)
        XCTAssertTrue(deleted.hasChanges)
        XCTAssertTrue(deleted.events.isEmpty)
    }

    func testCancelledBatchCanBeRetried() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = SyncFolderTransport(root: root)
        _ = try await transport.open()
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await transport.readBatch(incremental: true)
        }
        do { _ = try await cancelled.value; XCTFail("Cancelled scan must stop") } catch is CancellationError {} catch { XCTFail("\(error)") }
        _ = try await transport.readBatch(incremental: true)
    }
}

extension SyncTransportTests {
    func testDeferredBatchLoadsHistoricalDocumentsOneAtATime() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = SyncFolderTransport(root: root)
        let space = try await transport.open()
        let routine = UUID(), device = UUID()
        for index in 1...8 {
            let event = SyncEvent(spaceID: space, id: UUID(), deviceID: device, counter: Int64(index), createdAt: Date(timeIntervalSince1970: 1), operations: [SyncOperation(kind: .routine, id: routine.uuidString, values: ["name": "과거 버전 \(index)"])])
            let document = try RoutineCSVDocument.make(routineID: routine, spaceID: space, state: SyncReducer.reduce([event]), today: Date())
            _ = try await transport.publishCSV(document, deviceID: device)
        }
        let batch = try await transport.readBatch(incremental: true, deferDocuments: true)
        XCTAssertTrue(batch.documents.isEmpty, "Historical baselines must not all be retained by the batch")
        XCTAssertEqual(batch.changedDocumentURLs.count, 8)
        var names = Set<String>()
        for url in batch.changedDocumentURLs {
            let file = try await transport.readDocument(at: url)
            names.insert(file.document.name)
            XCTAssertEqual(file.document.routineID, routine)
        }
        XCTAssertEqual(names.count, 8)
        await transport.acknowledge(batch)
        let idle = try await transport.readBatch(incremental: true, deferDocuments: true)
        XCTAssertTrue(idle.changedDocumentURLs.isEmpty)
    }
}

extension SyncTransportTests {
    func testUnchangedHistoryAvoidsReloadingBaselinePayloads() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = SyncFolderTransport(root: root)
        let space = try await transport.open(), device = UUID()
        let routines = (0..<10).map { _ in UUID() }
        for revision in 1...15 {
            let event = SyncEvent(spaceID: space, id: UUID(), deviceID: device, counter: Int64(revision), createdAt: Date(timeIntervalSince1970: 1), operations: routines.map {
                SyncOperation(kind: .routine, id: $0.uuidString, values: ["name": "루틴 \(revision) \($0)"])
            })
            let state = try SyncReducer.reduce([event])
            for document in try RoutineCSVDocument.makeAll(spaceID: space, state: state, today: Date()) {
                _ = try await transport.publishCSV(document, deviceID: device)
            }
        }
        let fullStart = ContinuousClock.now
        let full = try await transport.readBatch()
        let fullTime = fullStart.duration(to: .now)
        XCTAssertEqual(full.documents.count, 150)
        await transport.acknowledge(full)
        let idleStart = ContinuousClock.now
        let idle = try await transport.readBatch(incremental: true, deferDocuments: true)
        let idleTime = idleStart.duration(to: .now)
        XCTAssertFalse(idle.hasChanges)
        XCTAssertTrue(idle.events.isEmpty)
        XCTAssertTrue(idle.changedDocumentURLs.isEmpty)
        XCTAssertTrue(idle.documents.isEmpty)
        print("SYNC_BENCHMARK history=150 full=\(fullTime) idle=\(idleTime) fullBaselines=150 idleBaselines=0")
    }
}

extension SyncTransportTests {
    func testPartialDownloadKeepsCompletedDocumentsAndRetriesOnlyWaitingFile() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = SyncFolderTransport(root: root), device = UUID()
        let space = try await transport.open()
        var urls: [URL] = []
        for index in 0..<3 {
            let routine = UUID()
            let event = SyncEvent(spaceID: space, id: UUID(), deviceID: device, counter: 1, createdAt: Date(timeIntervalSince1970: 1), operations: [SyncOperation(kind: .routine, id: routine.uuidString, values: ["name": "문서 \(index)"])])
            let doc = try RoutineCSVDocument.make(routineID: routine, spaceID: space, state: SyncReducer.reduce([event]), today: Date())
            urls.append(try await transport.publishCSV(doc, deviceID: device))
        }
        let missing = urls[1].deletingLastPathComponent().appendingPathComponent("baseline.json")
        let saved = try Data(contentsOf: missing)
        try FileManager.default.removeItem(at: missing)
        let placeholder = missing.deletingLastPathComponent().appendingPathComponent(".baseline.json.icloud")
        try Data().write(to: placeholder)
        let first = try await transport.readBatch(incremental: true, deferDocuments: true, allowPartialDownloads: true)
        XCTAssertTrue(first.waitingDownloads.contains(missing), "waiting=\(first.waitingDownloads), expected=\(missing)")
        for url in [urls[0], urls[2]] {
            _ = try await transport.readDocument(at: url)
            await transport.acknowledgeDocument(at: url, in: first, context: "state-1")
        }
        let retry = try await transport.readBatch(incremental: true, deferDocuments: true, allowPartialDownloads: true)
        let remaining = await transport.documentsToProcess(in: retry, context: "state-1")
        XCTAssertEqual(remaining, [urls[1]], "Completed files must survive a different file's download wait")
        try FileManager.default.removeItem(at: placeholder)
        try saved.write(to: missing)
        let downloaded = try await transport.readBatch(incremental: true, deferDocuments: true, allowPartialDownloads: true)
        XCTAssertTrue(downloaded.waitingDownloads.isEmpty)
        let next = await transport.documentsToProcess(in: downloaded, context: "state-1")
        XCTAssertEqual(next, [urls[1]])
        _ = try await transport.readDocument(at: urls[1])
        await transport.acknowledgeDocument(at: urls[1], in: downloaded, context: "state-1")
        let changedState = await transport.documentsToProcess(in: downloaded, context: "state-2")
        XCTAssertEqual(Set(changedState), Set(urls), "Real state changes still require conflict re-evaluation")
    }

    func testPartialEventDownloadDoesNotDiscardAlreadyAppliedEvents() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = SyncFolderTransport(root: root), device = UUID()
        let space = try await transport.open()
        let events = (0..<2).map { index in SyncEvent(spaceID: space, id: UUID(), deviceID: device, counter: Int64(index + 1), createdAt: Date(timeIntervalSince1970: 1), operations: [SyncOperation(kind: .routine, id: UUID().uuidString, values: ["name": "이벤트 \(index)"])]) }
        try await transport.publish(events)
        let file = root.appendingPathComponent("changes/\(device)/\(events[1].id).json")
        let saved = try Data(contentsOf: file)
        try FileManager.default.removeItem(at: file)
        let placeholder = file.deletingLastPathComponent().appendingPathComponent(".\(file.lastPathComponent).icloud")
        try Data().write(to: placeholder)
        let first = try await transport.readBatch(incremental: true, deferDocuments: true, allowPartialDownloads: true)
        XCTAssertEqual(first.events, [events[0]])
        await transport.acknowledgeEvents(in: first)
        let retry = try await transport.readBatch(incremental: true, deferDocuments: true, allowPartialDownloads: true)
        XCTAssertTrue(retry.events.isEmpty)
        XCTAssertTrue(retry.waitingDownloads.contains(file), "waiting=\(retry.waitingDownloads), expected=\(file)")
        try FileManager.default.removeItem(at: placeholder); try saved.write(to: file)
        let restored = try await transport.readBatch(incremental: true, deferDocuments: true, allowPartialDownloads: true)
        XCTAssertEqual(restored.events, [events[1]])
    }
}

extension SyncTransportTests {
    func testListConfigMigrationAndRemotePriority() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let local = root.appendingPathComponent("local.json")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("{\"itemSpacing\":3}".utf8).write(to: local)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("shared"), withIntermediateDirectories: true)
        let transport = SyncFolderTransport(root: root.appendingPathComponent("shared"))
        _ = try await transport.open()
        let migrated = try await transport.loadListLayout(migratingFrom: local)
        XCTAssertEqual(migrated.itemSpacing, 3)
        let remote = root.appendingPathComponent("shared/Config/list-layout.json")
        try Data("{\"itemSpacing\":12}".utf8).write(to: remote)
        let loaded = try await transport.loadListLayout(migratingFrom: local)
        XCTAssertEqual(loaded.itemSpacing, 12)
        try Data("broken".utf8).write(to: remote)
        do { _ = try await transport.loadListLayout(migratingFrom: local); XCTFail("Must preserve malformed remote config") } catch {}
        XCTAssertEqual(try String(contentsOf: remote), "broken")
        XCTAssertEqual(try String(contentsOf: local), "{\"itemSpacing\":3}")
    }

    func testListConfigPlaceholderIsNotOverwritten() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let transport = SyncFolderTransport(root: root)
        _ = try await transport.open()
        let folder = root.appendingPathComponent("Config")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data().write(to: folder.appendingPathComponent(".list-layout.json.icloud"))
        do { _ = try await transport.loadListLayout(migratingFrom: root.appendingPathComponent("missing.json")); XCTFail("Must wait for cloud file") }
        catch is SyncDownloadPending {} catch { XCTFail("Unexpected: \(error)") }
        do { try await transport.saveListLayout(ListLayoutConfig()); XCTFail("Must not overwrite an undownloaded cloud file") }
        catch is SyncDownloadPending {} catch { XCTFail("Unexpected: \(error)") }
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("list-layout.json").path))
    }
}


extension SyncTransportTests {
    func testSaveLayoutPersistsAllControlsAndCanRestoreDefaults() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = SyncFolderTransport(root: root)
        _ = try await transport.open()
        var config = ListLayoutConfig()
        config.itemMinHeight = 80
        config.durationHeightPerMinute = 1.2
        config.gapHeightPerHour = 48
        config.itemSpacing = 16
        config.lineInset = 12
        try await transport.saveListLayout(config)
        let saved = try await transport.loadListLayout(migratingFrom: root.appendingPathComponent("unused.json"))
        XCTAssertEqual(saved, config)
        XCTAssertEqual(AgendaSegment(id: "hour", start: 0, end: 60, isGap: false).height(using: saved), 122)
        try await transport.saveListLayout(ListLayoutConfig())
        let reset = try await transport.loadListLayout(migratingFrom: root.appendingPathComponent("unused.json"))
        XCTAssertEqual(reset, ListLayoutConfig())
    }
}
