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
- 담임교사는 자기 current Classroom의 덕목을 추가, 편집, 사용 종료할 수 있다.
- 학생 입력 화면에 노출되는 active 덕목은 최대 5개다. 기본 3개에 최대 2개를 추가하는 UX를 기본으로 한다.
- Classroom은 성장 기록을 위해 최소 1개의 active 덕목을 유지해야 하며 마지막 active 덕목은 사용 종료할 수 없다.
- 5개 제한은 active 덕목 수에 대한 domain/application invariant이며 DB를 5개 점수 column으로 고정하지 않는다.
- 과거 기록이 있는 덕목은 hard delete하지 않는다. 사용 종료 후에도 과거 기록에서 의미를 보존한다.
- 단순 오타나 표현 수정은 rename할 수 있으며 과거 기록에도 현재 이름을 표시하는 방향을 기본으로 한다.
- 의미가 다른 덕목으로 교체할 때는 rename보다 기존 덕목 사용 종료 후 신규 덕목 추가를 기본 원칙으로 한다.
- 덕목과 일일 점수는 별도 row 관계를 가져 입력 당시 덕목 구성을 보존할 수 있어야 한다. 구체 model과 schema 이름은 구현 단계에서 정한다.
- 담임은 필요할 때 active 덕목을 추가하거나 사용 종료할 수 있다.
- 이미 저장된 학생의 일일 기록은 이후 Classroom의 active 덕목 변경 때문에 자동으로 추가·삭제되지 않는다.
- 아직 기록하지 않은 학생은 기록을 처음 저장할 때의 active 덕목을 기준으로 자기평가한다.
- 같은 날짜라도 덕목 변경 전후에 저장한 학생의 평가 항목 수가 다를 수 있으며, 이를 이유로 기존 제출을 무효화하거나 미제출 학생의 기록을 강제 생성하지 않는다.

## 학생 일일 기록

- 학생은 starter의 Classroom token/QR, 학생 선택, PIN 인증 흐름을 재사용한다.
- 이름, 학년, 반, 번호를 직접 입력하지 않고 로그인한 Student identity를 사용한다.
- 학생당 하루 하나의 일일 성장 기록만 존재한다.
- 학생은 기록을 처음 저장할 때 적용되는 덕목을 각각 1~5점으로 자기평가한다.
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
- 같은 날 다시 수정할 때는 처음 저장된 기록의 덕목 구성을 유지한다. 그 사이 새로 추가되거나 사용 종료된 학급 덕목을 기존 기록에 자동 반영하지 않는다.
- 날짜가 지나면 학생은 과거 기록을 수정할 수 없으며 read-only로 조회한다.
- 학생은 기록 날짜를 직접 선택하지 않는다. create/update 대상은 application 기준 `오늘`의 자기 기록이다.
- 학생이 parameter를 조작해 과거 또는 미래 날짜의 기록을 생성·수정할 수 없어야 한다.
- 과거 기록은 숫자 표보다 입력 당시 UI와 유사한 read-only 자기평가 화면으로 보여준다.
- 과거 화면은 해당 날짜에 실제 평가한 덕목만 보여준다. 현재 active 덕목으로 과거 기록을 재구성하지 않는다.
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

## 학생 성장 추이

- 학생은 자신의 기록을 line chart로 확인할 수 있다.
- 첫 prototype은 쑥쑥칭찬통장에서 사용했던 line chart 패턴의 재사용을 우선 고려한다.
- metric navigation은 `[종합]`과 현재 active 덕목을 기본으로 구성하며, 과거 score가 존재하는 사용 종료 덕목의 추이도 조회할 수 있어야 한다.
- 구체적인 navigation 표현은 구현 단계에서 정하며 기본 metric은 `종합`이다.
- 종합과 개별 덕목의 Y축은 모두 1~5다.
- 덕목 생성 전 날짜나 해당 덕목 score가 없는 날짜는 0점이 아니라 데이터 없음이다.
- 새 덕목 line은 실제 평가가 시작된 시점부터 나타난다.
- 최대 5개 덕목과 종합 navigation은 모바일에서 horizontal scroll 가능한 UI를 고려한다. 구체 Tailwind 구현은 이 spec에서 정하지 않는다.

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

