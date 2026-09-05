# Roles And Permissions

## 권한 구조 요약

- 서버측 권한 판단의 중심은 Pundit policy와 `policy_scope`다.
- 모든 비-`index` 액션은 `verify_authorized`, `index` 액션은 `verify_policy_scoped` 대상이다.
- 전역 역할은 `User.role`의 `admin`, `teacher`, `student`를 유지한다.
- 학교 소속과 학교별 권한은 `SchoolMembership`의 `member`, `manager`로 표현한다.
- 학생의 교실 소속은 `ClassroomMembership`으로 표현한다.
- canonical teacher assignment는 nullable `Classroom.teacher_id`이며 teacher와 classroom은 각각 상대를 최대 하나만 가진다.
- UI 숨김은 편의 수단일 뿐이며 policy, scope와 controller/domain validation이 최종 권한 경계다.

teacher assignment는 `Classroom.teacher_id`를 사용한다. 신규 teacher membership을 만들지 않고 `ClassroomMembership`은 학생 소속에 사용한다.

## 역할 설명

### Global admin

- 모든 학교의 관리 가능한 teacher와 classroom을 조회·관리한다.
- 학교 manager를 지정·교체·해제한다.
- `/admin/*` school operations 영역에 접근한다.
- school, grade, lifecycle과 cardinality 불변식을 우회할 수 없다.

### 학교 manager

- 자기 학교의 teacher, classroom과 student 운영만 관리한다.
- 자기 학교 ordinary teacher의 profile, lifecycle과 단일 담당 classroom을 관리한다.
- 다른 학교, global admin 권한, manager role과 manager lifecycle을 변경할 수 없다.
- manager라는 이유만으로 미담당 classroom의 학생 운영 권한을 얻지 않는다.

학교별 manager는 `SchoolMembership.role == "manager"`로 없거나 한 명만 둔다. `School.manager_id`는 추가하지 않으며 manager 지정·교체·해제는 global admin만 수행한다.

### 일반 teacher

- `/teachers`와 `/admin/*` school operations 영역에 접근할 수 없다.
- `Classroom.teacher_id`로 자신에게 배정된 active classroom 하나에서 학생 운영 기능을 사용한다.
- 담당 classroom이 없으면 정상 안내 상태를 본다.
- 같은 학교라는 이유만으로 미담당 classroom에 접근할 수 없다.

### Student

- active student `ClassroomMembership`으로 연결된 자기 classroom과 자기 정보에만 접근한다.
- 교실 구조, 다른 사용자 정보와 운영 관리 기능을 변경할 수 없다.
- PIN/token 로그인과 짧은 student session 정책을 따른다.

## 주요 권한 매트릭스

| 리소스/액션 | global admin | manager | 일반 teacher | student |
|---|---|---|---|---|
| `/teachers` | 모든 학교 | 자기 학교 | 불가 | 불가 |
| `/classrooms` 목록·상세 | 모든 학교 | 자기 학교 | 담당 active classroom | 자기 active membership classroom |
| classroom 생성·구조 수정 | 가능 | 자기 학교 | 불가 | 불가 |
| teacher profile 관리 | 가능 | 자기 학교 허용 범위 | 불가 | 불가 |
| teacher lifecycle | member·manager | 자기 학교 member만 | 불가 | 불가 |
| teacher 단일 classroom 배정 | 가능 | 자기 학교 | 불가 | 불가 |
| 학생 명부·PIN 관리 | 가능 | 실제 담당 teacher인 경우 | 실제 담당 classroom | 불가 |
| manager 지정·교체·해제 | 가능 | 불가 | 불가 | 불가 |
| `/admin/*` school operations | 가능 | 불가 | 불가 | 불가 |

## Teacher와 Classroom 경계

- teacher는 최대 하나의 `SchoolMembership`을 가진다.
- `SchoolMembership.grade`는 `nil` 또는 정수 1부터 6이다.
- teacher는 classroom 없이 학교와 학년만 가질 수 있다.
- classroom은 담당 teacher 없이 존재할 수 있다.
- 신규 assignment 시 teacher와 classroom은 같은 school과 grade야 하며 둘 다 active여야 한다.
- teacher와 classroom은 각각 다른 현재 assignment가 없어야 한다.
- teacher 비활성화 시 현재 assignment를 해제하고 재활성화 때 자동 복원하지 않는다.
- classroom 비활성화 시 assignment와 student membership을 보존하고 운영만 잠그며, 재활성화하면 보존된 관계를 다시 사용한다.
- classroom grade 변경으로 담당 teacher와 불일치가 생기면 저장을 거부한다.

담당 변경은 기존 classroom의 `teacher_id` 해제와 새 classroom의 `teacher_id` 설정을 한 transaction에서 처리한다. 관계를 해제해도 학생 membership이나 과거 서비스 기록을 삭제하지 않는다.

## Student membership 경계

- student는 active classroom membership을 최대 하나만 가진다.
- inactive student membership은 과거 소속 기록으로 보존한다.
- 학생 조회·변경은 URL classroom, student membership과 actor의 classroom 권한을 함께 확인한다.
- 다른 classroom이나 허용 scope 밖 membership id를 제출해도 변경하지 않는다.
- student hard delete보다 membership lifecycle을 우선한다.

## 현재 assignment 구조

```text
Classroom.teacher_id nullable
foreign key: users
unique index: teacher_id where teacher_id is not null
```

## 문서 유지 원칙

- 실제 endpoint와 policy를 기준으로 현재 구현과 canonical 문서가 일치하는지 확인한다.
- service-specific domain이 starter에서 제거되면 그 policy와 route 설명도 활성 문서에서 제거한다.
- 새 액션은 UI 노출뿐 아니라 policy, scope와 server validation을 함께 검토한다.
