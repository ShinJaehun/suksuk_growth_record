# Classroom SchoolYear Migration

## 목적

`Classroom`의 school context를 직접 `School` 소속에서 `SchoolYear` 소속으로 옮기고,
현재 `name`을 canonical `class_label`로 정리한다. 이 문서는 안전한 schema/data/runtime
cutover 계약과 구현 결과를 기록한다.

## Current state

현재 `Classroom`은 필수 `school_id`, 필수 `grade`, nullable `name`, `active`, nullable
`teacher_id`와 student login token을 가진다. `School#classrooms`와
`Classroom#school`이 school scope의 기준이다. School은 DB상 active SchoolYear가 0개일
수 있고 partial unique index로 최대 1개만 가질 수 있다. 신규 운영 School 생성과 seed는
active SchoolYear를 만들지만 과거 또는 비정상 data까지 정확히 하나임을 보장하지 않는다.

현재 `name`은 반 식별자 전용으로 제한되지 않는다.

- seed: `1반`, `2반`
- factory: `Classroom N`
- specs/UI data: `1반`, `2반`, `가`, `4학년 1반`, `6학년 기러기반`, `새싹 학급`,
  `상세 학급 이름`, `2학년 지정 교실` 등
- model: presence validation 없이 최대 50자만 검사
- form: “교실 이름”, 예시 “4학년 1반”
- helper: grade prefix가 없으면 `grade학년 + name`을 표시하고 이미 있으면 중복하지 않음

따라서 현재 `name` 전체를 단순 suffix 제거만으로 의미 보존된 반 label이라고 추정할 수
없다.

## Target state

```text
School
└── SchoolYear
    └── Classroom
        ├── grade
        ├── class_label
        ├── active
        └── teacher_id
```

Classroom은 정확히 하나의 `SchoolYear`에 속한다. School은
`classroom.school_year.school`로만 결정하고 별도 `school_id`를 남기지 않는다.
`SchoolYear#classrooms`를 canonical collection으로 사용하며 School 단위 조회는
`school.school_years`를 통해 명시적인 year scope를 선택한다.

최종 canonical fields는 다음과 같다.

- `school_year_id`, required
- `grade`, integer `1..6`
- `class_label`, required normalized string
- `active`, required boolean
- `teacher_id`, nullable이며 이번 phase에서 유지

## Dependency inventory

### Runtime scope와 authorization

`ClassroomPolicy::Scope`, manager scope, classroom index school filter와 School workspace
count가 `school_id` 또는 `School#classrooms`를 사용한다. Student/teacher policy와 navigation은
`classroom.school.active?`를 상위 lifecycle 경계로 사용한다. 전환 후에는
`joins(school_year: :school)`, `school_year_id`와 `classroom.school_year.school`을 사용한다.
현재 active 운영 surface는 active SchoolYear classroom만 반환하고 planning/archived row로
fallback하지 않는다.

### CRUD, form과 query

Classroom create는 admin이 School을 선택하거나 manager의 annual School을 사용하고,
update는 `school_id` 변경을 금지한다. Teacher/classroom picker, school teacher 관리,
School dashboard와 index preload가 `School#classrooms`, `classroom.school_id`, `:school`
include/join/order를 사용한다. 전환 후 선택한 School의 정확히 하나인 active SchoolYear를
server가 resolve해 `school_year_id`를 지정한다. Persisted classroom의 SchoolYear는 일반
CRUD에서 변경하지 않는다. Query와 preload는 `SchoolYear#classrooms` 및
`classroom.school_year.school`로 교체한다.

Form parameter는 내부 column 이름을 노출하지 않고 계속 “학교”, “학년”, “반”을 사용한다.
`name` parameter와 validation/presentation은 `class_label`로 교체하되 label은 “반”, 저장값
표시는 `class_label + "반"`으로 한다. 학년은 별도 UI 값으로 유지한다.

### Teacher assignment

Classroom model, teacher save service와 candidate query는 현재 teacher annual School과
`Classroom.school_id`를 비교한다. 전환 후 동일 School만으로는 충분하지 않으며 teacher와
Classroom의 `school_year_id`가 정확히 같아야 한다.

### Student login/session

Student token/PIN, existing-session validation과 student policy는 active Classroom 및
`classroom.school.active?`를 검사한다. Student `ClassroomMembership`, token과 PIN 계약은
유지하고 상위 조건만 active `classroom.school_year` 및 active
`classroom.school_year.school`로 바꾼다. Planning/archived classroom에서는 student login과
일반 student mutation을 fail closed한다.

### Integrity audit

Teacher assignment audit sample과 mismatch query가 `classrooms.school_id`를 사용한다.
전환 후 classroom/teacher `school_year_id`를 직접 비교하고 sample의 School은 양쪽
SchoolYear join으로 계산한다. Student ClassroomMembership role audit은 그대로 유지한다.

### Seed, factory와 specs

