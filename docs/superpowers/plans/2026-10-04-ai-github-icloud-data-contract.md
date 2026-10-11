# AI GitHub–iCloud Data Contract Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 서버 없이 AI가 루틴을 조작하고 GitHub 데이터 저장소와 기존 iCloud 폴더를 검증·병합하는 macOS CLI를 제공한다.

**Architecture:** 기존 Swift SyncReducer/CSVImporter/SyncFolderTransport를 재사용한다. RoutineCore 내부에 구현을 두고 공개 진입점 하나만 CLI에 노출한다. 불변 이벤트를 교환하고 읽기용 JSON·CSV를 생성하며, Git과 iCloud의 부분 실패는 영속 outbox로 복구한다.

**Tech Stack:** Swift 5.9+, macOS 14+, Foundation, CryptoKit, Swift Package Manager, Git CLI, XCTest. 앱 지원 기준은 iOS 17+/macOS 14+ 유지. 새 외부 런타임 의존성 없음.

**Spec:** `docs/superpowers/specs/2026-10-04-ai-github-icloud-data-contract-design.md`

## Global Constraints

- 앱은 기존 iCloud 폴더만 사용한다. 앱에 GitHub 로그인이나 가져오기 기능을 추가하지 않는다. 상시 MCP 서버는 운영하지 않는다.
- 앱 코드 저장소와 비공개 개인 데이터 저장소를 분리한다.
- MCP의 도구 정의 방식을 참고하되 정식 MCP 통신 구현으로 표시하지 않는다.
- 기존 이벤트는 수정하거나 삭제하지 않는다.
- 기존 baseline/manifest/CSV/receipt를 덮어쓰지 않는다.
- 삭제·초기화·이력 정리·공간 이동·시간 블록 조작은 v1에서 제외한다.
- force push하지 않는다. 폴더 쓰기 성공을 아이폰 적용 성공이라고 보고하지 않는다.
- 실데이터를 테스트 fixture로 커밋하지 않는다. 주기적 AI 실행은 이번 범위 밖이다.

## Review Focus

1. 한글·공백·명령 치환 문자를 가진 경로: shell 문자열을 만들지 않고 Process 인자 배열 사용(Task 5).
2. 같은 requestID의 다른 payload 및 다른 날짜 재사용: 오류로 거부하고 기존 이벤트 보존(Task 2, 6).
3. 세부 작업 이름 변경 후 과거 날짜 수정: 과거 stepIDs/stepNames 보존, 미존재 단계 거부(Task 3).
4. iCloud 기록 후 push 실패·프로세스 중단: 이벤트/생성 객체 ID가 바뀌지 않고 재시도(Task 6).
5. 계획 직후 CSV·원격 HEAD 변경 또는 iCloud placeholder 등장: stale_plan/download_pending 반환, 누락을 삭제로 해석하지 않음(Task 4, 6).

## 작업 경계 및 파일 배치

- `TodayRoutine/Automation/`: 계약, 조회·변경 생성, 병합, Git, outbox, 공개 진입점. macOS 전용 부분은 `#if os(macOS)`로 감싼다.
- `Tools/RoutineCLI/main.swift`: RoutineCore 공개 진입점 호출만 담당.
- `contracts/v1/`: 작업 카탈로그와 JSON Schema. `templates/routine-data/`: 데이터 저장소용 AGENTS.md/README/.gitignore.
- `TodayRoutine/Sync/CSVBatchProcessor.swift`: coordinator에서 추출하는 순수 CSV 처리; 앱과 도구가 공용 사용.
- `TodayRoutineTests/Automation*Tests.swift`: synthetic 데이터 기반 단위·통합 테스트.
- `docs/ai-data-workflow.md`: 설치, JSON 호출, 오류 복구와 최초 연결 절차.

현재 checkout에는 이전 앱 작업의 미커밋 변경과 개인 exports가 있다. 실행 시작 시 using-git-worktrees 스킬을 적용하고, 필요한 현재 작업 상태를 보존하는 격리 전략을 확인한다. HEAD만으로 새 checkout을 만들면 minuteOverride 등 설계의 전제가 누락된다. 관련 파일만 현재 내용으로 가져오고 exports는 제외한다. 이전 변경을 되돌리거나 일괄 stage하지 않는다.

## Task 1: 공용 CSV 처리와 CLI 진입점

