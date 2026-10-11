# 미리 알림 전용 일감 전환 검증 · 2026-10-09

## 변경 결과

- 일감 화면은 Apple 미리 알림만 표시하고 상단 추가 버튼도 미리 알림 편집기를 연다.
- 내부 TaskEditor를 제거하고 오늘의 집계·시간 배치·집중·타임블록 연결 선택에서 내부 일감을 제외했다.
- 앱 실행 시 완료 여부와 관계없이 기존 내부 일감을 삭제한다. 타임블록은 제목과 시간을 유지하고 task 연결만 해제한다.
- 로컬 레코드 삭제, 블록 연결 해제, 동기화 삭제 이벤트 기록을 같은 저장 트랜잭션에서 처리한다. 실패 시 전부 롤백한다.
- 저널에만 남은 task와 task 연결 블록도 처리한다. 블록은 저널에만 있더라도 삭제하지 않고 연결 필드만 비운다.
- 원격 수신과 로컬 이벤트 적용 경로에서 구버전 일감을 정리한다. 동일 이벤트를 재수신해도 삭제한 일감이 복원되거나 이벤트가 계속 늘지 않는다.
- 과거 파일을 읽기 위한 TaskItem 타입은 유지한다. 보관·이전 UI와 EventKit으로의 자동 복사는 없다.

## 검증

기준선 공유 모델 테스트 132개가 통과했다. 최종 전체 공유 모델 테스트는 140개, 실패 0개다.

```sh
swift test --build-system native --scratch-path /private/tmp/today-routine-tests
```

새 LegacyTaskCleanupTests 8개는 일반 삭제, 블록 보존, 저널에만 있는 데이터, 저장 실패 롤백과 재시도, 재실행 후 오프라인 삭제 전송 대기열, 기기 간 삭제 전달, 구버전 재전송과 새 UUID, 중복 수신, 최초 연결/appendLocal을 검증한다. 구현 전 API 부재 및 수신 테스트의 16개 실패 단언을 확인한 뒤 통과시켰다.

macOS 빌드 성공:

```sh
xcodebuild -project TodayRoutine.xcodeproj -scheme TodayRoutineMac \
  -destination 'platform=macOS' -derivedDataPath /private/tmp/today-routine-mac-build \
  build CODE_SIGNING_ALLOWED=NO
```

이 빌드 산출물은 실행용 앱으로 설치하지 않았다.

iOS 시뮬레이터 테스트 빌드 성공. 관련 UI 테스트 10개는 최초 묶음 실행과 실패 항목 재검증을 합쳐 모두 통과했다.

- AppleRemindersWorkflowTests 7개: 상단 추가, 미연결/읽기 전용 안내, 권한 상실, 기존 일감 삭제/블록 보존, 작성 검증, 접근 거부, 편집/완료/재실행.
- WorkflowTests 3개: 스크롤 스택 복원 및 완료, 큰 글자 루틴/미리 알림, 루틴 집중 종료/완료.
- 10개 묶음에서 8개 통과 후, 화면 조작 전에 상단으로 이동하도록 테스트를 보완해 남은 2개를 각각 재검증했다. 최종 미리 알림 완료 테스트는 `TEST SUCCEEDED`로 종료했다.
- 원본 로그: `/private/tmp/today-routine-core-final.log`, `/private/tmp/today-routine-ui-final.log`, `/private/tmp/today-routine-ui-recheck.log`, `/private/tmp/today-routine-ui-completion.log`, `/private/tmp/today-routine-mac-build.log`, `/private/tmp/today-routine-mac-ui.log`.

```sh
xcodebuild -project TodayRoutine.xcodeproj -scheme TodayRoutine \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  -derivedDataPath /private/tmp/today-routine-ios-build \
  test CODE_SIGNING_ALLOWED=NO -collect-test-diagnostics never \
  -only-testing:TodayRoutineUITests/AppleRemindersWorkflowTests \
  -only-testing:TodayRoutineUITests/WorkflowTests/testPendingStackScrollReturnAndComplete \
  -only-testing:TodayRoutineUITests/WorkflowTests/testTodayWithoutStepsHasNoExpansion \
  -only-testing:TodayRoutineUITests/WorkflowTests/testStepsAndPlanningWithLargeText
```

테스트는 UUID별 저장소와 가짜 미리 알림 원본을 사용했다. 기존 화면은 시간표와 목록 모두 현재 시각으로 자동 스크롤한다. 테스트에서 목록 보기를 지정하고 상단 항목 조작 전 화면 위로 이동하도록 보완했다. 제품의 자동 스크롤 동작은 변경하지 않았다.

## 제한

- Mac UI 테스트 `TodayRoutineMacUITests/SyncWorkflowTests`는 자동화 모드 초기화 시간 초과로 테스트 본문을 실행하지 못했다. Mac 빌드 성공과 별도로 미검증이다.
- 실제 Apple 계정 간 동기화, 실기기 권한 및 실제 디스크 공간 부족은 검증하지 않았다. 동기화 로직은 독립 저장소로, 저장 실패는 실패 주입으로 검증했다.
- 사용자 실행 앱 설치·교체와 실제 사용자 데이터 삭제는 수행하지 않았다. 업데이트 앱 실행 시 삭제가 적용된다.
- 기존 동기화 이력과 외부 백업은 유지된다. 이전 이벤트의 task는 활성 상태로 복원하지 않는다.

## 검토 및 작업 범위

별도 검토자가 이번 변경만 검토했으며 수정이 필요한 production 코드 문제는 발견하지 않았다. 기존 미커밋 작업이 다수 있어 기존 파일을 통째로 커밋하지 않고 작업 디렉터리에 변경을 남겼다. Git diff 공백 검사를 통과했다.
