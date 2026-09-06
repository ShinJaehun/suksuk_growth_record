# Current System

## 문서 목적

현재 starter에 실제로 존재하는 공통 학교·교실·사용자 구조를 기록한다. 추출 과정에서 제거된 service-specific 도메인은 현재 시스템으로 설명하지 않는다.

이 문서는 현재 runtime을 설명한다. annual teacher User와 SchoolYear는 현재 구현이며, 아직 도입하지 않은 HomeroomAssignment와 StudentEnrollment target은 [`school_year_architecture.md`](../specs/school_year_architecture.md)와 구분한다.

## 핵심 역할

- `admin`: 전체 학교 범위의 관리 권한을 가진다.
- `teacher`: 하나의 `SchoolYear`에 속하며 `User.school_role`로 member 또는 manager 역할을 가진다.
- `student`: student `ClassroomMembership`으로 교실에 속한다.

인증 주체는 `User` 하나를 유지한다. teacher, student와 admin을 별도 인증 모델로 분리하지 않는다.

## 인증과 학생 세션

- teacher와 admin은 Devise 로그인 흐름을 사용한다.
- inactive teacher는 로그인하거나 일반 운영 권한을 얻을 수 없다.
- student는 교실 범위 PIN/token 로그인 흐름을 사용한다.
- PIN 로그인은 classroom, active student membership과 PIN을 서버에서 확인한다.
- 학생 로그인 성공 시 기존 session을 reset하고 student로 로그인한다.
- student session은 짧은 TTL과 마지막 활동 시각으로 관리한다.
- 만료되거나 재발급으로 무효화된 token은 사용할 수 없다.

## 학교와 교실

- 모든 `Classroom`은 하나의 active/inactive lifecycle과 변경 불가능한 `school_id`를 가진다.
- `Classroom.grade`는 필수 정수 1부터 6이며 표시·filter·정렬 정책은 canonical grade spec을 따른다.
- global admin은 모든 학교 범위, manager는 자기 학교 범위에서 school과 classroom을 관리한다.
- 일반 teacher는 담당 active classroom만 운영한다.
- school 또는 classroom 비활성화는 물리 삭제가 아니며 학생 membership과 과거 기록을 보존한다.

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
Classroom.teacher_id nullable
foreign key: users
unique index: teacher_id where teacher_id is not null

Teacher 0..1 ↔ 0..1 Classroom
```

- teacher는 담당 classroom이 없거나 하나다.
- classroom은 담당 teacher가 없거나 한 명이다.
- 신규 assignment 시 teacher와 classroom은 같은 school과 grade를 가지며 둘 다 active여야 한다.
- 신규 teacher `ClassroomMembership`은 만들지 않는다.
- `ClassroomMembership`은 학생 classroom 소속에 사용한다.
- teacher 비활성화 시 현재 `teacher_id`를 해제하고 재활성화 때 자동 복원하지 않는다.
- classroom 비활성화 시 현재 `teacher_id`와 student membership을 보존한 채 운영을 잠그며, 재활성화하면 보존된 관계를 다시 사용한다.
- classroom grade 변경이 `User.grade`와 충돌하면 먼저 assignment를 해제해야 한다.

## Teacher 운영 영역

- `/teachers`는 global admin과 manager의 canonical 개별 teacher 관리 영역이다.
- global admin은 모든 학교, manager는 자기 학교 teacher만 관리한다.
- 일반 teacher는 접근할 수 없다.
- teacher form은 학교, 학년, 단일 학급 순서로 구성한다.
- 학교와 학년이 유효할 때만 같은 school·grade의 active 미배정 classroom을 후보로 조회한다.
- teacher 생성 시 최초 password를 입력할 수 있지만 기존 teacher update에서는 manager가 password를 변경할 수 없다.
- teacher 목록은 annual school, `User.grade`, 단일 classroom과 lifecycle 상태를 표시한다.

## 학생 관리

- 학생의 classroom 소속 source는 `ClassroomMembership(role: "student")`다.
- active student membership은 현재 소속이고 inactive membership은 과거 소속 기록이다.
- 학생의 현재 운영 lifecycle은 `User.active`가 아니라 `ClassroomMembership.status`로 관리한다.
- 한 student는 active classroom membership을 최대 하나만 가진다.
- 같은 classroom의 active 학생끼리 `student_number`가 중복될 수 없으며 번호는 교사가 직접 관리한다.
- 학생은 classroom별 출석번호, name, gender, avatar와 PIN을 기존 운영 정책에 따라 관리한다.
- 담당 teacher와 admin은 학생 명부, 학생 정보와 PIN을 관리할 수 있다.
- 학생 자신은 허용된 자기 정보와 PIN 중심 흐름만 사용한다.
- 학생 avatar는 role과 gender에 맞는 `avatar_key` pool과 fallback 정책을 유지한다.

## 권한 원칙

- Pundit policy와 `policy_scope`가 서버측 권한의 기본 경계다.
- controller와 domain validation은 school, grade, lifecycle과 assignment cardinality를 다시 확인한다.
- `school_id`, `teacher_id`, `classroom_id`와 membership id parameter 조작으로 scope를 넓힐 수 없다.
- manager 권한은 자기 school로 제한하고 일반 teacher는 담당 classroom 밖으로 확장하지 않는다.
- UI 숨김만으로 권한을 보장하지 않는다.

## 관련 canonical 문서

- 장기 SchoolYear architecture: [`school_year_architecture.md`](../specs/school_year_architecture.md)
- 학교 운영 lifecycle과 1:1 teacher assignment: [`school_operations_lifecycle.md`](../specs/school_operations_lifecycle.md)
- 학교와 교실 경계: [`school_classroom_boundaries.md`](school_classroom_boundaries.md)
- classroom grade: [`classroom_grade_foundation.md`](../specs/classroom_grade_foundation.md)
- 학생 membership lifecycle: [`student_membership_lifecycle.md`](../specs/student_membership_lifecycle.md)
- 학생 명부: [`student_roster.md`](../specs/student_roster.md)