**Files:** Modify `Package.swift`, `TodayRoutine/Sync/SyncCoordinator.swift`; Create `TodayRoutine/Sync/CSVBatchProcessor.swift`, `TodayRoutine/Automation/AutomationCLI.swift`, `Tools/RoutineCLI/main.swift`; Test `TodayRoutineTests/AutomationCSVTests.swift`.

**Interfaces:** `CSVBatchProcessor.process(files: [SyncCSVFile], events: [SyncEvent], state: SyncState) throws -> CSVBatchResult`; result는 `events`, `conflicts`, `warnings`를 가진다. `public enum AutomationCLI`의 `public static func run(arguments: [String]) async -> Int32`만 외부에 공개한다.

- [ ] 기존 테스트 기준선 실행: `swift test --scratch-path /private/tmp/today-routine-ai-tests`. 기존 실패는 먼저 분리하여 보고한다.
- [ ] 실패 테스트 작성: `testAlreadyImportedCellIsNotReapplied`에서 두 번째 처리의 events가 비어 있어야 한다. `testPartialConflictUsesSameCellEventIDs`에서 앱 경로와 도구 경로의 ID/bytes가 같아야 한다. `testResolvedConflictDoesNotReappear`도 추가한다.
- [ ] `swift test --scratch-path /private/tmp/today-routine-ai-tests --filter AutomationCSVTests`로 새 타입 미정의 실패 확인.
- [ ] coordinator의 문서별 baseline 보정, normalized hash, sourceEvents, resolvedConflicts, alreadyApplied 판정을 공용 처리기로 옮긴다. 문서 순서와 순차 state 갱신을 기존과 동일하게 유지한다. coordinator는 반환 이벤트 저장과 UI 갱신을 담당한다. CLI는 warnings가 하나라도 있으면 쓰기를 중단한다.
- [ ] Package에 Automation sources와 `routine` executable target을 추가한다. Xcode가 새 파일을 자동 포함하는지 project 구성을 확인하고 필요 시 파일 참조를 명시한다. 앱에서 CLI 실행은 하지 않는다.
- [ ] 위 필터와 `--filter Sync` 테스트 실행 후 `swift build --scratch-path /private/tmp/today-routine-ai-tests --product routine` 성공 확인.
- [ ] 이 작업의 변경 파일만 커밋: `refactor: share CSV import planning with automation`.

## Task 2: 버전 계약·요청/결과·카탈로그

**Files:** Create `TodayRoutine/Automation/AutomationContract.swift`, `AutomationRequest.swift`, `AutomationResult.swift`, `contracts/v1/catalog.json`, `contracts/v1/request.schema.json`, `contracts/v1/result.schema.json`, `contracts/v1/contract.schema.json`; Test `TodayRoutineTests/AutomationContractTests.swift`.

**Interfaces:** `AutomationContract`(contractVersion=1, syncVersion=1, toolVersion, spaceID, timezone); `AutomationRequest`(requestID, operation, spaceID, arguments, expectedVersions); `AutomationResult`(requestID, status, eventIDs, summary, conflicts, localPublished, gitCommit, gitPushed, acknowledgedDeviceIDs). `AutomationCodec.decodeRequest(_ data: Data) throws -> AutomationRequest`, `AutomationCodec.requestHash(_ request: AutomationRequest) throws -> String`.

- [ ] 실패 테스트: `testUnknownOperationAndVersionRejected`, `testMissingMutationDateRejected`, `testDifferentPayloadChangesRequestHash`, `testAllCatalogOperationsHaveSchemas`. 날짜는 실제 달력 날짜, 시간은 00:00–23:59 또는 override 해제 null, timezone은 유효한 IANA 값이어야 한다. 알 수 없는 필드는 거부한다.
- [ ] `swift test --scratch-path /private/tmp/today-routine-ai-tests --filter AutomationContractTests`에서 실패 확인.
- [ ] 설계의 10개 작업을 enum으로 구현하고 작업별 인자를 typed decode한다. JSON Schema는 draft 2020-12, additionalProperties=false, 날짜/시간의 추가 의미 검증은 Swift에서 수행한다. schema/catalog과 Swift 허용 작업·enum/필수 키의 일치 테스트를 둔다.
- [ ] 입출력은 JSON 파일 또는 stdin/stdout, 진단은 stderr. 오류 코드는 설계의 5개와 `unsupported_operation`, `request_reused`, `invalid_request`를 정의한다. Git 토큰과 원문 개인 데이터를 오류에 출력하지 않는다.
- [ ] 테스트 통과 후 해당 파일만 커밋: `feat: define versioned automation task contract`.

