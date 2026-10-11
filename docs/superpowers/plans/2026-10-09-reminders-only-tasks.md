# Reminders-only Tasks Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** 내부 일감 기능과 기존 데이터를 삭제하고 일감 사용을 Apple 미리 알림으로 통일한다.

**Architecture:** SwiftData의 기존 타입은 파일 호환용으로 유지하고 내부 일감 레코드와 연결을 트랜잭션으로 정리한다. 동기화 상태의 일감에도 삭제 이벤트를 남겨 재수신 시 복원되지 않게 한다. UI는 기존 AppleRemindersModel을 사용한다.

**Tech Stack:** Swift, SwiftUI, SwiftData, EventKit, XCTest; iOS 17 / macOS 14 이상. 외부 의존성 추가 없음.

**Spec:** `docs/superpowers/specs/2026-10-09-reminders-only-tasks-design.md`

## Global Constraints

- 완료 여부와 관계없이 기존 내부 일감을 삭제하며, 보관 화면이나 미리 알림으로의 이전 기능은 만들지 않는다.
- TaskItem 타입은 기존 저장소와 동기화 파일을 읽고 정리하는 호환 계층으로만 유지한다.
- 타임블록 자체의 제목, 날짜, 시작·종료 시각은 보존한다. 루틴 연결은 유지한다.
- 내부 일감 삭제는 EventKit 삭제 API를 호출하지 않는다.
- 기존 동기화 이력 파일과 사용자가 별도로 만든 백업 파일을 지우거나 다시 쓰는 작업은 포함하지 않는다.
- 기존 작업 디렉터리의 다른 변경은 보존하고 이 작업과 관련된 파일만 수정한다.
- 실제 사용자 저장소에서 시험하지 않는다. 테스트 전용 저장소 및 가짜 EventKit 접근 계층을 사용한다.

## Review Focus

1. 로컬에는 없고 동기화 저널에만 남은 일감: 삭제 이벤트를 생성하고 복원하지 않는다. Task 1에서 검증.
2. 저장 공간 부족: 일감, 블록 연결, 삭제 이벤트를 모두 롤백하고 오류를 표시한다. Task 1에서 검증.
3. 오프라인 구버전이 새 UUID나 오래된 블록 연결을 전송: 일감을 제거하고 블록 내용은 보존한다. Task 2에서 검증.
4. 선택했던 미리 알림 목록의 권한 상실/삭제: 내부 일감으로 대체 생성하지 않는다. Task 3에서 검증.
5. 기존 pending-stack UI fixture가 내부 일감을 생성: 루틴 기반 fixture로 바꿔 스크롤 및 집중 회귀를 계속 검증한다. Task 4에서 검증.

## 파일 구성과 실행 원칙

- 새 `TodayRoutine/Data/LegacyTaskCleanup.swift`: 레거시 레코드 삭제 및 트랜잭션 진입점.
- `TodayRoutine/Sync/StoreSyncAdapter.swift`: 저널의 일감 삭제 이벤트와 수신 경로 정리.
- `TodayRoutine/App/TodayRoutineApp.swift`: 첫 화면 전에 정리하고 실패를 드러내는 초기화.
- `PlanningView.swift`, `TodayView.swift`, `TimeBlockEditor.swift`, `FocusSessionView.swift`: 내부 일감 사용 경로 제거.
- 새 `TodayRoutineTests/LegacyTaskCleanupTests.swift`와 기존 동기화/UI 테스트: 삭제 및 회귀 검증.
- 기존 작업 트리에 미커밋 변경이 많다. 현재 내용으로 테스트 기준선을 기록하고 관련 변경만 만든다. 현재 변경을 빠뜨리는 기본 브랜치 기반 worktree를 만들지 않는다. 공유 파일은 전체 파일을 무조건 스테이징하지 않고 이번 작업의 diff만 커밋한다.
- 테스트 fixture에 필요한 레거시 타입을 무리하게 제거하지 않는다. 앱의 일반 화면 및 쓰기 경로에서 사용되지 않는 것이 기능 제거 기준이다.

### Task 1: 원자적인 내부 일감 정리

**Files:** 새 `TodayRoutine/Data/LegacyTaskCleanup.swift`, 수정 `TodayRoutine/Sync/StoreSyncAdapter.swift`, 새 `TodayRoutineTests/LegacyTaskCleanupTests.swift`.

