---
version: alpha
name: Today Routine
description: 오늘의 루틴 — iPhone과 Mac에서 하루의 실천, 일정, 읽을거리를 정리하는 네이티브 앱
colors:
  reader-text-light: "#222222"
  reader-text-dark: "#EFEFEF"
  reader-link-light: "#007F79"
  reader-link-dark: "#5DD8D1"
  reader-code-light: "#F1F2F3"
  reader-code-dark: "#252525"
typography:
  reader-body:
    fontFamily: "-apple-system, sans-serif"
    fontSize: 17px
    lineHeight: 1.65
  focus-timer:
    fontFamily: "system-ui"
    fontSize: 48px
    fontWeight: 500
rounded:
  time-block: 6px
  reader-code: 8px
  pending-stack: 10px
  agenda-card: 12px
spacing:
  micro: 4px
  compact: 8px
  section-inner: 10px
  control: 12px
  page: 16px
  section: 20px
  focus: 24px
components:
  completion-control:
    width: 44px
    height: 44px
  agenda-card:
    rounded: "{rounded.agenda-card}"
  reader-code:
    rounded: "{rounded.reader-code}"
    padding: "{spacing.control}"
---

# 오늘의 루틴 · Design System

## Overview

오늘의 루틴은 반복할 일, 개별 일감, 캘린더 일정, 읽을거리를 하루의 흐름 안에서 다루는 개인용 앱이다. 화면은 조용하고 실용적이어야 한다. 사용자가 지금 할 일과 완료 상태를 빠르게 파악하고, 필요한 세부 정보만 펼쳐 볼 수 있도록 한다.

시각적 중심은 시스템 배경 위의 선명한 텍스트와 청록색 강조다. SF Symbols, 기본 내비게이션, 목록, 폼, 날짜 선택기를 사용한다. 여백과 글자 굵기로 정보의 순서를 만들고, 작은 상태 아이콘으로 진행 상황을 표현한다. 한국어 문구는 짧고 차분하게 쓴다. 대표 문구는 “작은 실천이 만드는 하루”다.

### 문서 범위와 적용 방법

