# School Year Foundation

## 목적

이 문서는 [`school_year_architecture.md`](school_year_architecture.md)의 Phase 1을 구체화한다. 이번 phase는 `SchoolYear`와 School별 학년도 cardinality를 위한 독립 foundation만 추가하며 기존 학교 운영을 SchoolYear에 연결하지 않는다.

## 범위와 현재 runtime

현재 runtime은 `SchoolMembership`, `Classroom.school_id`, `Classroom.teacher_id`, student `ClassroomMembership`, 단일 `User` role 구조, Devise email/password와 학생 PIN/token 인증을 사용한다. Phase 1 이후에도 이 구조와 public behavior는 그대로 유지한다.

`SchoolYear` row가 없거나 active SchoolYear가 없는 School도 기존 runtime을 계속 사용할 수 있다. 기존 School, Classroom, teacher와 student 데이터를 임의의 SchoolYear에 자동 귀속하거나 backfill하지 않는다.

## 모델 관계

```text
School
└── has_many SchoolYears

SchoolYear
└── belongs_to School
```

`SchoolYear`는 정확히 하나의 School에 속하며 `school_id`는 필수다. 한 School은 SchoolYear를 여러 개 가질 수 있고 초기 bootstrap 상태에서는 하나도 갖지 않을 수 있다.

## 속성

```text
school_id: foreign key, null: false
year: integer, null: false
status: string, null: false, default: "planning"
created_at: datetime, null: false
updated_at: datetime, null: false
```

현재 프로젝트의 lifecycle status가 string-backed enum과 DB check constraint를 함께 사용하는 관례를 따르므로 `status`도 단순한 string-backed enum을 권장한다. 이는 schema와 partial index 조건을 읽기 쉽게 유지한다. 별도 state-machine abstraction은 사용하지 않는다.

## Year 규칙

`year`는 integer `1000..9999`만 허용한다. 현재 날짜에 상대적인 범위 제한을 두지 않는다.

```text
1000  valid
2025  valid
2026  valid
9999  valid
999   invalid
10000 invalid
```

같은 School에서는 같은 `year`를 둘 이상 저장할 수 없다. 다른 School 사이의 같은 `year`는 허용한다.

```text
UNIQUE (school_id, year)
```

Rails validation은 이해하기 쉬운 오류를 제공하고, DB unique index가 경쟁 조건을 포함한 최종 무결성을 방어한다.

## Status 규칙

허용 상태는 다음 세 가지다.

```text
planning
active
archived
```

잘못된 상태는 model enum/validation과 DB check constraint로 모두 거부한다. 새 SchoolYear의 기본 상태는 `planning`이다. 새 학년도는 운영 전에 준비되는 context이며, 생성만으로 현재 운영 학년도를 바꾸지 않아야 하기 때문이다.

## School별 cardinality

한 School에서 허용되는 상태별 개수는 다음과 같다.

```text
planning 0..1
active   0..1
archived 0..N
```

다음 상태는 허용한다.

```text
SchoolYears = []

2026 active
2027 planning

2023 archived
2024 archived
2025 archived
2026 active
2027 planning
```

같은 School에 active 또는 planning SchoolYear가 각각 둘 이상 존재할 수 없다. 다른 School의 상태 cardinality에는 영향을 주지 않는다. Active와 planning의 최대 한 개 제약은 status 조건을 가진 PostgreSQL partial unique index로 경쟁 조건에 안전하게 보장한다. Model validation은 사용자 친화적 오류를 위한 보조 방어다.

Archived에는 단일성 제약을 두지 않는다. 또한 DB는 School마다 active 또는 planning SchoolYear가 반드시 하나 존재하도록 강제하지 않는다. 정상 runtime이 active SchoolYear를 요구하는 시점과 readiness 정책은 후속 phase의 책임이다.

## Lifecycle transition 경계

장기 transition 방향은 다음과 같다.

```text
old active → archived
planning   → active
```

Rollover는 장기적으로 global-admin-only인 명시적 atomic operation이다. 그러나 Phase 1은 transition service, authorization, locking, transaction이나 UI를 구현하지 않는다. `archived`가 정상 operation에서 terminal/read-only라는 정책도 후속 lifecycle phase에서 server operation으로 강제한다.

이번 foundation의 enum은 상태 값을 표현하고 유효한 값만 저장하게 할 뿐, `archived → planning` 또는 `archived → active` 같은 transition 자체를 model callback으로 판정하거나 자동 수행하지 않는다.

## Ordering과 표시

Association이나 model에 default order를 숨기지 않는다. 소비자가 최신 학년도 순서를 필요로 할 때 명시적으로 `year DESC`를 적용하며, 필요성이 확인되면 이름이 분명한 scope를 후속 phase에서 추가한다.

