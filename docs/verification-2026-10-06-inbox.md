# 수신함 구현 및 검증 — 2026-10-06

## 구현

- 아이폰·맥의 다섯 번째 수신함 탭. 전체 / 루틴 알림 / 구독 글과 나중에 읽기 필터.
- HTTPS RSS·Atom 구독 등록·삭제, 최초 한 번 통합 브리핑 등록, 수동 및 진입 시 갱신.
- 피드 본문의 텍스트 표시, 원문 브라우저 열기, 읽음·저장 상태, 필터별 목록 위치 복원.
- 기존 루틴 알림 계획에서 예정 시각이 지난 기록을 수신함에 보관. 실제 OS 전달 여부는 주장하지 않음.
- 독립 로컬 JSON 원자적 저장. 구독 삭제 시 저장 글 유지, 쓰기 실패 시 이전 상태 유지, 손상 파일 원본 보존.
- Mac sandbox에 RSS 요청용 outbound network.client entitlement 추가.

## 확인한 결과

- 기존 핵심 테스트 기준선: **51개 통과**.
- 전체 핵심 테스트 최종: **74개 통과**, 실패 0개.
  - `swift test --build-system native --scratch-path /private/tmp/today-routine-tests`
  - 저장소·RSS/Atom·크기 제한·HTTPS 리다이렉트·취소·구독 삭제 중 응답·읽기 상태·루틴 알림 경계 검증.
- 아이폰 수신함 전용 최종 UI: 읽기/저장/재실행, 구독 추가/삭제/루틴 알림 상세, 위치 복원/손상 저장소 격리, 큰 글자 화면 **4개 통과** (`/private/tmp/inbox-ui-verified.xcresult`).
- Mac 앱: `xcodebuild ... -scheme TodayRoutineMac -destination 'platform=macOS' ... build` **BUILD SUCCEEDED**.
- 실제 FeedClient와 FeedParser로 지정된 통합 브리핑 피드 요청: **13개 글 / 본문 13개**. 테스트 fixture는 별도 가상 데이터이며 실제 글 본문을 저장소에 커밋하지 않음.
- `git diff --check` 통과.

## 전체 UI 검사에서 남은 제약

아이폰 전체 기존 UI 테스트 10개 중 8개 통과, 2개 실패:

1. `WorkflowTests.testCreateCompleteAndRelaunch`: 오늘 화면에서 `아침 독서 완료` 버튼을 찾지 못함.
2. `WorkflowTests.testStepsAndPlanningWithLargeText`: 오늘 화면에서 `매일 아침 마음을 가다듬는 긴 이름의 루틴 단계 보기` 버튼을 찾지 못함.

현재 작업 이전부터 수정되어 있던 TodayView는 이번 수신함 작업에서 변경하지 않았다. 해당 테스트는 기존 오늘 화면 구조와 맞지 않는 버튼을 찾다가 실패하며 수신함 테스트 3개와 동기화 테스트 2개는 같은 실행에서 모두 통과했다. 따라서 전체 UI 테스트가 통과했다고 주장하지 않는다.

Mac UI 테스트는 `Timed out while enabling automation mode`로 러너 초기화에 실패하여 실제 UI 검증을 수행하지 못했다. Mac 빌드 통과와 UI 검증은 구분한다.

실패 시 Xcode 진단 수집이 오래 멈추는 현상이 있어 결과가 모두 출력된 작업 소유 프로세스만 종료했다. 최종 수신함 전용 실행은 `-collect-test-diagnostics never`와 독립 resultBundlePath를 사용한다.

## 구현 판단과 전달 상태

- 승인된 계획의 기존 작업 보존 방침에 따라 현재 feature/today-routine-ios에서 작업했다. 작업 시작 시 RootView/AppModel/프로젝트 파일을 임시 백업해 이후 수신함 추가분을 비교했다.
- 기존 루틴 저장소·CSV/iCloud Drive 형식은 변경하지 않았다. 수신함은 같은 기기에서만 복원된다.
- 글 본문은 텍스트만 표시한다. 이미지/영상 및 원문 전체 추출, 피드 자동 발견은 첫 버전 범위 밖이다.
- 새 코어 파일은 커밋했으며, 기존 사용자 변경이 섞인 화면 통합 파일은 기존 변경을 함께 커밋하지 않기 위해 작업 트리에 유지한다.
- 직접 작업 요청에 따라 구현과 최종 코드 검토는 이 세션에서 수행했다. 별도 에이전트 리뷰는 수행하지 않았다.

## 화면 확인

[큰 글자 수신함](screenshots/inbox-large-text.png), [글 상세](screenshots/inbox-reading.png)를 확인했다. 실행 인자만으로는 다크 모드가 적용되지 않아 시뮬레이터 appearance 설정으로 재검증했다. 해당 UI 테스트도 통과했으며 [다크 모드 화면](screenshots/inbox-dark.png)을 직접 확인했다. 시뮬레이터는 밝은 모드로 복원했다.
