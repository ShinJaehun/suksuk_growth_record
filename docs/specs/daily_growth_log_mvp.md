# Daily Growth Log MVP

**Status:** approved

## 제품과 목적

- 한국어 표시명: 쑥쑥성장기록장
- 영문 표시명: Daily Growth Log
- repository: `suksuk_growth_record`

담임교사가 학급의 성장 덕목을 정하고, 학생은 주로 종례시간에 자기평가 점수와 성찰을 기록한다. 교사는 실시간 입력 현황과 학급 통계를 확인하고, 학생은 자신의 과거 기록과 성장 추이를 돌아본다.

## Project lineage와 foundation 경계

이 저장소는 다음 starter baseline에서 분기했다.

- source repository: `ShinJaehun/suksuk_school_starter`
- source tag: `starter-current-year-baseline-2026-09`
- source commit: `47bed6e`

성장기록장은 starter의 현재 runtime foundation을 그대로 사용한다.

```text
School
└── SchoolYear
    ├── annual teacher User
    └── Classroom
        ├── HomeroomAssignment
        └── Student
```

teacher/admin 인증, Classroom token/QR와 Student PIN/session 인증, active SchoolYear 경계, Classroom 직속 Student, current HomeroomAssignment 기반 담임 권한은 기존 architecture와 canonical spec을 따른다. 이를 설명하는 foundation 문서는 성장기록장에서도 유효하며 삭제하지 않는다.

starter의 planning/archived SchoolYear full operation, rollover와 planning-year bulk management roadmap은 성장기록장의 active roadmap이 아니다.

## 덕목

- 덕목은 Classroom 단위다.
- 새/current Classroom에는 기본 덕목 `독서`, `봉사`, `감사`가 제공된다.
- 성장기록 기능 도입 시 기존 current Classroom에도 기본 덕목 3개를 정확히 한 번 bootstrap한다. 이후 새 Classroom도 같은 기본 덕목으로 시작하며 중복 생성하지 않는다.
- 아래 Authorization에서 정한 성장기록 운영 권한이 있는 사용자는 current active Classroom의 덕목을 추가, 편집, 사용 종료할 수 있다.
- 학생 입력 화면에 노출되는 active 덕목은 최대 5개다. 기본 3개에 최대 2개를 추가하는 UX를 기본으로 한다.
- Classroom은 성장 기록을 위해 최소 1개의 active 덕목을 유지해야 하며 마지막 active 덕목은 사용 종료할 수 없다.
- 5개 제한은 active 덕목 수에 대한 domain/application invariant이며 DB를 5개 점수 column으로 고정하지 않는다.
- 과거 기록이 있는 덕목은 hard delete하지 않는다. 사용 종료 후에도 과거 기록에서 의미를 보존한다.
- rename은 단순 오타나 표현 수정 용도이며, 추가·사용 종료와 함께 아래 Classroom 날짜별 configuration 적용 규칙을 따른다.
- 의미가 다른 덕목으로 교체할 때는 rename보다 기존 덕목 사용 종료 후 신규 덕목 추가를 기본 원칙으로 한다.

### Classroom 날짜별 덕목 configuration