Seed와 factory는 School과 `name`으로 Classroom을 만든다. 전환 후 명시적인 SchoolYear와
normalized `class_label`을 사용한다. Request/model/policy/helper specs의 school scope,
School association, `name` validation·parameter·표시 assertion은 새 source와 “반” 표시
계약으로 교정한다. Historical migrations와 phase 문서는 당시 schema 기록으로 보존한다.

## Existing Classroom backfill policy

Existing Classroom마다 현재 `classrooms.school_id`가 가리키는 School의 active SchoolYear가
정확히 하나여야 한다. 그 row만 `classroom.school_year_id`로 사용한다.

- active SchoolYear 0개: 중단
- active SchoolYear 2개 이상: DB invariant 위반으로 중단
- planning/archived year 선택 금지
- 현재 날짜, School 생성일이나 최신 year로 추론 금지
- SchoolYear 자동 생성 금지

Backfill은 Classroom ID 순서처럼 결정적인 순서로 수행할 수 있지만, 실패를 건너뛰거나
일부 School만 완료 상태로 간주하지 않는다. 모든 preflight가 먼저 통과한 뒤 transaction
안에서 수행한다.

## class_label normalization

입력은 다음 순서로 normalize한다.

1. 앞뒤 공백을 제거한다.
2. 끝의 `반` 한 글자를 제거한다.
3. 다시 앞뒤 공백을 제거한다.
4. 결과가 비면 거부한다.

```text
"1"      -> "1"
"1반"    -> "1"
" 가반 " -> "가"
"햇살반" -> "햇살"
"반디"   -> "반디"
```

내부 또는 시작 부분의 `반`은 제거하지 않는다. Model normalization을 canonical write
boundary로 두고 DB는 required/nonblank, length와 uniqueness를 방어한다. 기존 50자 제한은
normalized 저장값에도 유지하며 normalization 뒤 50자를 넘으면 거부한다.

## Existing name data policy

SQL preflight는 각 `name`에 동일 normalization을 계산하고 다음을 fail-fast한다.

- `name IS NULL` 또는 blank
- normalization 뒤 blank
- normalization 뒤 50자 초과
- 같은 target SchoolYear와 grade 안에서 normalized value collision

예를 들어 같은 학년도/학년에 `1`과 `1반`이 함께 있으면 둘 다 `1`이 되므로 중단한다.
Migration은 suffix를 여러 번 제거하거나 rename, 번호 부여 또는 충돌 row 선택을 하지
않는다.

Migration은 설명형 이름인지 의미가 애매한 이름인지 heuristic으로 판정하지 않는다.
운영자는 migration 전에 `id, school_id, grade, name, normalized_class_label` 목록을 별도로
검토한다. Migration은 객관적인 invariant만 검사하고 grade prefix나 `학급`/`교실` 표현을
임의 제거하지 않는다.

2026-09-06 development DB 사전 검토에서 기존 3개 Classroom은 각각 `1반 -> 1`,
`2반 -> 2`, `11 -> 11`로 확인했고 active SchoolYear 누락·중복과 normalization collision은
없었다. Production에서도 같은 객관적 preflight를 migration이 다시 수행한다.

## DB invariants

최종 DB는 다음을 보장한다.

- `school_year_id NOT NULL`, foreign key to `school_years`
- `grade NOT NULL`, integer `1..6` check 유지
- `class_label NOT NULL`, blank/canonical storage 방어
- normalized `class_label` 최대 50자
- unique `(school_year_id, grade, class_label)`
- 서로 다른 SchoolYear에서는 같은 grade/class_label 허용
- `active NOT NULL`과 기존 default 유지
- nullable `teacher_id` FK와 partial unique index 유지

`school_id`와 `name`은 새 source의 constraints와 runtime cutover 검증 뒤 제거한다.

## Runtime cutover

- School scope: `classroom.school_year.school`
- Classroom collection: 명시적인 `SchoolYear#classrooms`
- Current School UI/query: 해당 School의 유일한 active SchoolYear scope
- Structure create/update: active SchoolYear에서만 허용
- Student login/operation: active School, active SchoolYear, active Classroom 필요
- Planning Classroom: 후속 planning bootstrap UI에서만 준비 가능
- Archived Classroom: 후속 historical surface에서 read-only

현재 route와 active UI는 SchoolYear selector를 새로 노출하지 않는다. Active SchoolYear가
정확히 하나가 아니면 create, candidate query와 normal runtime operation은 fail closed하며
planning/archived year로 fallback하지 않는다.

## Teacher assignment

Assignment는 다음을 모두 만족해야 한다.

- target User가 active teacher다.
- `teacher.school_year_id == classroom.school_year_id`다.
- 그 SchoolYear가 active이고 School도 active다.
- `teacher.grade == classroom.grade`이며 grade가 존재한다.
- Classroom이 active다.
- 기존 teacher/Classroom 1:1 cardinality를 만족한다.

