# School Operations Lifecycle

## 목적

학교 공통 starter에서 teacher와 classroom의 운영 lifecycle, 역할별 접근·관리 권한, 일반 운영 영역과 향후 global admin bulk management 영역의 경계를 정의한다. 교사와 교실의 기존 다대다 담당 구조 및 과거 기록을 보존하면서 활성 상태를 일상적인 운영 lifecycle로 사용한다.

## 용어와 현재 구조

- global admin은 `User.role == "admin"`인 사용자다.
- 학교 대표 선생님은 `User.role == "teacher"`이고 해당 학교의 `SchoolMembership.role == "manager"`인 사용자다.
- 일반 선생님은 `User.role == "teacher"`이고 `SchoolMembership.role == "member"`인 사용자다.
- teacher는 최대 하나의 `SchoolMembership`으로 학교에 속한다.
- 교사의 담당 교실은 `ClassroomMembership(role: "teacher")`로 표현한다.
- `Classroom`은 `School`에 속하며 기존 학년 정책은 [Classroom Grade Foundation](classroom_grade_foundation.md)을 따른다.

## 운영 영역 구조

### 일반 운영 영역

- `/teachers`는 global admin과 학교 대표 선생님이 사용하는 일반 교사 운영 영역이다.
- `/classrooms`는 global admin, 학교 대표 선생님, 일반 선생님이 각자의 권한 범위에서 사용하는 일반 교실 운영 영역이다.
- 현재 `/admin/teachers`의 개별 교사 관리 책임은 향후 `/teachers`로 이동한다. 이는 단순 URL alias가 아니라 일반 school operations 영역으로 책임을 옮기는 것이다.
- 현재 `/classrooms`의 일반 운영 책임은 유지한다.
- 기존 기능은 이 정책 정의만을 이유로 즉시 삭제하지 않는다. 기능 이동 이후 필요에 따라 navigation 숨김이나 기존 endpoint 정리를 별도로 수행할 수 있다.

### global admin bulk management

- `/admin/teachers`와 `/admin/classrooms`는 global admin 전용 bulk management 영역이다.
- 학교 대표 선생님과 일반 선생님은 UI 노출 여부와 무관하게 `/admin/*` school operations endpoint에 접근할 수 없다.
- 실제 bulk UI와 update 처리 정책은 이 spec에서 구현 대상으로 삼지 않는다.

## 역할별 권한

### Global admin

global admin은 다음 권한을 가진다.

- 모든 학교 범위의 `/teachers`와 `/classrooms` 접근
- `/admin/teachers`와 `/admin/classrooms` 접근
- 학교 범위 제한 없이 teacher와 classroom 관리
- manager 계정의 활성/비활성 변경
- 기존 global admin 영역에서 manager role 승격/강등

global admin도 Pundit policy, `policy_scope`와 서버 검증을 우회하지 않는다. 교사와 교실의 학교가 다른 assignment 등 데이터 불변식을 만들 수 없다.

### 학교 대표 선생님

학교 대표 선생님의 모든 권한은 자신의 `SchoolMembership.school_id` 범위로 제한된다.

`/teachers`에서 다음을 할 수 있다.

- 자기 학교 teacher 조회 및 추가
- 자기 학교에 새 teacher를 생성할 때 최초 `password`와 `password_confirmation` 설정
- 자기 학교 teacher의 이름, 이메일, 성별, avatar 등 현재 starter가 지원하는 일반 profile 수정
- 자기 학교 일반 선생님(`SchoolMembership member`)의 활성/비활성 변경
- 자기 학교 teacher의 복수 담당 교실 배정·해제
- 자기 자신의 일반 profile 수정

다음은 할 수 없다.

- 다른 학교 teacher 조회·수정 또는 다른 학교로 이동
- teacher의 global admin 권한 부여·해제
- manager role 승격·강등
- 기존 teacher의 비밀번호 직접 변경 또는 초기화
- 자기 자신을 포함한 manager 계정의 활성/비활성 변경

manager lifecycle은 manager 수나 다른 active manager 존재 여부와 관계없이 global admin만 관리한다. 일반 profile 편집 권한과 lifecycle·role 변경 권한은 서로 분리한다.

`/classrooms`에서 다음을 할 수 있다.