- 덕목 적용과 history의 canonical 단위는 `Classroom + 날짜`다. 날짜별로 하나의 effective virtue configuration을 가지며, 해당 날짜에 평가할 Virtue 구성과 각 Virtue의 표시 이름을 보존한다. 같은 Classroom의 같은 recorded_on에 속한 모든 학생 record는 동일한 구성과 이름을 사용한다. 학생별 최초 저장 시점에 따른 별도 configuration은 허용하지 않는다.
- 성장기록 운영 권한이 있는 사용자가 관리하는 Virtue 상태는 앞으로 적용할 현재 설정이며 특정 날짜의 effective configuration과 구분한다. 정확한 model/table/schema 이름, persistence와 lookup/create 방식은 implementation 단계에서 결정한다.
- 오늘 Classroom에 DailyGrowthRecord가 하나도 없다면 권한 있는 사용자의 추가·사용 종료·rename을 오늘 configuration에 반영할 수 있다. 이후 그날 입력하는 모든 학생은 동일한 변경된 configuration을 사용한다.
- 오늘 첫 DailyGrowthRecord가 생성되면 그 날짜 configuration은 확정(frozen)된다. 이후 권한 있는 사용자가 현재 설정을 변경해도 오늘 configuration은 바뀌지 않으며 변경은 다음 날짜부터 적용한다. 이미 입력한 학생의 재수정과 아직 미입력인 학생의 최초 입력 모두 확정된 오늘 configuration을 사용한다.
- 첫 DailyGrowthRecord 생성과 권한 있는 사용자의 덕목 설정 변경이 동시에 발생하더라도 둘의 적용 순서는 원자적으로 결정되어야 한다. 설정 변경이 configuration 확정보다 먼저 완료되면 그 변경을 오늘 configuration에 포함하고, configuration 확정이 먼저 완료되면 해당 설정 변경은 다음 날짜부터 적용한다. 어떤 경우에도 같은 Classroom + 날짜에 서로 다른 configuration이 생겨서는 안 된다.
- configuration 확정이나 이후 권한 있는 사용자의 설정 변경으로 기존 completion을 취소하거나 재입력을 강요하지 않는다.
- 지난 날짜의 configuration과 학생 기록은 소급 변경하지 않는다. 권한 있는 사용자의 설정 변경으로 과거 score 추가·삭제, Virtue 교체, 표시 이름·score 값·reflection 변경을 하지 않는다. 예를 들어 9/8의 `독서`는 9/9에 rename해도 9/8에서는 그대로 유지한다.

예: 9/8에 `독서`를 `책 읽기`로 rename하고 `배려`를 추가한 경우(이후 추가 변경 없음):

| 변경 시점의 Classroom 상태 | 9/8 모든 학생의 구성·이름 | 9/9 구성·이름 |
|---|---|---|
| 09:00, 아직 record 없음 | 책 읽기 / 봉사 / 감사 / 배려 | 책 읽기 / 봉사 / 감사 / 배려 |
| 08:30 학생 A 기록 후 10:00 변경 | A 재수정과 미입력 B 모두 독서 / 봉사 / 감사 | 책 읽기 / 봉사 / 감사 / 배려 |

아래 관리 화면과 색상 정책은 구현을 위한 승인된 contract이며 구현 완료를 뜻하지 않는다.

### 교사 덕목 관리 화면

- Classroom 상세 화면에 해당 Classroom의 담임, 해당 SchoolYear의 school manager, global admin을 위한 `덕목 관리` 진입점을 둔다. 세 역할은 별도 관리 시스템 없이 같은 덕목 domain invariant와 관리 화면을 사용한다. 관리 화면은 active 덕목과 사용 종료된 덕목을 구분하며 기존 position/display order를 사용한다.
- active 덕목의 이름·색상 수정과 사용 종료, 새 덕목 추가를 지원한다. 사용 종료된 덕목은 history 보존을 위해 목록에서 확인한다.
- 복잡한 admin table보다 하나의 일반 page 안에 읽기 쉬운 form을 두는 작은 학급 운영 화면을 우선한다. 제목 `덕목 관리`, active 개수(예: `3 / 5`), active 목록(color swatch·이름·수정·사용 종료), 추가 form(이름·palette 선택·미선택 시 자동 배정), 사용 종료 목록으로 구성한다. modal은 필수가 아니며 business logic은 view에 두지 않는다.
- active가 5개면 추가할 수 없고 1개면 마지막 덕목을 사용 종료할 수 없다. UI는 기존 domain invariant를 반영하며 parameter 조작이나 direct request로도 우회할 수 없어야 한다.
- 빈 이름, 최대 개수 초과, 마지막 active 종료, invalid palette color 등 validation 실패는 같은 관리 화면에 이해할 수 있는 오류로 표시한다. 실패한 변경은 partial state를 남기지 않으며 성공 후 목록은 DB canonical state를 반영한다.

