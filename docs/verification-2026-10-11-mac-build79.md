# Mac 빌드 79 재배포 검증 — 2026-10-11

- 버전 1.0 (79). 현재 작업 디렉터리에서 개발 인증서 서명 빌드 성공.
- 핵심 테스트 168개, 버전 스크립트 테스트 3개 통과. 코드 서명과 ZIP 무결성 검증 성공.
- 배포 파일: `/Users/hyunho/Library/Mobile Documents/com~apple~CloudDocs/Release/TodayRoutineMac-1.0-build79.zip`.
- 원본/복사본 SHA-256 일치: `3897004c6e9cdd2a95d65107abd43db6572c3e47e55540d5dc1280246e5e7899`.
- 빌드 로그: `/private/tmp/today-routine-deploy-79.log`.
- 테스트 로그: `/private/tmp/today-routine-deploy-79-tests.log`.
- 이번 배포에서는 UI 테스트 및 NativeLogseq 패키지 별도 테스트를 실행하지 않았다. 기존 설치 앱 교체/실행 및 iPhone 설치는 수행하지 않았다.
- iCloud 서버 업로드 완료: `isUbiquitousItem=true`, `ubiquitousItemIsUploaded=true`, 업로드 오류 없음.