- 자기 학교의 active·inactive classroom 조회
- 자기 학교에 classroom 추가
- 교실 이름과 학년 등 구조 정보 수정
- 복수 담당 teacher 배정·해제
- classroom 활성/비활성 전환과 재활성화

다른 학교 classroom은 URL이나 parameter 조작으로도 조회·수정할 수 없다.

### 일반 선생님

- `/teachers`와 `/admin/*` school operations 영역에 접근할 수 없다.
- `/classrooms` 접근 범위는 자신이 teacher `ClassroomMembership`을 가진 active classroom으로 제한한다.
- 담당 active classroom이 0개이면 접근 가능한 담당 교실이 없다는 정상 안내 상태를 보여준다.
- 담당 active classroom이 1개이면 `/classrooms` 목록 대신 해당 `/classrooms/:id`로 바로 진입한다.
- 담당 active classroom이 2개 이상이면 `/classrooms` 목록에 자신의 담당 active classroom만 표시한다.
- 담당 active classroom에서는 학생 명부, 학생 정보, 학생 PIN 등 기존 운영 권한을 사용할 수 있다.
- 교실 이름·학년, 담당 teacher, classroom 활성 상태, 학교 구조를 변경할 수 없다.

## 복수 교사와 복수 담당 교실

- 한 teacher가 같은 학교의 여러 classroom을 담당할 수 있다.
- 한 classroom을 같은 학교의 여러 active teacher가 담당할 수 있다.
- 관계의 canonical source of truth는 `ClassroomMembership(role: "teacher")`다.
- `/teachers`는 teacher 관점에서 복수 담당 classroom을 관리한다.
- `/classrooms`는 classroom 관점에서 복수 담당 teacher를 관리한다.
- 단일 `Classroom.teacher_id` 구조로 변경하지 않으며 `SchoolMembership`에 teacher의 단일 grade를 추가하지 않는다.

## Teacher lifecycle

Teacher lifecycle은 기존 `User.active`를 사용한다.

### Active teacher

- 정상 로그인과 운영이 가능하다.
- 조건을 충족하는 새 teacher `ClassroomMembership`에 배정될 수 있다.

### Inactive teacher

- 로그인할 수 없다.
- 새 담당 classroom에 배정될 수 없다.
- 일반 운영 권한을 갖지 않는다.
- 기존 `SchoolMembership`, `ClassroomMembership`과 과거 서비스 기록을 삭제하지 않는다.
- 기존 teacher membership이 있어도 classroom 조회나 mutation 권한을 얻지 않는다.

비활성화는 삭제가 아니다. 재활성화하면 보존된 membership과 기록을 유지하며, 다른 활성 조건과 권한 검증을 다시 충족할 때 기존 담당 관계를 통해 운영할 수 있다.

학교 대표 선생님은 자기 학교의 member teacher만 비활성화·재활성화할 수 있다. manager 계정 lifecycle과 manager role 변경은 global admin만 수행한다.

## Classroom lifecycle

`Classroom`에 다음 공통 lifecycle 속성을 도입한다.

```text
active:boolean, default: true, null: false
```

이번 spec 단계에서는 migration을 만들지 않는다.

### Active classroom

- 정상 운영할 수 있다.
- 신규 student 및 teacher membership을 배정할 수 있다.
- 일반 선생님의 담당 교실 목록과 직접 진입 대상이 될 수 있다.

### Inactive classroom

- 삭제하지 않고 기존 membership과 학생·서비스 기록을 보존한다.
- 신규 student와 teacher를 배정할 수 없다.
- 학생 관리 등 일반 운영 mutation을 허용하지 않는다.
- 일반 선생님의 목록, 자동 진입과 정상 운영 대상에서 제외한다.
- 학교 대표 선생님은 자기 학교 범위에서, global admin은 관리 권한 범위에서 조회하고 재활성화할 수 있다.

inactive School에 대한 기존 lifecycle과 접근 차단이 상위 경계다. classroom의 active 상태가 inactive School의 운영을 다시 허용하거나 기존 School policy를 우회하지 않는다.

## 교사·교실 배정 불변식

새 teacher assignment를 만들 때 다음을 모두 만족해야 한다.

- 대상 사용자는 active teacher다.
- 대상 classroom은 active다.
- teacher의 `SchoolMembership.school_id`와 `Classroom.school_id`가 같다.
- 학교 대표 선생님의 변경 대상은 자기 학교에 한정된다.

