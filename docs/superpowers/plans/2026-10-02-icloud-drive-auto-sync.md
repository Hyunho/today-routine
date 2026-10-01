# iCloud Drive CSV + JSON Auto Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. 기존 작업과 같이 이 대화에서 직접 구현하고 마지막에 독립 리뷰 한 번을 수행한다.

**Goal:** 루틴별 날짜 × 세부작업 완료 여부 CSV를 직접 편집할 수 있고 아이폰·맥 앱 사이에 JSON 변경 이력이 자동 동기화되는 기능을 구현한다.

**Architecture:** SwiftData는 각 기기의 로컬 저장소로 유지한다. 데이터 변경과 전송 대기 이벤트를 같은 저장 트랜잭션에 기록하고, 불변 JSON 파일로 전달한다. CSV는 기준 JSON과 비교한 셀 변경을 이벤트로 변환하며 앱의 새 출력은 버전별 디렉터리로 분리한다.

**Tech Stack:** Swift 5, SwiftUI, SwiftData, Foundation 파일 조정·문서 선택, CryptoKit SHA256, XCTest, 기존 Python 프로젝트 생성기. 외부 패키지 없음.

**Spec:** `docs/superpowers/specs/2026-10-02-icloud-drive-auto-sync-design.md`

## Global Constraints

- iOS 17 이상, macOS 14 이상. 한국 날짜와 월요일 주 경계 유지.
- 루틴마다 CSV 하나: 첫 열 `날짜`, 나머지 열은 세부작업 이름, 셀은 TRUE/FALSE. 단계가 없으면 `날짜,완료`.
- CSV 셀 변경과 날짜 행 추가는 자동 반영. 빈 셀·없어진 행·없어진 열을 삭제나 미완료로 추정하지 않는다.
- 루틴·단계·동기화 ID는 JSON에 저장한다. CSV 열 이름 수정·새 단계 생성은 자동 수용하지 않고 오류 안내한다.
- 일감·블록·그룹은 JSON으로 동기화한다. 알림 권한·사용 설정은 기기별로 유지한다.
- 같은 Apple 계정의 사용자 선택 iCloud Drive 전용 폴더를 연결한다. 웹사이트·CloudKit·배포는 포함하지 않는다.
- SQLite 파일 자체를 공유 폴더에 두지 않는다. 기기 데이터와 편집 중인 기존 CSV를 덮어쓰지 않는다.
- 정상 흐름에 가져오기 버튼이 필요하지 않는다. 충돌·권한 만료·잘못된 입력은 상태 화면으로 알린다.
- 앱이 정지된 동안의 즉시 동기화, 일정한 iCloud 전달 시간, 영구 고정 경로의 최신 CSV는 보장하지 않는다.
- 첫 버전에서 이벤트 자동 삭제·압축을 하지 않는다. 폴더 연결 해제는 로컬/클라우드 기록 삭제가 아니다.
- 형식 버전 1. 파일 접근 오류에 로컬 데이터를 초기화하거나 메모리 저장으로 대체하지 않는다.

## Review Focus

- 오래된 CSV를 열어 둔 채 앱에서 다른 셀을 수정: 실제 편집 셀만 합치고 최신의 다른 셀을 잃지 않아야 함 — Task 3.
- 파일의 전송 순서가 다르거나 중복·중간 실패·시계 오차가 있음: 수렴·하루 최대 1회 집계·재시도 안전성 — Tasks 1, 2, 5.
- 단계 이름 변경·삭제와 과거 날짜 CSV: 원래 단계 ID/기록을 현재 열에 잘못 연결하지 않음 — Tasks 1, 3.
- 보안 범위 URL 만료, 지연 다운로드, 교체된 폴더, 손상 JSON: 사용자 데이터 유지와 재연결 안내 — Tasks 4, 5.
- 최초 연결에서 두 기기가 다른 데이터를 보유하거나 빈 상태임: 기존 UUID와 기록 보존, 무언의 초기화·삭제 금지 — Tasks 2, 5.

## 파일 구성과 의존성

