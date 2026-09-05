# Annual Teacher User Migration

## 목적

이 문서는 [`school_year_architecture.md`](school_year_architecture.md)의 Phase 2를 구체화한다. 현재 teacher `User`와 `SchoolMembership` 구조를 SchoolYear별 annual teacher User로 안전하게 전환하기 위한 schema, data migration과 source cutover 경계를 정의한다.

최종 로그인 UI 전체나 SchoolYear 하위 도메인 전환은 이 문서의 범위가 아니다. Phase 1의 `SchoolYear` foundation은 [`school_year_foundation.md`](school_year_foundation.md)를 따른다.

## Current와 target

현재 구조는 다음과 같다.

```text
User
├── role: admin | teacher | student
├── email / encrypted_password
├── active
└── has_one SchoolMembership
     ├── school_id
     ├── role: member | manager
     └── grade
```

현재 Devise는 email/password로 teacher와 admin을 인증한다. Teacher의 school, school role과 grade 조회, policy scope, lifecycle, classroom assignment와 관리 service는 `SchoolMembership`에 직접 의존한다.

장기 target은 다음과 같다.

```text
User
├── global admin: SchoolYear 비종속
└── teacher: 정확히 하나의 SchoolYear에 속하는 annual account
     ├── school_year_id
     ├── login_id / encrypted credential
     ├── school_role: member | manager
     ├── grade
     └── active

Student
└── 후속 phase에서 User와 분리
```

Teacher User 하나는 사람의 영구 identity가 아니라 한 SchoolYear의 teacher account다. 같은 사람이 다음 해에도 근무하면 새 User를 발급하며 이름, email, `login_id`, avatar 등으로 연도간 동일인을 추론하거나 자동 연결하지 않는다.

Global admin User는 SchoolYear에 종속되지 않는다. Student User는 이번 phase에 그대로 남고 teacher annual field를 요구하지 않는다.

## Target field 책임

Teacher User는 `school_year_id`를 통해 School scope를 얻는다.

```text
teacher.school_year.school
```

별도 `school_id`를 User에 중복 저장하지 않는다. 현재 `SchoolMembership.school_id`는 compatibility 기간에만 유지한다.

School 내부 역할은 `school_role`을 사용한다. Teacher User 자체가 이미 한 SchoolYear에 종속되므로 필드마다 `annual`을 반복하지 않으면서도 기존 identity kind인 `User.role`과 의미를 즉시 구분할 수 있다.

```text
User.role        → admin | teacher | student
User.school_role → member | manager (teacher only)
```

`grade`는 annual teacher 운영 정보이며 `nil` 또는 integer `1..6`이다. Manager, 비담임 teacher와 학년 미배정 teacher를 지원하기 위해 required로 만들지 않는다.

## Compatibility schema

첫 schema migration은 기존 row와 runtime을 깨지 않도록 다음 nullable column을 `users`에 준비한다.

```text
school_year_id: nullable foreign key
login_id: nullable string
school_role: nullable string
grade: nullable integer
```

Global admin과 student User에는 이 값들이 없다. Existing teacher도 explicit backfill 전까지 nil일 수 있으므로 Phase 2A에서는 role-dependent `NOT NULL`을 적용하지 않는다.

DB는 compatibility 상태에서도 다음을 방어한다.

- `school_year_id`는 `school_years` foreign key이며 cascade delete하지 않는다.
- `(school_year_id, login_id)`는 두 값이 존재할 때 unique다.
- `school_role`은 `NULL`, `member`, `manager`만 허용한다.
- `grade`는 `NULL` 또는 `1..6`만 허용한다.
- 같은 SchoolYear의 manager annual role은 최대 한 명이다.

Teacher만 annual field를 가져야 하고 target teacher는 SchoolYear, `login_id`, `school_role`이 필요하다는 최종 role-dependent DB CHECK는 기존 teacher backfill과 cutover가 완료된 뒤 추가한다. Phase 2A에 이를 먼저 적용하면 현재 teacher와 student/admin 공존 schema를 깨뜨린다.

## Login ID

`login_id`는 teacher authentication identifier이며 email이나 영구 사람 identity가 아니다.

```text
UNIQUE (school_year_id, login_id)
```

같은 SchoolYear의 같은 `login_id`는 금지하고 다른 SchoolYear에서는 재사용할 수 있다. Phase 2A는 column과 DB invariant만 준비하며 authentication lookup은 바꾸지 않는다. Normalization과 case 처리 등 credential 입력 세부 규칙은 Phase 2C authentication spec에서 확정한다.

Existing teacher의 `login_id`를 email, 이름이나 다른 profile에서 자동 생성하지 않는다. 기존 teacher cutover에는 명시적으로 준비된 `login_id`가 필요하다.

## Email과 credential continuity