global admin도 학교 불일치 assignment를 만들 수 없다. inactive teacher 또는 inactive classroom에는 신규 관계를 만들 수 없다. lifecycle 전환만으로 기존 membership을 강제 삭제하지 않는다.

신규 student assignment도 active classroom에만 허용한다. inactive School에 대한 기존 배정 제한을 함께 적용한다.

## 삭제 정책

- 활성/비활성이 teacher와 classroom의 기본 lifecycle이다.
- 학교 대표 선생님은 teacher나 classroom을 삭제하지 않고 비활성화한다.
- 이 spec은 teacher 물리 삭제 권한을 확대하지 않는다. global admin의 실제 teacher 삭제 허용 여부와 조건은 별도 정책으로 남긴다.
- global admin의 classroom 삭제는 잘못 생성된 빈 교실 등 제한적인 정리 용도를 지향한다.
- student/teacher membership 또는 서비스 기록이 있는 classroom은 삭제하지 않고 비활성 상태로 보존한다.
- 현재 `Classroom`의 delete protection을 약화하지 않는다.
- 이 삭제 방향을 위해 이번 spec 단계에서 새 삭제 기능을 만들지 않는다.

## `/teachers` 일반 운영 영역

권한 범위는 다음과 같다.

- global admin: 모든 학교
- 학교 대표 선생님: 자기 학교
- 일반 선생님: 접근 불가

기본 기능은 teacher 목록, teacher 추가, 일반 profile 편집과 복수 담당 classroom 배정·해제다. 학교 대표 선생님은 자기 학교의 `SchoolMembership member` teacher만 활성/비활성 변경할 수 있고, global admin은 member teacher와 manager teacher 모두 활성/비활성 변경할 수 있다. manager role 승격·강등은 기존처럼 global admin 전용이다. global admin에게는 학교 범위 선택을 제공할 수 있지만 학교 대표 선생님에게 다른 학교 선택 UI나 parameter를 제공하지 않는다. 모든 record 조회와 변경은 서버에서 역할별 school scope를 다시 검증한다.

학교 대표 선생님은 자기 학교에 새 teacher를 생성할 때 최초 인증 정보를 설정하기 위해 `password`와 `password_confirmation`을 입력할 수 있다. global admin의 기존 teacher 생성 password 흐름도 유지한다.

기존 teacher를 update할 때 학교 대표 선생님에게 허용되는 속성은 name, email, gender, avatar와 허용된 classroom assignments 등 일반 profile·운영 정보로 제한한다. update strong parameters에는 `password`와 `password_confirmation`을 허용하지 않으며, 일반 profile 수정 권한이 비밀번호 변경 권한으로 확대되어서는 안 된다. 기존 teacher의 비밀번호 변경·초기화는 별도 password reset 정책으로 정의하기 전까지 이 기능의 범위에 포함하지 않는다.

## `/classrooms` 일반 운영 영역

권한 범위는 다음과 같다.

- global admin: 모든 학교의 관리 가능한 classroom
- 학교 대표 선생님: 자기 학교의 active·inactive classroom
- 일반 선생님: 자신이 담당하는 active classroom

global admin과 학교 대표 선생님은 권한 범위에서 classroom 추가, 이름·학년 수정, 복수 담당 teacher 배정·해제, 활성/비활성 전환을 할 수 있다. 일반 선생님은 구조를 변경하지 않고 담당 active classroom의 학생·운영 기능만 사용한다.

학년 값, 표시, 목록 필터와 정렬은 [Classroom Grade Foundation](classroom_grade_foundation.md)을 유지한다. lifecycle 필터는 grade와 school filter를 적용하기 전 역할별 `policy_scope`에서 허용된 범위를 넘어서는 결과를 만들 수 없다.

## `/admin` bulk management 경계

향후 `/admin/teachers`와 `/admin/classrooms`는 표 기반 bulk management UX를 참고할 수 있으나 다음 정책을 지킨다.

- global admin only
- 한 번에 한 학교를 선택해 관리
- policy 또는 scope 밖 record 수정 금지
- starter의 복수 teacher·복수 classroom membership 모델 유지
- 투표 앱의 `login_id`, 단일 `teacher_id`, `SchoolMembership.grade`, `class_label`, `school_year` 구조를 복제하지 않음