- 2026-10-09의 로컬 작업 트리에 있는 SwiftUI 구현을 기준으로 추출했다. 커밋되지 않은 구현도 포함한다.
- 새 화면을 디자인하거나 기존 화면을 수정하는 AI와 사람이 공유하는 UI 기준서다. 기능별 상세 동작은 해당 코드와 `docs/superpowers/specs/`를 함께 확인한다.
- 본문의 “현재”는 코드에서 확인한 동작이다. “권장”과 검토 목록은 향후 디자인에 적용할 지침이며, 모든 화면에서 검증된 구현을 뜻하지 않는다.
- YAML에는 코드에서 확인한 고정값만 담았다. SwiftUI의 수치는 pt이며, YAML의 px는 디자인 도구로 전달하기 위한 논리 크기 표기다. 물리 픽셀이나 모든 플랫폼에서의 동일한 렌더링을 뜻하지 않는다.
- 시스템 색상과 의미 기반 글꼴은 OS, 테마, 글자 크기 설정에 따라 달라진다. 본문의 네이티브 매핑을 우선한다. YAML의 reader 색상을 앱 전체 색상으로 확대 적용하지 않는다.
- Google의 [DESIGN.md 초안 구조](https://github.com/google-labs-code/design.md/blob/main/docs/spec.md)를 참고했다. Stitch 가져오기 및 공식 도구의 스키마 검증은 수행하지 않았다.

### 구현 근거

| 기준 | 소스 |
|---|---|
| 전역 tint, 한국어·시간대 설정 | [TodayRoutineApp.swift](TodayRoutine/App/TodayRoutineApp.swift) |
| 탭 구조, Mac 창, 빈 상태 | [RootView.swift](TodayRoutine/App/RootView.swift) |
| 완료 표시와 기본 시트 크기 | [PlatformViews.swift](TodayRoutine/App/PlatformViews.swift) |
| 오늘 화면과 시간 블록 | [TodayView.swift](TodayRoutine/Features/Today/TodayView.swift) |
| 시간순 카드 | [AgendaTimeline.swift](TodayRoutine/Features/Today/AgendaTimeline.swift) |
| 섹션과 선택적 스크롤 효과 | [PendingStackTracking.swift](TodayRoutine/Features/Today/PendingStackTracking.swift) |
| 집중 화면 | [FocusSessionView.swift](TodayRoutine/Features/Today/FocusSessionView.swift) |
| 피드 목록과 상세 | [InboxView.swift](TodayRoutine/Features/Inbox/InboxView.swift), [InboxDetailView.swift](TodayRoutine/Features/Inbox/InboxDetailView.swift) |
| 읽기 본문 스타일 | [FeedBodyRenderer.swift](TodayRoutine/Services/FeedBodyRenderer.swift), [FeedBodyView.swift](TodayRoutine/Features/Inbox/FeedBodyView.swift) |
| 월간 캘린더 | [MonthCalendarContent.swift](TodayRoutine/Features/Calendar/MonthCalendarContent.swift) |
| 일감과 루틴 목록 | [PlanningView.swift](TodayRoutine/Features/Planning/PlanningView.swift), [RoutinesView.swift](TodayRoutine/Features/Routines/RoutinesView.swift) |

## Colors

### 네이티브 팔레트와 역할

| 역할 | SwiftUI 표현 | 사용 의도 |
|---|---|---|
| 주 강조색 | `Color.teal`, 전역 `.tint(.teal)` | 주요 행동, 선택된 Mac 탭, 완료, 북마크, 읽지 않은 글의 표식 |
| 주 텍스트 | `.primary` | 제목과 읽어야 할 핵심 내용 |
| 보조 텍스트 | `.secondary` | 날짜, 시간, 반복 주기, 출처, 설명, 미완료 표시 |
| 낮은 우선순위 | `.tertiary` | 보조 chevron, 일정 종료 시각 등 |
| 따뜻한 강조 | `Color.orange` | 오늘의 해 아이콘, 건너뜀, 일부 갱신 실패 안내, 시간표의 일반 항목 |
| 시간의 기준점 | `Color.red` | 현재 시간 선과 월간 캘린더의 오늘 날짜 |
| 캘린더 구분 | 이벤트의 `calendarColor` | 연결한 캘린더의 원래 색상 보존 |
| 기본 바탕 | 시스템 배경, 기본 List/Form 배경 | 밝은 모드와 어두운 모드에 적응 |
| 떠 있는 보조 영역 | `.regularMaterial`, 탭 영역의 `.bar` | 배경 맥락을 유지하면서 제어 요소를 분리 |

청록색은 핵심 팔레트지만 역할은 문맥에 따라 다르다. 완료는 체크 모양, 저장은 북마크, 읽지 않음은 점과 글자 굵기를 함께 사용한다. 주황색도 건너뜀과 시간표 항목에서 함께 쓰이므로 색만으로 상태를 판단하게 하지 않는다. 빨간색 현재 시간 표시는 오류가 아니다. 삭제는 시스템의 destructive 역할과 명확한 문구로 구별한다.

### 표면과 투명도

- 시간순 카드: 청록색 7% 채움, 15% 윤곽선.
- 시간 블록: 항목 색상 18% 채움, 완료하면 8%. 캘린더 색상이 있으면 이를 우선하며, 일반 항목은 주황색, 타임블록은 청록색이다.
- 상단 미완료 스택: regular material 바탕, 청록색 30% 윤곽선.
- 시간 구분선: 보조색 20%. 현재 시간 선은 빨간색이며 작은 점과 시간 레이블을 동반한다.

### 피드 본문의 고정 팔레트

내장 웹 읽기 영역은 본문 텍스트에 밝은 모드 `#222222`, 어두운 모드 `#EFEFEF`를 쓴다. 링크는 각각 `#007F79`, `#5DD8D1`, 코드 배경은 `#F1F2F3`, `#252525`다. 배경 자체는 투명하게 두어 앱 화면과 이어지게 한다. 이 값은 `FeedBodyRenderer`의 실제 CSS이며 `Color.teal`의 HEX 정의가 아니다.

## Typography

기본은 플랫폼 시스템 글꼴이다. 네이티브 화면에서는 고정 크기보다 SwiftUI 의미 기반 스타일을 사용한다. 한국어는 시스템의 글꼴 대체 기능을 따른다.

| 역할 | 현재 스타일 | 사용 위치 |
|---|---|---|
| 큰 제목 | `.largeTitle.bold()` | 집중할 작업명, 캘린더 월 |
| 강조 요약 | `.title2.bold()` | 완료 개수, 글 상세 제목 |
| 목록 제목 | `.headline` | 루틴, 일감, 일정 제목 |
| 피드 제목 | `.body`, 미열람은 semibold·열람은 regular | 읽음 여부를 굵기로 구별 |
| 설명 | `.subheadline` + secondary | 노트, 피드 요약, 안내 |
| 메타데이터 | `.caption` / `.caption2` + secondary | 출처, 날짜, 시각, 반복 주기 |
| 집중 타이머 | 48pt, medium, rounded | 경과 시간; 숫자 폭 고정 |

시간과 카운터에는 `monospacedDigit()`를 사용해 값이 바뀔 때 정렬이 흔들리지 않게 한다. 집중 타이머는 한 줄을 유지하며 현재 최소 축소 비율은 0.6이다.

읽기 본문은 기본 17px, 줄 높이 1.65이며 `@ScaledMetric(relativeTo: .body)`를 통해 글자 크기 설정을 반영한다. 본문 제목 줄 높이는 1.3, h1/h2/h3 크기는 본문의 1.7/1.4/1.2배다. 코드는 시스템 모노스페이스를 사용한다.

목록에서는 필요한 경우 제목 두 줄, 피드 요약 두 줄 제한을 사용하지만 상세 내용은 세로로 확장한다. 긴 한국어 제목과 큰 글자 설정을 함께 확인하는 것을 권장한다.

## Layout

### 화면 구성

주 내비게이션은 `오늘 → 일감 → 피드 → 캘린더 → 루틴`의 다섯 탭이다. iPhone은 기본 `TabView`, Mac은 하단의 아이콘·텍스트 버튼을 사용한다. 각 기능은 자체 내비게이션과 도구 모음을 갖는다.

| 화면 | 정보의 순서와 구성 |
|---|---|
| 오늘 | 날짜와 완료·남은 개수 → 해당 날짜 마감 미리 알림 → 목록/시간 블록 선택 → 종일·시간 미정·시간순 항목·주간 목표 |
| 일감 | Apple 미리 알림 연결과 관리 → 미완료/완료 미리 알림 → 앱의 미완료/완료 일감 |
| 피드 | 필터·개수·나중에 읽기 → 그룹과 글 목록 → 글 상세 |
| 캘린더 | 연도와 월 → 요일 → 7열 날짜 그리드 → 선택한 날의 일정 |
| 루틴 | 반복 설정과 상태를 확인하는 목록 → 루틴 상세 편집 |
| 집중 | 상단 종료 → 작업명 → 경과 시간 → 노트·단계 → 완료하고 종료 |

오늘 화면의 기본 보기는 현재 “시간 블록”이다. 시간표는 세로 스크롤하며 현재 시각을 빨간 선으로 표시한다. 겹친 항목은 열로 나누고, 시간 미정과 주간 목표는 시간 축 바깥에 둔다. 목록 보기에서는 시간 레일과 카드로 시간순 흐름을 나타낸다.

### 간격과 크기

- 오늘 화면: 좌우 16pt, 위아래 12pt, 큰 섹션 사이 20pt, 섹션 내부 10pt.
- 피드 목록: 행의 기본 세로 여백 16pt. 상세 읽기: 외곽 20pt, 내부 요소 사이 18pt.
- 집중 화면: 콘텐츠 외곽 24pt, 주요 요소 사이 28pt, 본문 최대 너비 560pt.
- 완료 버튼: 공통 컴포넌트의 터치 영역 44×44pt. 신규 주요 아이콘 버튼도 이 크기를 기준으로 설계하는 것을 권장한다.
- Mac 루트 창: 최소 너비 360pt, 이상적 너비 440pt, 최대 너비 480pt; 최소 높이 560pt, 이상적 높이 760pt.
- 공통 Mac 편집 시트: 최소 360×480pt, 이상적 420×660pt.

간격은 기존 용도별 수치를 재사용한다. 모든 화면이 엄격한 8pt 그리드에 맞춰진 것은 아니다. 기본 화면은 좁은 단일 열 구성을 유지한다. Valley와 피드 글 상세에는 너비 52pt의 오른쪽 도구 사이드바를 두며, 44×44pt 웹으로 열기 버튼으로 기본 브라우저를 실행한다. 웹 주소가 없으면 버튼을 비활성화한다. 오른쪽 상단 도구 모음의 사이드바 버튼은 항상 표시하며 펼치기·숨기기를 전환한다. 기본 상태는 펼침이며, 숨기면 본문이 빈 공간을 사용한다.

## Elevation & Depth

화면 계층은 여백, 구분선, 연한 채움과 시스템 material로 표현한다. 큰 그림자나 장식용 그라디언트를 기본 요소로 추가하지 않는다. 편집은 시스템 시트, 확인과 오류는 시스템 대화상자의 계층을 따른다.

오늘 목록의 선택적 원통 효과는 텍스트를 회전하지 않고 중심에서 멀어질수록 크기만 줄인다. 현재 기본값은 꺼짐이며 `Reduce Motion` 설정에서는 효과를 적용하지 않는다. 새 콘텐츠가 이 효과를 전제로만 읽히게 만들지 않는다.

## Shapes

| 요소 | 형태 |
|---|---|
| 시간 블록 | 모서리 반경 6pt |
| 본문 코드 상자 | 반경 8px |
| 상단 미완료 스택 | 반경 10pt |
| 시간순 카드 | 반경 12pt |
| 시간 레이블과 작은 배지 | Capsule |
| 완료·미완료·건너뜀 | 원형 SF Symbols |
| 캘린더 오늘·선택 날짜 | 원형 배경, 날짜 영역 30×30pt |
| 기본 버튼·폼·선택기 | 플랫폼 기본 형태 |

모든 요소를 동일한 큰 둥근 카드로 감싸지 않는다. 일반 목록은 정렬과 구분선을 유지하고, 시간상 범위를 갖는 항목에 카드 형태를 사용한다.

## Components

### 완료 제어

공통 `CompletionCheckButton`과 `CompletionStatusLabel`의 의미를 유지한다.

| 상태 | 기호 | 색상 | 레이블 |
|---|---|---|---|
| 미완료 | `circle` | secondary | 미완료 / 완료 |
| 완료 | `checkmark.circle.fill` | teal | 완료 / 완료 취소 |
| 건너뜀 | `minus.circle.fill` | orange | 건너뜀 / 건너뛰기 취소 |

접근성 레이블에는 작업명과 실행할 행동을, 값에는 현재 상태를 담는다. 행의 상세 열기와 완료 전환은 별개의 동작이다. 체크 영역을 누를 때 상세 화면까지 함께 열리지 않도록 유지한다.

### 버튼과 폼

집중 화면의 “작업 완료하고 종료”처럼 핵심 행동은 `borderedProminent`와 큰 컨트롤 크기로 강조한다. “원문 열기”, “루틴 상세 열기”는 `bordered`, 목록의 상세 열기는 plain, 독립된 행 내부 체크는 borderless를 사용한다.

편집은 grouped Form과 시스템 입력 요소를 사용한다. 아이콘만 있는 추가·설정·북마크 버튼에는 행동을 설명하는 접근성 레이블을 제공한다. 삭제는 destructive 버튼과 확인 대화상자를 사용한다. 저장 실패는 “저장하지 못했습니다”와 실제 오류 설명으로 전달한다.

### 루틴·일감·일정 행

제목을 먼저 읽고 그 아래 반복 주기, 날짜·시간, 단계 수, 출처를 보게 한다. 완료 버튼은 해당 화면의 기존 위치를 따른다. 캘린더 일정은 원본 캘린더 색상 막대로 출처를 구별한다. 세부 단계가 있으면 펼침 제어를 제공한다.

시간표의 드래그는 배치 조정이다. 현재 iPhone에서는 길게 누른 뒤 이동하며 화면에 안내 문구가 있다. 상세 화면의 시간 변경 경로도 유지한다.

### 피드 행과 읽기 화면

출처·시간은 작고 흐리게, 제목은 가장 잘 읽히게, 요약은 보조 텍스트로 배치한다. 읽지 않은 글은 semibold 제목과 청록색 표식, 읽은 글은 regular 제목으로 표현한다. 저장한 글은 채운 북마크로 구별한다.

읽음·나중에 읽기·루틴 완료는 서로 독립된 상태다. 글을 열어 읽었다는 사실을 루틴 완료로 표현하지 않는다. 상세 화면은 출처 → 제목 → 날짜 → 구분선 → 본문 순서를 따르고, 웹으로 열기는 오른쪽 도구 사이드바에 둔다. 코드와 표는 내부 가로 스크롤을 허용하고 전체 화면 너비를 밀어내지 않는다.

### 빈 상태·로딩·오류

빈 상태는 `ContentUnavailableView` 또는 `EmptyHint`로 구성한다. 기호, 짧은 제목, 다음 행동을 알려주는 설명을 함께 둔다. 오늘 목록의 예시는 “오늘의 리듬을 시작해요”와 “첫 루틴 추가”다. 읽기 본문이 없으면 “피드에 본문이 없습니다. 원문에서 확인하세요.”로 안내한다.

불러오는 중에는 설명이 있는 `ProgressView`를 사용한다. 일부 구독 갱신 실패는 목록을 유지한 채 주황색의 옅은 안내 영역과 “확인” 버튼을 보여준다. 권한 없음, 빈 데이터, 읽기 전용, 저장 실패를 서로 다른 상태로 설명한다.

### 아이콘과 문구

SF Symbols를 사용한다. 탭은 `sun.max`, `tray`, `tray.full`, `calendar`, `repeat`; 설정은 `gearshape`, 추가는 `plus`, 저장은 `bookmark`, 외부 원문은 `arrow.up.right.square`다.

사용자 문구는 “일감”, “루틴”, “시간 블록”, “나중에 읽기” 등 기존 용어를 재사용한다. 앱은 한국어 로케일과 한국 시간 기준을 사용하므로 새 날짜·시간 UI도 이를 따른다. Mac 하단에는 현재 CPU·메모리 사용량이 작은 보조 텍스트로 표시되며 주요 콘텐츠보다 시각적 우선순위가 낮다.

## Do's and Don'ts

- **유지:** 시스템 색상과 의미 기반 텍스트 스타일, 한국어 레이블, 청록색 행동 강조, 간결한 단일 열 구조.
- **유지:** 상태마다 색상과 기호 또는 문구를 함께 제공하고, 완료 취소·건너뛰기 취소를 구별한다.
- **권장:** 새 화면 검토 시 밝은/어두운 모드, 큰 글자, 긴 한국어 제목, 좁은 Mac 창, VoiceOver, Reduce Motion을 확인한다. 이 문서 작성만으로 접근성 검증이 완료된 것은 아니다.
- **피하기:** 시스템 색상을 임의의 고정 HEX로 치환하거나 읽기 영역의 팔레트를 앱 전체에 강제하는 일.
- **피하기:** 읽음·저장·완료 상태의 혼동, 원본 캘린더 색상 제거, 색만으로 오류나 완료를 표현하는 일.
- **피하기:** 불필요한 대형 배너, 과도한 그림자, 새로운 장식 글꼴, 기존 기능 흐름과 무관한 레이아웃 변경.
- **유지 관리:** 화면의 공통 색상·글꼴·간격·상태 의미를 변경할 때 이 문서와 구현 근거를 함께 갱신한다.

### AI에 전달할 요청 예시

> DESIGN.md를 기준으로 오늘의 루틴에 새 화면을 설계하세요. 플랫폼 시스템 글꼴과 배경, 청록색 행동 강조, 기존 탭과 단일 열 구성을 유지하세요. 제목·보조 정보·독립된 완료 제어의 위계를 재사용하고 빈 상태, 로딩, 오류도 포함하세요. SwiftUI에서는 동적 시스템 색상과 의미 기반 글꼴을 사용하세요. 디자인 도구에서 이를 재현하기 위해 고정 색상이나 크기가 필요하면 근사값임을 명시하고, 구현 시 네이티브 토큰으로 연결하세요.
