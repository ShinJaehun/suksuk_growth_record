# Current System

## 문서 목적

현재 starter에 실제로 존재하는 공통 학교·교실·사용자 구조를 기록한다. 추출 과정에서 제거된 service-specific 도메인은 현재 시스템으로 설명하지 않는다.

이 문서는 현재 runtime을 설명한다. annual teacher User, SchoolYear, HomeroomAssignment와 Classroom 직속 Student가 현재 구현이다. Student에는 별도 StudentEnrollment를 두지 않는다.

## 핵심 역할

- `admin`: 전체 학교 범위의 관리 권한을 가진다.
- `teacher`: 하나의 `SchoolYear`에 속하며 `User.school_role`로 member 또는 manager 역할을 가진다.
- `student`: 별도 `Student` row로 하나의 Classroom에 직접 속한다.

teacher와 admin은 `User`이고 student는 별도 `Student`다. Student는 Devise User가 아니며 Rails session + PIN으로 인증한다.

## 인증과 학생 세션

- teacher와 admin은 Devise 로그인 흐름을 사용한다.
- inactive teacher는 로그인하거나 일반 운영 권한을 얻을 수 없다.
- student는 교실 범위 PIN/token 로그인 흐름을 사용한다.
- PIN 로그인은 classroom, active Student와 PIN을 서버에서 확인한다.
- 학생 로그인 성공 시 기존 session을 reset하고 별도 Student session context를 설정한다.
- student session은 짧은 TTL과 마지막 활동 시각으로 관리한다.
- 만료되거나 재발급으로 무효화된 token은 사용할 수 없다.

## 학교와 교실

- 모든 `Classroom`은 하나의 변경 불가능한 `SchoolYear`, normalized `class_label`, active/inactive lifecycle을 가진다. 학교는 `classroom.school_year.school`로 결정한다.
- `Classroom.grade`는 필수 정수 1부터 6이며 표시·filter·정렬 정책은 canonical grade spec을 따른다.
- global admin은 모든 학교 범위, manager는 자기 학교 범위에서 school과 classroom을 관리한다.
- 일반 teacher는 담당 active classroom만 운영한다.
- school 또는 classroom 비활성화는 물리 삭제가 아니며 Student row와 과거 기록을 보존한다.

## Teacher의 학교와 학년

- teacher의 현재 학교는 `User.school_year.school`, 학교 역할은 `User.school_role`, 학년은 `User.grade`가 canonical source다.
- teacher는 정확히 하나의 `SchoolYear`에 속하고 `User.school_role`은 `member` 또는 `manager`다.
- `User.grade`는 `nil` 또는 정수 1부터 6이다.
- teacher는 classroom 없이 school과 grade만 가질 수 있다.
- 별도 Grade model은 사용하지 않는다.
- 한 active SchoolYear의 manager는 없거나 한 명이며 canonical source는 `User.school_role == "manager"`다.
- manager가 없는 임시 상태는 허용하지만 한 school에 둘 이상을 둘 수 없다. global admin은 manager 수에 포함하지 않는다.
- manager 지정·교체·해제는 global admin만 수행하고 `School.manager_id`는 추가하지 않는다.
- teacher의 학교 소속과 권한에는 별도 membership model을 두지 않는다.

## Teacher assignment

현재 구조는 다음과 같다.

```text
HomeroomAssignment(classroom_id, teacher_id, started_on, ended_on)
current: ended_on IS NULL
partial unique: current classroom_id / current teacher_id

Teacher 0..1 ↔ 0..1 Classroom
```

- teacher는 담당 classroom이 없거나 하나다.
- classroom은 담당 teacher가 없거나 한 명이다.
- 신규 assignment 시 teacher와 classroom은 같은 SchoolYear와 grade를 가지며 teacher, classroom, SchoolYear, School이 active여야 한다.
- 학생 classroom 소속은 `Student.classroom_id`가 canonical source다.
- teacher 비활성화 시 current assignment를 종료하고 재활성화 때 자동 복원하지 않는다.
- classroom 비활성화 시 current assignment와 Student row를 보존한 채 운영을 잠그며, 재활성화하면 보존된 관계를 다시 사용한다.
- classroom grade 변경이 `User.grade`와 충돌하면 먼저 assignment를 해제해야 한다.

## Teacher 운영 영역

- `/teachers`는 global admin과 manager가 active SchoolYear teacher를 관리하는 canonical 개별 teacher 관리 영역이다.
- global admin은 각 학교의 active SchoolYear teacher를, manager는 자기 active SchoolYear teacher만 관리한다.
- 일반 teacher는 접근할 수 없다.
- teacher form은 학교, 학년, 단일 학급 순서로 구성한다.
- 학교와 학년이 유효할 때만 같은 SchoolYear·grade의 active 미배정 classroom을 후보로 조회한다.
- teacher 생성 시 temporary password를 자동 발급하며 기존 teacher update에서는 password를 변경하지 않는다.
- teacher 목록은 annual school, `User.grade`, 단일 classroom과 lifecycle 상태를 표시한다.

### Teacher credential 사용성 계약

현재 Teacher 운영·인증 흐름의 credential 표시와 발급 계약은 다음과 같다.