### Virtue 색상

- 각 Virtue는 application이 관리하는 제한된 palette에서 정확히 하나의 유효한 표시 색상을 가진다. 흰 배경의 SVG line/point에서 식별 가능한 충분히 진하고 구별 가능한 색상을 최소 8개 정도 제공하는 방향을 기본으로 한다. 정확한 Tailwind class/hex 값은 implementation concern이다.
- Virtue에 palette 색상을 안정적으로 식별하는 값을 DB에 저장하고 명시적으로 변경할 때까지 유지한다. exact schema name은 구현 단계에서 결정한다. 매 request나 metric 선택마다 임시 random 값을 만들거나 virtue id modulo 방식으로 색상을 계산하지 않는다.
- 같은 Classroom의 active Virtue는 서로 다른 색상을 사용해야 한다. 수동 선택·수정과 direct request도 다른 active Virtue가 사용하는 색상을 선택할 수 없다. 사용 종료된 Virtue는 기존 color identity를 유지하며 inactive 상태에서는 색상 중복을 허용한다. 새 덕목에서 색상을 선택하지 않으면 현재 active 덕목이 사용하지 않는 palette 색상을 자동 배정한다. 정확한 random 알고리즘은 canonical contract가 아니며 저장 후에는 고정된 color identity다.
- 기본 덕목 `독서`, `봉사`, `감사`도 각각 유효한 색상을 가진다. 도입 전 존재하는 모든 Virtue는 안전하고 재현 가능한 migration/backfill로 하나의 유효한 색상을 갖게 하며, 이후 새 Classroom bootstrap도 기본 덕목의 색상을 함께 배정한다. backfill의 정확한 색 선택은 business contract가 아니다.
- 색상은 Virtue의 현재 presentation identity이며 날짜별 historical configuration의 구성·이름 보존 대상에 포함하지 않는다. 성장기록 운영 권한이 있는 사용자가 active 덕목의 색상을 변경하면 과거·현재 chart 모두 현재 색상을 사용하되 날짜별 configuration과 score/history data를 rewrite하지 않는다. 날짜 적용 규칙을 따르는 rename과는 별도 정책이며, 사용 종료된 덕목도 기존 color identity를 유지한다.
- 저장된 색상은 학생 chart의 덕목별 시각적 identity이며 이후 교사 통계·월간 visualization에서도 재사용할 수 있는 기준이다.

### 덕목 관리 feature의 제외 범위

- drag-and-drop/reorder, 사용 종료 덕목 reactivation, hard delete, arbitrary free-form hex/color picker는 제공하지 않는다.
- 학생별 덕목 설정, 학교 공통/global virtue library, virtue template, score scale 변경, 기존 DailyGrowthRecord 구성 rewrite는 포함하지 않는다.
- 월간 visualization, 교사 학급 통계, realtime/Action Cable/Turbo broadcast 추가, 학생 graph에 여러 덕목 line 동시 표시는 포함하지 않는다.
- 날짜별 configuration 정책에서도 event sourcing, generic audit framework, arbitrary effective date 선택 UI, 성장기록 운영 권한이 있는 사용자의 과거 configuration 수정, 학생별 configuration, color snapshot, 전체 Virtue versioning framework는 포함하지 않는다.

## 학생 일일 기록

- 학생은 starter의 Classroom token/QR, 학생 선택, PIN 인증 흐름을 재사용한다.
- 이름, 학년, 반, 번호를 직접 입력하지 않고 로그인한 Student identity를 사용한다.
- 학생당 하루 하나의 일일 성장 기록만 존재한다.
- 학생 입력 화면은 현재 active Virtue 목록을 직접 기준으로 삼지 않고, 위 Classroom 날짜별 configuration에 따라 자기 Classroom의 오늘 effective configuration으로 구성한다. 학생은 그 덕목을 각각 1~5점으로 자기평가한다.
- 기록을 저장하려면 해당 기록에 포함되는 덕목 점수를 모두 선택한다.
- 성찰 또는 오늘의 생각은 선택 입력이다.
- `입력완료`는 해당 학생의 오늘 성장 기록이 저장되었음을 뜻하며 성찰 작성 여부에는 의존하지 않는다.
- 점수는 행동 중심 표현을 사용한다.

