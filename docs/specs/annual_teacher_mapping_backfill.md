# Annual Teacher Mapping and Backfill

## 목적

이 문서는 [Annual Teacher User Migration](annual_teacher_user_migration.md)의
Phase 2B를 구체화한다. Phase 2A에서 준비한 nullable shadow field를 기존 teacher
User에 명시적으로 mapping하는 운영 경계를 정의한다.

```text
users.school_year_id
users.login_id
users.school_role
users.grade
```

Phase 2B는 authentication 또는 authorization cutover가 아니다. 완료 후에도
`SchoolMembership`이 current runtime의 authoritative source이며 User annual field는
2C 전환을 위해 검증된 shadow projection이다.

## 절대 원칙

Mapping operation은 business meaning을 추측하지 않는다. 다음 값으로 target
SchoolYear, teacher identity 또는 `login_id`를 자동 결정하지 않는다.

- 현재 날짜나 가장 최근 year
- active SchoolYear가 존재한다는 사실만으로 한 자동 연결
- teacher 이름, email, avatar 또는 profile
- classroom, classroom grade 또는 teacher assignment
- 기존 문자열과 유사한 `login_id`

운영자가 명시적으로 승인한 target SchoolYear와 mapping input만 사용한다. 잘못되거나
빠진 값을 자동 보정하거나 대상에서 조용히 제외하지 않는다.

## Mapping unit

하나의 batch는 정확히 하나의 target SchoolYear만 대상으로 한다. 따라서 School
scope도 `target_school_year.school` 하나로 고정된다.

```text
Target SchoolYear: 2026 / 쑥쑥초등학교

Teacher User #10 -> tara0411
Teacher User #12 -> apple09
```

SchoolYear 단위 batch는 school mismatch와 manager cardinality를 명확하게 검증하고,
실패 및 transaction rollback의 범위를 작게 유지한다. 여러 School 또는 SchoolYear를
하나의 전역 batch나 transaction에 섞지 않는다.

## Explicit input

Batch context와 각 row가 제공해야 할 값은 다음뿐이다.

```text
batch: target_school_year_id
row:   teacher_user_id, login_id
```

`school_role`과 `grade`를 mapping input에서 받지 않는다. 이 값은 operation 실행
시점의 authoritative `SchoolMembership`에서 읽는다.

```text
SchoolMembership.school_id -> target School 검증
SchoolMembership.role      -> User.school_role
SchoolMembership.grade     -> User.grade
```

실제 mapping data를 source-controlled migration이나 repository fixture에 하드코딩하지
않는다. Password, temporary credential과 email도 mapping input이나 결과 report에
포함하지 않는다.

## Input transport와 구현 형태

추천 구현은 Phase 2B 전용 service와 얇은 Rake task의 조합이다.

- 외부 local CSV는 `teacher_user_id`, `login_id` row만 전달한다.
- Rake task argument 또는 environment input은 target SchoolYear ID와 CSV path를
  명시한다.
- task는 파일 읽기, dry-run 선택과 결과 출력을 담당한다.
- service는 parsing이 끝난 명시적 row와 target SchoolYear를 받아 validation, lock,
  transaction 및 projection을 담당한다.

CSV는 단순한 tabular mapping에 충분하고 deployment-specific data를 repository에
남기지 않는다. Service를 분리하면 dry-run과 real run이 같은 preflight를 사용하고
domain behavior를 RSpec으로 검증할 수 있다. Generic ETL framework, 관리 UI 또는
schema/data migration은 만들지 않는다.

Mapping file은 source control 밖에서 관리하며 task가 자동으로 repository에 복사하거나
보존하지 않는다. 파일 권한과 전달 방식은 배포 환경의 운영 절차로 다룬다.

## Target SchoolYear

기존 current-runtime teacher backfill의 target은 `active` SchoolYear로 제한한다.

- `active`: 허용
- `planning`: 거부. 다음 학년도 teacher는 planning bootstrap에서 새 annual User로
  별도 생성한다.
- `archived`: 거부. 현재 teacher를 과거 연도에 소급 배정하지 않는다.

School에 active SchoolYear가 없더라도 날짜나 다른 year로 자동 대체하지 않는다.
운영자가 올바른 active SchoolYear를 먼저 명시적으로 준비해야 한다.

## Teacher와 membership eligibility

각 input row는 다음을 모두 만족해야 한다.