- `TodayRoutine/Sync/SyncTypes.swift`, `SyncValidation.swift`, `SyncReducer.swift`: 값 타입 전송 형식, 검증, 순서와 상태 계산.
- `TodayRoutine/Sync/SyncJournal.swift`, `StoreSyncAdapter.swift`: SwiftData 이벤트·대기열·처리 상태, 모델과 값 타입 변환.
- `TodayRoutine/Sync/CSVCodec.swift`, `RoutineCSVDocument.swift`, `CSVImporter.swift`: CSV 파싱, 날짜별 표와 기준 상태, 변경 감지.
- `TodayRoutine/Sync/SyncFolderAccess.swift`, `SyncFolderTransport.swift`, `FileChangeMonitor.swift`: 권한 복원, 조정된 파일 접근, 변경 감시.
- `TodayRoutine/Sync/SyncCoordinator.swift`: 한 번에 하나의 전송/수신/CSV 주기, 복구·상태.
- `TodayRoutine/Features/Settings/SyncSettingsView.swift`, `SyncConflictView.swift`: 폴더 선택, 상태, CSV 열기, 오류·충돌 해결.
- `TodayRoutine/App/PlatformViews.swift`, `RootView.swift`, `TodayRoutineApp.swift`: 플랫폼 차이, 맥 내비게이션 및 실행 시점 연결.
- `TodayRoutine/Data/RoutineStore.swift`, `StoreActions.swift`, `PlanningActions.swift`: 트랜잭션과 작업 의미를 동기화 계층에 전달.
- `scripts/generate-project.py`, `TodayRoutine.xcodeproj/`, `Package.swift`, `TodayRoutine/TodayRoutineMac.entitlements`: 맥 대상·공유 코어 테스트 구성.
- `TodayRoutineTests/{SyncReducerTests,SyncStoreTests,CSVTests,SyncTransportTests,SyncCoordinatorTests}.swift`: 핵심 자동 테스트.
- `TodayRoutineUITests/SyncWorkflowTests.swift`, `TodayRoutineMacUITests/SyncWorkflowTests.swift`: 플랫폼별 UI 테스트.
- `docs/examples/sync/`, `README.md`, `docs/sync-verification.md`: 예제와 확인 결과.

Tasks 1→2→3→4→5 순서로 공통 동기화 계약을 구현한다. Task 6에서 맥 UI와 설정을 연결하고 Task 7에서 실제 두 앱 흐름을 검증한다. 중간 task는 독립 단위 테스트로 검증하며 마지막 UI가 연결되기 전 사용자에게 동기화 완료라고 보고하지 않는다.

## 공통 타입 계약 보완

- `SyncState`는 루틴·단계·그룹·날짜 기록·일감·블록의 Codable 값 타입 맵, 삭제 표시, 과거 단계 스냅샷, 필드별 마지막 논리 버전을 포함한다. SwiftData 모델 객체를 이벤트에 직접 넣지 않는다.
- `SyncFolderBatch`는 검증 가능한 이벤트 바이트, CSV/기준 JSON 쌍, 상대 영수증, 아직 내려받지 못한 파일과 손상·충돌 진단을 구별한다. 읽기 순서를 곧 적용 순서로 사용하지 않는다.
- `SyncReceipt`는 spaceID, deviceID, 적용 완료 이벤트 ID 목록, 확인 시각이다. 다른 기기의 파일을 읽었다는 사실만으로 적용 완료를 기록하지 않는다.
- `CSVImportResult`는 적용 가능한 SyncOperation 배열, 결정적 편집 식별자, CSVConflict 배열이다. `CSVConflict`는 문서/루틴/날짜/단계 ID, 기준값·현재값·편집값, 기준·현재 논리 버전을 포함한다. 현재 값이 기준과 같아도 중간에 변경 후 취소한 이력이 있으면 버전을 비교한다. 현재 값과 편집값이 같으면 충돌 해결이 필요 없다.
- CSV에서 같은 편집을 두 기기가 발견한 경우 eventID는 공간·문서·기준 버전·정규화 변경 해시로 결정하고, 논리 순번은 해당 기준의 최댓값+1, 출처 식별자는 문서 ID로 고정한다. 실제 기기 작업 이벤트와 CSV 출처 이벤트를 구별한다. 작성 시각 차이만으로 같은 ID의 이벤트 바이트가 달라지지 않게 한다.
- `SyncStatus`는 disconnected, checking, pending(건수), waitingForPeer, idle(마지막 확인), permissionRequired, blocked(이유) 상태다. `ConflictChoice`는 keepApp 또는 useCSV이며 어느 선택도 과거 이벤트 원본을 삭제하지 않는다.