Global admin User의 email은 계속 필수 authentication identifier다. Teacher User는 target에서 email을 인증에 사용하지 않으며 School-scoped `login_id + password`로 인증한다. `users.email` column은 global admin 인증과 optional contact data를 위해 유지할 수 있다.

Teacher email은 optional contact/profile data다. Existing teacher email은 migration 중 자동 삭제하지 않으며 값이 남아 있어도 authentication lookup에 사용하지 않는다. Phase 2A와 2B에서는 current Devise email/password login을 보존하기 위해 `users.email`의 nullability, global unique index, Devise validation과 authentication key를 즉시 변경하지 않는다.

`encrypted_password`, Devise password hashing과 session machinery는 teacher annual credential에도 재사용하는 것을 기본 방향으로 한다. Phase 2C에서 teacher lookup을 School-scoped `login_id`로 전환하되 global admin의 system authentication과 student PIN/token flow를 함께 바꾸지 않는다.

Teacher email optionalization과 global admin email requirement 분리는 실제 login cutover인 Phase 2C에서 함께 수행한다. Planning teacher를 email 없이 정상 생성하는 것도 이 경계 이후에 허용한다.

`password_change_required`는 temporary-password authentication이 실제로 사용하는 Phase 2C에 추가한다. Phase 2A에서 사용되지 않는 auth state를 미리 추가하지 않는다.

## School role과 manager cardinality

기존 `SchoolMembership.role`의 `member/manager`는 target `User.school_role`로 이동한다. 같은 SchoolYear에서 manager teacher User는 `0..1`이다.

DB는 개념적으로 다음 partial unique index로 경쟁 조건을 방어한다.

```text
UNIQUE school_year_id
WHERE role = 'teacher'
  AND school_role = 'manager'
  AND school_year_id IS NOT NULL
```

Model validation은 사용자 친화적 오류를 위한 보조 방어다. Manager 지정·해제 authorization과 UI는 이번 phase에서 변경하지 않는다.

## SchoolMembership compatibility와 source cutover

`SchoolMembership`은 Phase 2에서 즉시 삭제하지 않는다. 현재 controller, policy, navigation context, teacher save service와 integrity audit가 school, role과 grade를 이 model에서 읽고 쓴다.

Source는 단계별로 하나만 명확히 둔다.

1. Phase 2A에서는 `SchoolMembership`이 current runtime authoritative source다. 새 User columns는 nullable compatibility schema다.
2. Phase 2B는 명시적 mapping으로 새 columns를 backfill하고 old/new projection 일치 여부를 감사한다. 새 fields는 migration/shadow state이며 runtime authorization, query와 write의 authoritative source는 계속 `SchoolMembership`이다.
3. Phase 2C 직전에 `SchoolMembership`의 current values를 기준으로 final reconciliation과 integrity audit를 수행한다.
4. Phase 2C는 teacher authentication, authorization과 annual authority read/write를 User columns로 한 번에 cutover한다. 이 시점부터 annual teacher User가 single source of truth이고 SchoolMembership은 compatibility residue다.
5. 충분한 검증 뒤 별도 cleanup phase에서 SchoolMembership association, query, index와 table을 제거한다.

Backfill과 cutover 사이에 teacher school/role/grade 변경을 계속 허용하면 두 projection이 어긋날 수 있다. 기본 전략은 짧은 controlled cutover와 직전 final reconciliation이며, 모든 mutation을 양쪽에 쓰는 temporary dual-write layer를 만들지 않는다. 이는 source-of-truth 모호성, drift, debugging 비용과 제거할 transitional code를 줄인다.

실제 운영상 2B와 2C를 장기간 분리 배포해야 해서 dual-write가 반드시 필요하다는 증거가 생기면 해당 implementation spec에서 별도 사용자 결정을 받는다. 어떤 경우에도 두 source를 장기간 authoritative하게 병행하지 않는다.

## Existing teacher mapping과 backfill

Phase 1은 기존 School에 SchoolYear를 자동 생성하지 않았다. 따라서 Phase 2가 모든 existing teacher를 임의의 현재 연도에 연결해서는 안 된다.

권장 절차는 다음과 같다.

1. School별 대상 active SchoolYear를 운영자가 명시적으로 확인하거나 생성한다.
2. Existing teacher의 `SchoolMembership.school_id`와 대상 SchoolYear의 School이 같은지 검증한다.
3. `school_year_id`, `school_role`, `grade`를 기존 membership에서 backfill한다.
4. `login_id`는 명시적으로 제공된 mapping만 사용하며 추론하지 않는다.
5. 누락, 다른 School, duplicate login ID와 manager 충돌이 있으면 임의 선택하지 않고 중단한다.
6. Backfill 결과와 현재 membership projection을 감사한 뒤 authentication/source cutover를 승인한다.

