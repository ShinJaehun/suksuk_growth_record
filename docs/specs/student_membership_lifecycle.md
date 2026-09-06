# Student Lifecycle

## 목적

학생의 active/inactive lifecycle, 권한과 session 경계를 정의한다. 현재 구현 계약은 Student 전환 뒤에도 가능한 그대로 보존한다.

## 현재 runtime

현재 학생은 `User(role: student)`이고 소속과 상태는 student `ClassroomMembership`이 담당한다.

- membership status는 `active`/`inactive`이며 기본값은 active다.
- active는 현재 운영 학생, inactive는 보존된 과거 소속이다. inactive는 active 학생 수에서 제외된다.
- student User는 active membership을 최대 하나 가진다.
- Classroom의 active 학생은 최대 30명이다.
- `Classroom#students`와 PIN 로그인 선택 목록에는 active 학생만 포함한다.
- 구성원 관리 화면에서는 active/inactive를 함께 조회하고 inactive 학생을 복구할 수 있다.
- inactive 학생은 로그인, 현재 교실 기능 접근과 새 활동 생성을 할 수 없다.

### 비활성화와 복구

- 삭제 UI와 직접 `DELETE` 요청은 User를 hard delete하지 않고 현재 membership을 inactive로 바꾼다.
- 비활성화할 때 소속, 기존 기록과 출석번호를 보존한다.
- inactive 학생은 교사/admin이 상세·계정 관리·복구 대상으로 조회할 수 있다.
- 복구 시 다른 Classroom의 active membership 존재, 현재 Classroom active 30명 제한과 active 출석번호 충돌을 다시 검사한다.
- 복구가 실패하면 기존 membership 상태를 유지하고 다른 membership을 자동 변경하지 않는다.
- 복구 최종 검증과 저장은 Classroom과 student lock 안에서 수행한다.
- 학생 학급 이동은 자동 처리하지 않으며 별도 명시적 기능 없이는 membership을 옮기지 않는다.

### 권한 경계

- 비활성화/복구는 `ClassroomPolicy#manage_members?`를 따른다.
- global admin은 모든 Classroom을 관리할 수 있다.
- 현재 ordinary teacher는 담당 Classroom만 관리하며 student는 관리할 수 없다.
- 현재 runtime에서 manager도 실제 담당 teacher가 아니면 학생 데이터에 접근하지 않는다.
- 학생은 본인이며 URL Classroom의 active membership이 있을 때만 접근한다.
- 조작된 Classroom 또는 student id로 scope를 넓힐 수 없다.

### PIN과 session

- 신규 학생은 4자리 PIN이 필수이며 student User에 Devise email/password를 저장하지 않는다.
- inactive 학생은 PIN 선택 목록과 로그인 검증에서 제외한다.
- 로그인 session의 Classroom membership이 inactive가 되면 다음 request에서 로그아웃하고 해당 Classroom 로그인 화면으로 보낸다.
- Classroom, SchoolYear 또는 School이 inactive 상태가 되어도 다음 request에서 사용할 수 없다.
- 20분 inactivity TTL과 PIN 시도 제한을 유지한다.

### 구현 원칙

- controller는 `authorize`, `policy_scope`와 흐름을 담당하고 view에서 복잡한 권한 판단을 하지 않는다.
- 일반 운영 화면과 PIN 일괄 재설정은 active 학생만 대상으로 한다.
- 개별·여러 학생 등록과 복구는 저장 직전 Classroom lock 안에서 active 학생 수를 재검증한다.
- 학생 gender/avatar의 현재 validation과 legacy 호환 동작은 [`student_roster.md`](student_roster.md)를 따른다.

## 승인된 target

최종적으로 `Student belongs_to Classroom`이며 Student 자체의 `active`가 위 membership status 책임을 이어받는다.

- hard delete 대신 inactive로 전환하고 학생 row와 기록을 보존한다.
- inactive 복구, 최대 30명, 번호 충돌과 transaction/lock 계약을 유지한다.
- ordinary teacher 권한은 current HomeroomAssignment, manager 권한은 annual school-wide role에서 파생한다.
- Student는 Devise User가 아니며 별도 Rails session + PIN context를 사용한다.
- 매 request에서 Student, session Classroom, Classroom, SchoolYear와 School eligibility를 검사한다.
- planning SchoolYear에서는 명단 준비가 가능하지만 학생 login은 금지한다.
- archived SchoolYear는 Student.active를 바꾸지 않고 하위 자료와 당시 상태를 read-only로 보존한다.
- 다른 학년도에는 새 Student를 만들며 반 이동 history나 별도 학적 lifecycle을 추가하지 않는다.

Migration과 legacy 제거는 [`student_model_migration.md`](student_model_migration.md), 명단 계약은 [`student_roster.md`](student_roster.md)를 따른다.