## 공통 검증 명령

코어: `swift test --build-system native --scratch-path /private/tmp/today-routine-tests`.
선택 검사: 위 명령에 `--filter SyncReducerTests` 등 테스트 클래스를 추가한다.
iOS: `xcrun simctl list devices available`에서 사용 가능한 iPhone UDID를 고른 다음 `xcodebuild -project TodayRoutine.xcodeproj -scheme TodayRoutine -destination 'id=<UDID>' -derivedDataPath /private/tmp/today-routine-ios-build test CODE_SIGNING_ALLOWED=NO`.
macOS: `xcodebuild -project TodayRoutine.xcodeproj -scheme TodayRoutineMac -destination 'platform=macOS' -derivedDataPath /private/tmp/today-routine-mac-build test`.
맥 로컬 UI 테스트 서명이 필요하면 Xcode의 로컬 서명을 사용하며 인증서나 계정 설정은 임의로 만들지 않는다. 서명이 불가능하면 빌드·코어 결과와 UI 미검증 사유를 분리한다. 각 명령의 실제 종료 상태와 XCTest 결과를 확인한다.

### Task 1: 변경 형식과 결정적 상태 계산

**Files:** SyncTypes.swift, SyncValidation.swift, SyncReducer.swift, Package.swift, SyncReducerTests.swift.
**Interfaces:** `SyncEvent: Codable, Equatable` (version, spaceID, eventID, deviceID, logicalCounter, createdAt, operations); `SyncOperation: Codable, Equatable`; `SyncState: Codable, Equatable`; `SyncReducer.reduce(_ events: [SyncEvent]) throws -> SyncState`; `SyncValidation.validate(_ event: SyncEvent) throws`.

- [ ] 이벤트·상태 계약과 실패 테스트를 먼저 작성한다. `testOutOfOrderAndDuplicateConverge`: `reduce([a,b,a]) == reduce([b,a])`. `testClockSkewDoesNotOrderEvents`: 작성 시각이 역전돼도 논리 순번·기기 ID·이벤트 ID 순서 유지. `testDifferentFieldsSurvive`: 이름 변경과 메모 변경 둘 다 유지.
- [ ] `testConcurrentStepsAndWholeCompletion`: 서로 다른 단계의 체크 보존, 전체 완료 후 해제는 미완료, 동일 루틴/날짜 집계 1. `testDeletionDoesNotResurrect`: 삭제 뒤 늦은 수정으로 일감·블록이 되살아나지 않음. `testHistoricStepsKeepIdentity`: 당시 이름/단계 정보 보존.
- [ ] 코어 선택 검사를 실행해 구현 부재 또는 기존 동작 차이로 실패함을 확인한다. 설정 오류는 재현 증거가 아니다.
- [ ] `SyncOperation`은 루틴 속성 패치, 단계·그룹 변경, 날짜 상태 설정, 단계 boolean 설정, 일감·블록 변경/삭제로 구성한다. 임의 JSON 키를 모델에 직접 적용하지 않는다. 반복 설정과 시간 범위는 묶음으로 검증한다. 상태는 불변 이벤트의 안정 정렬 후 작업을 적용해 계산하고 tombstone으로 삭제를 보존한다.
- [ ] 초기 기록은 baseline 작업으로 포함하고 당시 이름/유효 단계 ID·이름을 보존한다. 기존 기록에 단계 이름이 없으면 임의의 현재 이름을 과거 이름으로 단정하지 않고 '과거 단계' 표시를 사용한다.
- [ ] 알려지지 않은 형식·enum, 잘못된 날짜·시간·UUID 관계, 같은 ID의 다른 내용을 거부한다. 선택 검사와 기존 코어 전체가 PASS이면 커밋 `feat: add deterministic sync event model`.