- 기존 teacher 관리의 canonical edit surface는 `/teachers/:id/edit`다. 관리 권한이 있는 사용자는 persisted teacher의 canonical `login_id`를 `선생님 ID` 등 기존 UI와 일관된 label의 read-only presentation으로 확인한다. login_id 수정 input을 새로 활성화하지 않으며 신규 teacher 생성 form의 기존 login_id 입력은 유지한다.
- 교사 본인의 account/profile surface는 `/users/edit`다. 로그인한 User가 teacher인 경우에만 자기 `login_id`를 read-only로 표시하고 global admin에게는 teacher login_id field를 표시하지 않는다. 두 화면의 ID 표시는 수정 권한을 부여하지 않는다.
- login_id normalization, SchoolYear scope와 uniqueness, login route 및 authentication lookup은 그대로 유지한다.
- `Teachers::TemporaryPassword`는 쑥쑥교실투표와 같은 canonical 규칙으로 temporary password를 생성한다. 정확히 8자이며 허용 문자는 `ABCDEFGHJKLMNPQRSTUVWXYZ23456789`다. 혼동하기 쉬운 I, O, 0, 1은 제외하고 대상 teacher의 login_id와 case-insensitive하게 동일하면 다시 생성한다. 최초 발급과 재발급 모두 같은 generator를 사용한다. `AnnualTeacherUsers::TemporaryCredential`이 이 작은 generator를 사용하며 generic credential framework로 확장하지 않는다.
- 최초 발급·재발급 모두 `password_change_required = true`와 최초 로그인 뒤 강제 비밀번호 변경을 유지한다. 재발급하면 이전 password로 신규 인증할 수 없다.
- 평문은 request-local one-time 결과에서만 표시하고 DB/session/flash/audit에 저장하지 않는다. 기존 결과 응답의 `no-store`/Turbo cache 방지, `TeacherCredentialEvent`, credential mutation과 audit의 transaction을 유지한다.
- rate-limit의 credential-generation recovery 계약을 유지한다. 재발급된 credential은 기존 credential의 실패 누적으로 잠긴 인증 시도와 구분되며 기존 rate-limit/authentication 경계를 변경하지 않는다.

Acceptance:

- 관리자는 `/teachers/:id/edit`에서 기존 teacher의 login_id를, teacher 본인은 `/users/edit`에서 자기 login_id를 확인할 수 있다. 두 화면 모두 기존 teacher login_id를 수정 가능하게 만들지 않으며 global admin의 `/users/edit`에는 해당 field가 없다.
- 신규 teacher 생성 form의 기존 login_id 입력과 normalization/SchoolYear-scoped uniqueness·인증 lookup은 유지된다.
- 최초 발급·재발급 temporary password는 지정 charset만 사용하는 정확히 8자이고 login_id와 case-insensitive하게 동일한 후보는 재생성한다.
- forced-change, request-local one-time 표시, 평문 비저장, audit transaction, 재발급 후 이전 password 신규 인증 차단과 credential-generation rate-limit recovery가 유지된다.

이번 변경에는 `/teacher` 또는 GET `/teachers/:id` 신규 route, persisted login_id 수정 기능, SchoolYear-scoped teacher login 변경, `/users/sign_in` 통합, global admin 인증 변경, DB migration/schema 변경, temporary password 만료시간, 새 credential table/framework와 UI 전체 redesign을 포함하지 않는다. 완료된 historical cutover 문서는 재작성하지 않는다.

## 학생 관리

- 학생의 classroom 소속 source는 `Student.classroom_id`다.
- `Student.active`가 현재 운영 포함 여부를 나타내며 inactive Student도 row와 기존 기록을 보존한다.
- `Student.student_number`는 nullable이고 같은 classroom의 active Student끼리 non-null 번호가 중복될 수 없다.
- 학생은 classroom별 name, student_number, gender, avatar와 PIN을 Student 하나에서 관리한다.
- 담당 teacher와 admin은 학생 명부, 학생 정보와 PIN을 관리할 수 있다.
- 학생 자신은 별도 Student session에서 허용된 자기 정보와 PIN 중심 흐름만 사용한다.
- 학생 avatar는 gender에 맞는 `avatar_key` pool과 fallback 정책을 유지한다.
- 학생용 `User`와 `ClassroomMembership`은 runtime/schema에 존재하지 않는다.

## 권한 원칙

- Pundit policy와 `policy_scope`가 서버측 권한의 기본 경계다.
- controller와 domain validation은 school, grade, lifecycle과 assignment cardinality를 다시 확인한다.
- `school_id`, `teacher_id`, `classroom_id`와 Student id parameter 조작으로 scope를 넓힐 수 없다.
- manager 권한은 자기 school로 제한하고 일반 teacher는 담당 classroom 밖으로 확장하지 않는다.
- UI 숨김만으로 권한을 보장하지 않는다.

## 관련 canonical 문서

- 장기 SchoolYear architecture: [`school_year_architecture.md`](../specs/school_year_architecture.md)
- 학교 운영 lifecycle과 1:1 teacher assignment: [`school_operations_lifecycle.md`](../specs/school_operations_lifecycle.md)
- 학교와 교실 경계: [`school_classroom_boundaries.md`](school_classroom_boundaries.md)
- classroom grade: [`classroom_grade_foundation.md`](../specs/classroom_grade_foundation.md)
- Student lifecycle: [`student_membership_lifecycle.md`](../specs/student_membership_lifecycle.md)
- 학생 명부: [`student_roster.md`](../specs/student_roster.md)
