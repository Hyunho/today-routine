# Today Routine iOS Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** 로컬 저장으로 동작하는 오늘의 루틴 아이폰 앱을 만들고 시뮬레이터에서 검증한다.

**Architecture:** SwiftUI 화면, SwiftData 저장소, 순수 일정 규칙, 알림 서비스로 분리한다. 화면의 변경은 저장소 서비스를 거치고 저장 실패를 사용자에게 표시한다. 그룹별 정렬은 화면용 계산이며 저장된 수동 순서를 변경하지 않는다.

**Tech Stack:** Swift, SwiftUI, SwiftData, UserNotifications, XCTest, Xcode.

**Spec:** `docs/superpowers/specs/2026-09-30-today-routine-ios-design.md`

## Global Constraints

- 최소 iOS 17, 아이폰 앱, 한국어 기본, 시스템 글자 크기와 밝은·어두운 화면 지원.
- CloudKit 동기화를 끄고 서버 없이 작동한다. 외부 라이브러리는 첫 버전에 사용하지 않는다.
- 날짜 키와 주간 경계는 Asia/Seoul, 월요일부터 일요일까지로 계산한다.
- 첫 실행은 빈 목록. 운영 데이터 자동 복사·업로드 없음.
- 매일 / 요일 선택 / 주 1~7회 목표. 루틴은 하루 최대 1회 완료 집계.
- 알림은 다음 7일의 미래 예약 중 가까운 60개까지. 주간 횟수형 자동 알림 제외.
- App Store/TestFlight 배포, TickTick, 위젯, 실시간 활동은 범위 밖.
- 첫 작업에서 현재 작업 폴더의 전용 저장소와 작업 상태를 확인한다. 다른 작업이 없으면 전용 구현 브랜치를 사용한다.

## Review Focus

- 같은 시간과 시간 미지정 항목: 안정적인 정렬, 수동 순서 불변. Task 2에서 검증.
- 한국 자정·월요일 경계: 날짜 및 주간 기록의 중복·누락 방지. Task 2에서 검증.
- 디스크 저장 실패: 입력 보존, 성공 표시 금지, 기존 파일 자동 초기화 금지. Task 1·3에서 검증.
- 그룹·일감 삭제와 단계 편집: 연결 해제와 과거 기록 보존. Task 1·3·4에서 검증.
- 알림 거부와 과도한 예약: 앱 사용 가능, 가까운 미래 예약만 유지. Task 5에서 검증.

## 파일 구성

- `TodayRoutine.xcodeproj/project.pbxproj`, `TodayRoutine.xcodeproj/xcshareddata/xcschemes/TodayRoutine.xcscheme`: 앱·단위 테스트·UI 테스트 타깃, 공유 스킴.
- `TodayRoutine/App/TodayRoutineApp.swift`, `RootView.swift`: 저장소 초기화, 오류 복구, 네 개 탭.
- `TodayRoutine/Models/Routine.swift`, `RoutineDayRecord.swift`, `PlanningModels.swift`: 설계의 7개 영속 모델과 열거형.
- `TodayRoutine/Data/RoutineStore.swift`: 저장·삭제·실행 상태 전이, 오류 처리.
- `TodayRoutine/Domain/RoutineRules.swift`, `ReminderPlanner.swift`: 날짜, 반복, 정렬, 집계, 예약 후보 생성.
- `TodayRoutine/Features/Today/TodayView.swift`: 날짜별 실행 목록과 단계 체크.
- `TodayRoutine/Features/Routines/RoutinesView.swift`, `RoutineEditor.swift`, `GroupEditor.swift`: 관리와 편집.
- `TodayRoutine/Features/Planning/PlanningView.swift`, `TaskEditor.swift`, `TimeBlockEditor.swift`: 일감과 시간 배치.
- `TodayRoutine/Features/History/HistoryView.swift`: 주간 기록.
- `TodayRoutine/Features/Settings/SettingsView.swift`, `TodayRoutine/Services/NotificationService.swift`: 알림 설정·권한·예약.
- `TodayRoutineTests/StoreTests.swift`, `RoutineRulesTests.swift`, `PlanningTests.swift`, `ReminderTests.swift`: 핵심 규칙 테스트.
- `TodayRoutineUITests/WorkflowTests.swift`: 생성→완료→재실행 흐름.
- `README.md`, `.gitignore`: 실행 방법, 제한, 로컬 빌드 산출물 제외.

## 공통 검증 명령

실행 시 `xcrun simctl list devices available`에서 사용 가능한 iPhone UDID 하나를 선택하고 아래 `<UDID>`에 대입한다.
빌드: `xcodebuild -project TodayRoutine.xcodeproj -scheme TodayRoutine -sdk iphonesimulator -destination 'id=<UDID>' -derivedDataPath .build build CODE_SIGNING_ALLOWED=NO`
테스트: 같은 명령에서 `build`를 `test`로 교체한다. 필요 시 `-only-testing:TodayRoutineTests/테스트클래스`로 제한한다.
실패가 예상되는 테스트는 해당 동작의 부재 때문에 실패했는지 확인한다. 설정 문제는 실패 증거로 대체하지 않는다.
각 작업의 테스트 성공 후 해당 파일만 스테이징하고 의미 있는 단위로 커밋한다.