| 점수 | 표현 |
|---:|---|
| 1 | 거의 실천하지 못했어요 |
| 2 | 조금 실천했어요 |
| 3 | 보통이에요 |
| 4 | 잘 실천했어요 |
| 5 | 아주 잘 실천했어요 |

- 오늘 기록은 저장 후 같은 날 다시 수정할 수 있다.
- 같은 날 다시 수정할 때는 확정된 Classroom 날짜 configuration의 score 구성과 표시 이름을 유지하고, 허용 범위 안에서 score 값과 reflection만 수정한다.
- 날짜가 지나면 학생은 과거 기록을 수정할 수 없으며 read-only로 조회한다.
- 학생은 기록 날짜를 직접 선택하지 않는다. create/update 대상은 application 기준 `오늘`의 자기 기록이다.
- 학생이 parameter를 조작해 과거 또는 미래 날짜의 기록을 생성·수정할 수 없어야 한다.
- 과거 기록은 숫자 표보다 입력 당시 UI와 유사한 read-only 자기평가 화면으로 보여준다.
- 과거 read-only 화면은 해당 날짜에 확정된 Classroom configuration의 덕목과 표시 이름을 사용한다. 현재 Virtue 이름으로 바꾸거나 현재 active 덕목 목록으로 과거 기록을 재구성하지 않는다.
- 이전/다음은 기록이 존재하는 날짜 사이를 이동하고, 오늘로 돌아오면 현재 editable 상태와 자연스럽게 연결되는 방향을 기본으로 한다.
- prototype은 기존 application `Time.zone`을 날짜 기준으로 사용하며 별도의 학교별 timezone은 추가하지 않는다.
- prototype에서는 주말·휴일 여부만으로 오늘 기록 입력을 별도 차단하지 않는다.

## 종합 성장점수

종합 성장점수는 해당 날짜에 실제 존재하는 덕목 점수의 산술평균이며 항상 1.0~5.0 범위다. 덕목 수가 바뀌어도 같은 scale로 비교할 수 있도록 raw 합계를 장기간 비교 지표로 사용하지 않는다.

```text
독서 4 / 봉사 3 / 감사 5
→ 종합 4.0 / 5

독서 4 / 봉사 4 / 감사 5 / 배려 3
→ 종합 4.0 / 5
```

종합은 source score에서 계산 가능한 derived metric으로 우선 취급하며 total score column 저장을 미리 확정하지 않는다. 덕목 구성이 다른 날짜도 척도는 같지만 측정 구성에는 차이가 있다. prototype에서는 별도 시각적 change marker를 구현하지 않는다.

주간 chart에서 `종합`을 표시할 때만 이 평균을 `종합 평균 / 5 × 100`으로 환산한다. 예를 들어 평균 4.0은 80%다. 이 percentage는 저장 컬럼이 아닌 display-derived metric이며 canonical 종합 성장점수의 1.0~5.0 정의를 변경하지 않는다.

## 학생 성장 추이

