# 캘린더 루틴 및 주간 목표 정리 — 2026-10-08

## 반영한 동작

- 새 루틴의 반복 방식은 매일 / 요일 선택이다. 기존 `weeklyGoal` 데이터는 읽기·동기화 호환성을 유지하며 자동 삭제하거나 변환하지 않는다.
- 사용자가 명시한 PTTP 한 개만 실행 중이던 Mac 앱의 실제 저장소에서 삭제했다. 해당 루틴에는 하위 단계, 날짜 기록, 알림 설정, 연결 시간 블록이 없었다. 앱의 저장 트랜잭션으로 삭제 이벤트를 생성했으며 동기화 폴더 발행 상태를 확인했다. 다른 기기가 이를 수신했는지는 확인하지 않았다.
- 루틴 탭은 캘린더 반복 일정을 한글 주간 / 월간 / 연간으로 분류한다. 매일은 주간, 2주마다는 월간, 3개월마다는 연간에 해당한다. 각 항목에는 실제 반복 표현과 다음 날짜를 표시한다.
- 설정에서 표시할 빈도를 각각 선택할 수 있다. 기본값은 세 분류 모두 표시이며 선택은 기기별로 저장된다.
- 기존 루틴 편집 화면에서 캘린더 루틴으로 전환할 수 있다. 캘린더·시작일·소요 시간(시간 지정 루틴만)을 선택하고 생성 확인 버튼을 눌러야 Apple 캘린더에 새 반복 일정이 저장된다. 시간 미정 루틴은 하루 종일 일정이다.
- 제목·시간·반복은 캘린더가 관리한다. 기존 Routine UUID, 하위 단계, 완료 기록은 앱에 보존한다. 오늘 화면에서 연결된 캘린더 일정과 앱 루틴을 중복 표시하지 않으며 하위 단계와 완료 상태는 앱 기록을 사용한다.
- 캘린더 일정 삭제·권한 거부·식별자 불일치가 앱 기록을 삭제하지 않는다. 루틴 탭에 연결 상태를 표시한다.
- 링크는 로컬 항목 ID, 외부 ID, 캘린더/계정 정보와 앱 UUID URL 표식을 사용한다. 후보가 중복되면 자동으로 연결하지 않는다. 새 일정 생성 후 앱 저장이 실패하면 생성 영수증을 유지해 재시도 때 중복 생성을 줄인다.

## 검증

- `swift test`: 121 tests, 0 failures.
- Mac: `python3 scripts/build_mac_local.py --derived-data /private/tmp/today-calendar-routines` 성공. 기존 Apple Development 서명으로 캘린더 권한의 코드 서명 조건을 유지했다.
- iPhone 시뮬레이터: `xcodebuild ... -destination 'generic/platform=iOS Simulator' ... CODE_SIGNING_ALLOWED=NO` 성공.
- 이후 사용자 설치 요청으로 실제 iPhone 17에 Release 서명 빌드 1.0 (47)을 업데이트 설치했다. `devicectl device install app` 성공, `device process launch` 성공, 설치된 `com.hyunho.TodayRoutine` 등록을 재확인했다. 기존 앱을 제거하지 않았다. 실기기 빌드 경로는 `/private/tmp/today-calendar-iphone/Build/Products/Release-iphoneos/TodayRoutine.app`이다.
- 최종 실행 앱: `/private/tmp/today-calendar-routines/Build/Products/Debug/TodayRoutineMac.app`.
- 실제 저장소: `/Users/hyunho/Library/Application Support/default.store`. 재실행 후 새 링크 컬럼 존재, PTTP 0개, 나머지 루틴 16개 / 하위 단계 31개 / 날짜 기록 63개, SQLite quick_check `ok` 확인.
- 테스트 범위: 종일 일정 종료 날짜, 요일 선택의 첫 실행일, 기존 단계/완료 기록 보존, 링크 동기화, 저장 실패 롤백, 재실행 후 생성 영수증 복구, 중복 식별자 거부, 복합 반복 규칙의 분류, 선택 설정 유지, 특정 루틴 삭제 후 동기화 재생 시 다른 데이터 보존.
- 실제 개인 캘린더에 시험 일정을 만들지 않았다. EventKit 쓰기 경로는 컴파일 검증했으며 사용자 확인을 통한 실제 생성·동기화는 미검증이다. GUI 클릭을 통한 전체 전환 동작도 미검증이다.

## 호환성과 제한

- 연결 정보는 새 동기화 필드 `calendarLink`를 사용한다. 연결을 공유할 모든 기기에 새 앱 버전이 필요하다. 구버전은 새 필드를 거부할 수 있어 전환 화면에 업데이트 안내를 표시한다.
- 캘린더 일정 알림은 기존 앱 알림에서 자동 이전하지 않는다. 전환 화면에 Apple 캘린더에서 설정하도록 안내한다.
- 앞으로 12개월 안에 나타나는 반복 시리즈를 표시한다. 복합 규칙의 빈도 판별에는 최대 2년의 발생일을 읽고, 한 반복 주기를 관찰할 수 있을 때 최대 날짜 간격을 사용한다. 이동한 반복 일정은 가능한 경우 원래 발생일을 기준으로 한다. 일수 간격의 경계는 주간 7일, 월간 31일, 연간 366일이며, 연 1회보다 드문 규칙은 세 분류에서 제외한다.
- 완료 기록은 기존 앱과 같이 루틴별 하루 단위다.

## 로컬 백업

Git에서 제외한 `exports/private-backups/`에 다음 파일을 보관했다.

- `2026-10-08-before-PTTP-deletion.store`
- `2026-10-08-before-calendar-routines.store`

삭제 이벤트는 이미 동기화 폴더에 발행되었다. PTTP 복원이 필요하면 백업의 항목을 새 UUID로 복원해야 하며, 현재 저장소 전체를 오래된 백업으로 덮어쓰면 안 된다.

Apple API 참고: [반복 일정 생성](https://developer.apple.com/documentation/eventkit/creating-a-recurring-event), [일정 저장과 사용자 확인](https://developer.apple.com/documentation/eventkit/creating-events-and-reminders).