`2026학년도` 표시 helper도 Phase 1의 필수 foundation이 아니다. Dropdown, selector, navigation, login과 historical UI가 도입되는 phase에서 실제 presentation 문맥에 맞춰 결정한다.

## 삭제와 FK 경계

SchoolYear physical delete를 정상 운영 action으로 제공하지 않는다. School 삭제가 SchoolYear를 자동 cascade-delete하지 않도록, 현재 School의 관련 기록 보존 관례에 맞춰 `School#school_years`는 `dependent: :restrict_with_error`를 사용하고 DB foreign key도 cascade 없이 유지하는 방향을 canonical로 한다.

Phase 1에는 SchoolYear 아래의 운영 record가 아직 없으므로 SchoolYear 자체의 하위 delete 규칙이나 삭제 UI를 새로 만들지 않는다. Archived history의 구체적인 삭제·복구 운영은 이번 범위가 아니다.

## DB와 model의 책임

DB가 최종 방어하는 invariant는 다음과 같다.

- `school_id`, `year`, `status`는 `NOT NULL`이다.
- `school_id`는 `schools`를 참조하는 foreign key다.
- `year`는 DB check constraint로 `1000..9999` 범위만 허용한다.
- `(school_id, year)`는 unique다.
- 같은 School의 `status = 'active'` row는 최대 하나다.
- 같은 School의 `status = 'planning'` row는 최대 하나다.
- `status`는 `planning`, `active`, `archived` 중 하나다.

Model은 association, enum, year 범위와 uniqueness validation으로 빠르고 이해하기 쉬운 오류를 제공한다. Model validation만으로 경쟁 조건을 방어하려 하지 않는다.

정확한 index와 constraint 이름은 구현 phase에서 현재 naming convention에 맞춰 정한다.

## Acceptance criteria

1. School은 SchoolYear를 여러 개 가질 수 있다.
2. SchoolYear는 정확히 하나의 School에 속한다.
3. `year`는 integer `1000..9999`만 허용하며, model validation과 DB check constraint로 모두 보호한다.
4. 같은 School의 같은 year는 중복될 수 없다.
5. 서로 다른 School에서는 같은 year를 사용할 수 있다.
6. `status`는 `planning`, `active`, `archived` 중 하나다.
7. 새 SchoolYear의 기본 status는 `planning`이다.
8. 한 School에는 active SchoolYear가 최대 하나다.
9. 한 School에는 planning SchoolYear가 최대 하나다.
10. 한 School에는 archived SchoolYear가 여러 개 존재할 수 있다.
11. School은 SchoolYear, active year 또는 planning year가 0개인 DB 상태를 가질 수 있다.
12. Same-school active/planning uniqueness는 PostgreSQL DB constraint로 경쟁 조건에 안전하게 보호한다.
13. Phase 1 이후 기존 runtime behavior는 SchoolYear 존재 여부에 의존하지 않는다.
14. 기존 Classroom, User, SchoolMembership과 ClassroomMembership 구조를 변경하지 않는다.
15. Rollover, lifecycle transition authorization과 archived read-only enforcement를 구현하지 않는다.
16. 기존 데이터를 SchoolYear로 backfill하지 않는다.

## Non-goals

- annual teacher User 전환, teacher `login_id`와 temporary-password flow
- Devise 변경과 School-scoped login
- Classroom의 `school_year_id`와 `class_label`
- HomeroomAssignment
- Student/User 분리와 StudentEnrollment
- planning bootstrap UI와 manager school-wide authorization
- rollover orchestration과 archived login/read-only enforcement
- historical reporting
- 기존 데이터 backfill
- `/admin/*` 변경
- downstream `suksuk_growth` 등 서비스별 도메인
- controller, route, view와 presentation helper
- activated/archived timestamp 추가

## 과도 구현 방지

Phase 1에 UI, service layer, rollover orchestration, generic state machine, 새 gem, callback 기반 자동 activation/archive, 자동 year 생성이나 데이터 복사를 추가하지 않는다.

특히 새 active SchoolYear를 만들거나 저장할 때 기존 active SchoolYear를 자동 archive하지 않는다. 상태 전환은 후속 explicit service와 transaction phase의 책임이다.

## 예상 구현 파일

```text
app/models/school_year.rb
app/models/school.rb
db/migrate/..._create_school_years.rb
spec/models/school_year_spec.rb
spec/factories/school_years.rb
db/schema.rb
```

Controller, view와 route는 예상 범위에 포함하지 않는다. 정확한 구현 diff는 이 spec 승인 후 다시 최소 확인한다.