Existing teacher User는 선택된 SchoolYear의 annual User가 된다. 과거 학년도 User를 새로 발명하거나 한 User를 여러 SchoolYear에 연결하지 않는다. 다음 SchoolYear teacher User는 planning bootstrap에서 별도 생성한다.

각 existing teacher의 `school_year_id`, `login_id`, `school_role`, `grade`는 명시적으로 준비된 mapping source를 통해 설정한다. 그 입력은 bootstrap data, 관리자가 검토한 mapping 또는 controlled one-off input일 수 있으며 정확한 mechanism은 Phase 2B implementation spec에서 정한다. Migration은 현재 날짜, 가장 최근 year, active SchoolYear 존재, 이름, email, `login_id`나 classroom grade로 business meaning을 추측하지 않는다.

## Planning과 archived teacher User

Planning SchoolYear에는 다음 해 teacher User를 생성할 수 있어야 한다. Schema는 planning status를 이유로 teacher row 생성을 거부하지 않는다. Planning account의 normal runtime login 차단은 Phase 2C authentication policy 책임이다.

Archived SchoolYear의 teacher User는 삭제하거나 다른 연도 User로 바꾸지 않는다. 과거 Classroom, 작성 기록과 향후 HomeroomAssignment가 당시 User를 계속 참조할 수 있어야 한다. Archived login과 read-only enforcement는 후속 phase다.

## User.active

Teacher User의 `active`는 해당 annual account 자체의 사용 가능 상태다. 이는 `SchoolYear.status`와 별개다.

- Teacher User inactive는 개별 annual account의 인증·운영을 차단한다.
- SchoolYear planning/active/archived는 학년도 전체 operation context를 결정한다.
- SchoolYear archive는 teacher User를 자동 inactive로 바꾸지 않는다.

Compatibility 기간에는 현재 teacher lifecycle과 `Classroom.teacher_id` 해제 behavior를 유지한다. HomeroomAssignment 도입 뒤 assignment lifecycle 효과는 해당 phase spec에서 다시 정렬한다.

## Historical User FK 영향

현재 active schema에서 teacher User를 직접 참조하는 핵심 관계는 `Classroom.teacher_id`이며, `SchoolMembership.user_id`와 student용 `ClassroomMembership.user_id`도 같은 users table을 참조한다. 현재 starter에는 한 teacher User가 여러 SchoolYear에 걸쳐 재사용돼야 한다는 schema invariant가 없다.

Annual teacher User는 과거 record가 당시 User를 그대로 참조하게 하므로 historical 의미를 보존한다. Migration과 cleanup은 기존 User FK를 다른 연도 User로 재지정하거나 teacher User를 삭제해서는 안 된다. `Classroom.teacher_id`는 HomeroomAssignment phase 전까지 current runtime 관계로 유지한다.

## 추천 migration sub-phases

### Phase 2A — Compatibility schema foundation

- Nullable `school_year_id`, `login_id`, `school_role`, `grade` 추가
- Foreign key, grade/role CHECK와 login/manager partial unique index 추가
- Existing Devise, User validation과 SchoolMembership source 유지
- Existing data backfill과 authentication 변경 없음

### Phase 2B — Explicit mapping and backfill

- School별 initial SchoolYear와 teacher mapping을 명시적 입력으로 확정
- Existing membership의 school/role/grade를 User annual fields로 backfill
- Explicit `login_id` mapping 적용
- 충돌 보고와 rollback-safe data migration
- 새 fields는 shadow state로 유지하고 SchoolMembership을 authoritative source로 유지
- SchoolMembership 삭제 없음

### Phase 2C — Authentication and authority cutover

- Teacher authentication을 School-scoped `login_id` lookup으로 전환
- Global admin authentication과 student PIN/token flow 분리 유지
- `password_change_required`, temporary password와 rate limiting 도입
- Teacher annual field에 role-dependent validation/DB CHECK 적용
- Policy, scope, service와 navigation read/write source를 User annual fields로 전환
- Cutover 직전 SchoolMembership 기준 final reconciliation과 integrity audit 수행
- Cutover 뒤 annual teacher User를 single source of truth로 사용
- Planning login 차단과 existing email-login cutover를 한 배포 경계로 검증

Legacy SchoolMembership 제거는 2C 검증 뒤 별도 cleanup이다.

## Migration risks

