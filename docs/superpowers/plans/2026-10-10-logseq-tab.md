# Logseq Tab Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Execution method: user approved inline execution on 2026-10-10.

**Goal:** 오늘의 루틴 Mac 앱의 Logseq 탭에서 bilog 편집기로 노트를 편집하고, 전환·종료 시 안전하게 저장한다.

**Architecture:** bilog를 커밋에 고정한 Git 서브모듈이자 로컬 Swift 패키지로 연결한다. bilog는 편집·파일 접근·저장을 제공하고, TodayRoutine의 Mac 전용 호스트는 탭, 창, 메뉴와 앱 생명주기를 연결한다. 기존 iOS 타깃에는 bilog를 연결하지 않는다.

**Tech Stack:** Swift 5.9+, SwiftUI, AppKit, Swift Package Manager, Xcode, Git submodules, XCTest.

**Spec:** `docs/superpowers/specs/2026-10-10-logseq-tab-design.md` (2026-10-10 사용자 승인, 서브모듈 수정안).

## Execution Status

2026-10-10: 구현과 로컬 빌드 60을 만들었다. 패키지 94개·저장/종료 하네스 7개 테스트를 통과했고 Mac/iOS 빌드와 Mac 테스트 컴파일을 확인했다. 독립 리뷰의 저장 잠금/Markdown 실행 취소 문제를 보완했다. 상세 결과와 미검증 범위는 `docs/verification-2026-10-10-logseq-tab.md`를 따른다. 실제 화면 검증은 사용자 요청으로 생략했고, bilog 원격 푸시는 추가 사용자 승인 후 완료했고, 새 저장소에서 원격 서브모듈 초기화도 검증했다. 아래 체크리스트는 원래 요구 조건을 남겨 후속 검증 범위를 추적한다.

## Global Constraints

- macOS 14 이상, 기존 iOS 17 이상 지원 유지.
- 원격: `git@github.com:Hyunho/bilog.git`; 경로: `Packages/NativeLogseq`; 시작 커밋: `e67791a40242395346472e2a4e39b84292d14015`.
- 탭 순서: 오늘 / 일감 / 피드 / 캘린더 / Logseq / 전체. Logseq 아이콘은 `doc.text`.
- 루틴 창 폭 360–480pt, Logseq 기본 폭 1120pt·최소 폭 760pt. 화면 영역을 넘지 않게 조정한다.
- 그래프는 기존 500ms 자동 저장, Markdown은 명시적 저장과 전환·종료 저장. 외부 충돌을 덮어쓰지 않는다.
- 단독 bilog 앱의 실행 타깃과 기존 테스트를 보존한다. 원본 `~/Work/logseq` 체크아웃을 수정하지 않는다.
- 기존 미커밋 작업을 보존한다. 전체 파일 일괄 스테이징/초기화하지 않는다. 구현 시 using-git-worktrees 지침에 따라 현재 작업 내용이 누락되지 않는 실행 위치를 정한다.
- 문서 승인 시점에는 구현·서브모듈 추가·원격 게시를 실행하지 않는다.

## Review Focus

1. 한글 조합 도중 탭/집중/창 전환: 조합 확정 실패 시 화면과 입력 유지 (작업 2, 4, 5).
2. 외부 편집 또는 저장 실패: 전환/종료 취소, 사본 저장 실패 후에도 원본 편집 유지 (작업 2, 4, 5).
3. 재실행 후 폴더 접근 불가 또는 stale bookmark: 기존 노트를 변경하지 않고 재선택 가능 (작업 2).
4. 복수 창/숨겨진 편집기: 오래된 텍스트 버퍼나 비활성 메뉴가 현재 문서에 적용되지 않음 (작업 3–5).
5. 다른 Mac의 새 체크아웃: 원본 로컬 폴더 없이 고정된 서브모듈로 빌드 가능 (작업 1, 6).

## File and Test Boundaries

