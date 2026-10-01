# 루틴 CSV 예제

루틴 한 개의 날짜별 완료 표 예제입니다. 실제 앱 파일은 앱에서 루틴을 만든 후 동기화 설정의 최신 CSV에서 열어 주세요. 이 예제를 기존 폴더에 덮어쓰면 열 ID 기준이 없으므로 자동 수신 대상이 아닙니다.

`baseline.json`에는 `version`, `spaceID`, `documentID`, `revisionID`, `routineID`, `name`, `columns`(제목과 stepID), `state`(필드별 기준 버전 포함), `dates`, `createdAt`이 저장됩니다. `manifest.json`의 SHA256은 기준 JSON의 무결성을 검사합니다. CSV 본문은 편집 대상이므로 초기 해시와 같을 필요가 없습니다. 기준 JSON은 앱이 생성하며 손으로 작성하지 않습니다.