### Task 1: 로컬 저장소와 앱 골격

**Files:** App/, Models/, Data/RoutineStore.swift, Xcode 프로젝트·스킴, StoreTests.swift, .gitignore.
**Interfaces:** `@MainActor RoutineStore.init(container: ModelContainer)`, `save() throws`, `loadSnapshot() throws -> StoreSnapshot`; `PersistenceFactory.make(url: URL?, inMemory: Bool) throws -> ModelContainer`. StoreSnapshot은 루틴, 단계, 그룹, 날짜별 기록, 일감, 블록, 알림 설정 배열을 제공한다.

- [ ] SwiftData의 7개 모델을 테스트 픽스처로 다룰 최소 타입 계약과 테스트 타깃을 준비한다. UUID·생성·수정 시각, 루틴·날짜 유일 키를 정의한다.
- [ ] `testReopenPreservesAllModels`: 임시 저장소에 각 모델 저장 후 새 컨테이너로 다시 열었을 때 ID와 값이 같음을 검증한다.
- [ ] `testInvalidStoreReportsErrorWithoutReset`: 손상된 임시 파일에서 열기 실패, 원본 바이트 불변을 검증한다. 테스트 실행으로 미구현 실패를 확인한다.
- [ ] CloudKit 없는 저장소, 수동 저장 및 오류 반환, 초기화 실패 재시도 화면과 기본 탭을 구현한다. 오류 시 임시 메모리 저장소로 몰래 대체하지 않는다.
- [ ] 두 테스트와 시뮬레이터 빌드가 통과하면 커밋한다.

### Task 2: 반복·정렬·날짜 규칙

**Files:** Domain/RoutineRules.swift, RoutineRulesTests.swift.
**Interfaces:** `RoutineRules.dayKey(_ date: Date) -> String`, `weekStart(_ date: Date) -> Date`, `isScheduled(_ routine: Routine, on: Date) -> Bool`, `timeSorted(_ routines: [Routine]) -> [Routine]`, `completedCount(routineID: UUID, records: [RoutineDayRecord], week: Date) -> Int`.

- [ ] `testGroupedTimeSort`: 06:30, nil, 05:30, 05:45 입력이 05:30, 05:45, 06:30, nil 순서가 되고 원래 sortOrder가 불변인지 검증한다. 동률과 그룹 없음도 검증한다.
- [ ] `testSeoulMidnightAndMonday`: UTC 일요일 15:00가 한국 월요일이고 날짜 키가 바뀌는지, 주 경계가 월요일인지 검증한다.
- [ ] `testWeekdaysAndArchivedRoutine`: 선택 요일만 표시되고 일시정지·보관 루틴은 예정 목록에서 제외되는지 검증한다. 건너뜀 제외 집계도 추가한다.
- [ ] 미구현 실패를 확인한 뒤 Gregorian·Asia/Seoul 달력과 안정 정렬을 구현한다. 시간 동률은 sortOrder, UUID 순으로 비교한다.
- [ ] RoutineRulesTests 통과 후 커밋한다.

### Task 3: 루틴 관리·오늘 실행·주간 기록

**Files:** Features/Today/, Features/Routines/, Features/History/, Data/RoutineStore.swift, StoreTests.swift, WorkflowTests.swift.
**Interfaces:** `upsertRoutine(_ draft: RoutineDraft) throws`, `setStatus(routineID: UUID, date: Date, status: DayStatus) throws`, `toggleStep(routineID: UUID, stepID: UUID, date: Date) throws`, `deleteGroup(id: UUID) throws`; RoutineDraft는 편집 가능한 설계 필드 전체와 단계 목록을 가진 값 타입이다.

- [ ] `testCompletionIsIdempotentAndReversible`: 반복 완료 요청에도 기록 1개, 완료 취소 시 집계 0을 검증한다.
- [ ] `testLastStepCompletesAndUncheckReopens`: 모든 단계 완료→전체 완료, 하나 해제→미완료, 전체 완료→모든 단계 체크를 검증한다.
- [ ] `testHistorySurvivesRoutineEdits`: 어제의 이름 스냅샷·완료 단계가 오늘 편집 이후 동일함을 검증한다. `testDeleteGroupOnlyUnlinksRoutines`도 추가한다.
- [ ] 의도한 실패를 확인한 뒤 draft 기반 편집, 빈 이름·빈 요일·범위 밖 주간 목표 검증, 수동 정렬·그룹 관리·일시정지·보관·복원을 구현한다.
- [ ] 오늘의 시간순/시간 미정/주간 목표 구역, 단계와 완료·건너뜀·복원, 주간 완료 횟수 화면을 연결한다. 저장 실패 시 draft를 유지하고 변경은 롤백한다.
- [ ] `testCreateCompleteAndRelaunch` UI 테스트로 추가→완료→종료→재실행 후 표시와 주간 집계를 검증한다. 관련 단위 테스트와 함께 통과 후 커밋한다.