bulk update의 atomic transaction, row validation, rollback, dirty tracking은 별도 canonical spec에서 정의한다.

## 운영 후보 선택 UI의 확장성

### 공통 후보 선택 원칙

학교 운영 UI에서 teacher 또는 classroom 후보를 선택할 때 전체 후보를 무제한으로 한 번에 렌더링하지 않는다. 먼저 사용자가 관리할 수 있는 school scope를 확정한 뒤 그 school 안에서만 후보를 조회하고, 현재 모델에 존재하거나 기존 관계에서 파생할 수 있는 기준으로 후보를 좁힌다.

- server-side policy scope와 validation을 최종 권한 경계로 사용하며 검색과 필터는 그 범위를 넓힐 수 없다.
- 모든 school의 후보 데이터를 HTML이나 JavaScript에 미리 내려받고 화면에서 숨기는 방식은 사용하지 않는다.
- 필요하면 GET query parameter, Turbo Frame 부분 갱신 또는 server-side pagination으로 필요한 범위만 조회한다.
- 구체적인 전송 방식은 구현 시점의 starter 구조와 데이터 규모에 맞는 가장 단순한 방식을 선택하며 autocomplete나 외부 검색 library 도입을 요구하지 않는다.
- 후보 조회에서 N+1 query를 만들지 않는다.
- 필터 편의를 위한 `teacher.grade`, `SchoolMembership.grade` 등의 중복 속성이나 별도 Grade 모델을 추가하지 않는다.

### Teacher의 학년 파생 의미

teacher의 학년은 별도 저장 값이 아니라 `ClassroomMembership(role: teacher)`과 연결된 `Classroom.grade`에서 파생한다.

- `1학년`부터 `6학년`: 해당 grade의 classroom에 teacher membership이 하나라도 있는 teacher
- `미배정`: teacher 역할의 `ClassroomMembership`이 하나도 없는 teacher
- `전체`: 현재 허용된 school scope의 모든 대상 teacher

한 teacher가 여러 학년의 classroom을 담당하면 해당하는 각 학년 필터 결과에 모두 포함한다.

### `/teachers/new`, `/teachers/:id/edit` classroom picker

global admin은 teacher form에서 school을 먼저 선택하고, 선택한 school의 active classroom만 assignment 후보로 조회한다. 그 후보를 `Classroom.grade`의 전체 또는 1학년부터 6학년 기준으로 좁힌 뒤 복수 선택할 수 있다. 선택하지 않은 다른 school의 classroom은 HTML 후보 목록에 포함하지 않는다.

학교 대표 선생님의 school은 자신의 membership이 속한 학교로 고정한다. school 선택 UI를 제공하지 않으며 자기 학교의 active classroom만 전체 또는 1학년부터 6학년 기준으로 좁혀 복수 선택할 수 있다.

두 역할 모두 inactive classroom을 신규 assignment 후보로 받지 않는다. 기존 teacher에게 이미 연결된 inactive classroom membership은 picker 필터링이나 update 때문에 우발적으로 삭제하지 않는다. 다른 school 또는 inactive classroom ID를 직접 제출해도 서버에서 거부한다. 버튼, tab 또는 select 중 구체적인 grade filter UI는 기존 starter UI와의 일관성을 기준으로 구현 단계에서 결정한다.

### `/schools/:id/edit` 대표 선생님 picker

대표 선생님 후보는 global admin이 선택한 현재 school에 소속된 active teacher로 제한한다. 모든 teacher를 긴 `<select>`에 무제한으로 렌더링하는 형태로 고정하지 않고, 다음 기준을 server-side scope 안에서 조합해 좁힐 수 있게 한다.

- 검색: 이름 또는 이메일
- 학년: 전체, 1학년부터 6학년, 미배정

학년과 미배정의 의미는 이 문서의 teacher 학년 파생 정의를 따른다. 후보에는 동명이인을 구별할 수 있도록 이름, 이메일과 현재 담당 classroom 요약을 함께 표시한다. 담당 classroom이 없는 teacher는 미배정 상태를 명확히 표시한다.

이 picker는 manager role의 승격·강등 권한을 변경하지 않는다. 대표 선생님 선택과 role 변경은 기존 정책대로 global admin만 수행한다.

## 권한 검증 원칙