- 학생용 공통 navigation의 `성장` 항목은 학생 자신의 주간 성장 추이 화면으로 연결한다. `오늘` 입력 화면과 후속 `월간` 화면의 역할은 변경하지 않는다.
- 기본 주와 이전/다음 주 이동은 월요일부터 일요일까지의 calendar week를 기준으로 한다. 기본 화면은 application 기준 오늘이 포함된 현재 주이며 이전 주와 다음 주로 이동할 수 있다. 현재 주에서는 미래 주로 이동하는 다음 주 navigation을 제공하지 않거나 비활성화한다.
- 주간 chart와 weekly presentation의 표시 범위는 월요일부터 금요일까지 5일이다. 토요일과 일요일은 X축과 주간 표시 범위에서 제외하며, 주말 기록이 존재해도 chart에 표시하지 않는다. 이는 visualization 정책으로, `DailyGrowthRecord` domain의 주말·휴일 입력 허용 정책은 변경하지 않는다.
- metric navigation은 `[종합] [독서] [봉사] [감사] ...` 형태로 전환하며 기본 metric은 `종합`이다. 현재 active 덕목을 기본으로 노출하고, 사용 종료된 덕목도 주간 chart 표시 범위인 월요일부터 금요일 사이에 실제 score가 존재하면 조회할 수 있어야 한다. 구체적인 Tailwind 표현은 구현 단계에서 정한다.
- weekly metric의 Virtue identity·조회 구조와 색상 정책은 유지한다. metric navigation처럼 Virtue 자체를 선택하는 UI는 현재 Virtue 이름을 사용할 수 있지만, historical DailyGrowthRecord의 내용을 표시할 때는 해당 날짜에 확정된 Classroom configuration의 이름이 canonical source다. 현재 이름을 사용하는 선택 UI가 과거 configuration을 변경하지는 않는다.
- `종합` chart는 해당 날짜의 canonical 종합 평균을 percentage로 환산하여 표시하고 Y축은 0~100%로 둔다. 의미 있는 tick은 0/20/40/60/80/100%를 기본으로 한다.
- 개별 덕목 chart의 Y축은 0~5다. 실제 score는 1..5만 존재하며 Y축의 0은 시각적 baseline일 뿐 score 0을 의미하지 않는다.
- 색상 기능의 승인 contract에 따라 `종합` graph는 Virtue palette와 시각적으로 구분되는 product 고정색을, 개별 덕목 graph의 line과 point marker는 위 Virtue 색상 정책의 저장된 현재 색상을 사용한다. metric navigation의 작은 color indicator/swatch는 선택 사항이며 구체 UI는 구현 단계에서 결정한다.
- 기록이 없는 날짜와 record는 있지만 선택한 덕목 score가 없는 날짜는 모두 0점이 아닌 데이터 없음으로 취급한다. 새 덕목은 실제 score가 처음 생긴 날짜부터 나타나며, 데이터 없음과 실제 낮은 점수를 시각적으로 혼동시키지 않는다.
- 첫 prototype은 `suksuk_praise` 학생 주간 dashboard의 SVG graph visual을 최대한 그대로 재사용한다. 월~금 5개 point 위치, viewBox/spacing/grid, 두꺼운 둥근 line/path, 원형 point marker, 날짜/요일 배치와 이전/다음 주 navigation 패턴을 재사용하되 praise/coupon 전용 icon·marker·count와 summary card는 가져오지 않으며 새 chart library를 추가하지 않는다.
- 월간 visualization, 교사 학급 통계 chart, realtime, Action Cable/Turbo 변경, score 저장 방식 변경, 새 DB column/model, ranking, 학생 간 비교, arbitrary 기간 선택 UI와 chart library 도입 확정은 이 prototype의 범위가 아니다.

## Monthly visualization 후속 방향

Google Health Heart Points 스타일의 월간 달력 시각화는 지원 가능한 일일 score/date 구조를 유지하되 첫 prototype 범위에서는 후속 기능으로 둔다.

- 기본 metric은 종합 성장점수다.
- navigation에서 개별 덕목을 선택할 수 있다.
- 날짜별 점수를 원의 크기 등으로 표현하고, 덕목 생성 전 날짜는 원 없음 또는 데이터 없음으로 표시한다.
- 월간 raw 누계보다 월 평균(1~5)과 기록 일수를 우선한다.
- 날짜의 원에서 해당 날짜의 read-only 성장 기록으로 이동할 수 있다.
- 이 기능을 위해 별도 저장 모델을 미리 추가하지 않고 일일 score/date에서 계산할 수 있어야 한다.

## 교사 Classroom workflow와 realtime

담임교사는 자기 current Classroom에서 오늘의 완료 수와 대상 학생별 입력 상태를 확인한다.