## Task 3: 조회 및 루틴 변경 생성

**Files:** Create `TodayRoutine/Automation/RoutineOperations.swift`, `AutomationStateValidation.swift`, `AutomationViews.swift`; Test `TodayRoutineTests/AutomationOperationTests.swift`.

**Interfaces:** `RoutineOperations.list(request: AutomationRequest, state: SyncState) throws -> Data`; `RoutineOperations.makeEvent(request: AutomationRequest, state: SyncState, deviceID: UUID, now: Date) throws -> SyncEvent`; `AutomationStateValidation.validate(_ state: SyncState) throws`; `AutomationViews.render(state: SyncState, spaceID: UUID, dayKey: String) throws -> [String:Data]`.

- [ ] 실패 테스트: `testDayTimeDoesNotChangeRoutineTime`에서 record.minuteOverride=1260, routine.minute 불변; `testCompleteSetsApplicableStepsTrue`; `testSkipClearsStepCompletion`; `testHistoricalStepNamesPreserved`; `testTombstonedOrMissingTargetRejected`; `testStaleVersionRejected`; `testRoutineAndStepCreateDefaults`; `testUnrelatedFieldUpdateIsPreserved`.
- [ ] `swift test --scratch-path /private/tmp/today-routine-ai-tests --filter AutomationOperationTests`에서 실패 확인.
- [ ] routine.create/update, step.create/update, record.set_status/set_step/set_time을 구현한다. 신규 record만 현재 세부 작업 snapshot으로 초기화하고 기존 record는 유지한다. command가 영향을 주는 status/모든 step의 기대 버전도 확인한다. routine 반복 설정은 관련 필드를 묶어 검증한다. 새 event counter=state.counter+1, request에서 파생한 안정 ID를 사용하고 timestamp/counter는 Task 6 ledger에서 고정한다.
- [ ] 참조·필수 속성·enum·날짜·시간을 검증한다. 기존에 삭제된 부모의 과거 기록은 보존하되 새 변경이 삭제 대상에 쓰는 것은 거부한다. 기존 읽기 전용 task/block 이력도 보존한다.
- [ ] views는 결정적으로 생성한다. CSV는 날짜+세부 작업 완료 열을 제공하며 UUID 파일명으로 이름 충돌을 방지한다. `routines.json`에 ID와 이름 매핑을 포함한다. 파생 파일만 재생성하고 임의 파일 삭제는 금지한다.
- [ ] 테스트 통과 후 관련 파일만 커밋: `feat: add validated routine automation operations`.

## Task 4: 읽기 전용 병합 계획

**Files:** Create `TodayRoutine/Automation/AutomationSnapshot.swift`, `AutomationPlanner.swift`; Test `TodayRoutineTests/AutomationPlannerTests.swift`.

**Interfaces:** `AutomationSnapshot`(spaceID, events, documents, receipts, fileHashes); `AutomationPlan`(planID, request, requestHash, sourceHashes, expectedRemoteCommit, eventsToCloud, eventsToGit, renderedViews, conflicts); `AutomationPlanner.make(request: AutomationRequest, cloud: AutomationSnapshot, repository: AutomationSnapshot, remoteCommit: String, now: Date) throws -> AutomationPlan`.

- [ ] 실패 테스트: `testEventUnionKeepsBothPeers`, `testDuplicateIDWithDifferentBytesRejected`, `testDifferentSpaceRejected`, `testEditedCSVIncludedWithoutRewritingBaseline`, `testCSVWarningsPreventPlan`, `testMissingDownloadDoesNotBecomeDeletion`, `testFingerprintChangesAfterCSVEdit`.
- [ ] `swift test --scratch-path /private/tmp/today-routine-ai-tests --filter AutomationPlannerTests`에서 실패 확인.
- [ ] 기존 transport를 통해 iCloud snapshot을 읽고 존재하는 space만 허용한다. Git snapshot은 변경 이벤트 envelope 검증을 공유하되 iCloud 쓰기와 분리한다. 원본 payload bytes/hash 보존으로 동일 이벤트 재직렬화 차이를 방지한다. symlink·파일 크기·경로·공간·버전 검사도 적용한다.
- [ ] 이벤트 합집합에 공용 CSV 처리 결과를 합치고 Task 3 검증·명령을 적용한다. 계획은 전체 관련 파일 집합과 바이트 해시를 기록한다. 키 순서가 고정된 JSON 계획과 요청 hash를 로컬 상태 폴더에 저장한다. 원격/실데이터 변경 없이 계획을 표시한다.
- [ ] 테스트 통과 후 관련 파일만 커밋: `feat: plan event-based Git and iCloud reconciliation`.