## Authorization

서버측 권한은 starter의 policy, scope와 controller/domain validation 원칙을 재사용한다.

- Student는 자기 기록만 생성하고 당일 수정하며 과거 기록을 조회할 수 있다.
- 담임 teacher는 current HomeroomAssignment로 담당하는 자기 active Classroom의 덕목을 관리하고, 학생 입력 현황, 기록과 학급 통계를 조회할 수 있다.
- 다른 Student 또는 다른 Classroom의 직접 URL과 parameter 조작으로 scope를 넓힐 수 없다.
- school manager 또는 global admin이라는 운영 역할만으로 학생의 성장 점수와 성찰 기록 조회 권한을 자동으로 부여하지 않는다.
- 성장기록 domain의 교사 권한은 current HomeroomAssignment를 기준으로 한다.
- 관리자용 성장기록 조회나 지원 기능은 필요할 경우 별도 spec에서 결정한다.

## 데이터와 history invariants

- `student + recorded_on`당 daily record는 최대 하나다.
- `daily record + virtue`당 score는 최대 하나다.
- score는 1..5다.
- daily record에는 최소 하나 이상의 score가 존재한다.
- 저장된 daily record에는 그 기록을 처음 저장할 때 평가한 덕목 score가 존재한다.
- 덕목 활성 상태가 바뀌어도 과거 score가 가리키는 덕목 의미는 사라지지 않는다.
- 새 덕목 생성 이전 날짜에 score 0을 자동 보충하지 않는다.
- Classroom의 active 덕목 변경은 이미 저장된 daily record의 덕목 구성을 소급 변경하지 않는다.
- 날짜가 지난 기록은 Student가 update할 수 없다.
- Student가 임의의 `recorded_on`을 지정하여 과거·미래 기록을 생성하거나 수정할 수 없다.
- total/average는 해당 날짜에 실제 존재하는 score만 사용한다.
- daily record의 당시 Classroom 귀속은 이후 Student의 현재 Classroom이 바뀌더라도 보존되어야 한다.
- realtime 상태와 DB canonical state를 분리한다.

정확한 DB index, check constraint, model과 migration 설계는 implementation 단계에서 정한다.

## Prototype non-goals

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
2. 담임은 자기 active Classroom의 active 덕목을 1개 이상, 최대 5개까지 관리할 수 있다.
3. 담임이 active 덕목을 변경해도 이미 저장된 학생 기록의 덕목 구성은 소급 변경되지 않는다.
4. 아직 기록하지 않은 학생은 저장 시점의 active 덕목으로 오늘 기록을 작성할 수 있다.
5. 학생은 자기 오늘 기록의 덕목을 1~5점으로 평가하여 저장할 수 있으며 성찰은 선택 사항이다.
6. 학생은 임의의 과거·미래 날짜를 지정하여 기록할 수 없다.
7. 학생은 같은 날 자기 기록을 다시 수정할 수 있으며 기존 기록의 덕목 구성을 유지한다.
8. 지난 기록은 학생에게 read-only다.
9. 학생은 다른 학생 기록에 접근할 수 없다.
10. 학생 저장 후 담임 Classroom 화면이 realtime으로 완료 상태를 반영한다.
11. 새로고침한 완료 상태는 DB canonical state와 일치한다.
12. 담임은 완료 학생의 오늘 기록을 확인할 수 있다.
13. 학생은 종합 및 덕목별 line chart를 확인할 수 있고 과거 score가 있는 사용 종료 덕목의 추이도 확인할 수 있다.
14. 종합 성장점수는 해당 기록에 실제 존재하는 score의 산술평균이다.
15. 덕목이 중간에 추가되어도 과거 또는 기존 기록에 0점을 자동 보충하지 않는다.
16. 담임은 현재 active Student 기준 입력률과 실제 저장 score 기준 종합·덕목별 기본 추이를 확인할 수 있다.