**Interfaces:**
- 제공: `RoutineStore.removeLegacyTasks() throws -> Void` — 독립 트랜잭션을 열고 정리한다.
- 제공: `RoutineStore.removeLegacyTaskRecords() throws -> Void` — 호출자가 연 트랜잭션 안에서 모든 TaskItem 삭제 및 task 연결 해제만 수행한다.
- 제공: `StoreSyncAdapter.captureLegacyTaskRemoval(before: [String: SyncObject]) throws -> Void` — 현재 저널의 살아 있는 task 객체를 before에 보충한 뒤 기존 capture를 사용한다. 활성 저널의 task 연결 블록도 비교 기준에 포함한다.
- 사용: `RoutineStore.transaction(_:)`, `StoreSyncAdapter.exportState()`, `capture(before:)`, `saveOperation`.

- [x] 완료/미완료 일감, task 연결 블록, routine 연결 블록을 직접 저장한 fixture를 만든다. `testCleanupDeletesTasksAndPreservesBlocks`에서 정리 후 `XCTAssertTrue(snapshot.tasks.isEmpty)`, task 블록의 두 연결 필드 nil, 기존 제목/날짜/시작/종료 동일, routine 연결 동일을 검증한다.
- [x] `testCleanupDeletesJournalOnlyTasks`에서 저널에는 task가 있으나 로컬에는 없는 상태를 만든다. 정리 후 `XCTAssertTrue(state.tombstones.contains("task/" + id.uuidString))`를 검증한다.
- [x] `testCleanupRollbackAndRetry`에서 `saveOperation`으로 저장 실패를 주입한다. `XCTAssertThrowsError(try store.removeLegacyTasks())` 후 원본 일감 수, 블록 연결, 저널 이벤트 수가 모두 원래대로인지 검증한다. 실패를 해제하고 재시도하면 모두 정리되어야 한다.
- [x] `swift test --build-system native --scratch-path /private/tmp/today-routine-tests --filter LegacyTaskCleanupTests`로 새 API 부재 또는 실패하는 단언을 확인한다.
- [x] 위 인터페이스를 구현한다. 수동 capture 중 자동 capture가 중복되지 않도록 기존 `syncApplying` 값을 보존/복원한다. 동기화 설정이 없으면 로컬 정리만 수행한다. 변경이 없으면 이벤트와 저장 작업을 생략한다.
- [x] `testCleanupIsIdempotentAndKeepsPendingDeletion`을 추가한다. 두 번 정리 후 이벤트 수 동일, 오프라인 삭제 이벤트가 pendingEvents에 존재함을 검증한다. 위 명령을 재실행해 통과를 확인한다.
- [x] 이번 작업 diff만 커밋한다: `feat: remove legacy task data atomically`.

### Task 2: 초기화 및 동기화 수신에 정리 적용

**Files:** `TodayRoutine/App/TodayRoutineApp.swift`, `TodayRoutine/Sync/StoreSyncAdapter.swift`, `TodayRoutineTests/SyncStoreTests.swift`, `TodayRoutineTests/LegacyTaskCleanupTests.swift`.

**Interfaces:** Task 1의 세 메서드를 사용한다. `StoreSyncAdapter.ingest(_:)`, `appendLocal(_:)`, `enable(spaceID:deviceID:)`의 외부 시그니처는 유지한다.

- [x] `testIngestRetiresNewLegacyTaskAndDetachesBlock`을 작성한다. 새 task UUID 및 해당 연결 블록을 원격 이벤트로 수신한 뒤 로컬 tasks 비어 있음, 블록 내용 보존/연결 nil, task tombstone 및 미발행 로컬 삭제 이벤트를 검증한다.
- [x] `testReplayDoesNotRestoreTasksOrGrowJournal`에서 동일 이벤트 재수신 후 일감 수 0과 이벤트 수 불변을 검증한다. 두 번째 저장소가 생성된 삭제 이벤트를 수신하는 경로도 검증한다.
- [x] `testAppendLocalAndEnableRetireLegacyTasks`에서 appendLocal 및 최초 동기화 연결 경로 모두 정리되는지 검증한다. `testIngestCleanupFailureRollsBackIncomingEvent`로 수신 이벤트 기록까지 롤백되는지 확인한다.
- [x] `swift test --build-system native --scratch-path /private/tmp/today-routine-tests --filter 'SyncStoreTests|LegacyTaskCleanupTests'`로 실패를 확인한다.
- [x] ingest/appendLocal에서 원격 상태 적용과 Task 1의 레코드 정리·삭제 capture를 같은 기존 트랜잭션 안에서 수행한다. 중첩 트랜잭션을 열지 않는다. enable에서도 최초 스냅샷 생성 전후 순서를 맞추어 레거시 데이터가 활성 task로 발행되지 않게 한다.
- [x] AppModel.open의 첫 reload 및 sync.restore 이전에 removeLegacyTasks를 호출한다. 오류는 startupError로 전달한다. 실패를 무시하는 `try?` 정리나 화면에서만 숨기는 방식은 금지한다.
- [x] 위 테스트를 다시 실행해 통과를 확인한다. 기존 task 유지 가정의 동기화 테스트는 새 정책에 맞게 수정하되 routine/step/group/record 병합 검증은 유지한다.
- [x] 이번 작업 diff만 커밋한다: `fix: prevent legacy tasks returning through sync`.