### Task 2: 저장 트랜잭션과 영속 대기열

**Files:** SyncJournal.swift, StoreSyncAdapter.swift, RoutineStore.swift, StoreActions.swift, PlanningActions.swift, SyncStoreTests.swift.
**Interfaces:** `StoreSyncAdapter.init(store: RoutineStore)`; `enable(spaceID: UUID, deviceID: UUID) throws`; `ingest(_ events: [SyncEvent]) throws`; `pendingEvents() throws -> [SyncEvent]`; `markPublished(ids: [UUID]) throws`; `exportState() throws -> SyncState`.

- [ ] `testLocalSaveAndOutboxAreAtomic`: 주입한 저장 실패 후 데이터와 이벤트 모두 0개 변경. `testRelaunchRetainsPendingEvents`: 파일 저장소 재열기 후 같은 이벤트 ID가 대기. `testRemoteApplyAndReceiptAreAtomic`: 적용 실패 후 상태/영수증 모두 이전 값.
- [ ] `testOldStoreMigrationKeepsAllSevenModels`: 동기화 모델이 없는 기존 파일을 열어 ID·필드·기록을 그대로 유지. `testBootstrapEmptyAndNonemptyStores`: 빈 기기는 기존 데이터를 삭제하지 않고, 다른 UUID의 동일 이름 루틴은 둘 다 보존.
- [ ] 실패 확인 후 SyncJournalEntry와 SyncDeviceState 모델을 기존 Schema에 추가한다. 이벤트 바이트·해시·대기/발행 여부·논리 순번을 저장한다. 스키마 업그레이드 전 안전한 값 타입 백업을 만들고 기존 파일 자동 초기화는 금지한다.
- [ ] 기존 StoreActions의 의미를 작업으로 변환하고 데이터 저장과 같은 context.save에 묶는다. 원격 수신은 로컬 이벤트를 다시 생성하지 않는다. 알림 환경 설정 변경은 공유 작업에서 제외한다. 과거 단계의 메타데이터도 동기화 상태로 보존한다.
- [ ] 원격 적용 시 로컬에 이미 받은 전체 이벤트 집합으로 영향을 받는 상태를 다시 계산한다. 손상 이벤트로 유효한 로컬 상태를 지우지 않는다. `SyncStoreTests`와 전체 코어 PASS 후 커밋 `feat: persist sync journal atomically`.

### Task 3: 루틴별 CSV와 셀 변경 수신

**Files:** CSVCodec.swift, RoutineCSVDocument.swift, CSVImporter.swift, CSVTests.swift, docs/examples/sync/.
**Interfaces:** `CSVCodec.decode(_ data: Data) throws -> [[String]]`; `encode(_ rows: [[String]]) -> Data`; `RoutineCSVDocument.make(routineID: UUID, state: SyncState, today: Date) throws -> RoutineCSVDocument`; `CSVImporter.diff(data: Data, baseline: RoutineCSVDocument, current: SyncState) throws -> CSVImportResult`.

