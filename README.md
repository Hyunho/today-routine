# 오늘의 루틴 · iPhone

SwiftUI와 SwiftData로 만든 개인 루틴 앱입니다. 데이터는 기기에 저장하며 서버·계정·사이트 동기화 없이 사용할 수 있습니다.

## 실행

1. `TodayRoutine.xcodeproj`를 Xcode에서 엽니다.
2. `TodayRoutine` 스킴과 iPhone 시뮬레이터를 선택합니다.
3. Run을 실행합니다. 최소 지원 버전은 iOS 17입니다.

실기기 설치 시 Xcode의 Signing & Capabilities에서 본인의 개발 팀과 사용 가능한 Bundle Identifier를 선택해야 합니다. 현재 프로젝트에는 개발 팀이나 인증서가 포함되어 있지 않습니다.

## 기능

- 오늘의 루틴과 예정 일감, 단계 체크, 완료·건너뜀·취소
- 매일·요일별 반복, 주간 횟수 목표, 그룹, 보관과 복원
- 수동 순서, 시간순, 그룹별 보기. 그룹 안은 시간순, 시간 미정은 마지막
- 일감과 타임블록 편집, 겹침 안내, 연결 항목 관리
- 한국 시간 기준 주간 완료 횟수
- 사용자 허용에 따른 기기 알림

알림은 앞으로 7일의 가까운 60개까지 예약하며 앱 활성화와 변경 시 갱신합니다. 7일 이상 앱을 열지 않으면 다음 알림이 자동 연장되지 않습니다. 주간 횟수 목표 루틴은 자동 알림 대상에서 제외됩니다. 집중 모드 등 운영체제 설정에 따라 알림 표시가 달라질 수 있습니다.

첫 실행은 빈 목록입니다. 기존 웹사이트 데이터는 복사하지 않습니다. 앱 삭제 시 데이터가 사라질 수 있으며 OS 백업은 사용자의 설정에 따릅니다.

## 검증

2026-10-02: 핵심 테스트 20개 및 iPhone 17e의 UI 테스트 5개 통과(기기 알림 예약·취소 포함). [상세 검증과 구현 판단](docs/verification-2026-10-02.md)을 참고하세요.

공유 모델·저장소·일정 규칙 테스트:

```sh
swift test --build-system native --scratch-path /private/tmp/today-routine-tests
```

시뮬레이터 UI 테스트:

```sh
xcrun simctl list devices available
xcodebuild -project TodayRoutine.xcodeproj -scheme TodayRoutine \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  -derivedDataPath /private/tmp/today-routine-ios-build test CODE_SIGNING_ALLOWED=NO
```

시뮬레이터 이름은 설치된 기기에 맞게 바꿉니다. 빌드 산출물은 `/private/tmp`를 사용해 Documents 폴더의 Finder 확장 속성이 테스트 번들 서명에 영향을 주지 않게 합니다.
UI 테스트는 독립 저장 파일을 사용하므로 일반 앱의 사용자 데이터를 초기화하지 않습니다.

프로젝트 파일 재생성: `python3 scripts/generate-project.py`. 외부 패키지를 내려받지 않습니다.

## 범위

App Store·TestFlight 배포, TickTick, iCloud/웹 동기화, 위젯, 실시간 활동은 이번 버전에 포함하지 않습니다. 실기기 설치와 실기기 알림 전달은 별도 서명·기기 환경에서 검증해야 합니다.