### Task 3: 일감 화면을 미리 알림으로 통일

**Files:** `TodayRoutine/Features/Planning/PlanningView.swift`, `TodayRoutine/Features/Planning/AppleRemindersViews.swift`, `TodayRoutineUITests/AppleRemindersWorkflowTests.swift`, 필요 시 `TodayRoutine/App/AppleRemindersFixture.swift`.

**Interfaces:** 기존 `AppleRemindersModel.writableLists`, `hasAccess`, `selectedIDs`, `save(_:)`, `AppleReminderDraft(listID:)`와 AppleReminderEditor를 사용한다. EventKit API 변경 없음.

- [x] `testPrimaryAddCreatesReminderOnly` UI 테스트를 작성한다. 가짜 목록 연결 후 상단 추가 버튼으로 편집 화면을 열고 저장한다. 재실행 후 미리 알림 목록에서 새 항목을 확인하고 내부 TaskEditor 경로가 없는지 검증한다.
- [x] `testAddWithoutWritableListOpensConnection`과 `testRevokedAccessCannotCreateLocalTask`에서 미연결/읽기 전용/권한 상실 상태의 버튼이 연결 안내를 제공하고 내부 일감 입력으로 이동하지 않는지 검증한다. fixture에서 전체 쓰기 호출을 확인해 legacy 정리가 EventKit을 호출하지 않음을 검증한다.
- [x] 사용 가능한 iPhone 시뮬레이터를 `xcrun simctl list devices available`로 찾고 `xcodebuild -project TodayRoutine.xcodeproj -scheme TodayRoutine -destination 'platform=iOS Simulator,name=<확인한 기기>' -derivedDataPath /private/tmp/today-routine-ios-build test CODE_SIGNING_ALLOWED=NO -only-testing:TodayRoutineUITests/AppleRemindersWorkflowTests`를 실행해 실패를 확인한다.
- [x] PlanningView의 내부 task state, 목록, 삭제 대화상자, TaskEditor sheet를 제거한다. 상단 추가는 writableLists가 있고 접근 가능하면 미리 알림 편집기로, 아니면 연결 화면으로 이동한다. 상태별 안내를 구분하고 원본 목록 선택은 기존 편집기에서 유지한다.
- [x] 동일 UI 테스트를 다시 실행해 통과를 확인한다.
- [x] 이번 작업 diff만 커밋한다: `feat: use Apple Reminders for all task actions`.

### Task 4: 오늘·타임블록·집중 모드의 내부 일감 경로 제거

**Files:** `TodayRoutine/Features/Today/TodayView.swift`, `TodayRoutine/Features/Today/FocusSessionView.swift`, `TodayRoutine/Features/Planning/TimeBlockEditor.swift`, `TodayRoutine/App/TodayRoutineApp.swift`, `TodayRoutineTests/FocusSessionTests.swift`, `TodayRoutineUITests/WorkflowTests.swift`, `TodayRoutineUITests/AppleRemindersWorkflowTests.swift`.

**Interfaces:** TodayEntry에서 TaskItem 의존성을 제거한다. FocusSession.Target.task는 기존 세션 방어 및 레거시 테스트에 필요하면 유지하되 UI 생성/완료 쓰기를 금지한다.

- [x] 테스트 전용 legacy fixture 플래그로 완료/미완료 일감과 연결 블록을 첫 초기화 전에 주입한다. `testLegacyTasksDisappearOnUpgrade`에서 오늘·일감 목록과 집계에 내부 일감이 없고 블록이 남는지 재실행까지 검증한다.
- [x] `testReminderCompletionUpdatesTodayCount`에서 선택 날짜 미리 알림 완료에 따른 집계 변경을 검증한다. 루틴과 블록 집중 테스트를 유지한다.
- [x] 기존 `--uitest-pending-stack`의 task 생성 fixture를 시간 지정 루틴 24개로 교체한다. 스크롤 복원/누적 목록 테스트는 해당 루틴 제목으로 동일 사용자 동작을 검증한다.
- [x] 관련 WorkflowTests/AppleRemindersWorkflowTests를 Task 3의 UI 명령으로 실행해 실패를 확인한다.
- [x] TodayView에서 tasks, selectedTask, taskRow, 드래그/상세/집중 task 분기와 집계 항을 제거한다. 날짜별 미리 알림 섹션은 유지한다. TimeBlockEditor의 task 선택지를 제거한다. TaskEditor에 연결된 앱 경로가 없는지 `rg`로 확인한다.
- [x] AppModel.reload 시 레거시 task 집중 세션을 종료하고 FocusSessionView에서 task 완료 쓰기를 제거한다. routine/block 집중의 동작은 유지한다.
- [x] 위 UI 테스트와 `swift test --build-system native --scratch-path /private/tmp/today-routine-tests --filter FocusSessionTests`가 통과하는지 확인한다.
- [x] 이번 작업 diff만 커밋한다: `refactor: remove internal task presentation and focus actions`.