같은 School의 다른 SchoolYear teacher를 배정할 수 없다. `Classroom.teacher_id`는 유지하며
`HomeroomAssignment`를 도입하지 않는다.

## Lifecycle

`Classroom.active`와 `SchoolYear.status`는 독립적이다. SchoolYear archive는 Classroom을
inactive로 바꾸지 않는다.

- active SchoolYear + active Classroom: 정상 current operation
- active SchoolYear + inactive Classroom: 기존 inactive lifecycle
- planning SchoolYear Classroom: 준비 data이며 student/ordinary runtime 금지
- archived SchoolYear Classroom: read-only

Current CRUD와 lifecycle action은 active SchoolYear만 mutation한다. Planning bootstrap,
rollover와 archived UI는 이번 phase에서 구현하지 않는다.

## Data preflight

Schema cutover 전에 read-only query/runner로 다음을 모두 확인한다.

1. 모든 Classroom에 현재 School이 있다.
2. 각 School에 active SchoolYear가 정확히 하나다.
3. 모든 `name`이 present하고 normalization 결과가 present이며 50자 이하다.
4. `(target school_year_id, grade, normalized_class_label)` collision이 없다.
5. 모든 assigned teacher가 Classroom의 target SchoolYear와 같은 `school_year_id`, 같은
   grade를 가지며 teacher/User, SchoolYear, School과 Classroom lifecycle 조건을 만족한다.
6. 운영자가 기존 name과 normalized candidate 목록의 의미 적합성을 사전에 확인했다.

오류는 관련 School/Classroom/User ID와 원인을 보고하고 전체 migration을 중단한다.
자동 SchoolYear 생성, name 의미 추정, rename, collision 해결 또는 partial backfill은 하지
않는다. 실제 development/production data 조회와 correction은 구현 승인 뒤 운영자가
수행한다.

## Acceptance criteria

1. Classroom은 최종적으로 정확히 하나의 SchoolYear에 속한다.
2. School은 `classroom.school_year.school`로만 결정한다.
3. Existing Classroom은 기존 School의 유일한 active SchoolYear로만 backfill한다.
4. Active SchoolYear가 정확히 하나가 아니면 migration이 fail-fast한다.
5. `class_label`은 strip, 끝의 단일 `반` 제거, 재-strip 순서로 normalize하며 blank를
   거부한다.
6. Blank, oversized normalized value와 같은 SchoolYear/grade normalization collision은
   fail-fast한다.
7. DB가 unique `(school_year_id, grade, class_label)`을 보장한다.
8. Teacher와 Classroom은 같은 School이 아니라 같은 SchoolYear여야 한다.
9. `Classroom.teacher_id`와 기존 1:1 cardinality는 유지한다.
10. Student User, `ClassroomMembership`, token과 PIN/session 구조를 유지한다.
11. `Classroom.active`와 `SchoolYear.status`를 독립 lifecycle로 유지한다.
12. Planning/archived Classroom의 normal runtime mutation과 student login을 fail closed한다.
13. `school_id`와 `name`은 새 source cutover와 dependency-zero 검증 뒤 제거한다.
14. UI는 “학교”, “학년”, “반”을 사용하고 내부 `SchoolYear`/`class_label` 이름을 노출하지
    않는다.
15. Historical migrations는 수정하거나 삭제하지 않는다.

## Implementation order

1. Nullable `school_year_id`와 `class_label` 및 FK/index 기반을 추가한다.
2. 전체 data preflight와 운영자 name mapping 검토를 완료한다.
3. 한 transaction에서 active SchoolYear와 normalized name을 backfill하고 결과를 검증한다.
4. Application association, scope, authorization, CRUD, assignment, student session,
   presentation, seed/factory/spec을 SchoolYear/class_label source로 cutover한다. 이 시점부터
   새 source만 읽고, 짧은 compatibility window에 필요한 old columns는 새 source에서
   파생해 쓸 수 있으나 fallback source로 읽지 않는다.
5. `school_year_id`, `class_label`, canonical/length 및 composite unique constraints를
   적용한다.
6. `school_id`/`name` runtime read/write와 데이터 mismatch가 0임을 검증한다.
7. 후속 cleanup migration에서 `school_id`, `name`, old FK/index를 제거하고 temporary
   compatibility write를 제거한다.

한 migration에서 nullable schema, data 의미 검증, application cutover와 old column drop을
동시에 처리하지 않는다.

## Non-goals

- `HomeroomAssignment` 또는 `Classroom.teacher_id` 제거
- Student model 분리, `StudentEnrollment` 또는 `ClassroomMembership` 제거
- planning bootstrap UI, rollover 또는 archived historical UI
- credential reissue 또는 teacher cross-School transfer
- automatic classroom copy, automatic promotion 또는 SchoolYear 자동 생성
- manager history, generic migration framework 또는 새 gem