```text
오늘 기록 23 / 28 완료

1 김가은   입력완료
2 김민준   입력완료
3 박서준   미입력
```

- 학생의 오늘 기록은 DB 저장이 성공한 뒤 Turbo Stream/Action Cable로 해당 학급 담임 화면의 상태를 `입력완료`로 갱신한다.
- 담임은 완료 상태에서 해당 학생의 오늘 기록을 확인할 수 있다.
- 교사용 detail은 학생 history UI보다 compact summary 형태를 허용한다.
- Action Cable은 canonical data source가 아니다. broadcast를 놓쳐도 새로고침하면 DB 상태와 일치해야 한다.
- prototype에는 polling fallback을 추가하지 않는다.

## 교사 학급 통계

prototype은 다음 통계를 제공한다.

- 오늘 입력 완료 수 / 전체 대상 학생 수
- 날짜별 학급 종합 평균
- 날짜별 각 덕목 평균
- 종합 / 덕목별 line chart 탐색

학생 개인 통계와 학급 통계는 같은 source score를 사용한다.

- 오늘 입력률 denominator는 현재 active Student 수를 기준으로 한다.
- 오늘 미입력인 active Student도 입력률 denominator에는 포함한다.
- 날짜별 종합/덕목 평균은 실제 저장된 score만 집계한다.
- 미입력 Student나 해당 덕목 score가 없는 Student를 0점으로 간주하지 않는다.
- 같은 날짜에 학생별 덕목 구성이 달라도 각 덕목 평균은 그 덕목 score가 실제 존재하는 기록만 사용한다.
- Student가 이후 inactive가 되더라도 이미 저장된 과거 기록은 유지한다.

ranking, 점수순 학생 정렬과 학생 간 경쟁은 MVP 범위 밖이다.

## 교사용 학생 성장기록 조회

- Classroom에서 Student를 선택했을 때의 canonical 조회 surface는 `/classrooms/:classroom_id/students/:id`다. 별도의 `/classrooms/:classroom_id/students/:student_id/growth` 조회 route를 만들지 않는다.
- 이 Student show의 주된 책임은 권한 있는 사용자가 해당 Student의 성장기록을 read-only로 확인하는 것이다. 학생 계정·구성원 관리 상세 화면과 성장기록 조회 화면을 이중으로 두지 않는다.
- 해당 Classroom에 속한 Student만 Classroom scope를 통해 조회하며, 담임, 해당 SchoolYear의 school manager, global admin이 아래 Authorization에 따라 접근할 수 있다.
- Student가 저장한 DailyGrowthRecord / DailyGrowthScore와 날짜별 frozen configuration을 canonical source로 사용한다.
- 오늘 기록이 없으면 미입력 상태를 표시하고, 오늘 기록이 있으면 학생 입력 화면과 같은 덕목·점수·성찰 구성을 read-only로 보여준다. 덕목 이름은 오늘 frozen configuration의 이름을 사용한다.
- 교사, school manager, global admin은 이 Student show에서 Student 대신 score나 reflection을 입력하거나 수정할 수 없다.
- 학생 자신의 `/student/growth_record`는 자기 Student session을 사용하는 입력·수정 entry point로 유지한다. 교사용 Student show와 같은 성장기록 presentation을 재사용할 수 있지만, 학생용 write 동작은 계속 current_student를 대상으로 하는 StudentGrowthRecordsController가 담당한다.
- Student의 이름, 번호, 아바타, PIN, 활성 상태 등 계정·구성원 관리 책임은 기존 edit 및 구성원 관리 흐름에 유지한다. 성장기록 read 권한을 가진 school manager에게 이러한 Student 관리 권한까지 자동으로 부여하지 않는다.
- 향후 오늘 입력 현황에서 Student를 선택하는 링크는 `/classrooms/:classroom_id/students/:id`를 대상으로 한다. realtime/Turbo/Action Cable 현황 갱신은 별도 feature에서 구현한다.

## Authorization

