# Apple 미리 알림 연동 검증

버전: 1.0 (빌드 2). iOS 17 / macOS 14 이상, EventKit 직접 접근.

## 통과

- `swift test --build-system native --scratch-path /private/tmp/today-routine-tests`: 전체 81개 테스트 통과.
- 미리 알림 단위 테스트 7개: 종일/시간대 날짜 변환, 선택 목록 한정 조회, 연결 해제 시 원본 보존, 권한 취소 시 표시 제거, 완료 실패 시 상태 보존, 진행 중 조회 후 연결 해제, 선택 재실행/오늘 마감 필터, 원본 시간대·반복·알림·우선순위 보존을 검증.
- 아이폰 18 Pro 시뮬레이터 `AppleRemindersWorkflowTests`: 3개 통과. 목록 선택·원본 편집·오늘 완료·재실행·연결 해제, 추가·빈 제목 재저장·읽기 전용, 권한 거부 안내.
- iOS 및 macOS Debug 빌드 성공.
- 두 앱의 생성된 Info.plist에서 `NSRemindersFullAccessUsageDescription`, 버전 1.0/빌드 2 확인.
- 버전 관리 스크립트 테스트 3개 통과. `git diff --check` 통과.

## 구현 검토

EventKit 원본을 저장 직전에 refresh하고 조회 당시 항목과 비교한다. 외부 수정·삭제·목록 권한 변경은 저장을 중단하며 편집 내용을 남긴다. 제목·메모·마감일 이외의 속성은 덮어쓰지 않는다. 선택한 목록 ID만 기기별 UserDefaults에 저장하며, 기존 SwiftData/파일 동기화에는 원본 복사본을 만들지 않는다.

## 검증 범위

화면 테스트는 실제 개인 데이터에 접근하지 않는 격리된 테스트 소스를 사용했다. EventKit 필드 보존 테스트는 메모리상의 EKReminder로 실행했다. 실제 계정의 TCC 권한 요청, 외부 앱과의 수정 충돌, iCloud 기기 간 전달, 반복 완료 시 다음 항목 생성은 실기기에서 추가 확인해야 한다. 이번 실행은 미리 알림 UI 테스트만 대상으로 했으며 전체 기존 UI 테스트를 재실행하지 않았다. 맥은 빌드 검증만 수행했다.

최종 UI 결과: `/private/tmp/today-layout-build/Logs/Test/Test-TodayRoutine-2026.10.06_08-38-19-+0900.xcresult`.