- `Packages/NativeLogseq`: 편집기 공통 API와 기존 코어/UI 테스트. 변경은 서브모듈의 `codex/logseq-embedding` 브랜치에서 커밋한다.
- `TodayRoutine/Features/Logseq/`: Mac 호스트, 탭 뷰, 창 크기 관리, 종료 조정. 모든 소스에 macOS 컴파일 가드를 둔다.
- `TodayRoutine/App/`: 공유 호스트 수명, 집중/탭 전환, 앱 delegate와 Commands 연결.
- `TodayRoutineMacTests/LogseqHostTests.swift`: 호스트의 비동기 전환·종료 단위 테스트. 프로젝트 생성기에 Mac hosted unit-test 타깃을 추가하고 Mac scheme에 포함한다. 앱 타깃을 `@testable import TodayRoutineMac`한다.
- `TodayRoutineMacUITests/LogseqWorkflowTests.swift`: 실제 탭/메뉴/창과 격리 파일 기반 테스트. 기존 피드 UI 테스트도 회귀 실행한다.

## Task 1: 서브모듈과 라이브러리 빌드

**Files:** `.gitmodules`, `Packages/NativeLogseq/Package.swift`, `scripts/generate-project.py`, `scripts/build_mac_local.py`, 생성 Xcode 프로젝트/스킴.
**Interfaces:** Mac 앱이 `import NativeLogseqUI` 가능. 기존 `NativeLogseq` 실행 제품 유지.

- [ ] 원격 시작 커밋 존재와 양쪽 작업 상태를 재확인한다. `git submodule add git@github.com:Hyunho/bilog.git Packages/NativeLogseq` 후 시작 커밋에서 `codex/logseq-embedding` 브랜치를 만든다. 동일 경로/브랜치가 이미 존재하면 먼저 내용과 진행 상태를 확인한다.
- [ ] 패키지 제품에 `.library(name: "NativeLogseqCore", targets: ["NativeLogseqCore"])`, `.library(name: "NativeLogseqUI", targets: ["NativeLogseqUI"])`를 추가한다.
- [ ] 프로젝트 생성기에 `XCLocalSwiftPackageReference`, Mac 전용 product dependency/framework link와 Mac unit-test 타깃을 추가한다. iOS와 RoutineCore는 의존하지 않는다. 생성기/로컬 빌드 진입점에서 패키지 누락 시 `git submodule update --init --recursive`를 안내하고 실패한다.
- [ ] `python3 scripts/generate-project.py`와 아래 패키지 테스트/빌드를 실행한다. 라이브러리뿐 아니라 단독 실행 앱도 빌드되어야 한다. 단순 프로젝트 선언에 별도 형식 미러링 테스트는 만들지 않는다.
- [ ] 서브모듈의 라이브러리 변경과 상위 빌드 연결 변경을 각각 선택적으로 커밋한다. 상위 gitlink가 로컬 전용 커밋일 경우 원격 재현 완료로 보고하지 않는다.

## Task 2: 파일 접근과 내장 편집기 API

**Files (bilog):** `Sources/NativeLogseqUI/{AppState,EditorSession,WorkspaceCommands,WorkspaceView,GraphPickerView}.swift`, 새 `WorkspaceAccess.swift`; 대응 `Tests/NativeLogseqUITests/WorkspaceAccessTests.swift`, 기존 AppState/EditorSession 테스트.
**Interfaces:** `AppState.restoreWorkspace() async throws`, 기존 `flush() async throws`; `EditorSession.prepareToLeave() async throws`; `WorkspaceCommands.init(state:session:isActive:)`의 `isActive` 기본값 true. `WorkspaceView`의 기존 단독 앱 생성자는 유지한다.