| Risk | Why | Safe direction |
|---|---|---|
| Devise email requirement와 global uniqueness | Teacher와 admin이 같은 table과 Devise config를 공유한다 | 2A/2B에서 변경하지 않고 2C에서 admin email 인증과 optional teacher contact를 분리한다 |
| `User.role`과 school role 혼동 | 하나는 account kind, 다른 하나는 SchoolYear authority다 | 의미가 직접 드러나는 별도 `school_role` 이름과 허용값 CHECK를 사용한다 |
| SchoolMembership 제거에 따른 runtime 파손 | Policy, service, scope와 lifecycle이 직접 의존한다 | 새 source cutover 및 audit 전에는 table과 association을 유지한다 |
| Existing teacher의 SchoolYear/login ID 불명확 | Phase 1이 current year를 추정하거나 생성하지 않았다 | 명시적 School/year/login mapping 없이는 backfill하지 않는다 |
| User FK의 historical 의미 손상 | Classroom 등 기존 record가 당시 teacher를 참조한다 | User 삭제·교체 없이 annual row 자체를 보존한다 |
| Planning teacher의 우발적 login | Schema는 planning teacher 생성을 허용해야 한다 | 2C authentication lookup에서 active SchoolYear만 normal login 대상으로 삼는다 |
| Manager 경쟁 조건 | Model validation만으로 동시 승격을 막지 못한다 | SchoolYear별 manager partial unique index를 둔다 |
| Student와 admin의 같은-table 공존 | Teacher-only required field를 즉시 NOT NULL로 만들 수 없다 | Nullable compatibility columns 후 role-dependent CHECK를 cutover 때 적용한다 |

## Acceptance criteria

1. Global admin User는 SchoolYear 비종속으로 유지한다.
2. Teacher User는 target에서 정확히 하나의 SchoolYear에 속한다.
3. Student User는 Phase 2에서 유지되고 teacher annual field를 요구하지 않는다.
4. Teacher User는 매 SchoolYear 별도 row이며 연도간 동일인을 자동 연결하지 않는다.
5. 같은 SchoolYear의 `login_id`는 중복될 수 없고 다른 SchoolYear에서는 재사용할 수 있다.
6. Teacher의 `school_role`은 `member` 또는 `manager`이며 `User.role`과 구분한다.
7. 같은 SchoolYear의 manager teacher User는 최대 한 명이다.
8. Grade는 teacher User의 nullable annual 정보로 이동하며 `1..6`만 허용한다.
9. Teacher의 School은 `school_year.school`로 resolve하고 User에 `school_id`를 중복 저장하지 않는다.
10. SchoolMembership은 source cutover와 검증 전에 삭제하지 않는다.
11. Teacher email은 target authentication requirement가 아니며, 값이 남아 있으면 optional contact/profile data다.
12. Phase 2A/2B 직후 current `/users/sign_in` email/password login은 계속 동작한다.
13. Existing teacher를 임의의 SchoolYear에 backfill하거나 login ID를 추론하지 않고 명시적 mapping source만 사용한다.
14. Planning SchoolYear의 teacher User row를 schema가 허용한다.
15. Archived SchoolYear의 teacher User와 historical FK를 보존한다.
16. SchoolYear archive는 `User.active`를 자동 변경하지 않는다.
17. Phase 2A와 2B에서는 SchoolMembership이 authoritative runtime source이고 새 fields는 shadow state다.
18. Phase 2C 직전에 SchoolMembership 기준 final reconciliation과 integrity audit를 수행한다.
19. Cutover 뒤 annual teacher User가 authentication, authorization과 annual authority read/write의 single source of truth다.
20. Temporary dual-write compatibility layer를 기본 전략으로 도입하지 않는다.

## Non-goals

- Student 모델 분리와 StudentEnrollment
- Classroom의 `school_year_id`, `class_label`과 HomeroomAssignment 구현
- Manager school-wide authorization 구현
- Rollover와 archived read-only UI/enforcement
- Historical reports
- 최종 login form과 UI 구현
- Temporary-password UI와 bulk teacher UI
- SchoolYear UI와 `/admin/*` 재설계
- Downstream service-specific domain
- Legacy SchoolMembership의 즉시 삭제

## Open questions

현재 Phase 2 architecture 수준의 미해결 정책은 없다.

세부 mapping mechanism과 cutover operation은 Phase 2B/2C implementation spec에서 결정한다. Route/controller 이름, migration class와 index 이름, temporary password 형식 같은 구현 세부는 architecture Open Question이 아니다.

## 예상 구현 파일

### 2A

```text
db/migrate/..._add_annual_fields_to_users.rb
app/models/user.rb
spec/models/user_spec.rb
db/schema.rb
```

### 2B

```text
db/migrate/..._backfill_annual_teacher_users.rb
app/services/school_structure/integrity_audit.rb (필요한 경우)
관련 migration/audit spec
```

### 2C

```text
app/models/user.rb
config/initializers/devise.rb
app/controllers/users/sessions_controller.rb
app/controllers/application_controller.rb
app/policies/*
app/services/teachers/*
db/migrate/..._enforce_annual_teacher_constraints.rb
관련 model/request/policy/service specs
```

정확한 파일과 배포 경계는 각 sub-phase spec 승인 뒤 최소 확인한다.