- User가 존재한다.
- `User.role == "teacher"`다.
- batch 안에서 같은 User ID가 한 번만 등장한다.
- User가 정확히 현재의 `has_one SchoolMembership`을 가지고 있다.
- `membership.school_id == target_school_year.school_id`다.
- Membership role은 현재 enum의 `member` 또는 `manager`다.
- Membership grade는 `nil` 또는 `1..6`이다.

Admin, student, membership이 없는 teacher와 다른 School의 teacher가 포함되면 batch
전체를 실패시킨다. 자동 skip이나 school/year 교정은 하지 않는다.

## login_id boundary

Phase 2B는 입력된 `login_id`의 exact string을 그대로 저장한다.

- blank 또는 whitespace-only 값은 거부한다.
- `login_id.strip != login_id`인 leading/trailing whitespace 입력도 거부한다.
- batch 안의 exact duplicate를 거부한다.
- target SchoolYear에서 같은 exact login ID를 다른 User가 가진 경우 거부한다.
- 대소문자 변환, strip, format 또는 length normalization을 수행하지 않는다.

Whitespace 입력을 거부할 때도 operation이 값을 자동 `strip`해서 저장하지 않는다.
현재 input teacher 자신의 shadow state가 requested target, exact login ID와 현재
membership projection에 모두 일치하면 self-collision이 아니라 `already_mapped`
no-op이다.

`Tara`와 `tara`의 최종 동일성은 2C authentication semantics다. Phase 2B preflight는
case-folding했을 때 충돌하는 ID를 결과에 위험으로 보고하되 자동 변환하거나 임의로
한쪽을 거부하지 않는다. 2C 정책 확정과 cutover 전 integrity audit에서 반드시
해소한다.

## Preflight

Validation과 mutation을 분리한다. Batch 전체를 읽은 뒤 다음을 모두 확인하기 전에는
어떤 User도 수정하지 않는다.

1. Target SchoolYear가 존재하고 `active`다.
2. 모든 input row에 User ID와 non-blank이며 leading/trailing whitespace가 없는
   `login_id`가 있다.
3. 모든 User가 존재하고 teacher다.
4. Input에 중복 User ID나 exact duplicate login ID가 없다.
5. 모든 teacher에게 SchoolMembership이 존재한다.
6. 모든 membership School이 target SchoolYear의 School과 같다.
7. Membership role과 grade가 허용 범위다.
8. Target SchoolYear에서 동일 login ID를 가진 다른 User와 충돌하지 않는다. 현재
   input User 자신의 정확히 동일한 completed mapping은 제외한다.
9. Input projection과 기존 shadow manager를 distinct teacher User ID로 합쳐 manager가
   최대 한 명이다.
10. Teacher가 다른 SchoolYear에 mapping되어 있지 않다.
11. 기존 annual field가 완전히 null이거나 정확히 동일한 완료 상태다.
12. Partial 또는 다른 shadow state가 없다.

정적 input 검증을 먼저 수행하고, transaction에서 관련 row를 lock한 뒤 DB-dependent
preflight를 다시 수행한다. 두 번째 검증도 모두 끝나기 전에는 update하지 않는다.

Preflight failure는 원인과 충돌 대상만 보고하고 batch 전체를 실패시킨다. 자동 skip,
부분 성공, role 강등, login ID 변경 또는 기존 shadow 값 overwrite는 하지 않는다.

## Existing shadow state와 idempotence

각 teacher의 네 annual field를 하나의 상태로 판단한다.

```text
모두 NULL
-> mapping 대상

school_year_id, login_id, school_role, grade가
requested target과 현재 membership projection에 정확히 일치
-> already mapped, no-op 성공

일부만 존재
-> inconsistent state, batch 실패

다른 target 또는 다른 값 존재
-> conflicting state, batch 실패
```

`grade = nil`은 값이 빠진 partial state가 아니라 유효한 projection이다. 완전성 판단은
`school_year_id`, `login_id`, `school_role`의 존재와 grade의 authoritative projection
일치 여부를 함께 사용한다.

동일 batch 재실행은 mapped row를 변경하지 않고 성공하며 `already_mapped`로 집계한다.
따라서 같은 User의 정확히 동일한 completed mapping은 existing login collision로
판정하지 않는다.
반면 mapping 후 SchoolMembership role/grade가 바뀌어 projection이 drift한 상태는
자동 갱신하지 않고 충돌로 실패한다. Drift 해소는 2C 직전 final reconciliation의
책임이다.

