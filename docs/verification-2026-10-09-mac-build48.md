# Mac 빌드 48 교체 및 실행 확인 — 2026-10-09

- 사용자의 교체·확인 요청에 따라 `scripts/build_mac_local.py`로 기존 개발 인증서를 사용해 빌드 48을 생성했다. 빌드와 코드 서명 검증 성공.
- 기존 PID 12445를 정상 종료한 뒤 기존 설치 앱과 `default.store` 및 존재하는 WAL/SHM을 `/private/tmp/today-routine-upgrade-48-backup`에 백업했다.
- `/Users/hyunho/Applications/TodayRoutineMac.app`을 교체하고 실행했다. 설치 번들 버전 48, 새 PID 72194 및 실행 경로 확인.
- 교체 전후 루틴 16개, 동기화 이벤트 269개로 동일. 관찰 구간 Sync 카테고리 오류 로그 없음.
- 교체 전: `top` CPU 29.2~44.6%, MEM 841~891MB.
- 교체 후 00:37:26~00:38:02: MEM 55~56MB. CPU 표본은 0.1, 25.9, 0.0, 0.1, 4.4, 2.2, 0.1%. 첫 top 표본의 CPU 0은 계산에서 제외한다. CPU 누적 시간은 12.72초에서 14.44초로 증가(약 36초 동안 약 1.72 CPU초).
- `sample`: physical footprint 55.7MB, 실행 후 최고 88.1MB.
- 로그: `/private/tmp/today-build48-top-startup.txt`, `/private/tmp/today-build48-top-steady.txt`, `/private/tmp/today-build48-top-final.txt`, `/private/tmp/today-build48-sample.txt`.
- 관찰은 짧은 로컬 실행 검증이다. 동기화 순간의 일시적 CPU 상승은 남으며 장시간 사용·iPhone 실기기 결과를 의미하지 않는다. 아이폰 설치본은 교체하지 않았다.
- 버전 스크립트 테스트 3개 통과, `git diff --check` 통과.
