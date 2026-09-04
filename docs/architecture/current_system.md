# Current System

## 문서 목적

현재 starter에 실제로 존재하는 공통 학교·교실·사용자 구조와 확정된 teacher assignment migration target을 구분해 기록한다. 추출 과정에서 제거된 service-specific 도메인은 현재 시스템으로 설명하지 않는다.

## 핵심 역할

- `admin`: 전체 학교 범위의 관리 권한을 가진다.
- `teacher`: `SchoolMembership`으로 학교에 속하며 member 또는 manager 역할을 가진다.
- `student`: student `ClassroomMembership`으로 교실에 속한다.

인증 주체는 `User` 하나를 유지한다. teacher, student와 admin을 별도 인증 모델로 분리하지 않는다.

## 인증과 학생 세션

- teacher와 admin은 Devise 로그인 흐름을 사용한다.
- inactive user는 로그인하거나 일반 운영 권한을 얻을 수 없다.
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

- teacher는 최대 하나의 `SchoolMembership`을 가진다.
- `SchoolMembership.role`은 `member` 또는 `manager`다.
- `SchoolMembership.grade`는 `nil` 또는 정수 1부터 6이다.
- teacher는 classroom 없이 school과 grade만 가질 수 있다.
- `User.grade`와 별도 Grade model은 사용하지 않는다.
- 한 school의 manager는 없거나 한 명이며 canonical source는 `SchoolMembership.role == "manager"`다.
- manager 지정·교체·해제는 global admin만 수행하고 `School.manager_id`는 추가하지 않는다.

## Teacher assignment: 현재 구현

현재 checkout의 teacher assignment는 아직 `ClassroomMembership(role: "teacher")`를 사용한다. 관련 controller, service, policy, scope와 UI도 이 구현에 의존하는 부분이 남아 있다.

이 구조를 최종 1:1 모델로 완료된 것처럼 해석하지 않는다.

## Teacher assignment: canonical migration target

확정된 target은 다음과 같다.

```text
Classroom.teacher_id nullable
foreign key: users
unique index: teacher_id where teacher_id is not null

Teacher 0..1 ↔ 0..1 Classroom
```

- teacher는 담당 classroom이 없거나 하나다.
- classroom은 담당 teacher가 없거나 한 명이다.
- 연결된 teacher와 classroom은 같은 school과 grade를 가지며 둘 다 active여야 한다.
- 신규 teacher `ClassroomMembership`은 만들지 않는다.
- migration 이후 `ClassroomMembership`은 학생 classroom 소속에 사용한다.
- teacher 또는 classroom 비활성화 시 현재 `teacher_id`를 해제하고 재활성화 때 자동 복원하지 않는다.
- classroom grade 변경이 teacher의 membership grade와 충돌하면 먼저 assignment를 해제해야 한다.

기존 teacher membership 데이터는 migration 전에 감사한다. 1:1 호환 관계만 자동 이전하고 다중 assignment 충돌은 임의 선택하지 않으며 명시적으로 정리한 뒤 이전한다.

## Teacher 운영 영역

- `/teachers`는 global admin과 manager의 canonical 개별 teacher 관리 영역이다.
- global admin은 모든 학교, manager는 자기 학교 teacher만 관리한다.
- 일반 teacher는 접근할 수 없다.
- teacher form은 학교, 학년, 단일 학급 순서로 구성한다.
- 학교와 학년이 유효할 때만 같은 school·grade의 active 미배정 classroom을 후보로 조회한다.
- teacher 생성 시 최초 password를 입력할 수 있지만 기존 teacher update에서는 manager가 password를 변경할 수 없다.
- teacher 목록은 school, `SchoolMembership.grade`, 단일 classroom과 lifecycle 상태를 표시한다.

## 학생 관리

- 학생의 classroom 소속 source는 `ClassroomMembership(role: "student")`다.
- active student membership은 현재 소속이고 inactive membership은 과거 소속 기록이다.
- 한 student는 active classroom membership을 최대 하나만 가진다.
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

- 학교 운영 lifecycle과 1:1 teacher assignment: [`school_operations_lifecycle.md`](../specs/school_operations_lifecycle.md)
- 학교와 교실 경계: [`school_classroom_boundaries.md`](school_classroom_boundaries.md)
- classroom grade: [`classroom_grade_foundation.md`](../specs/classroom_grade_foundation.md)
- 학생 membership lifecycle: [`student_membership_lifecycle.md`](../specs/student_membership_lifecycle.md)
- 학생 명부: [`student_roster.md`](../specs/student_roster.md)