- navigation과 UI 숨김은 편의 수단이며 권한의 최종 방어선이 아니다.
- Pundit policy와 `policy_scope`로 읽기·행위 범위를 제한한다.
- controller와 domain validation에서 school 및 lifecycle 불변식을 다시 검증한다.
- `school_id`, `teacher_id`, `classroom_id` 등 URL·parameter 조작으로 허용 범위를 넘을 수 없어야 한다.
- inactive teacher, inactive classroom과 inactive School 상태를 mutation 시점에 서버에서 확인한다.
- profile 편집, lifecycle 변경, role 변경은 각각 독립된 권한으로 검사한다.

## 현재 코드와 구현 선행조건

다음은 canonical policy와 현재 구현의 차이이며 후속 구현에서 해소한다.

1. `Schools::TeachersController#teacher_params`는 create와 update에 공통으로 password 관련 parameter를 허용한다. `/teachers` 일반 운영 구현에서는 manager의 create에만 최초 `password`와 `password_confirmation`을 허용하고 update에서는 제외하도록 strong parameters를 분리해야 한다.
2. `UserPolicy#update?`는 현재 global admin만 허용한다. 자기 학교 manager의 일반 teacher profile 편집 권한을 profile 전용 정책 경계로 추가해야 한다.
3. `Classroom.active`가 없다. 후속 migration에서 `default: true`, `null: false`로 추가하고 model, policy와 scope에 반영해야 한다.
4. inactive classroom의 신규 assignment와 일반 mutation을 차단하는 서버 검증이 없다.
5. 일반 teacher의 담당 active classroom 1개 자동 진입 정책이 구현되어 있지 않다.
6. 일반 `/teachers` route와 `/admin/classrooms`가 없다. 후속 책임 이동과 bulk 영역 구현이 필요하다.
7. 현재 `ClassroomPolicy::Scope`와 `/classrooms` controller는 classroom lifecycle을 구분하지 않는다. manager/admin 관리 조회와 일반 teacher 운영 조회를 역할에 맞게 분리해야 한다.
8. `Teachers::SaveWithAssignments`와 assignment 입력 경로는 inactive teacher와 inactive classroom의 신규 배정을 명시적으로 차단하도록 보강해야 한다.
9. 현재 `Classroom` delete protection은 student membership을 중심으로 한다. 기존 보호를 약화하지 않고 teacher membership 및 서비스 기록이 있는 classroom의 보존 정책을 충족해야 한다.

## Acceptance criteria