- [ ] 문서 값 타입에 documentID, routineID, revisionID, 기준 논리 순번, 헤더→단계 ID 매핑, 날짜별 셀 기준값, 기준 상태 해시를 정의한다. 결과는 적용 가능한 변경과 동일 셀 충돌을 구별한다.
- [ ] `testRoutineMatrixFormat`: `날짜,물 마시기,독서`와 TRUE/FALSE 값, 날짜 정렬 검증. `testNoStepsUsesCompletionColumn`: `날짜,완료`. `testQuotedKoreanAndBOM`: UTF-8 BOM 입력, 쉼표·줄바꿈·따옴표·CRLF 왕복. 엑셀 수식처럼 시작하는 열 제목의 가역 이스케이프 검증.
- [ ] `testStaleCSVOnlyChangesEditedCells`: 기준 [FALSE,FALSE], 앱 현재 [FALSE,TRUE], CSV [TRUE,FALSE]이면 첫 셀만 체크해 최종 [TRUE,TRUE]. `testMissingRowsColumnsAndBlankDoNotDelete`: 누락과 빈 값으로 기존 기록이 바뀌지 않음. `testSameCellConflict`: 기준/현재/편집본이 충돌하면 선택 필요 상태.
- [ ] `testDuplicateDateAndInvalidBooleanRejectWholeFile`, `testDateAddedOnceAcrossDevices`, `testRenamedOrUnknownHeadersRejected`, `testHistoricalStepMapping`, `testResaveDoesNotUnskip`를 추가하고 실패 확인한다.
- [ ] 정규화된 셀 변경을 하루·단계별 작업으로 변환한다. 동일 원본 버전+변경의 식별자는 SHA256에서 파생해 중복 관측 시 안정적이다. 같은 버전의 이미 처리한 변경을 재저장하면 새 작업이 아니며 과거 편집본의 같은 변경 재적용은 최신 버전을 사용하도록 안내한다.
- [ ] 기존 기록 날짜와 오늘 날짜를 출력한다. 유효한 새 날짜 행도 입력 가능하며 날짜 이동은 기존 기록 삭제가 아니다. 해당 날짜에 없는 단계는 빈 셀로 출력하고 이름만으로 ID를 추정하지 않는다.
- [ ] 예제 CSV/기준 JSON/열 설명을 docs/examples에 작성한다. CSVTests 및 전체 코어 PASS 후 커밋 `feat: add editable per-routine CSV documents`.

### Task 4: 폴더 연결과 파일 전달

**Files:** SyncFolderAccess.swift, SyncFolderTransport.swift, FileChangeMonitor.swift, SyncTransportTests.swift.
**Interfaces:** `SyncFolderTransport` protocol: `readBatch() async throws -> SyncFolderBatch`, `publish(_ events: [SyncEvent]) async throws`, `publishCSV(_ documents: [RoutineCSVDocument]) async throws`, `writeReceipt(_ receipt: SyncReceipt) async throws`; `SyncFolderAccess.connect(url: URL) throws`, `restore() throws -> URL`, `disconnect()`; `FileChangeMonitor.start(url: URL, onChange: @escaping () -> Void)`, `stop()`.

- [ ] `testInterruptedWriteIsNotImported`: 일부 바이트만 있는 임시 파일 무시. `testDuplicateIDWithDifferentBytesRejected`, `testMissingDownloadRetries`, `testUnknownVersionPausesSpace`, `testCSVExportsNeverReplacePriorVersion`, `testLostFolderPermissionPreservesLocalData` 실패 확인.
- [ ] 폴더 구조는 `space.json`, `changes/<deviceID>/<eventID>.json`, `tables/<deviceID>/<revisionID>/<routineID>/{루틴.csv,baseline.json}`, `receipts/<deviceID>.json`. manifest 생성 경쟁은 서로 다른 spaceID를 자동 합치지 않고 연결 오류로 처리한다.
- [ ] Foundation 조정 접근으로 임시 파일 작성 후 완성된 이벤트를 노출한다. CSV/기준 JSON은 manifest 해시가 모두 맞을 때만 읽는다. 파일명·symlink·상대 경로가 선택 폴더 밖으로 벗어나지 않도록 검증한다. JSON 원본을 실행하거나 임의 경로에 쓰지 않는다.
- [ ] 파일 presenter와 활성 상태 재검사를 결합한다. iCloud placeholder는 다운로드 요청 후 보류한다. NSFileVersion의 충돌 내용은 보존·검사한다. CSV 출력은 기존 버전에 쓰지 않고 새 버전을 만든다. JSON 해시와 버전 불일치는 오류로 노출한다.
- [ ] 사용자 선택 보안 범위 URL의 시작/해제, 플랫폼 지원에 맞는 bookmark 저장/복원, stale/실패 시 재연결을 구현한다. 사용자 iCloud 설정 변경이나 광범위한 디스크 권한 요청은 하지 않는다.
- [ ] 임시 로컬 폴더를 쓰는 테스트 PASS 후 커밋 `feat: add coordinated folder sync transport`. 실제 iCloud 검증은 Task 7에서 분리한다.

