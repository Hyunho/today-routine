# Mac Logseq 탭 검증 — 2026-10-10

## 결과물과 소스

- 앱: 버전 1.0, 빌드 60.
- 개발 서명 앱: `/private/tmp/today-routine-logseq-signed/Build/Products/Debug/TodayRoutineMac.app`.
- ZIP: `exports/TodayRoutineMac-1.0-build60.zip`.
- SHA-256: `5fea5697e67012f5c26fa53951e9c5e6252c4f8abb22261031b02c51301a0c92`.
- bilog 원격: `git@github.com:Hyunho/bilog.git`, 로컬 작업 브랜치 `codex/logseq-embedding`.
- 서브모듈 고정 커밋: `6a93d643414586b9969b6fe9f8a2d3f3e377c54d`.
- 사용자 명시적 승인 후 두 커밋을 `origin/codex/logseq-embedding`에 푸시했다. 새 임시 저장소에서 GitHub를 대상으로 `git submodule update --init --recursive`를 실행해 고정 커밋 `6a93d643414586b9969b6fe9f8a2d3f3e377c54d`와 깨끗한 작업 트리를 확인했다. `main`은 변경하지 않았다.
- 기존 앱 프로세스와 `~/Applications/TodayRoutineMac.app`은 교체/종료하지 않았다.

## 자동 검증

| 항목 | 결과 | 로그 |
| --- | --- | --- |
| 최종 RoutineCore 전체 테스트 | 145개 통과 | `/private/tmp/logseq-routine-final.log` |
| 최종 bilog 패키지 테스트 | UI/편집기 52개 + 코어 42개 = 94개 통과 | `/private/tmp/logseq-package-final.log` |
| Mac 앱 내 호스트 테스트 (초기 구현) | 6개 통과 | `/private/tmp/logseq-host-green.log` |
| 최종 호스트/종료 테스트 | 실제 소스를 링크한 임시 SwiftPM 하네스에서 7개 통과 | `/private/tmp/logseq-recovery-green.log` |
| 최종 Mac 단위·UI 테스트 빌드 | 성공, 실행 결과와 구분 | `/private/tmp/logseq-test-compile.log` |
| iPhone 시뮬레이터 빌드 | 성공 | `/private/tmp/logseq-ios-final.log` |
| 개발 인증서 서명 Mac 빌드 | 성공 | `/private/tmp/logseq-signed-final.log` |
| 별도 경로 빌드 | 로컬 git clone으로 고정 커밋을 받아 별도 소스 스냅샷에서 성공 | `/private/tmp/logseq-relocation-build.log` |
| 새 원격 서브모듈 초기화 | GitHub에서 고정 커밋을 받아 초기화 성공 | `/private/tmp/bilog-remote-submodule-2pa_c_ai` |
| 버전 스크립트 | 3개 통과; 서브모듈 누락 시 초기화 안내 확인 | 실행 출력 |
| 서명·ZIP | `codesign --verify --deep --strict`와 ZIP 무결성 검사 통과 | `/private/tmp/logseq-zip-check.log` |

서명 확인은 keychain 접근이 가능한 승인된 환경에서 성공했다. 제한된 샌드박스 안에서는 신뢰 저장소 접근으로 `CSSMERR_TP_NOT_TRUSTED`가 발생했으며, 실제 서명 빌드 스크립트와 별도의 승인된 확인에서 모두 성공했다.

## 회귀 검토와 보완

독립 리뷰가 발견한 두 문제를 수정했다.

1. 저장 실패 뒤 사본을 내보내는 동안 공유 편집 잠금이 풀리는 문제: 복구·사본 내보내기·확인까지 편집 잠금을 유지한다. 지연된 내보내기 중 편집 불가, 탭 전환 거절, 중복 종료 거절과 사본 내용 보존을 검증했다.
2. 탭/집중/창 이동으로 Markdown 화면이 재생성될 때 실행 취소와 커서가 사라지는 문제: EditorSession이 Markdown 텍스트 뷰를 보유한다. 같은 문서 재표시 시 undo/caret 유지, 다른 문서 전환 시 과거 undo 미사용을 검증했다.

새 API가 없을 때 회귀 테스트의 컴파일 실패를 확인한 뒤 구현했다. 최종 전체 패키지 테스트와 호스트 하네스는 실패 0건이다.

## 확인하지 않은 항목

Mac이 잠겨 UI 테스트가 실행 단계에서 대기했다. 사용자가 실제 화면 검증을 건너뛰도록 요청하여 해당 실행을 중단했다. 이후 앱 호스팅 테스트도 잠금 세션에서 대기해, 화면이 필요 없는 저장/종료 로직은 실제 소스를 심볼릭 링크한 임시 SwiftPM 하네스로 검증했다. AppModel 탭/집중 통합 테스트 2개는 최종 컴파일만 확인했다.

실제 탭 표시, 창 크기·키 창 이동·메뉴 활성화, 한국어 입력기 조합 상태, 집중 화면 왕복, sandbox 파일 선택/재실행 권한 흐름은 수동 또는 UI 실행 검증이 남아 있다. 별도 경로 빌드는 로컬 커밋 복제 기반이며, 이후 동일 커밋을 GitHub에서 새 서브모듈로 받아 초기화하는 검증도 성공했다. 소스가 동일하므로 원격 초기화 후 중복 빌드는 실행하지 않았다.

## 작업 보존

기존 기능 대부분이 이미 미커밋 상태였다. 현재 기능 브랜치에서 기존 변경을 보존했고, 기존 파일이 섞인 앱 통합 변경은 작업 폴더에 남겼다. 상위 저장소에는 서브모듈 등록/고정만 별도 커밋했고, 편집기 공통 변경은 bilog 서브모듈 내부에 두 커밋으로 저장했다. 원본 `~/Work/logseq` 작업 폴더는 변경하지 않았다.
