# Mac 빌드 51 재배포 검증 — 2026-10-10

- 버전: 1.0 (51). 현재 작업 디렉터리에서 개발 인증서로 서명 빌드 성공.
- 핵심 테스트 145개, 버전 스크립트 테스트 3개 통과. 코드 서명, ZIP 무결성 및 원본/복사본 SHA-256 일치 확인.
- 파일: `/Users/hyunho/Documents/TodayRoutine-Releases/TodayRoutineMac-1.0-build51.zip`.
- SHA-256: `d82e1f7bf946f3a094d01c3398b40096b8c629a1336fc6321bbfd2509d158a70`.
- 빌드 로그: `/private/tmp/today-routine-deploy-51.log`.
- 테스트 로그: `/private/tmp/today-routine-deploy-51-tests.log`.
- 설치 앱 교체/실행 및 iPhone 설치는 수행하지 않았다.
- iCloud 서버 업로드 완료 확인: `isUbiquitousItem=true`, `ubiquitousItemIsUploaded=true`, 업로드 오류 없음. 복사 직후 일시적 계정 접근 오류는 재확인 시 해소됐다.