- [ ] 테스트를 먼저 추가한다: `testRecentWorkspaceUsesInjectedPreferences`는 별도 suite에만 최근 경로 저장; `testRestoreFailurePreservesCurrentDocument`는 접근 실패 후 현재 문서 유지; `testPrepareToLeaveSavesMarkdown`은 미저장 문자열이 파일에 기록됨을 확인한다. 한글 조합 실패·외부 변경 시 throw와 내용 보존도 검증한다.
- [ ] bookmark 처리는 `WorkspaceAccess`에서 묶고, 권한 시작/해제와 bookmark 해석을 주입 가능한 작은 어댑터로 둔다. 테스트에서 stale bookmark 갱신, 권한 거절, 새 문서 열기 실패 시 이전 접근 유지, 교체 성공 시 이전 접근 해제를 검증한다.
- [ ] 패키지 테스트를 실행해 신규 테스트가 기대한 미구현 API/동작 때문에 실패하는지 확인한다.
- [ ] 경로 저장의 `UserDefaults.standard` 직접 접근을 주입된 preferences로 교체한다. 단독 앱은 기본 `.standard`로 기존 경로 복원 호환성을 유지한다. 호스트는 `com.hyunho.TodayRoutineMac.logseq` suite를 쓴다. 테스트 suite는 UUID로 분리한다.
- [ ] `prepareToLeave()`는 작업 중이면 오류, 조합 확정 실패면 오류, 그 외 `flush()` 완료 후 반환한다. 실패를 삼키지 않는다. 파일 선택·생성·복원 모두 같은 접근 수명 관리를 사용한다. 사본 내보내기도 선택 URL 접근 수명을 보장한다.
- [ ] Commands는 비활성일 때 Logseq 명령 항목과 대체 CommandGroup을 제공하지 않아 기본 Undo/Redo를 보존한다. WorkspaceView는 내장 호스트가 레이아웃 최소 폭을 제어할 수 있게 옵션을 추가하되 기본값은 기존 760pt로 유지한다.
- [ ] 기존 및 신규 패키지 테스트, 단독 앱 빌드를 통과시킨 뒤 서브모듈 변경을 커밋한다.

## Task 3: 세션 호스트와 Logseq 탭

**Files:** 새 `TodayRoutine/Features/Logseq/{LogseqHost,LogseqTabView}.swift`, `TodayRoutine/App/{TodayRoutineApp,RootView}.swift`, 새 `TodayRoutineMacTests/LogseqHostTests.swift`, 새 `TodayRoutineMacUITests/LogseqWorkflowTests.swift`.
**Interfaces:** `@MainActor final class LogseqHost: ObservableObject`는 `state: AppState`, `session: EditorSession`, `restoreOnce() async`, `prepareToLeave() async -> Bool`, 읽기 전용 `isTransitioning: Bool`, `pageStack: [String]` 제공. 저장 실패는 `state.errorMessage`에 표시하고 false 반환.

- [ ] `testRestoreOnceDoesNotResetEdits`, `testDuplicateTransitionDoesNotFlushTwice`를 작성한다. 호스트 테스트에서는 저장 작업을 주입해 중간 대기/실패를 제어한다. 초기에는 미구현으로 실패해야 한다.
- [ ] AppModel 수명에 공유 LogseqHost 하나를 둔다. 첫 탭 진입에만 복원하고 집중 화면과 다른 탭에서도 호스트는 유지한다. 열린 문서와 편집 세션을 새로 만들지 않는다.
- [ ] 루트의 Mac TabView와 하단 버튼, 전체 바로 가기, 페이지 경로 표시에 Logseq를 추가한다. 단독 앱 환경설정을 자동으로 가져오지 않는다. 그래프/파일 선택 시작 화면을 재사용한다.
- [ ] 복수 창에서 하나의 편집 세션에 동시에 연결된 텍스트 뷰를 만들지 않는다. 키 창을 편집 호스트로 삼고, 키 창 변경 전 기존 호스트의 조합/저장을 완료한 뒤 편집 화면을 넘긴다. 실패하면 기존 창을 활성화한다. 다른 창에는 현재 편집 창으로 이동하는 버튼을 표시한다. 단축키는 활성 편집 창에만 연결한다.
- [ ] Debug 전용 `--uitest-logseq <temporary-path>`로 격리 문서를 연결한다. 기존 `--uitest-store` UUID를 preferences 격리에도 사용한다. UI 테스트에서 탭 존재, 문서 열기, 경로 표시, 왕복 시 내용 유지, 두 창 사이 전환을 검증한다.
- [ ] 신규 Mac 단위/UI 테스트를 통과시키고 상위 변경만 선택적으로 커밋한다.

## Task 4: 저장을 거치는 화면 전환과 창 크기

**Files:** 새 `TodayRoutine/App/LogseqNavigation.swift`, 새 `TodayRoutine/Features/Logseq/LogseqWindowSizing.swift`, 기존 `RootView.swift`, `TodayRoutineApp.swift`, `Features/Today/{TodayView,FocusSessionView}.swift`, `Features/Routines/CalendarRoutineSections.swift`; 작업 3의 테스트 파일.
**Interfaces:** AppModel의 `selectTab(_ name: String) async -> Bool`, `setFocusSession(_ next: FocusSession?) async -> Bool`. 기존 공개 selectedTab은 표시/바인딩 읽기에 유지하되 실제 전환 쓰기는 두 메서드 안에 집중한다. `LogseqWindowSizing`은 창별 일반/Logseq 프레임을 보관한다.