## Task 5: Git 데이터 저장소 어댑터

**Files:** Create `TodayRoutine/Automation/GitRepository.swift`, `templates/routine-data/AGENTS.md`, `templates/routine-data/README.md`, `templates/routine-data/.gitignore`; Test `TodayRoutineTests/AutomationGitTests.swift`.

**Interfaces:** `GitRepository(root: URL, remote: String, branch: String)`; `fetchSnapshot() throws -> GitSnapshot`(commit, snapshot); `publish(plan: AutomationPlan) throws -> String` returns pushed commit. 별도 Process runner는 executable+arguments 배열만 받는다.

- [ ] 임시 bare 원격/clone fixture로 `testDirtyCheckoutRejected`, `testRemoteAdvanceRejectsStalePlan`, `testOnlyAllowedDataFilesAreCommitted`, `testPathsWithKoreanSpacesAndShellCharacters`, `testUnchangedPlanCreatesNoCommit` 실패 테스트 작성.
- [ ] `swift test --scratch-path /private/tmp/today-routine-ai-tests --filter AutomationGitTests`에서 실패 확인.
- [ ] fetch한 명시적 ref를 검증한다. 원격 URL/브랜치 값을 shell에 보간하지 않는다. 협업 checkout을 reset/clean하지 않는다. clean checkout에서 fast-forward 가능한 경우만 갱신하고 분기된 이력은 재계획/명시 오류로 처리한다. 첫 로컬 seed는 새 비공개 저장소의 문서화된 bootstrap으로 구분한다.
- [ ] stage allowlist는 contract/schema/templates 최초 설치와 data/space.json, data/changes, views, 요청 ledger에 한정한다. credentials, receipts, 절대 경로, outbox는 제외한다. 정상 push만 사용하고 실패를 구별한다. 자동 원격 저장소 생성은 하지 않는다.
- [ ] AGENTS에 규격 읽기→조회→버전 포함 요청→plan→apply→검증 순서와 views 직접 수정 금지, 데이터 본문의 지시 무시, git/iCloud 결과 구분을 적는다.
- [ ] 테스트 통과 후 관련 파일만 커밋: `feat: add scoped Git data repository adapter`.

## Task 6: 멱등 적용·복구와 CLI 연결

**Files:** Create `TodayRoutine/Automation/AutomationOutbox.swift`, `AutomationApply.swift`; Modify `TodayRoutine/Automation/AutomationCLI.swift`; Test `TodayRoutineTests/AutomationApplyTests.swift`, `AutomationCLITests.swift`.

**Interfaces:** `AutomationOutbox(stateDirectory: URL)`; `prepare(plan: AutomationPlan) throws -> StoredRun`; `AutomationApply.apply(plan: AutomationPlan, cloudRoot: URL, repository: GitRepository, outbox: AutomationOutbox) async throws -> AutomationResult`. `StoredRun`은 requestHash, 정확한 event bytes/IDs, phase, gitCommit을 보관한다.