### Task 5: 통합 검증과 사용자 안내

**Files:** `README.md`, `CHANGELOG.md`, 새 `docs/verification-2026-10-09-reminders-only-tasks.md`, 필요한 경우 생성된 `TodayRoutine.xcodeproj/project.pbxproj`.

**Interfaces:** 신규 API 없음. Tasks 1–4 결과를 앱 빌드에 통합한다.

- [x] 새 파일이 Xcode 타깃에 포함되도록 `python3 scripts/generate-project.py`를 실행하고 생성 diff에 무관한 변경이 없는지 확인한다.
- [x] README/변경 기록에 내부 일감 자동 삭제, 보관·이전 없음, 블록 연결 해제, 모든 기기 업데이트 필요를 명시한다. 미리 알림 원본은 삭제 대상이 아님을 설명한다. 버전 변경과 설치는 실제 배포 범위에 맞춰 별도 판단하며 테스트만으로 사용자 앱을 교체하지 않는다.
- [x] `swift test --build-system native --scratch-path /private/tmp/today-routine-tests`를 실행해 전체 결과를 기록한다. 사전 기준선의 실패와 새 실패를 구분한다.
- [x] `xcodebuild -project TodayRoutine.xcodeproj -scheme TodayRoutineMac -destination 'platform=macOS' -derivedDataPath /private/tmp/today-routine-mac-build build CODE_SIGNING_ALLOWED=NO`와 Task 3의 iOS 테스트 명령으로 양쪽 빌드를 검증한다. 이 Mac 산출물은 실행용으로 설치하지 않는다.
- [x] 관련 iOS UI 회귀 테스트와 기존 Mac 동기화 UI 테스트를 실행한다. 사용할 수 없는 시뮬레이터/GUI 또는 실제 계정 검증은 미검증으로 명시한다. 일반 사용자 데이터에 접근하는 우회 테스트를 하지 않는다.
- [x] `git diff --check` 및 내부 task 생성/편집 경로 검색으로 최종 diff를 확인한다. 검증 문서에는 실제 실행 명령, 결과, 미검증 범위를 기록한다.
- [x] 이번 변경만 커밋한다: `docs: document reminders-only tasks and verification`.

## 계획 자체 검토

- 설계의 삭제, 저장소 호환성, EventKit 비변경은 Tasks 1–2와 Task 3 호출 검증이 담당한다.
- UI와 오늘 집계, 타임블록 및 집중 정리는 Tasks 3–4가 담당한다.
- 실패 롤백, 재실행, 지연 수신, 오프라인 대기열, 중복 이벤트는 Tasks 1–2에서 검증한다.
- 초기화와 수신에서 서로 다른 트랜잭션 경계를 사용하므로 레코드 정리와 독립 트랜잭션 진입점을 구분했다.
- 계획 실행 권장 방식은 이 대화에서 직접 구현이다. 저장소와 동기화 변경이 긴밀하게 연결되어 순차 구현이 적합하다.

## 실행 결과 · 2026-10-09

구현과 검증을 완료했다. 공유 테스트 140개, 관련 iOS UI 테스트 10개(실패 항목 재검증 포함), iOS/macOS 빌드가 통과했다. Mac UI 테스트는 자동화 모드 초기화 시간 초과로 본문 미실행이며, 실계정/실기기 검증과 앱 설치는 수행하지 않았다.

계획 조정: 저널에만 있는 블록을 삭제하지 않기 위해 일반 snapshot diff 대신 task 삭제와 block 연결 해제 이벤트만 명시적으로 생성한다. 기존 Today 화면 자동 스크롤 때문에 UI 테스트는 조작 전 상단으로 이동한다. 기존 미커밋 변경이 많은 공유 파일은 이번 작업에서 통째로 커밋하지 않고 현재 작업 트리에 남겼다. 별도 검토자의 production 코드 리뷰에서 수정이 필요한 사항은 없었다. 상세 결과는 `docs/verification-2026-10-09-reminders-only-tasks.md`에 기록했다.
