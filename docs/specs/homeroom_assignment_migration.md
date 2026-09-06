# HomeroomAssignment Migration

## 목적

현재 담임의 단일 source인 `classrooms.teacher_id`를 이력을 보존하는
`HomeroomAssignment`로 이전한다. 현재 담임 조회 API는 유지할 수 있지만 저장 source는
assignment row 하나로 통일하고, 검증 완료 뒤 `classrooms.teacher_id`를 제거한다.

이 문서는 승인된 migration과 runtime cutover 계약 및 구현 기준을 정의한다.

## Current state와 inventory

현재 `Classroom`은 nullable `teacher_id` FK와 null이 아닌 `teacher_id` unique index로
Classroom당 teacher 한 명, teacher당 Classroom 하나를 표현한다.

- Model: `Classroom.belongs_to :teacher`, `User.has_one :assigned_classroom`이며 Classroom이
  teacher role, active 상태, 같은 SchoolYear, 같은 grade와 active lifecycle을 검증한다.
- Write: `Teachers::SaveWithAssignment`만 정상 배정·이동·해제 흐름을 담당한다. teacher와
  관련 Classroom을 ID 순서로 lock하고 한 transaction에서 기존 `teacher_id`를 nil로 만든
  뒤 새 값을 저장한다.
- Replacement: 한 teacher를 비어 있는 다른 Classroom으로 옮기는 것은 허용한다. 이미
  다른 teacher가 배정된 Classroom을 직접 덮어쓰는 것은 model/service가 거부한다. 따라서
  새 구조에서도 occupied Classroom의 직접 replacement를 새 기능으로 만들지 않는다.
- Deactivation: teacher가 active에서 inactive로 바뀌면 User callback이 현재
  `assigned_classroom.teacher_id`를 nil로 만든다. Classroom 비활성화는 관계를 보존하고 새
  배정·이동·해제를 막는다.
- Read: Classroom/User model API, classroom/teacher controller와 form, teacher list,
  navigation/landing, `ClassroomPolicy`, `ClassroomStudentPolicy`, `UserPolicy`, index/show
  context가 `teacher`, `assigned_classroom` 또는 `teacher_id`를 사용한다.
- Authorization: 일반 teacher의 Classroom scope와 담임 여부는 `classrooms.teacher_id`로
  판단한다. Manager의 school-wide authority는 `User.school_role`과 SchoolYear에서 나오며
  담임 여부와 별개다.
- Audit: `SchoolStructure::IntegrityAudit`은 `classrooms.teacher_id`를 기준으로 teacher의
  SchoolYear, grade와 lifecycle 불일치를 검사한다.
- Seed/factory/spec: Classroom factory의 `teacher` association, `assign_teacher` helper와
  model/request/policy/service specs가 현재 column과 derived API를 사용한다.
- Delete: student membership이 없는 Classroom은 global admin이 삭제할 수 있으며 배정된
  teacher는 보존된다. `User#assigned_classroom`은 현재 `dependent: :nullify`다.
- Schema: `classrooms.teacher_id -> users.id` FK와 partial unique index가 있다.
- Historical migration: `20260904020000_migrate_teacher_assignments_to_classrooms.rb`의
  `teacher_id` 참조는 당시 schema 재현에 필요하므로 수정하거나 삭제하지 않는다.

## Target state

```text
Classroom
└── HomeroomAssignment
    ├── classroom_id
    ├── teacher_id
    ├── started_on
    └── ended_on (nullable)
```

`ended_on IS NULL`인 row만 current assignment다. 종료된 row는 삭제하거나 재사용하지
않는다. 새 배정은 새 row를 만들며 과거 row를 overwrite하지 않는다.

의미 있는 domain API는 유지한다.

- `Classroom#teacher`: current HomeroomAssignment의 teacher를 반환하는 derived API
- `User#assigned_classroom`: teacher의 current HomeroomAssignment가 가리키는 Classroom을
  반환하는 derived API
- 필요하면 `current_homeroom_assignment` association을 명시하되 historical collection과
  current association을 구분한다.

이 API들은 `classrooms.teacher_id` fallback을 사용하지 않는다.

## DB invariants

최종 table은 다음을 가진다.