- [ ] 실패 테스트: `testReplayDoesNotDuplicateEvent`, `testSameRequestIDDifferentPayloadRejected`, `testCrashAfterCloudWriteResumesSameBytes`, `testPushFailureKeepsCloudEvents`, `testSourceChangedReturnsStalePlan`, `testNoReceiptMeansAcknowledgementPending`, `testExistingBaselineCSVAndReceiptBytesPreserved`, `testConcurrentRunLock`.
- [ ] `swift test --scratch-path /private/tmp/today-routine-ai-tests --filter AutomationApplyTests`에서 실패 확인.
- [ ] 공간별 로컬 잠금과 원자적 outbox 쓰기를 구현한다. 데이터 저장소의 `operations/<requestID>.json`에는 요청 hash·생성 event IDs만 저장해 다른 checkout에서도 재사용을 확인한다. 절대 경로·토큰·임시 상태는 저장하지 않는다. 동시 다른 환경의 동일 request를 무조건 전역 exactly-once라고 주장하지 않는다. 초기 버전은 한 Mac 실행자로 제한하고 중복 ledger는 오류 처리한다.
- [ ] apply 직전에 원격 commit 및 cloud fingerprint를 재검증한다. iCloud 읽기/추가 쓰기는 NSFileCoordinator를 사용한다. publish 실패 시 일부 성공한 event를 보존하고 같은 bytes로 재시도한다. Task 5 push 후만 gitPushed=true, 실제 receipt에 event가 포함될 때만 acknowledgedDeviceIDs를 채운다.
- [ ] `routine catalog`, `routine invoke --request <file|-> --repo <path> --icloud <path> --state-dir <path> --remote <name> --branch <name>`를 연결한다. mutation invoke는 plan을 만들고 `sync.apply`가 planID로 실행한다. 모든 쓰기는 apply 경로를 통과하며 stdout에 구조화된 결과 하나를 출력한다.
- [ ] 위 테스트와 CLI subprocess 테스트 통과 후 관련 파일만 커밋: `feat: apply automation plans with durable recovery`.

## Task 7: 전체 검증과 사용 안내

**Files:** Create `docs/ai-data-workflow.md`, `TodayRoutineTests/AutomationWorkflowTests.swift`; Modify `README.md`.

- [ ] `testAppToGitToAIToAppRoundTrip` 작성: synthetic 앱 이벤트→로컬 bare Git→AI 완료/시간 변경→iCloud 대역→기존 adapter 수신 결과를 검증한다. 반복 실행 후 event 수 불변, 원래 CSV byte 불변, views 재생성 결과 일치를 확인한다.
- [ ] `swift test --scratch-path /private/tmp/today-routine-ai-tests --filter AutomationWorkflowTests` 실행, 발견된 통합 오류만 수정한다.
- [ ] 전체 `swift test --scratch-path /private/tmp/today-routine-ai-tests` 및 Mac/iOS simulator 빌드를 실행한다. xcodebuild는 기존 scheme TodayRoutineMac/TodayRoutine 사용, simulator는 CODE_SIGNING_ALLOWED=NO. 전체 테스트의 실제 개수와 결과를 보고한다.
- [ ] JSON 요청 예제, contract 버전 고정, 도구 빌드, 임시 저장소 시연, 정상 복구와 충돌 복구 절차를 문서화한다. 운영 Git/iCloud 접근 전에는 read-only plan과 로컬 백업을 만들도록 명시한다.
- [ ] 구현 방식에 맞는 코드 리뷰를 수행하고 수정 후 관련 검증만 반복한다. 기능 문서와 테스트를 명시적으로 커밋한다.
- [ ] 사용자에게 도구 결과와 제한을 전달한다. 실제 비공개 데이터 저장소 URL/브랜치를 요청하고 이후 연결 작업을 진행한다. 저장소 정보가 없더라도 도구 구현·테스트·문서는 완료한다. live 동기화나 아이폰 수신을 fixture 결과로 대체하여 완료라고 하지 않는다.

## 자체 검토 및 실행 선택

설계의 계약, CSV 의미 보존, 원본 이벤트 교환, 오류 코드, 멱등성, Git 범위, 다운로드·동시 수정 한계와 실데이터 도입을 Tasks 1–7에 대응시켰다. 신규 동시 실행의 전역 잠금을 구현하지 않는 대신 v1 실행자를 한 Mac으로 제한한다. 이는 아직 도착하지 않은 기기 이벤트를 감지할 수 없다는 설계의 제한을 유지한다.

권장 실행 방식은 이 세션에서 직접 구현(Native) 후 독립 최종 리뷰다. 공용 CSV 처리, 명령 생성, 병합·복구가 같은 이벤트 계약에 긴밀히 의존하므로 단계별로 일관되게 구현하고 회귀 검증하는 편이 적합하다. 대안은 작업별 구현·리뷰 에이전트 방식이며 더 많은 별도 문맥이 필요하다. 사용자 계획 검토와 실행 방식 선택 후 구현을 시작한다.