## Authoritative projection

실제 update 값은 lock 후 다시 읽은 현재 SchoolMembership에서 만든다.

```text
User.school_year_id = target_school_year.id
User.login_id       = explicit input login_id
User.school_role    = SchoolMembership.role 이름
User.grade          = SchoolMembership.grade
```

Input이 role 또는 grade를 포함하더라도 신뢰하거나 저장하지 않는다. Phase 2B 이후에도
runtime은 User의 projected role/grade를 읽지 않는다.

## Manager cardinality

Preflight는 mapping 대상의 projected manager와 target SchoolYear에 이미 존재하는
shadow manager를 distinct teacher User ID 기준으로 합친다. 동일 User가 existing
shadow manager이면서 input projected manager인 경우 한 명으로 계산하여 idempotent
no-op을 허용한다. 서로 다른 User ID가 둘 이상이면 전체 batch를 실패시킨다.

DB partial unique index는 동시성에 대한 최종 방어선이다. Operation은 충돌을 친화적으로
보고하되 임의로 manager를 선택하거나 다른 teacher를 `member`로 바꾸지 않는다.

## Atomicity와 locking

하나의 SchoolYear batch는 all-or-nothing이다.

```text
input/static preflight
-> transaction
-> target SchoolYear lock
-> 대상 User를 ID 순서로 lock
-> 해당 SchoolMembership을 ID 순서로 lock
-> DB-dependent preflight와 authoritative projection 재계산
-> 필요한 User update
-> integrity 확인
-> commit
```

고정된 lock 순서는 교착 가능성을 줄인다. Target SchoolYear lock은 같은 target의 2B
operation을 직렬화하고, User 및 membership row lock과 재검증은 현재 teacher 관리가
동시에 role/grade를 바꾸면서 stale projection을 만드는 것을 막는다. 전역 School이나
다른 SchoolYear까지 잠그지 않는다.

어느 update나 DB constraint가 실패해도 transaction 전체를 rollback한다. Phase 2B를
위해 장기간 dual-write나 sync callback을 추가하지 않는다.

## Dry-run과 결과 report

Operation은 mutation 없는 validation-only/dry-run을 지원한다. Dry-run은 real run과
같은 parser와 preflight 규칙을 사용하며 update 단계만 수행하지 않는다. 별도 validation
구현을 만들지 않는다. 그러나 dry-run 성공은 이후 real run 성공을 보장하지 않는다.
두 실행 사이에 User, SchoolMembership 또는 shadow state가 바뀔 수 있기 때문이다.
Real run은 transaction과 lock을 획득한 뒤 DB-dependent preflight와 authoritative
SchoolMembership projection을 반드시 다시 수행하고, dry-run 결과를 신뢰해 이를
생략하지 않는다.

결과는 최소한 다음을 보고한다.

- target SchoolYear와 School
- requested count
- mapped count
- already-mapped count
- 성공 여부와 failure reason
- 충돌한 User ID 또는 login ID
- case-fold collision 등 2C 전 해소할 위험

Password, credential, 불필요한 profile 정보는 출력하지 않는다. 정확한 console 형식과
logging destination은 implementation detail이다.

## Rollback과 reset

다음 세 의미를 구분한다.

- Operation 도중 실패: DB transaction rollback으로 batch mutation이 남지 않는다.
- Phase 2A schema rollback: schema migration의 책임이며 2B task와 무관하다.
- 성공한 mapping 취소: 자동 destructive reset command를 기본 제공하지 않는다.

2C 전에 shadow mapping을 되돌려야 할 실제 운영 사유가 생기면 대상과 현재 상태를
재검증하는 별도 controlled operation/runbook을 승인받아 수행한다. 일반적인 `clear all`
task나 mapping input을 이용한 자동 overwrite는 만들지 않는다.

## Phase 2C 경계와 drift

Phase 2B 성공 후에도 source 관계는 다음과 같다.

```text
SchoolMembership = authoritative runtime source
User annual fields = shadow projection
```

Policy가 `User.school_role`을 읽거나, controller가 `User.grade`를 읽거나, teacher save가
annual field를 dual-write하거나, login이 `User.login_id`를 사용하는 변경은 금지한다.