- `classroom_id NOT NULL`, FK to classrooms
- `teacher_id NOT NULL`, FK to users
- `started_on NOT NULL`
- `ended_on`, nullable date
- partial unique index on `classroom_id WHERE ended_on IS NULL`
- partial unique index on `teacher_id WHERE ended_on IS NULL`
- CHECK `ended_on IS NULL OR ended_on >= started_on`

Partial unique index가 동시 요청의 최종 cardinality 방어선이다. 같은 SchoolYear, grade,
teacher role과 lifecycle은 application validation과 assignment operation이 검사한다. 이
교차-table 규칙을 callback이나 불명확한 DB trigger로 중복 구현하지 않는다.

## Backfill과 data preflight

`classrooms.teacher_id IS NOT NULL`인 각 row마다 current HomeroomAssignment를 정확히 하나
생성한다. Backfill 전에 다음을 모두 fail-fast한다.

1. teacher User가 존재하고 role이 teacher다.
2. teacher와 Classroom의 `school_year_id`가 같다.
3. teacher와 Classroom의 grade가 같고 nil이 아니다.
4. teacher가 두 Classroom에 중복 배정되지 않았다.
5. target Classroom과 teacher별 current assignment collision이 없다.

Migration은 불일치를 자동 보정하거나 임의 assignment를 선택하지 않는다. Backfill 검증,
application dual-source 없는 cutover와 dependency-zero 확인 뒤 `classrooms.teacher_id`, 기존
index와 FK를 제거한다. Historical migration은 보존한다.

### Legacy `started_on` 정책

현재 repository에는 assignment 생성·변경 audit event나 신뢰 가능한 시작일 column이 없다.
`Classroom.created_at`, teacher `User.created_at`, SchoolYear 시작일과 `updated_at`은 실제 담임
시작일이 아니므로 사용하지 않는다.

`started_on`은 최종 NOT NULL이다. Legacy backfill row에는 migration 실행일을 실제 과거
담임 시작일이 아니라 “담임 이력 추적 cutover 기준일”로 기록한다. Nullable legacy 값은
사용하지 않으며 임의 날짜 추론도 금지한다.

## Assignment operation

`Teachers::SaveWithAssignment`의 현재 역할과 lock 순서를 최대한 유지한다.

- transaction 안에서 teacher와 관련 Classroom을 결정적인 순서로 lock한다.
- 같은 teacher의 current assignment와 target Classroom의 current assignment를 lock 후 다시
  조회하고 validation한다.
- 신규 배정은 current row가 없는 target에 새 assignment를 생성한다.
- 해제는 current row를 삭제하지 않고 `ended_on`을 operation date로 설정한다.
- 이동은 기존 current row 종료와 새 row 생성을 한 transaction에서 처리한다.
- 어느 저장도 실패하면 teacher profile/grade 변경과 assignment 변경 전체를 rollback한다.
- 이미 동일한 current assignment를 선택하면 history row를 추가하지 않는 idempotent
  success로 처리한다.
- 다른 teacher가 점유한 Classroom은 현재와 같이 거부한다. 먼저 별도 해제한 뒤 배정해야
  하며 direct replacement는 지원하지 않는다.

새로운 범용 locking abstraction은 만들지 않는다. Application validation과 lock은 친절한
오류와 race 축소를 담당하고 partial unique index가 최종 동시성 방어를 담당한다.

## Lifecycle

- Classroom inactive: current assignment를 자동 종료하지 않고 보존한다. Profile-only
  update는 허용하되 새 배정, 해제 또는 다른 Classroom으로 이동은 금지한다.
- Teacher inactive: 현재 contract를 유지해 같은 transaction에서 current assignment의
  `ended_on`을 기록한다. Classroom이 inactive여도 teacher lifecycle 정합성 처리를 위해 이
  종료는 허용한다. 재활성화 시 자동 복원하지 않는다.
- SchoolYear archived: assignment row를 변경하지 않고 당시 이력을 read-only로 보존한다.
  추가, 교체, 해제와 날짜 수정은 모두 금지한다.
- 같은 School이어도 다른 SchoolYear teacher는 배정할 수 없다.
- Manager authority와 담임 관계는 별개다. Manager도 같은 assignment invariant 아래 current
  담임이 될 수 있다.