- [ ] `testFailedSaveKeepsSelectedTab`, `testFocusEntryWaitsForSave`, `testRepeatedSelectionWhileSavingIsIgnored`를 먼저 작성하고 실패를 확인한다. 저장 성공 전에 선택 탭이나 focusSession이 바뀌지 않는지 검사한다.
- [ ] 직접 `selectedTab`/`focusSession` 변경과 TabView 바인딩 setter를 전환 메서드로 연결한다. 피드의 오늘 루틴 이동도 저장 성공 후에만 route를 설정한다. 실패 시 기존 선택·route·집중 상태를 보존한다. iOS는 동일 메서드에서 기존 즉시 전환 동작을 한다.
- [ ] Logseq를 떠날 때 `prepareToLeave()` 성공 후 텍스트 포커스를 정리하고 화면을 바꾼다. 이미 전환/문서 작업 중이면 중복 요청을 거절한다. 돌아올 때 문서 선택/커서 상태를 복원한다.
- [ ] 창 크기를 활성 콘텐츠 기준으로 계산한다. Logseq 최소 760pt/기본 1120pt, 일반 최소 360pt/최대 480pt. 사용 가능한 화면 폭이 760pt 미만이면 화면 폭을 우선하고 사이드바를 접는다. 집중 창은 기존 크기와 FocusWindowLevel을 유지한다. 일반/Logseq 마지막 프레임을 별도로 저장하고 비활성 탭의 frame 제약 전파를 막는다.
- [ ] UI 테스트에서 일반 → Logseq → 일반 → Logseq 폭 복원, 집중 모드 왕복, 외부 변경 시 전환 차단을 검증한다. 한글 조합 상태 전환은 실제 입력기로 수동 검증한다.
- [ ] 단위/UI 회귀 테스트 통과 후 커밋한다.

## Task 5: 메뉴·창 닫기·앱 종료

**Files:** 새 `TodayRoutine/Features/Logseq/LogseqCloseCoordinator.swift`, 새 `TodayRoutine/App/TodayRoutineMacDelegate.swift`, 기존 `TodayRoutineApp.swift`; 기존 Mac 단위/UI 테스트.
**Interfaces:** `LogseqCloseCoordinator.prepareToClose() async -> Bool`는 prepareToLeave와 실패 선택 흐름을 담당. delegate는 앱 종료와 창 닫기 콜백을 이 조정기에 연결한다. 테스트용으로 재시도/사본 URL/확인 응답을 주입한다.

- [ ] `testQuitFromOtherTabFlushesDirtyDocument`, `testCancelQuitRetainsEdits`, `testFailedCopyDoesNotClose`, `testDuplicateCloseGetsSingleDecision`를 추가해 실패를 확인한다. 사본 저장 실패 후 종료 성공을 반환하지 않는지 확인한다.
- [ ] 앱 종료는 terminateLater 후 비동기 저장 결과로 reply한다. 기존 편집 작업 중에는 종료를 취소한다. 저장 실패에는 재시도 / 사본 저장 후 종료 / 종료 취소를 제공하고 원본의 사본 확인 절차를 유지한다.
- [ ] 창 닫기는 저장 성공 뒤 해당 창만 닫는다. 저장 대기 중 재귀적인 close를 막는 플래그를 둔다. SwiftUI의 창 delegate를 무조건 덮어쓰지 말고 필요한 메시지만 처리하며 기존 delegate 동작을 보존한다.
- [ ] 앱 Commands에 활성 키 창의 Logseq 상태를 연결한다. 다른 탭의 Cmd+Z/Cmd+F가 Logseq 내용을 수정하지 않는지, Logseq의 Cmd+S/Cmd+O/원문/확대가 동작하는지 UI 확인한다.
- [ ] 테스트를 통과시키고 정상 종료/실패/다른 탭 종료/복수 창 닫기를 수동 확인한 뒤 커밋한다.

## Task 6: 전체 검증과 재현 가능한 전달