### Task 5: 자동 주기와 충돌 해결

**Files:** SyncCoordinator.swift, SyncCoordinatorTests.swift, TodayRoutineApp.swift.
**Interfaces:** `@MainActor @Observable SyncCoordinator` with `status: SyncStatus`, `conflicts: [CSVConflict]`; `connect(url: URL) async`, `localDataDidChange()`, `setActive(_ active: Bool)`, `refresh() async`, `resolve(conflictID: String, choice: ConflictChoice) async`, `disconnect()`.

- [ ] 두 파일 저장소와 공유 임시 폴더로 `testTwoStoresAutomaticallyExchangeChanges`, `testOfflineEditsRetryAfterReconnect`, `testDuplicateCSVImportDoesNotDoubleCount`, `testCSVEditDoesNotCreateExportLoop`, `testDisconnectKeepsBothCopies`, `testReceiptsDoNotClaimPeerAppliedBeforeReceipt`를 작성하고 실패 확인한다.
- [ ] 한 번에 한 주기만 실행한다. 변경 후 500ms debounce, 활성 상태에서 15초 재검사, 폴더 알림·실행·활성화 때 즉시 주기를 예약한다. 실패 재시도는 2/5/15/60초 상한으로 하고 비활성 상태에는 타이머를 중단한다. 테스트는 가짜 clock으로 지연을 제어한다.
- [ ] 주기는 완성 파일 읽기→검증→수신 적용→CSV 차이 적용/충돌 보류→미전송 이벤트 게시→새 CSV 버전 생성→적용 영수증 기록 순서다. 변화 없는 상태는 CSV를 재출력하지 않는다. 대기열이 없어도 상대 적용 완료가 없으면 '상대 기기 확인 대기'로 표시한다.
- [ ] 다른 기기에서도 동일 CSV 충돌이 발견될 수 있으므로 conflictID와 해결 작업을 안정 식별한다. 해결은 새로운 명시적 셀 설정 이벤트로 전달하고 선택하지 않은 원본 이력을 삭제하지 않는다. CSV 충돌 없는 변경은 자동으로 적용한다.
- [ ] 수신 적용 후 AppModel snapshot 갱신 및 해당 기기 알림 재계산. 동기화 경고가 편집 화면의 저장 오류 알림을 덮지 않게 분리한다. 전체 코어 PASS 후 커밋 `feat: orchestrate automatic sync and recovery`.

### Task 6: 맥 앱과 동기화 설정 UI

**Files:** PlatformViews.swift, RootView.swift, TodayRoutineApp.swift, 기존 Features 화면, SyncSettingsView.swift, SyncConflictView.swift, generate-project.py, Package.swift, TodayRoutineMac.entitlements, 두 플랫폼 SyncWorkflowTests.swift.
**Interfaces:** iOS와 macOS가 같은 AppModel/SyncCoordinator를 사용한다. macOS 스킴 `TodayRoutineMac`, bundle ID `com.hyunho.TodayRoutineMac`. iOS 기존 스킴·bundle ID 유지.