1. global admin은 policy와 scope 안에서 모든 학교의 `/teachers`와 `/classrooms`를 관리할 수 있다.
2. 학교 대표 선생님은 `/teachers`에서 자기 학교 teacher만 조회·추가·수정할 수 있다.
3. 학교 대표 선생님은 `/classrooms`에서 자기 학교 classroom만 조회·추가·수정할 수 있다.
4. 학교 대표 선생님은 URL 또는 parameter 조작으로 다른 학교 teacher나 classroom을 조회·수정할 수 없다.
5. 일반 선생님은 `/teachers`와 `/admin/*` school operations endpoint에 접근할 수 없다.
6. 일반 선생님의 담당 active classroom이 하나이면 해당 classroom으로 바로 진입한다.
7. 담당 active classroom이 복수이면 `/classrooms`에 그 teacher의 담당 active classroom만 표시한다.
8. 담당 active classroom이 없으면 오류가 아닌 정상 안내 상태를 표시한다.
9. 한 active teacher가 같은 학교의 여러 active classroom을 담당할 수 있다.
10. 한 active classroom을 같은 학교의 여러 active teacher가 담당할 수 있다.
11. inactive teacher는 로그인하거나 새 담당 classroom을 배정받을 수 없고 기존 membership만으로 운영 권한을 얻지 않는다.
12. inactive classroom에는 새 student나 teacher를 배정할 수 없다.
13. classroom 비활성화는 기존 membership과 학생·서비스 기록을 보존한다.
14. inactive classroom은 일반 선생님의 목록, 자동 진입과 mutation 대상에서 제외된다.
15. 학교 대표 선생님과 global admin은 각자의 관리 범위에서 inactive classroom을 조회하고 재활성화할 수 있다.
16. 학교 대표 선생님은 자기 학교에 새 teacher를 생성할 때 최초 `password`와 `password_confirmation`을 설정할 수 있다.
17. 학교 대표 선생님은 자기 학교 teacher와 자신의 이름·이메일·성별·avatar 등 일반 profile을 수정할 수 있지만 기존 teacher의 `password`와 `password_confirmation`은 update할 수 없다.
18. 학교 대표 선생님의 일반 profile 수정 권한은 기존 teacher의 비밀번호 변경·초기화 권한으로 확대되지 않는다.
19. 학교 대표 선생님은 teacher를 다른 학교로 이동하거나 manager role 또는 global admin 권한을 변경할 수 없다.
20. 학교 대표 선생님은 자기 자신이나 같은 학교의 다른 manager 계정을 비활성화·재활성화할 수 없다.
21. manager 계정의 활성/비활성 및 manager role 승격·강등은 global admin만 수행할 수 있다.
22. teacher와 classroom의 lifecycle 전환은 기존 membership과 과거 기록을 삭제하지 않는다.
23. 신규 teacher assignment는 active teacher, active classroom과 동일 학교 조건을 모두 만족해야 한다.
24. `/admin/teachers`와 `/admin/classrooms` school operations 화면은 global admin만 접근할 수 있다.
25. classroom 학년 동작은 `classroom_grade_foundation.md`의 데이터·표시·필터·정렬 정책을 유지한다.
26. global admin의 teacher form은 모든 학교의 classroom을 한 번에 렌더링하지 않는다.
27. global admin은 school을 먼저 선택하고 해당 school의 active classroom만 assignment 후보로 조회한다.
28. 학교 대표 선생님의 teacher form은 자기 학교의 classroom만 후보로 조회한다.
29. teacher form의 classroom 후보는 `Classroom.grade`의 전체 또는 1학년부터 6학년 기준으로 좁힐 수 있다.
30. 다른 school 또는 inactive classroom의 신규 assignment는 직접 parameter를 제출해도 서버에서 차단된다.
31. 기존 inactive classroom assignment는 form의 후보 filtering이나 update 때문에 우발적으로 삭제되지 않는다.
32. teacher의 학년은 별도 저장하지 않고 teacher `ClassroomMembership`과 `Classroom.grade`에서 파생한다.
33. 여러 학년을 담당하는 teacher는 해당하는 각 학년 filter 결과에 모두 포함된다.
34. teacher membership이 없는 teacher는 미배정 filter로 조회할 수 있다.
35. school manager 후보 검색은 현재 school에 소속된 active teacher만 대상으로 한다.
36. school manager 후보는 이름 또는 이메일로 검색할 수 있다.
37. 동명이인 후보는 이메일과 현재 담당 classroom 정보로 구별할 수 있고, 담당 classroom이 없으면 미배정 상태를 표시한다.
38. teacher와 classroom 후보 선택 UI는 scope 전체 데이터를 무제한으로 사전 loading하거나 숨겨서 rendering하지 않는다.
39. 후보 검색, grade filtering과 직접 parameter 조작은 policy scope 또는 authorization 범위를 넓히지 않는다.

## 제약

- 이 spec 단계에서는 구현, migration, route 변경 또는 기존 endpoint 삭제를 하지 않는다.
- lifecycle 구현은 기존 membership과 과거 서비스 기록을 파괴하지 않아야 한다.
- 기존 Pundit 경계를 우회하는 별도 조회나 update 경로를 만들지 않는다.
- 일반 운영 책임 이동과 bulk management 구현은 단계적으로 진행할 수 있지만 최종 권한 경계는 이 문서를 따른다.

## Non-goals

- 쑥쑥교실투표 코드 직접 복사
- `/admin` bulk management 실제 구현
- teacher 또는 classroom 물리 삭제 기능 확대
- `SchoolMembership.grade` 추가
- `Classroom.teacher_id` 추가 또는 단일 담임 구조로 변경
- 학년도 `school_year` 도입
- `class_label` 도입
- 교사 비밀번호 관리 또는 초기화 정책
- global admin 역할 편집
- manager 승격·강등 UI 변경
- 학생 도메인 재설계
- 성장기록 기능
- 서비스별 비즈니스 기능 추가
- teacher/classroom picker의 controller, view, policy, route, Stimulus 또는 Turbo Frame 구현
- 후보 pagination 또는 autocomplete 구현과 외부 검색 library 도입
