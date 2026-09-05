# Annual Teacher Schema Foundation

## 목적

이 문서는 [School Year Architecture](school_year_architecture.md)와
[Annual Teacher User Migration](annual_teacher_user_migration.md)의 Phase 2A를 구체화한다.

Phase 2A는 annual teacher target을 위한 nullable compatibility schema만 `users`에
준비한다. 기존 데이터를 매핑하거나 현재 인증·권한의 source of truth를 전환하지
않는다.

## Phase 경계

Phase 2A 완료 시에도 현재 runtime의 authoritative source는 `SchoolMembership`이다.
다음 동작은 그대로 유지한다.

- teacher의 email/password Devise 인증
- `SchoolMembership` 기반 학교, `role`, `grade` 조회와 권한 판단
- `Classroom.teacher_id` 기반 담임 관계
- student 역할의 `User`와 ClassroomMembership 기반 PIN/token 인증
- 기존 `User.active` lifecycle

새 annual field는 비어 있을 수 있는 compatibility/shadow schema다. Policy,
controller, service 및 기존 query는 이 값을 읽거나 쓰기 시작하지 않는다.

## 추가 schema

`users`에 다음 네 column을 추가한다.

| Column | Type | Null | Phase 2A 의미 |
| --- | --- | --- | --- |
| `school_year_id` | bigint foreign key | 허용 | 향후 annual teacher User가 속할 SchoolYear |
| `login_id` | string | 허용 | 향후 School-scoped teacher 인증 ID |
| `school_role` | string | 허용 | 향후 연도별 학교 역할 (`member`, `manager`) |
| `grade` | integer | 허용 | 향후 연도별 담당 학년 (`1..6`) |

네 column은 모두 nullable이어야 한다. 기존 teacher는 아직 explicit mapping 전이며,
global admin과 현재 student User는 annual field의 대상이 아니기 때문이다.

## SchoolYear relation

`users.school_year_id`는 `school_years`를 참조하는 nullable foreign key다.

- foreign key에 cascade delete를 설정하지 않는다.
- Phase 2A의 `User`에는 `belongs_to :school_year, optional: true`만 추가한다.
- teacher 필수, admin/student 금지와 같은 role-dependent validation은 추가하지 않는다.
- SchoolYear/User 삭제 lifecycle을 바꾸는 `dependent` option이나 callback을 추가하지 않는다.

Optional association은 schema 관계를 명시하고 후속 explicit mapping을 읽기 쉽게 하기
위한 최소 model API다. 아직 annual teacher runtime을 선언하는 의미는 아니다.

## login_id

`login_id`는 nullable string이며 Phase 2A에서는 normalization, 대소문자 정책,
format, length 및 authentication lookup을 정의하지 않는다. 이 정책은 2C
authentication spec에서 확정한다.

DB는 `(school_year_id, login_id)` composite unique index로 다음을 보장한다.

- 같은 SchoolYear의 같은 non-null `login_id`는 허용하지 않는다.
- 다른 SchoolYear에서는 같은 `login_id`를 허용한다.
- PostgreSQL의 일반 unique index NULL semantics에 따라 기존의 여러 null
  `login_id` row를 허용한다.

별도 partial condition이나 `NULLS NOT DISTINCT`는 사용하지 않는다. 둘 중 하나가
null인 row는 Phase 2A의 미매핑 compatibility state이기 때문이다.

## school_role

`school_role`은 `User.role`과 다른 개념이다.

- `User.role`: 현재 account kind/system role (`student`, `teacher`, `admin`)
- `school_role`: 향후 annual school authority (`member`, `manager`)

`school_role`은 nullable string이고 DB CHECK로 `NULL`, `member`, `manager`만
허용한다. Phase 2A에서는 enum, predicate, scope 또는 model validation을 추가하지
않는다. 사용되지 않는 shadow field를 runtime API처럼 노출하거나 현재
`SchoolMembership.role`과 혼동하지 않기 위해서다.