- [ ] UI 테스트로 연결 전 '기기에만 저장', 연결 후 폴더·대기·최신 CSV 열기, 권한 오류 재연결, CSV 충돌의 앱 값/CSV 값 선택 및 입력 보존 흐름을 먼저 작성한다. 파일 선택은 테스트 전용 임시 폴더 주입으로 자동 검사하고 실제 picker는 수동 확인한다.
- [ ] 생성기에 macOS 앱·UI 테스트 타깃과 리소스/entitlements를 추가한다. macOS 샌드박스는 사용자 선택 파일 읽기·쓰기로 한정한다. iCloud Documents capability를 사용하지 않고 사용자 선택 폴더 경로를 검증한다. 이 방식이 실제 설치 환경에서 불가능하면 CloudKit으로 몰래 전환하지 않고 제한을 보고한다.
- [ ] iOS 전용 topBar·navigationBarTitleDisplayMode·EditButton·스와이프 의존 조작을 플랫폼 분기로 정리한다. 맥은 사이드바, 최소 760×520 창, 접근 가능한 목록/편집 창, 삭제 확인, 위아래 순서 이동 및 키보드 조작을 제공한다. 기존 iOS 화면 기능은 유지한다.
- [ ] 설정에 폴더 선택, 마지막 수신, 대기 건수, 상대 확인, 오류 위치, CSV 버전 열기, 연결 해제를 표시한다. CSV 편집법과 TRUE/FALSE 의미, 행/열 삭제가 앱 삭제가 아님, Numbers에서 CSV로 저장해야 함을 짧게 안내한다.
- [ ] 프로젝트 재생성 후 iOS 기존 UI 테스트와 신규 동기화 UI 테스트, macOS 빌드·UI 테스트를 실행한다. 예상: 빌드 성공과 모든 자동 테스트 PASS. 통과 후 커밋 `feat: add Mac app and sync settings`.

### Task 7: 두 기기 검증과 전달

**Files:** SyncCoordinatorTests.swift, 두 플랫폼 UI 테스트, README.md, docs/sync-verification.md, 필요 시 재현한 결함 파일.

- [ ] 전체 코어 테스트를 실행하고 기존 20개 테스트를 포함한 결과를 기록한다. 기존 iOS 5개 UI 흐름과 새 흐름의 결과를 각각 확인한다. 저장 경계·동시 단계 체크·CSV 보류·오래된 편집본 회귀 검사가 빠졌으면 추가한다.
- [ ] iPhone 시뮬레이터와 맥 앱으로 루틴 생성→CSV 출력→CSV 셀 TRUE 수정→앱 전체 완료→앱에서 취소→새 CSV FALSE 확인을 수행한다. 원본 편집 파일이 보존되는지, 한 기기가 오프라인이었다 돌아와도 다른 셀 수정이 유지되는지 확인한다.
- [ ] 실제 iCloud 폴더 접근 가능 여부를 확인한다. 사용자의 폴더 선택·Apple 계정 로그인·기기 서명이 필요하면 그 단계만 사용자에게 맡긴다. 테스트용 공간을 만들며 기존 사용자 파일을 삭제하거나 변경하지 않는다. 실제 iCloud 두 기기 검증이 불가능하면 미검증으로 명시한다.
- [ ] 큰 글자·긴 단계명·동명 단계·맥 창 축소·설정 오류 화면을 캡처하고 검토한다. 실제 검증 OS와 최소 지원 OS를 구분한다.
- [ ] README에 폴더 연결, CSV 위치·편집, 갱신 지연, 버전별 파일 증가, 충돌 해결, 재연결, 백업·복구, 맥 실행과 서명을 기록한다. 구형 CSV 동일 편집 재적용의 제한과 최신 버전 사용을 숨기지 않는다.
- [ ] 전체 변경에 독립 리뷰를 한 번 수행한다. 중요한 결함은 재현 테스트로 수정하고 관련 전체 검사를 실행한다. `git diff --check`와 상태를 확인하고 커밋 `docs: record verified automatic sync workflows`. 실기기 미검증을 구현 완료와 구분해 전달한다.

## 자체 검토 및 실행 방식

설계의 루틴별 CSV, TRUE/FALSE 단계 상태, 외부 편집 자동 반영, JSON 변경 이력, 기기 저장 유지, 충돌·삭제·권한·오프라인 복구, 맥 UI 및 실제 iCloud 검증을 Tasks 1–7에 대응시켰다. 공유 DTO와 저장·파일 계층의 경계를 먼저 고정해 테스트가 실제 iCloud 계정 없이도 의미 있게 실행되도록 했다.

기존 세션의 직접 구현 방식을 유지한다. 이 계획은 구현 전 검토 대상이다. 실제 iCloud 권한과 기기 설치가 필요한 시점 전까지는 로컬 임시 폴더와 시뮬레이터로 검증할 수 있다.
