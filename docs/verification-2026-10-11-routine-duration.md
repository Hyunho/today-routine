# 루틴 소요시간 설정 검증 — 2026-10-11

- 루틴 편집의 `소요시간 지정`을 켜고 1~1,440분을 직접 입력한다. 끄면 미정으로 저장한다.
- 신규·기존 루틴의 기본값은 nil(미정)이다. 기존 시작시간과 완료 기록은 변경하지 않는다.
- 설정한 소요시간은 로컬 저장, 편집 재열기, 동기화의 설정·해제에 반영된다. 소요시간 필드가 없는 이전 동기화 데이터는 현재 값을 지우지 않는다.
- 오늘 목록은 설정된 종료시간과 시간에 따른 높이를 사용한다. 미정은 최소 높이이며 종료시간을 만들지 않는다. 자정을 넘는 시간은 당일 목록에서 24:00까지 표시하고 원래 소요시간 값은 보존한다.
- 캘린더 연결 루틴은 캘린더 이벤트의 시간을 사용한다.
- 전체 핵심 테스트 178개 통과: `/private/tmp/routine-duration-setting-tests.log`.
- Mac 빌드 성공: `/private/tmp/routine-duration-setting-build.log`.
- iOS Simulator 빌드 성공: `/private/tmp/routine-duration-setting-ios-build.log`.
- 읽기 전용 별도 코드 검토에서 수정이 필요한 문제 없음.
- UI 테스트(`testRoutineDurationCanBeSavedReopenedAndCleared`)는 컴파일됐지만 실행 단계에서 진행되지 않아 중단했다. 무서명과 로컬 임시 서명 모두 동일했으며 실제 UI 동작은 미검증이다. 로그: `/private/tmp/routine-duration-setting-ui.log`, `/private/tmp/routine-duration-setting-ui-signed.log`.
- 배포 및 설치 앱 교체는 수행하지 않았다. 다른 기기에서 새 소요시간 필드를 동기화하려면 업데이트가 필요하다.