**Files:** README.md, `docs/verification-2026-10-10-logseq-tab.md`, 필요한 빌드/스킴 수정과 최종 gitlink.
**Interfaces:** 원본 로컬 폴더 없이 빌드 가능한 상위 저장소와 원격에서 가져올 수 있는 bilog 커밋.

- [ ] 패키지 전체 테스트, RoutineCore 테스트, Mac 단위/UI 테스트와 기존 피드 툴바 회귀를 실행한다. 실패가 나면 원인과 영향 범위를 기록하고 관련 변경을 수정한 뒤 필요한 테스트만 재실행한다.
- [ ] iOS 시뮬레이터 build와 bilog 단독 앱 build를 실행한다. Mac 연결이 기존 플랫폼 또는 단독 앱을 깨뜨리지 않아야 한다.
- [ ] 샌드박스 환경의 재실행 bookmark 복원, 접근 거절/재선택, 실제 한글 입력, 저장 실패 시 복구 UI를 검증한다. 검증할 수 없는 항목은 성공으로 간주하지 말고 검증 기록에 남긴다.
- [ ] bilog 변경을 원격 작업 브랜치에 게시한 뒤 새 임시 체크아웃에서 해당 커밋 접근과 서브모듈 초기화를 확인한다. 새 체크아웃의 Mac build가 `~/Work/logseq` 없이 성공해야 한다. 상위 저장소의 기존 미커밋 구현이 많으므로 검증용 스냅샷에 이를 빠뜨리지 않되 사용자 변경을 임의로 커밋하지 않는다.
- [ ] `python3 scripts/build_mac_local.py --derived-data /private/tmp/today-routine-logseq-signed`로 개발 서명 앱을 빌드하고 codesign 검증을 확인한다. 기존 앱에 미저장 작업이 있으면 정상 종료로 보존하며 강제 종료하지 않는다. 설치/실행 검증은 기존 `~/Applications/TodayRoutineMac.app` 경로를 사용한다.
- [ ] README에 초기화/갱신/복구 명령과 기능 범위를 기록하고 테스트 결과를 검증 문서에 남긴다. 상위 gitlink를 검증한 원격 커밋으로 고정한다. 구현 방법에 맞는 코드 리뷰를 완료하고 결과를 반영한 뒤 완료를 보고한다.

## Verification Commands

출력은 각각 exit 0 및 테스트 실패 0건이어야 한다. 신규 테스트는 해당 `--filter` 또는 `-only-testing:`으로 먼저 red/green을 확인하고, 마지막에 아래 전체 범위를 실행한다.

```sh
swift test --package-path Packages/NativeLogseq --scratch-path /private/tmp/today-logseq-package
swift build --package-path Packages/NativeLogseq --scratch-path /private/tmp/today-logseq-package --product NativeLogseq
swift test --build-system native --scratch-path /private/tmp/today-routine-tests
xcodebuild -project TodayRoutine.xcodeproj -scheme TodayRoutineMac -destination 'platform=macOS' -derivedDataPath /private/tmp/today-logseq-mac test CODE_SIGNING_ALLOWED=NO
xcodebuild -project TodayRoutine.xcodeproj -scheme TodayRoutine -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/today-logseq-ios build CODE_SIGNING_ALLOWED=NO
```

Mac UI tests가 실행 권한/서명 문제로 시작하지 못하면 서명된 테스트 설정에서 다시 실행하고, 단순 빌드 성공을 UI 테스트 통과로 보고하지 않는다. 실제 실행용 앱에는 기존 개발 서명을 사용한다.

## Plan Review

- 설계의 서브모듈/재현성: 작업 1, 6; 편집 재사용/권한: 작업 2; 탭/세션/경로: 작업 3; 전환/창/집중: 작업 4; 단축키/종료: 작업 5; 전달: 작업 6.
- 공통 저장 경계는 `prepareToLeave()` 하나이며 작업 4와 5가 재사용한다. 사용자 노트와 기본 preferences는 테스트 대상에서 제외한다.
- 여러 창에서 같은 EditorSession의 activeTextView가 충돌하지 않도록 편집 뷰 소유 창을 하나로 제한한다. 화면이 작은 경우 최소 폭보다 실제 화면 영역을 우선한다.
- 실행 방식은 사용자 승인에 따라 동일 세션에서 직접 구현했다. 완료 범위와 남은 검증은 Execution Status와 검증 기록을 따른다.
