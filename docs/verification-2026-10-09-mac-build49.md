# Mac 빌드 49 iCloud Drive 배포 — 2026-10-09

- 현재 작업 디렉터리에서 `scripts/build_mac_local.py`로 1.0 (49) 개발 인증서 서명 빌드 성공. 코드 서명 검증과 ZIP 무결성 검사 성공.
- 배포 파일: `/Users/hyunho/Documents/TodayRoutine-Releases/TodayRoutineMac-1.0-build49.zip`.
- SHA-256: `e3de95e226e4df8bf9d4d2a5fa63d6121d79e9b810f353ab3367c8593d48e816`. 원본과 배포본 일치.
- 전체 공유 모델 테스트 140개 통과, 버전 스크립트 테스트 3개 통과.
- 최초 실행에서 재수신 테스트 1개 실패: Date()의 JSON 밀리초 인코딩 왕복으로 약 0.119마이크로초 차이 발생. LegacyTaskCleanupTests의 이벤트 시각을 정확히 표현 가능한 고정 시각으로 변경한 뒤 전체 통과. 제품 코드는 변경하지 않았다.
- 기존 설치 앱 교체나 실행은 하지 않았다. 업데이트 앱 실행 시 내부 일감 삭제가 적용되며 Apple 미리 알림 원본은 유지된다.
- iPhone 설치본은 이 배포에 포함하지 않았다. Mac Apple Silicon 개발 서명 앱이며 공증 배포가 아니다.
- 빌드 로그: `/private/tmp/today-routine-deploy-49.log`.
- 테스트 로그: `/private/tmp/today-routine-deploy-49-tests-final.log`.
- Foundation 파일 속성으로 iCloud 파일 여부 true, 서버 업로드 완료 true, 업로드 오류 없음 확인. 다른 기기 다운로드·설치는 미검증.