서버측 권한은 starter의 policy, scope와 controller/domain validation 원칙을 재사용한다.

- Student는 자기 기록만 생성하고 당일 수정하며 과거 기록을 조회할 수 있다.
- 현재 active SchoolYear / active School / active Classroom을 전제로, current HomeroomAssignment의 담임 teacher는 담당 Classroom의 성장기록 운영 권한을 가진다.
- school manager는 자기 current annual SchoolYear에 속한 모든 active Classroom에서, global admin은 모든 active School / active SchoolYear / active Classroom에서 같은 성장기록 운영 권한을 가진다.
- 성장기록 운영 권한에는 Classroom 덕목 조회·추가·rename·색상 수정·사용 종료, Student 입력 여부 조회, 저장된 Student 성장기록의 read-only 조회와 학급 성장 통계 조회가 포함된다.
- school manager와 global admin의 덕목 변경도 담임과 같은 Classroom lock 및 날짜별 configuration 적용·freeze·history 규칙을 따른다. 과거 기록이나 configuration을 rewrite하지 않는다.
- school manager는 다른 SchoolYear 또는 다른 학교의 Classroom에 접근할 수 없고, 일반 teacher는 담당하지 않는 Classroom의 성장기록 domain에 접근할 수 없다.
- Student는 계속 자기 기록만 접근한다. 직접 URL과 parameter 조작으로 다른 Student, Classroom, SchoolYear 또는 학교까지 scope를 넓힐 수 없다.
- inactive School, archived 또는 non-current SchoolYear, inactive Classroom에 대한 starter의 기존 권한 경계를 확대하지 않는다.

## 데이터와 history invariants

- `student + recorded_on`당 daily record는 최대 하나다.
- `daily record + virtue`당 score는 최대 하나다.
- score는 1..5다.
- daily record에는 최소 하나 이상의 score가 존재한다.
- `Classroom + recorded_on`에는 하나의 virtue configuration만 존재하며 모든 학생 record는 동일한 Virtue 구성과 표시 이름을 따른다. history의 canonical source와 확정·적용 시점은 위 Classroom 날짜별 configuration 규칙을 따른다.
- 덕목 활성 상태가 바뀌어도 과거 score가 가리키는 덕목 의미는 사라지지 않는다.
- 새 덕목 생성 이전 날짜에 score 0을 자동 보충하지 않는다.
- 첫 DailyGrowthRecord 생성으로 확정된 날짜와 과거 날짜의 configuration 및 DailyGrowthRecord / DailyGrowthScore는 teacher 설정 변경으로 rewrite하지 않는다. Virtue identity 관계도 보존한다.
- 날짜가 지난 기록은 Student가 update할 수 없다.
- Student가 임의의 `recorded_on`을 지정하여 과거·미래 기록을 생성하거나 수정할 수 없다.
- total/average는 해당 날짜에 실제 존재하는 score만 사용한다.
- daily record의 당시 Classroom 귀속은 이후 Student의 현재 Classroom이 바뀌더라도 보존되어야 한다.
- realtime 상태와 DB canonical state를 분리한다.

새 날짜별 configuration 정책에 필요한 기존 데이터 migration/backfill은 implementation 단계에서 안전하게 처리해야 한다. 정확한 model/table/column 이름, DB index, check constraint와 migration 설계는 이 문서에서 확정하지 않는다.

## Prototype non-goals

이번 성장기록 운영 권한과 교사용 조회 계약의 구현 범위에는 다음을 포함하지 않는다.

- 교사, school manager, global admin의 Student 대신 입력 또는 수정과 Student impersonation
- school manager 권한의 다른 SchoolYear 또는 다른 학교 확대
- 과거 DailyGrowthRecord / DailyGrowthScore / configuration 수정
- 새로운 role, generic permission framework, admin 전용 별도 성장기록 시스템
- realtime/Turbo/Action Cable 현황 갱신과 polling fallback
- 통계, ranking, 월간 기능 구현
- 교사용 Student show의 과거 기록 목록·탐색

