# School Operations Architecture

## 1. 목적과 범위

이 문서는 학교별 권한과 teacher·classroom 운영 구조에 관한 확정 정책을 정리한다.
현재 구현과 이 브랜치에서 단계적으로 구현할 정책을 구분하며, 세부 모델·policy·route 이름은 각 구현 단계에서 현재 Rails 구조에 맞춰 확정한다.

---

## 2. School의 책임

`School`은 다음 정보의 기준 범위다.

- 교실
- 교사의 학교 소속
- 학교별 관리자 권한

`/schools/:id`는 학교 이름과 교실·교사 수, 학교 관리자 현황을 제공한다. 상단에는 `/classrooms` 이동과 global admin 전용 `/schools/:id/edit` 학교 설정 진입을 표시하며, 학교 show 자체에는 교실·교사 상세 목록을 두지 않는다. 독립된 학교 설정 페이지에서 학교 이름, 표시 색상, 학교 관리자와 학교 활성 상태를 관리한다.

모든 `Classroom`은 하나의 `School`과 1~6 범위의 grade를 반드시 가진다. application validation과 DB `NOT NULL` 제약을 함께 적용하며 school이나 grade가 없는 legacy classroom은 허용하지 않는다.

---

## 3. global admin과 학교 manager

기존 전역 `User#role`은 `admin`, `teacher`, `student`를 유지하며 `school_manager` 같은 전역 role을 추가하지 않는다.

- global admin은 모든 학교를 관리한다.
- 학교 manager는 전역 role이 `teacher`인 사용자에게 학교 소속 단위로 부여하는 권한이다.
- 한 학교에는 manager가 없거나 한 명만 있을 수 있다.
- manager 지정과 해제는 초기에는 global admin만 수행한다.
- manager는 다른 manager를 지정하거나 해제할 수 없다.

manager의 canonical source는 active annual teacher의 `User.school_role == "manager"`이며 `School.manager_id`를 추가하지 않는다. 같은 active SchoolYear의 manager는 최대 하나이고 global admin은 이 수에 포함하지 않는다.

학교 manager는 자신이 manager로 소속된 학교에 한해 다음 기능을 관리한다.

- 학교 정보 열람
- 해당 학교의 학급 목록·상세 조회
- 해당 학교 학급 생성·기본 정보 수정
- 해당 학교 선생님 목록 조회
- 새 선생님을 해당 학교의 일반 구성원으로 생성
- 해당 학교 안에서 선생님의 단일 담당 교실 배정·해제

`SchoolPolicy`와 scope는 일반 teacher와 manager에게 자신의 학교만 노출한다. 일반 teacher는 학교를 열람할 수 있지만 운영 기능과 선생님 관리를 할 수 없고, manager는 자신의 학교 운영 기능과 학교별 선생님 관리만 사용할 수 있다. global admin은 모든 학교를 조회하고 `/admin/teachers`에서 전체 학교 선생님의 소속과 담당 학급을 통합 관리하지만 학교별 선생님 endpoint는 사용하지 않는다. 학교 생성·이름 수정·삭제는 global admin 전용이다.

이 policy는 학교 운영 정보와 학교별 선생님 관리 route에 연결된다. member는 자신의 학교 현황을 읽고 global admin은 manager를 지정·해제할 수 있다. manager는 학급을 다른 학교로 이동할 수 없고, teacher를 다른 학교로 이동하거나 학교 소속을 해제하거나 manager 지정·해제를 할 수 없다. 학교 manager의 teacher 생성은 URL의 학교로 고정되며 항상 일반 구성원으로 생성된다.

담당 teacher 배정·해제는 역할별 전용 경로에서 수행한다. teacher form은 학교, 학년, 단일 학급을 함께 관리하고 현재 담당 관계는 `Classroom.teacher_id`에 저장한다. classroom create/update는 담당 teacher를 동시에 지정하지 않는다. `/classrooms/:id/edit`에서 admin과 해당 학교 manager는 교실 이름·학년 등 구조 정보를 관리하고, 담당 teacher는 허용된 교실 운영 기능만 관리한다. manager가 담당 teacher가 아니라면 학생 관리와 운영 권한은 없다.

---

## 4. Annual teacher 역할

교사의 학교는 `User.school_year.school`, 학교 단위 역할은 `User.school_role`, 학년은 `User.grade`가 canonical source다. `school_role`은 `member` 또는 `manager`이며 한 active SchoolYear의 manager는 최대 한 명이다. Teacher의 학교 소속과 권한에는 별도 membership read/write 또는 fallback을 두지 않는다.

학급 담당 교사는 학급과 같은 학교와 학년을 가진 active teacher이며 그 `SchoolYear`와 `School`도 active여야 한다. `Classroom.teacher_id`는 한 teacher에게 최대 하나의 classroom만 연결하도록 DB uniqueness를 적용한다. 학교 manager의 운영 화면은 자기 학교의 단일 담당 관계만 변경하고 annual identity나 manager 역할은 변경하지 않는다.

teacher의 담당 classroom을 바꾸면 기존 classroom의 `teacher_id` 해제와 새 classroom의 `teacher_id` 설정을 한 transaction에서 처리한다. 같은 SchoolYear 안에서 grade를 변경한 뒤 유효한 classroom을 선택하지 않으면 미배정으로 저장한다. persisted annual teacher의 `school_year_id`는 일반 teacher-management operation에서 변경하지 않으며 cross-School transfer는 별도 annual account workflow가 필요하다. classroom 자체의 학교는 생성 후 변경할 수 없다.

현재 teacher assignment는 `Classroom.teacher_id`를 canonical source로 사용하며 teacher와 classroom 양쪽 모두 최대 하나의 상대만 가진다. `ClassroomMembership`은 student membership에 사용한다.

---

## 5. Lifecycle 경계

- teacher 비활성화는 현재 classroom assignment를 해제하며 재활성화 시 자동 복원하지 않는다.
- classroom 비활성화는 teacher assignment와 student membership을 보존한 채 운영을 잠근다.
- student의 현재 운영 상태는 `ClassroomMembership.status`로 관리한다.

---

## 6. 이번 범위에서 하지 않는 것

- 학교 manager의 다른 manager 지정·해제
- 교사당 여러 학교 소속
- 제거된 service-specific 도메인 재도입