### Task 4: 일감·타임블록

**Files:** Features/Planning/, Data/RoutineStore.swift, PlanningTests.swift.
**Interfaces:** `upsertTask(_ draft: TaskDraft) throws`, `setTaskCompleted(id: UUID, completed: Bool) throws`, `deleteTask(id: UUID) throws`, `upsertBlock(_ draft: BlockDraft) throws`, `deleteBlock(id: UUID) throws`; 날짜는 dayKey, 시간은 0~1439분, 연결은 enum(kind, UUID)로 표현한다.

- [ ] `testRejectsInvalidBlockRange`: 종료<=시작 및 하루 밖 시간을 거부한다. `testOverlapWarnsButAllowsSave`: 겹침 여부는 true이며 저장은 성공한다.
- [ ] `testDeletingTaskPreservesBlockTitle`: 연결 일감 삭제 후 블록 제목 유지·연결 nil을 검증한다. `testSchedulingDoesNotCompleteTask`: 배치만으로 완료가 바뀌지 않음을 검증한다.
- [ ] 실패 확인 후 일감·블록 목록과 편집 폼, 연결 선택, 겹침 경고, 삭제 확인을 구현한다. 제목이 공백이면 저장하지 않는다.
- [ ] 저장 실패 입력 보존과 일감·블록 재실행 유지 테스트를 포함해 PlanningTests 통과 후 커밋한다.

### Task 5: 기기 알림

**Files:** Domain/ReminderPlanner.swift, Services/NotificationService.swift, Features/Settings/SettingsView.swift, ReminderTests.swift.
**Interfaces:** `ReminderPlanner.requests(snapshot: StoreSnapshot, now: Date) -> [ReminderRequest]`; ReminderRequest는 안정 ID, 제목, 미래 fireDate를 가진다. `NotificationService.requestPermission() async throws -> Bool`, `refresh(snapshot: StoreSnapshot, now: Date) async throws`.

- [ ] `testNextSevenDaysLimitedToNearest60`: 60개 초과 후보에서 가까운 미래 60개만 반환하며 기간 밖/과거 후보를 제외한다.
- [ ] `testExcludesCompletedSkippedPausedWeeklyGoal`: 완료·건너뜀 날짜와 일시정지·보관·주간목표 루틴을 예약에서 제외한다.
- [ ] `testDeniedPermissionDoesNotPreventSaving`: 가짜 notification center의 거부 응답에도 저장소 기능이 계속 동작하는지 검증한다.
- [ ] 실패 확인 후 UserNotifications 어댑터와 설정 화면을 구현한다. 요청 순서를 직렬화해 오래된 비동기 갱신이 최신 예약을 덮어쓰지 않도록 한다.
- [ ] 활성화·설정/루틴 변경·완료 변경 시 재계산하고 오래된 앱 예약만 취소한다. 예약 실패와 7일 갱신 제한을 설정에 표시한다.
- [ ] ReminderTests 통과 및 시뮬레이터 예약 확인 후 커밋한다. 실기기 알림 검증 여부는 별도로 기록한다.

### Task 6: 통합 검증과 전달

**Files:** WorkflowTests.swift, README.md, 필요 시 결함이 발견된 기능 파일.
**Interfaces:** 앞선 작업의 앱 및 서비스 전체.

- [ ] 작은 아이폰 화면과 접근성 글자 크기로 루틴 추가·단계 체크·계획 편집·기록 확인 UI 흐름을 검증한다.
- [ ] 빈 상태, 긴 한글 제목, 밝은·어두운 화면에서 잘림과 조작 가능성을 확인한다.
- [ ] 전체 XCTest와 시뮬레이터 빌드를 실행한다. 실패는 원인을 수정하고 관련 검사부터 다시 실행한다.
- [ ] 앱을 시뮬레이터에 설치·실행하고 저장 유지·그룹 내부 시간순 정렬을 직접 확인한다.
- [ ] README에 프로젝트 실행, 최소 OS, 로컬 저장, 알림 기간 제한, 서명과 실기기 설치 확인 상태를 적는다.
- [ ] 변경 전체 리뷰와 최종 git diff --check를 수행한 뒤 검증 결과와 남은 제한을 사용자에게 전달한다.

## 자체 검토

설계의 네 탭, 반복·단계·보관, 그룹 정렬, 계획 연결, 기록 보존, 오류 처리, 로컬 저장, 알림 및 접근성을 작업에 대응시켰다.
실기기 설치·배포와 서버 연동을 완료 기준에 혼합하지 않았다. 작업 간 데이터 타입과 서비스 인터페이스를 맞췄다.
실행 방식 제안: 이 대화에서 직접 순차 구현. 저장소와 화면 간 의존성이 높아 통합 상태를 유지하며 검증하기 적합하다.