## grade

`users.grade`는 nullable integer다. DB CHECK는 `NULL` 또는 `1..6`만 허용한다.
현재 runtime에서는 계속 `SchoolMembership.grade`만 사용하며 `User#grade`를 읽거나
쓰는 흐름을 추가하지 않는다.

## Manager cardinality

장기 invariant인 SchoolYear별 manager teacher User 최대 한 명을 DB에서 미리
보호한다. PostgreSQL partial unique index의 개념은 다음과 같다.

```text
UNIQUE (school_year_id)
WHERE role = 'teacher'
  AND school_role = 'manager'
  AND school_year_id IS NOT NULL
```

이 index는 경쟁 조건에서도 manager를 두 명 만들 수 없게 한다. Phase 2A에서는
manager assignment, authorization, UI 또는 source cutover를 구현하지 않는다.

## DB constraints

DB가 다음 무결성의 최종 방어선이다.

- nullable foreign key: `users.school_year_id -> school_years.id`, cascade 없음
- unique index: `(school_year_id, login_id)`
- CHECK: `school_role IS NULL OR school_role IN ('member', 'manager')`
- CHECK: `grade IS NULL OR grade BETWEEN 1 AND 6`
- partial unique index: SchoolYear별 teacher `school_role = 'manager'` 최대 한 명

다음 role-dependent constraint는 2A에 추가하지 않는다.

```text
teacher -> school_year_id/login_id/school_role required
admin/student -> annual fields absent
```

기존 teacher mapping이 끝나지 않은 상태에서 이 제약을 적용하면 current runtime과
기존 데이터를 깨뜨린다. 2B mapping과 2C cutover 경계에서 적용 여부를 결정한다.

## Model validation 경계

Phase 2A에서는 `belongs_to :school_year, optional: true` 외 annual field용 model
validation을 추가하지 않는다.

- shadow field를 입력하는 현재 사용자 흐름이 없어 친화적 validation error가 아직
  필요하지 않다.
- DB CHECK와 unique index가 schema integrity를 보장한다.
- model validation은 2C의 실제 create/update flow와 오류 표시 요구가 확정될 때
  함께 추가한다.

특히 `school_role` enum이나 login/cardinality validation을 미리 추가해 현재
authorization source가 바뀐 것처럼 보이게 하지 않는다.

## Existing data와 source of truth

Phase 2A migration은 schema-only migration이다. 다음 data mutation을 수행하지
않는다.

- SchoolYear 자동 생성
- 기존 teacher의 `school_year_id` backfill
- `login_id` 생성 또는 email에서 추론
- `SchoolMembership.role`을 `school_role`로 복사
- `SchoolMembership.grade`를 `users.grade`로 복사

Phase 2A와 2B 동안 `SchoolMembership`이 authoritative source다. 새 field에 대한
dual-write, sync callback 또는 reconciliation callback을 만들지 않는다. 2B에서
명시적 mapping을 shadow state로 준비하고, 2C 직전 최종 reconciliation과 integrity
audit 후 한 번에 source를 전환한다.

## Runtime continuity

### Teacher

기존 teacher의 annual field가 모두 null이어도 email/password 로그인,
SchoolMembership 권한 및 classroom assignment가 이전과 동일하게 동작해야 한다.

### Global admin

Global admin은 annualization 대상이 아니다. 네 annual field가 모두 null인 상태에서
기존 email/password 인증과 system authority가 유지되어야 한다.

### Student

현재 student User도 네 annual field가 모두 null인 상태로 정상 동작해야 한다.
PIN/token 인증 및 student credential clearing logic을 변경하지 않는다.

## Email과 credential

Phase 2A에서는 `users.email`, `encrypted_password`, Devise modules,
`email_required?`, authentication keys 및 session flow를 변경하지 않는다.
Teacher email optionalization과 `login_id + password` cutover는 2C 책임이다.