- starter의 planning/archived SchoolYear 완성
- rollover
- `/admin/teachers` planning-year bulk bootstrap
- `/admin/classrooms` planning-year bulk configuration
- 월간 bubble calendar 실제 구현
- 고급 비교 분석
- 학생 ranking과 점수순 정렬
- 자동 평가 또는 AI 판정
- 부모 계정과 부모 조회
- Excel/CSV export
- push notification
- realtime polling fallback
- service-specific 복잡한 gamification
- 성장점수 누적 경쟁과 leaderboard

## Open Questions

현재 prototype 구현을 막는 미결 정책은 없다.

구현 과정에서 이 spec과 충돌하거나 새로운 제품 정책 결정이 필요하면 임의로 우회 구현하지 않고 spec을 먼저 다시 검토한다.

## Prototype acceptance criteria

1. 기존 current Classroom과 새 Classroom에 기본 덕목 `독서`, `봉사`, `감사`가 중복 없이 제공된다.
2. 담임은 자기 active Classroom의 active 덕목을 1개 이상, 최대 5개까지 관리하고 Student 성장기록을 조회할 수 있다.
3. school manager는 자기 current annual SchoolYear의 active Classroom에서 담임과 같은 성장기록 운영 권한을 가진다.
4. global admin은 active School / active SchoolYear / active Classroom에서 같은 성장기록 운영 권한을 가진다.
5. 일반 teacher는 담당하지 않는 Classroom의 덕목과 Student 성장기록에 접근할 수 없고, school manager는 자기 SchoolYear 범위를 벗어날 수 없다.
6. 권한 있는 사용자가 active 덕목을 변경해도 이미 저장된 Student 기록과 날짜별 configuration은 소급 변경되지 않으며 기존 Classroom + 날짜 configuration/history/color 계약을 유지한다.
7. 오늘 Classroom의 날짜별 configuration이 아직 확정되지 않았다면 첫 저장 시점의 current active 덕목으로 오늘 configuration을 확정하고, 이미 확정되어 있다면 아직 기록하지 않은 학생도 그 frozen configuration으로 기록한다.
8. 학생은 자기 오늘 기록의 덕목을 1~5점으로 평가하여 저장할 수 있으며 성찰은 선택 사항이다.
9. 학생은 임의의 과거·미래 날짜를 지정하여 기록할 수 없다.
10. 학생은 같은 날 자기 기록을 다시 수정할 수 있으며 기존 기록의 덕목 구성을 유지한다.
11. 지난 기록은 학생에게 read-only다.
12. 학생은 다른 학생 기록에 접근할 수 없다.
13. 학생 저장 후 성장기록 운영 권한이 있는 사용자의 Classroom 현황 화면이 realtime으로 완료 상태를 반영한다.
14. 새로고침한 완료 상태는 DB canonical state와 일치한다.
15. 성장기록 운영 권한이 있는 사용자는 완료 학생의 오늘 기록을 read-only로 확인할 수 있다.
16. `/classrooms/:classroom_id/students/:id`는 권한 있는 사용자를 위한 Classroom-scoped Student 성장기록 read-only surface이며, 별도의 Student growth 조회 route를 두지 않는다. 권한 있는 사용자는 이 화면에서 Student 대신 입력하거나 수정할 수 없다.
17. 향후 오늘 입력 현황의 Student 링크는 `/classrooms/:classroom_id/students/:id`를 대상으로 한다.
18. 학생은 종합 및 덕목별 line chart를 확인할 수 있고 과거 score가 있는 사용 종료 덕목의 추이도 확인할 수 있다.
19. 종합 성장점수는 해당 기록에 실제 존재하는 score의 산술평균이다.
20. 덕목이 중간에 추가되어도 과거 또는 기존 기록에 0점을 자동 보충하지 않는다.
21. 성장기록 운영 권한이 있는 사용자는 현재 active Student 기준 입력률과 실제 저장 score 기준 종합·덕목별 기본 추이를 확인할 수 있다.