2B 이후의 legitimate SchoolMembership mutation으로 shadow drift가 생길 수 있다.
이를 임시 sync layer로 해결하지 않는다. 2C 직전에 SchoolMembership current value를
기준으로 final reconciliation과 integrity audit를 수행하고, 그 결과가 완전히 유효할
때 authentication/authorization/read-write source를 annual teacher User로 한 번에
전환한다.

## Verification strategy

후속 implementation은 다음 최소 시나리오를 검증한다.

### 성공

- Valid teacher mapping과 SchoolYear/login ID 저장
- Current SchoolMembership role/grade projection
- `grade = nil` projection
- 동일 batch 재실행의 no-op 성공
- 정확히 동일한 completed mapping의 login ID가 self-collision으로 실패하지 않음
- 동일 User인 existing/input manager를 중복 집계하지 않음
- dry-run에서 동일 validation 결과와 mutation 없음
- dry-run 뒤 상태가 바뀌면 real run이 lock 아래에서 다시 검증함

### 실패와 mutation 없음

- Unknown User와 non-teacher User
- Missing SchoolMembership과 School mismatch
- Duplicate User input, blank 또는 leading/trailing whitespace login ID
- 다른 User가 소유한 duplicate/colliding login ID
- 서로 다른 User 사이의 manager conflict
- Partial/inconsistent shadow state
- 다른 SchoolYear 또는 다른 값의 existing mapping
- Transaction 중 한 row 실패 시 전체 rollback

### Continuity

- Backfill 후에도 SchoolMembership 기반 runtime 유지
- Existing email/password login 변경 없음
- Admin과 student annual field 변경 없음

## Acceptance Criteria

1. Mapping은 하나의 explicit target SchoolYear 단위로 수행한다.
2. Teacher User와 login ID는 명시적 mapping input에서만 얻는다.
3. SchoolYear를 날짜, active 여부 또는 profile에서 자동 추론하지 않는다.
4. `school_role`과 `grade`는 실행 시 authoritative SchoolMembership에서 projection한다.
5. Teacher User만 mapping할 수 있다.
6. Membership School과 target SchoolYear School이 같아야 한다.
7. 전체 preflight가 mutation 전에 완료된다.
8. Batch는 all-or-nothing transaction이다.
9. 같은 target SchoolYear에서 다른 User가 동일 login ID를 소유하면 전체 batch가
   실패하고, 자신의 정확히 동일한 completed mapping은 self-collision으로 보지 않는다.
10. Manager cardinality는 distinct teacher User ID 기준이며, 서로 다른 manager User가
    충돌하면 전체 batch가 실패한다.
11. Partial 또는 다른 existing mapping을 자동 overwrite하지 않는다.
12. 정확히 동일한 mapping 재실행은 no-op 성공한다.
13. 실패한 batch의 mutation은 남지 않는다.
14. 실제 mapping data를 repository source에 하드코딩하지 않는다.
15. Phase 2B 후에도 SchoolMembership이 authoritative runtime source다.
16. Temporary dual-write나 sync callback을 추가하지 않는다.
17. Devise와 login flow를 변경하지 않는다.
18. Admin과 student row를 변경하지 않는다.
19. 2C 직전 final reconciliation과 integrity audit 책임을 유지한다.
20. Credential, password 또는 email을 mapping input/report에 포함하지 않는다.
21. Blank, whitespace-only 및 leading/trailing whitespace login ID를 자동 수정하지 않고
    거부한다.
22. Dry-run 성공 여부와 무관하게 real run은 lock 아래에서 DB-dependent preflight와
    authoritative projection을 다시 수행한다.

## Non-goals

Phase 2C authentication cutover, login UI, teacher email optionalization, password
change/reset, temporary password, SchoolMembership source cutover/delete,
role-dependent final DB CHECK, manager authority expansion, next-year teacher bulk UI,
Classroom SchoolYear migration, HomeroomAssignment, Student 분리, StudentEnrollment,
rollover, archived login/reporting, service-specific data 및 generic ETL framework는
이번 phase에 포함하지 않는다.

## 예상 구현 파일

- `app/services/annual_teacher_users/mapping_backfill.rb`
- `lib/tasks/annual_teacher_users.rake`
- `spec/services/annual_teacher_users/mapping_backfill_spec.rb`

Input example이나 실제 mapping file은 repository에 추가하지 않는다. Phase 2A schema가
이미 존재하므로 Phase 2B에는 migration이나 schema 변경이 필요하지 않다.

## Open Questions

Phase 2B 수준의 미해결 정책 없음.