`password_change_required`, temporary password 및 reset/reissue state도 2A에 추가하지
않는다.

## FK, deletion과 rollback

SchoolYear 삭제가 annual teacher User를 cascade-delete해서는 안 된다. Phase 2A는
새로운 physical-delete UI나 association lifecycle side effect를 만들지 않는다.
참조 row가 생긴 뒤에는 cascade 없는 FK가 SchoolYear 삭제로 인한 teacher history
유실을 방지한다.

Data backfill이 없는 additive schema migration으로 작성하며, column, index, CHECK와
foreign key를 정상적으로 제거할 수 있는 rollback 구조를 유지한다.

## DB constraint regression 방향

후속 implementation spec은 최소한 다음 DB 방어를 직접 검증한다.

- 존재하지 않는 SchoolYear 참조 거부
- 같은 SchoolYear의 non-null `login_id` 중복 거부와 다른 SchoolYear 재사용 허용
- 잘못된 `school_role` 거부
- 범위를 벗어난 `grade` 거부
- 같은 SchoolYear의 두 번째 manager teacher 거부
- annual field가 null인 기존 global admin/student row 허용

Raw SQL/insert helper를 반복하지 않고, model validation을 우회해 DB constraint가 최종
방어선임을 확인하는 최소 regression으로 제한한다.

## Acceptance Criteria

1. `users.school_year_id`를 nullable foreign key로 준비한다.
2. `users.login_id`를 nullable string으로 준비한다.
3. `users.school_role`을 nullable string으로 준비한다.
4. `users.grade`를 nullable integer로 준비한다.
5. `school_year_id` foreign key에는 cascade delete가 없다.
6. 같은 SchoolYear의 같은 non-null `login_id` 조합은 DB에서 거부한다.
7. 다른 SchoolYear에서는 같은 `login_id`를 허용한다.
8. 기존 row 여러 개의 null `login_id`를 허용한다.
9. `school_role`은 DB에서 null, `member`, `manager`만 허용한다.
10. `grade`는 DB에서 null 또는 `1..6`만 허용한다.
11. 한 SchoolYear의 manager teacher 최대 한 명을 DB partial unique index로 보호한다.
12. role-dependent required constraint나 validation을 추가하지 않는다.
13. 기존 data를 backfill하거나 추론하지 않는다.
14. `SchoolMembership`을 current runtime source로 유지한다.
15. 현재 teacher email/password 로그인을 유지한다.
16. 현재 global admin 동작을 유지한다.
17. 현재 student PIN/token 동작을 유지한다.
18. policy, controller, service의 source를 변경하지 않는다.
19. `SchoolMembership`과 annual field 사이 temporary dual-write를 추가하지 않는다.
20. `password_change_required`를 추가하지 않는다.

## Non-goals

Phase 2A에서는 existing teacher mapping/backfill, SchoolYear 자동 생성, 실제
`login_id` 인증, School-scoped login, teacher email optionalization, temporary
password, `password_change_required`, SchoolMembership read/write cutover, manager
school-wide authorization, role-dependent required CHECK, Classroom의 SchoolYear 귀속,
HomeroomAssignment, Student 분리, StudentEnrollment, planning login 차단, archived
login, rollover, UI/controller/routes 및 bulk operation을 구현하지 않는다.

Concern, service abstraction, callback, 자동 SchoolYear/login ID 생성,
SchoolMembership sync, generic role abstraction, Devise 변경 또는 새 gem도 추가하지
않는다.

## 예상 구현 범위

- `db/migrate/..._add_annual_teacher_fields_to_users.rb`
- `app/models/user.rb`
- `spec/models/user_spec.rb`
- `db/schema.rb` (migration 실행 결과)

새 field를 명시적으로 설정하는 regression은 기존 User factory를 사용할 수 있으므로
factory 변경을 기본 범위에 포함하지 않는다.

## Open Questions

Phase 2A 수준의 미해결 정책 없음.