## Delete와 history retention

영구 이력 보존은 현재 delete contract와 충돌한다.

- Classroom: Assignment 이력이 하나라도 있으면 model association과 FK `RESTRICT`로
  physical delete를 거부한다. 이력이 없고 기존 student deletion guard도 통과한 미사용
  Classroom만 삭제할 수 있다.
- Teacher User: Assignment 이력이 하나라도 있으면 model association과 FK `RESTRICT`로
  physical delete를 거부한다. 정상 운영은 inactive lifecycle을 사용한다.

Assignment history에는 cascade delete나 nullify를 사용하지 않는다. Soft delete나 history
snapshot은 이번 범위에 새로 도입하지 않는다.

## Runtime cutover

- Policy scope와 담임 authorization은 current HomeroomAssignment join/existence로 판단한다.
- Navigation, landing, teacher/classroom form과 list는 derived `teacher` 및
  `assigned_classroom` API를 재사용한다.
- Candidate query는 current assignment가 없는 Classroom과 edit teacher 자신의 current
  Classroom만 포함한다.
- IntegrityAudit는 HomeroomAssignment를 기준으로 role, current cardinality, SchoolYear,
  grade와 active teacher/SchoolYear/School 불일치를 검사한다. 종료된 history는 날짜 순서와
  참조 무결성만 검사하고 current assignment처럼 권한 source로 사용하지 않는다.
- Seed, factory, `assign_teacher` helper와 specs는 정상 assignment operation/model을 통해
  row를 생성한다. `classrooms.teacher_id` raw write는 제거한다.
- Student `ClassroomMembership`, token, PIN/session과 Classroom lifecycle source는 변경하지
  않는다.

## Acceptance criteria

1. Current assignment는 Classroom당 최대 하나다.
2. Current assignment는 teacher당 최대 하나다.
3. Teacher와 Classroom은 정확히 같은 SchoolYear다.
4. Teacher grade와 Classroom grade가 같다.
5. Inactive teacher에게 새 assignment를 만들 수 없다.
6. Inactive Classroom에 새 배정·교체·해제를 할 수 없다.
7. Classroom deactivate는 current assignment를 보존한다.
8. Teacher deactivate는 current assignment를 종료하는 기존 contract를 보존한다.
9. Unassign은 row 삭제가 아니라 `ended_on` 기록이다.
10. Reassignment는 old row 종료와 new row 생성을 원자적으로 처리한다.
11. 종료된 historical assignment를 보존하고 current authority로 사용하지 않는다.
12. Archived SchoolYear에서는 assignment mutation을 금지한다.
13. Cutover 뒤 `Classroom.teacher_id`, 관련 FK와 index를 제거할 수 있다.
14. Current teacher와 assigned Classroom 조회는 HomeroomAssignment에서 파생한다.
15. IntegrityAudit는 HomeroomAssignment를 기준으로 동작한다.
16. Student와 `ClassroomMembership` 동작에 영향이 없다.
17. Occupied Classroom의 direct replacement를 계속 거부한다.
18. Partial unique index가 concurrent current assignment collision을 거부한다.

## Non-goals

- Student model 분리, StudentEnrollment 또는 ClassroomMembership 제거
- planning SchoolYear UI, rollover 또는 archived UI
- teacher credential 변경 또는 manager 정책 변경
- co-teacher, 복수 담임 또는 subject teacher
- 자동 다음 학년도 Classroom/assignment 복사
- soft delete, generic history framework 또는 새 gem

## Implementation order

1. HomeroomAssignment table/model, constraints와 focused contract specs를 추가한다.
2. Existing `teacher_id` data preflight 후 cutover date로 current assignment row를 backfill한다.
3. `Teachers::SaveWithAssignment`, deactivation, derived associations, policy/runtime와 audit를
   HomeroomAssignment source로 cutover한다.
4. Seed/factory/helper/spec에서 `teacher_id` 직접 write를 제거한다.
5. Runtime dependency와 backfill parity가 0인지 확인한다.
6. `classrooms.teacher_id`, 기존 FK/index를 제거한다.
