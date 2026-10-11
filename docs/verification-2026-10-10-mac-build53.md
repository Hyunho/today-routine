# Mac 빌드 53 툴바 충돌 수정 검증

## 보고된 증상과 재현

- 사용자 장비: MacBookAir10,1, macOS 26.5.1, TodayRoutineMac 1.0 (52).
- 15:40:33과 15:43:35의 두 보고서 모두 메인 스레드의 `NSToolbar._insertNewItemWithItemIdentifier` → SwiftUI `AppKitToolbarStrategy` → `EXC_BREAKPOINT / SIGTRAP` 경로를 보인다. 사용자는 웹 열기 이후 피드 진입과 연관된 간헐적 종료를 보고했다.
- 기존 Mac 루트는 피드와 전체의 `NavigationStack`을 ZStack에 계속 두고 opacity만 0으로 변경했다. 숨김 상태에서도 툴바 preference가 같은 창으로 전파된다.
- 독립 SwiftUI 재현 프로그램에서 두 겹친 스택에 각각 상세 페이지를 push하자 `NSToolbar.m:1696`의 assertion / `NSInternalInconsistencyException`으로 종료했다(exit 133). 예외 상세 reason은 시스템 로그에서 가려져 있으므로 사용자의 정확한 중복 식별자가 확인됐다고 주장하지 않는다.
- 재현 파일: `/private/tmp/toolbar-repro.swift`. 진단 보고서: `/Users/hyunho/Library/Logs/DiagnosticReports/toolbar-repro-2026-10-10-154628.ips`.

## 변경과 검증 결과

- `RootView.swift`의 Mac 콘텐츠를 선택값이 연결된 `TabView`로 변경했다. 각 화면에 tag를 지정하고 기존 하단 버튼으로 선택한다. opacity로 숨기는 중첩 스택과 hasOpened 플래그는 제거했다. iPhone 경로는 변경하지 않았다.
- 같은 재현 프로그램을 TabView로 바꾸면 정상 종료한다. 두 상세 화면을 10회 왕복한 추가 실행도 정상 종료했으며 활성 창의 `com.apple.SwiftUI.navigationStack.back` 항목이 정확히 하나인지 검사했다.
- 비교 재현: `/private/tmp/toolbar-tabs.swift`, `/private/tmp/toolbar-tabs-repeat.swift`. 출력: `/private/tmp/toolbar-tabs-repeat.log`.
- 전체 코어 테스트 145개 통과. 로그: `/private/tmp/today-toolbar-core.log`.
- Mac 앱 및 최종 UI 테스트 컴파일 성공. 로그: `/private/tmp/today-toolbar-final-test-build.log`.
- 개발 인증서 서명 빌드 성공, codesign deep/strict 검증 성공. 로그: `/private/tmp/today-toolbar-build53.log`.
- ZIP 무결성 검증 성공. SHA-256: `222e990b0b51b167e32b352f115cd22a0772f1e700784e2271a72bed8aa34e2e`.
- 결과물: `exports/TodayRoutineMac-1.0-build53.zip`.

## 남은 확인

- 개발 장비가 잠겨 있어 실제 앱의 XCTest 클릭 테스트는 실행하지 못했다. 별도 사용자 장비에서 원래 동작으로 재검증해야 한다. 단순 재현 성공을 실제 앱의 모든 경로 검증으로 간주하지 않는다.
- UI 테스트는 피드/전체 양쪽 상세 페이지 왕복과 툴바 분리, 외부 브라우저 열기 후 앱 복귀, Valley/설정/피드 왕복, 긴 글 스크롤 위치 유지를 확인하도록 추가/보강했다. 스크롤 유지와 macOS 14 실제 실행은 아직 확인하지 못했다.
- 로컬 수정 ZIP만 생성했다. 설치 앱 교체 또는 iCloud 업로드는 수행하지 않았다.
