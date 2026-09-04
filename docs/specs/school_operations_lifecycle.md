# School Operations Lifecycle

## 목적

학교 공통 starter에서 teacher와 classroom의 운영 lifecycle, 역할별 접근·관리 권한, 일반 운영 영역과 향후 global admin bulk management 영역의 경계를 정의한다. teacher와 classroom의 단일 담당 관계를 명확히 하고 활성 상태를 일상적인 운영 lifecycle로 사용한다.

## 용어와 현재 구조

- global admin은 `User.role == "admin"`인 사용자다.
- 학교 대표 선생님은 `User.role == "teacher"`이고 해당 학교의 `SchoolMembership.role == "manager"`인 사용자다.
- 일반 선생님은 `User.role == "teacher"`이고 `SchoolMembership.role == "member"`인 사용자다.
- teacher는 최대 하나의 `SchoolMembership`으로 학교에 속한다.
- teacher와 classroom의 현재 담당 관계는 nullable `Classroom.teacher_id`로 표현한다.
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
- 자기 학교 teacher의 단일 담당 교실 배정·해제
- 자기 자신의 일반 profile 수정

다음은 할 수 없다.

- 다른 학교 teacher 조회·수정 또는 다른 학교로 이동
- teacher의 global admin 권한 부여·해제
- manager role 승격·강등
- 기존 teacher의 비밀번호 직접 변경 또는 초기화
- 자기 자신을 포함한 manager 계정의 활성/비활성 변경

manager lifecycle은 manager 수나 다른 active manager 존재 여부와 관계없이 global admin만 관리한다. 일반 profile 편집 권한과 lifecycle·role 변경 권한은 서로 분리한다.

학교 대표 선생님은 학교마다 0명 또는 1명이다. 저장 구조는 기존 `SchoolMembership.role == "manager"`를 유지하고 `School.manager_id` 같은 중복 pointer를 추가하지 않는다. 같은 school의 manager membership은 최대 하나만 허용하며 global admin은 school manager 수에 포함하지 않는다. 초기 설정이나 교체 과정에서 manager가 잠시 없을 수 있지만 두 명 이상이 동시에 manager일 수는 없다. manager 지정·교체·해제는 global admin만 수행한다.

`/classrooms`에서 다음을 할 수 있다.

- 자기 학교의 active·inactive classroom 조회
- 자기 학교에 classroom 추가
- 교실 이름과 학년 등 구조 정보 수정
- 단일 담당 teacher 배정·해제
- classroom 활성/비활성 전환과 재활성화

다른 학교 classroom은 URL이나 parameter 조작으로도 조회·수정할 수 없다.

### 일반 선생님

- `/teachers`와 `/admin/*` school operations 영역에 접근할 수 없다.
- `/classrooms` 접근 범위는 `teacher_id`로 자신에게 배정된 active classroom으로 제한한다.
- 담당 active classroom이 0개이면 접근 가능한 담당 교실이 없다는 정상 안내 상태를 보여준다.
- 담당 active classroom이 1개이면 `/classrooms` 목록 대신 해당 `/classrooms/:id`로 바로 진입한다.
- 담당 active classroom에서는 학생 명부, 학생 정보, 학생 PIN 등 기존 운영 권한을 사용할 수 있다.
- 교실 이름·학년, 담당 teacher, classroom 활성 상태, 학교 구조를 변경할 수 없다.

## Teacher와 Classroom의 단일 담당 관계

- teacher는 담당 classroom이 없거나 정확히 하나다.
- classroom은 담당 teacher가 없거나 정확히 한 명이다.
- 현재 담당 관계의 canonical source of truth는 nullable `Classroom.teacher_id`다.
- `Classroom`은 teacher `User`를 optional association으로 참조하고 teacher는 최대 하나의 classroom을 가진다. 정확한 Rails association 이름은 구현 시 기존 `User` naming에 맞춘다.
- DB의 nullable `teacher_id` foreign key와 null이 아닌 값에 대한 unique index로 한 teacher가 여러 classroom을 동시에 담당하지 못하게 한다.
- `Classroom.teacher_id` 자체가 단일 값이므로 한 classroom에 여러 teacher를 배정하지 않는다.
- 신규 teacher `ClassroomMembership`은 생성하지 않는다. `ClassroomMembership`은 학생의 classroom 소속과 그에 필요한 기존 책임만 유지한다.

### 기존 teacher assignment 이전

기존 `ClassroomMembership(role: "teacher")` 데이터는 구현 단계에서 `Classroom.teacher_id`로 이전한 뒤 teacher assignment 책임에서 제거한다. 기존 데이터가 teacher와 classroom 양쪽에서 1:1로 호환될 때만 대응하는 `teacher_id`로 이전한다.

한 teacher가 여러 classroom을 담당하거나 한 classroom에 여러 teacher가 연결된 충돌 데이터가 있으면 migration이 임의의 관계를 선택하지 않는다. 구현 전에 실제 데이터를 점검하고 충돌을 명시적으로 정리한 뒤 이전한다. starter의 seed와 spec fixture도 새 invariant에 맞춘다. silent data loss는 허용하지 않는다.

## Teacher lifecycle

Teacher lifecycle은 기존 `User.active`를 사용한다.

### Active teacher

- 정상 로그인과 운영이 가능하다.
- 조건을 충족하는 active classroom 하나에 배정될 수 있다.

### Inactive teacher

- 로그인할 수 없다.
- 새 담당 classroom에 배정될 수 없다.
- 일반 운영 권한을 갖지 않는다.
- `SchoolMembership`과 과거 서비스 기록을 삭제하지 않는다.
- 비활성화 transaction에서 현재 담당 classroom의 `teacher_id`를 `nil`로 변경한다.

비활성화는 삭제가 아니다. 재활성화하면 membership과 과거 기록은 유지하지만 과거 담당 classroom은 자동 복원하지 않는다. 필요하면 활성 조건과 권한 검증 아래 다시 명시적으로 배정한다.

학교 대표 선생님은 자기 학교의 member teacher만 비활성화·재활성화할 수 있다. manager 계정 lifecycle과 manager role 변경은 global admin만 수행한다.

## Classroom lifecycle

`Classroom`에 다음 공통 lifecycle 속성을 도입한다.

```text
active:boolean, default: true, null: false
```

이번 spec 단계에서는 migration을 만들지 않는다.

### Active classroom

- 정상 운영할 수 있다.
- 신규 student membership과 단일 active teacher를 배정할 수 있다.
- 일반 선생님의 담당 교실 목록과 직접 진입 대상이 될 수 있다.

### Inactive classroom

- 삭제하지 않고 기존 student membership과 학생·서비스 기록을 보존한다.
- 신규 student와 teacher를 배정할 수 없다.
- 비활성화 transaction에서 현재 `teacher_id`를 `nil`로 변경한다.
- 학생 관리 등 일반 운영 mutation을 허용하지 않는다.
- 일반 선생님의 목록, 자동 진입과 정상 운영 대상에서 제외한다.
- 학교 대표 선생님은 자기 학교 범위에서, global admin은 관리 권한 범위에서 조회하고 재활성화할 수 있다.

inactive School에 대한 기존 lifecycle과 접근 차단이 상위 경계다. classroom의 active 상태가 inactive School의 운영을 다시 허용하거나 기존 School policy를 우회하지 않는다.

classroom을 재활성화해도 과거 담당 teacher를 자동 복원하지 않는다. 필요하면 active teacher를 다시 명시적으로 배정한다.

## 교사·교실 배정 불변식

teacher를 classroom에 배정할 때 다음을 모두 만족해야 한다.

- 대상 사용자는 active teacher다.
- 대상 classroom은 active다.
- teacher의 `SchoolMembership.school_id`와 `Classroom.school_id`가 같다.
- teacher의 `SchoolMembership.grade`와 `Classroom.grade`가 같고 grade가 `nil`이 아니다.
- teacher에게 다른 담당 classroom이 없다.
- classroom에 다른 담당 teacher가 없다.
- 학교 대표 선생님의 변경 대상은 자기 학교에 한정된다.

global admin도 이 불변식을 우회할 수 없다. 다른 school, 다른 grade, inactive teacher, inactive classroom 또는 이미 배정된 teacher/classroom ID를 직접 제출해도 거부한다.

teacher의 담당 classroom을 바꾸면 기존 classroom의 `teacher_id` 해제와 새 classroom의 `teacher_id` 설정을 하나의 transaction에서 처리한다. 미배정으로 변경하면 기존 `teacher_id`만 해제한다. 이 변경은 현재 운영 관계만 갱신하며 과거 서비스 기록이나 작성자 정보를 삭제하지 않는다.

teacher의 grade가 `nil`이면 classroom을 배정할 수 없다. 담당 classroom이 있는 teacher의 grade를 다른 값으로 변경할 때 기존 classroom을 유지할 수 없으며, 새 grade의 classroom을 선택하거나 미배정으로 저장해야 한다. grade 변경은 기존 classroom assignment를 자동으로 다른 classroom에 옮기지 않는다.

담당 teacher가 있는 classroom의 grade 변경으로 teacher의 membership grade와 불일치가 생기면 저장을 거부한다. 기본 운영 경로에서는 teacher grade를 자동 연쇄 변경하지 않으며 먼저 담당 teacher를 해제해야 한다.

신규 student assignment도 active classroom에만 허용한다. inactive School에 대한 기존 배정 제한을 함께 적용한다.

## 삭제 정책

- 활성/비활성이 teacher와 classroom의 기본 lifecycle이다.
- 학교 대표 선생님은 teacher나 classroom을 삭제하지 않고 비활성화한다.
- 이 spec은 teacher 물리 삭제 권한을 확대하지 않는다. global admin의 실제 teacher 삭제 허용 여부와 조건은 별도 정책으로 남긴다.
- global admin의 classroom 삭제는 잘못 생성된 빈 교실 등 제한적인 정리 용도를 지향한다.
- student membership 또는 서비스 기록이 있는 classroom은 삭제하지 않고 비활성 상태로 보존한다.
- 현재 `Classroom`의 delete protection을 약화하지 않는다.
- 이 삭제 방향을 위해 이번 spec 단계에서 새 삭제 기능을 만들지 않는다.

## `/teachers` 일반 운영 영역

권한 범위는 다음과 같다.

- global admin: 모든 학교
- 학교 대표 선생님: 자기 학교
- 일반 선생님: 접근 불가

기본 기능은 teacher 목록, teacher 추가, 일반 profile 편집과 단일 담당 classroom 배정·해제다. 학교 대표 선생님은 자기 학교의 `SchoolMembership member` teacher만 활성/비활성 변경할 수 있고, global admin은 member teacher와 manager teacher 모두 활성/비활성 변경할 수 있다. manager role 승격·강등은 기존처럼 global admin 전용이다. global admin에게는 학교 범위 선택을 제공할 수 있지만 학교 대표 선생님에게 다른 학교 선택 UI나 parameter를 제공하지 않는다. 모든 record 조회와 변경은 서버에서 역할별 school scope를 다시 검증한다.

학교 대표 선생님은 자기 학교에 새 teacher를 생성할 때 최초 인증 정보를 설정하기 위해 `password`와 `password_confirmation`을 입력할 수 있다. global admin의 기존 teacher 생성 password 흐름도 유지한다.

기존 teacher를 update할 때 학교 대표 선생님에게 허용되는 속성은 name, email, gender, avatar와 허용된 classroom assignments 등 일반 profile·운영 정보로 제한한다. update strong parameters에는 `password`와 `password_confirmation`을 허용하지 않으며, 일반 profile 수정 권한이 비밀번호 변경 권한으로 확대되어서는 안 된다. 기존 teacher의 비밀번호 변경·초기화는 별도 password reset 정책으로 정의하기 전까지 이 기능의 범위에 포함하지 않는다.

## `/classrooms` 일반 운영 영역

권한 범위는 다음과 같다.

- global admin: 모든 학교의 관리 가능한 classroom
- 학교 대표 선생님: 자기 학교의 active·inactive classroom
- 일반 선생님: 자신이 담당하는 active classroom

global admin과 학교 대표 선생님은 권한 범위에서 classroom 추가, 이름·학년 수정, 단일 담당 teacher 배정·해제, 활성/비활성 전환을 할 수 있다. 일반 선생님은 구조를 변경하지 않고 담당 active classroom의 학생·운영 기능만 사용한다.

학년 값, 표시, 목록 필터와 정렬은 [Classroom Grade Foundation](classroom_grade_foundation.md)을 유지한다. lifecycle 필터는 grade와 school filter를 적용하기 전 역할별 `policy_scope`에서 허용된 범위를 넘어서는 결과를 만들 수 없다.

## `/admin` bulk management 경계

향후 `/admin/teachers`와 `/admin/classrooms`는 표 기반 bulk management UX를 참고할 수 있으나 다음 정책을 지킨다.

- global admin only
- 한 번에 한 학교를 선택해 관리
- policy 또는 scope 밖 record 수정 금지
- starter의 단일 teacher assignment와 학생용 classroom membership 모델 유지
- 투표 앱의 `login_id`, `class_label`, `school_year` 구조를 복제하지 않음

bulk update의 atomic transaction, row validation, rollback, dirty tracking은 별도 canonical spec에서 정의한다.

## Teacher의 school-context 학년 정책

### Teacher 학년

teacher의 school-context 학년은 `SchoolMembership.grade`다. 현재 school 운영에서 teacher가 속한 학년이며 classroom assignment 없이도 독립적으로 저장할 수 있다.

학년은 teacher 개인의 전역 속성이 아니므로 `User.grade`를 만들지 않는다. 같은 teacher라도 school context에 속한 운영 정보이며 canonical source는 `SchoolMembership.grade`다.

`SchoolMembership.grade`는 nullable integer로 두고 `nil` 또는 정수 1부터 6까지만 허용한다. 이 정책은 teacher membership의 학년에 적용하며 student membership의 학년 의미를 이번 범위에서 확장하지 않는다. 기존 membership role과 lifecycle 정책을 유지한다.

teacher form의 classroom 후보는 teacher와 같은 school, `SchoolMembership.grade`와 같은 grade, active 상태이며 담당 teacher가 없는 classroom으로 제한한다. edit에서는 현재 teacher가 담당하는 classroom을 현재 선택값으로 포함할 수 있다. active teacher, teacher school membership 존재와 same-school 불변식도 함께 적용한다.

teacher 생성 시 school은 기존 정책대로 필요하고 학년은 `nil` 또는 1부터 6 중 하나이며 classroom assignment는 없거나 하나다. 따라서 classroom이 아직 없어도 school과 학년만으로 teacher를 생성할 수 있다.

teacher의 grade와 담당 classroom grade는 연결 상태에서 항상 일치해야 한다. grade를 변경해 불일치가 생기면 기존 담당 관계를 유지할 수 없으며 새 grade의 classroom 하나를 선택하거나 미배정으로 저장한다. 현재 담당 관계를 해제해도 과거 서비스 기록은 삭제하지 않는다.

global admin은 관리 가능한 teacher의 `SchoolMembership.grade`를 설정·수정할 수 있다. 학교 대표 선생님은 자기 school의 ordinary member teacher에 대해 설정·수정할 수 있고, 자신의 일반 profile·운영 정보는 기존 canonical 권한 범위 안에서 수정할 수 있다. ordinary teacher는 `/teachers`에서 학년을 관리할 수 없으며 다른 school의 membership grade는 URL 또는 parameter 조작으로도 변경할 수 없다. 이 권한은 lifecycle이나 manager role 변경 권한을 확대하지 않는다.

teacher 운영 목록에서 기본 학년 표시는 `SchoolMembership.grade`를 사용하고 값이 없으면 미배정 또는 기존 locale의 동일 의미를 표시한다. 학급은 `Classroom.teacher_id`로 연결된 단일 classroom을 표시하고 없으면 미배정으로 표시한다.

`school_memberships.grade` column은 nullable integer로 유지한다. 별도 Grade model이나 table은 만들지 않는다.

## 운영 후보 선택 UI의 확장성

### 공통 후보 선택 원칙

학교 운영 UI에서 teacher 또는 classroom 후보를 선택할 때 전체 후보를 무제한으로 한 번에 렌더링하지 않는다. 먼저 사용자가 관리할 수 있는 school scope를 확정한 뒤 그 school 안에서만 후보를 조회하고, 현재 모델에 존재하거나 기존 관계에서 파생할 수 있는 기준으로 후보를 좁힌다.

- server-side policy scope와 validation을 최종 권한 경계로 사용하며 검색과 필터는 그 범위를 넓힐 수 없다.
- 모든 school의 후보 데이터를 HTML이나 JavaScript에 미리 내려받고 화면에서 숨기는 방식은 사용하지 않는다.
- 필요하면 GET query parameter, Turbo Frame 부분 갱신 또는 server-side pagination으로 필요한 범위만 조회한다.
- 구체적인 전송 방식은 구현 시점의 starter 구조와 데이터 규모에 맞는 가장 단순한 방식을 선택하며 autocomplete나 외부 검색 library 도입을 요구하지 않는다.
- 후보 조회에서 N+1 query를 만들지 않는다.
- 필터 편의를 위한 `teacher.grade` 등의 중복 속성이나 별도 Grade 모델을 추가하지 않는다. teacher 학년에는 canonical `SchoolMembership.grade`를 사용한다.

### Teacher 학년 filter의 의미

teacher의 기본 학년 filter는 `SchoolMembership.grade`를 사용한다.

- `1학년`부터 `6학년`: `SchoolMembership.grade`가 해당 값인 teacher
- `미배정`: `SchoolMembership.grade`가 `nil`인 teacher
- `전체`: 현재 허용된 school scope의 모든 대상 teacher

teacher 학년 filter는 `SchoolMembership.grade`만 기준으로 한다. 현재 담당 학급은 `Classroom.teacher_id`로 연결된 단일 classroom이며 학년 filter의 source가 아니다.

### `/teachers/new`, `/teachers/:id/edit` classroom picker

teacher form은 school, 학년, 담당 classroom의 단일 단계형 흐름을 사용한다. 학년 select는 하나만 제공하며 그 값은 `SchoolMembership.grade`에 저장되는 동시에 classroom candidate를 좁히는 기준으로 사용한다.

global admin은 다음 순서로 선택한다.

1. school 선택
2. 학년 선택 또는 미배정
3. 선택한 school과 학년에 속한 active classroom 조회·표시
4. classroom 미배정 또는 하나 선택

학교 대표 선생님에게는 고정된 school 이름, 학년, 담당 classroom 순서로 제공하고 다른 school 선택 UI는 제공하지 않는다.

학년 옵션은 미배정과 1학년부터 6학년으로 한정하며 `전체 학년`을 제공하지 않는다. school이 없거나 학년이 정확한 1부터 6의 값이 아니면 classroom 후보를 empty scope로 처리하며 candidate query와 rendering을 하지 않는다. edit에서는 teacher의 현재 school과 persisted `SchoolMembership.grade`를 기본값으로 사용한다.

valid school과 학년이 선택되면 해당 school, 해당 grade와 active 상태를 모두 만족하고 다른 teacher에게 배정되지 않은 classroom만 후보로 조회·표시한다. edit에서는 현재 teacher 자신의 classroom을 현재 선택값으로 포함할 수 있다. 다른 school, 다른 grade, inactive 또는 이미 다른 teacher에게 배정된 classroom ID를 직접 제출해도 서버에서 거부한다.

`학교 및 담당 학급` 영역의 시각적 순서는 school, 학년, 담당 classroom으로 유지한다. 하위 후보를 아직 표시할 수 없는 상태에는 기존 locale과 UI style에 맞는 간단한 선택 안내를 표시할 수 있다.

학급 선택은 복수 checkbox나 누적 ID Set이 아닌 단일 select 또는 동등하게 단순한 single-choice UI를 사용한다. 별도의 `현재 담당 학급` summary 영역을 만들지 않고 현재 classroom을 선택값으로 표현한다. school이나 grade가 바뀌면 기존 선택을 초기화하고 새 범위의 후보를 조회한다. 사용자는 새 classroom 하나를 선택하거나 미배정으로 저장할 수 있다.

### `/schools/:id/edit` 대표 선생님 picker

대표 선생님 후보는 global admin이 선택한 현재 school에 소속된 active teacher로 제한한다. 모든 teacher를 긴 `<select>`에 무제한으로 렌더링하는 형태로 고정하지 않고, 다음 기준을 server-side scope 안에서 조합해 좁힐 수 있게 한다.

- 검색: 이름 또는 이메일
- 학년: 전체, 1학년부터 6학년, 미배정

학년 filter는 `SchoolMembership.grade`를 기준으로 하고 미배정은 그 값이 `nil`인 상태를 의미한다. 후보에는 동명이인을 구별할 수 있도록 이름, 이메일과 현재 단일 담당 classroom 정보를 함께 표시한다. 실제 담당 classroom이 없어도 teacher 학년이 있으면 해당 학년 filter에 포함한다. manager 후보는 정확히 한 명을 선택하며 여러 후보를 누적 선택하지 않는다.

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

1. 기존 teacher assignment code와 데이터는 `ClassroomMembership(role: "teacher")`를 사용한다. 구현 전에 1:1 호환 여부를 점검하고 충돌 데이터를 명시적으로 정리한 뒤 nullable `Classroom.teacher_id`로 이전해야 한다.
2. `Classroom.teacher_id`에는 `users` foreign key와 null이 아닌 값에 대한 unique index가 필요하다. 정확한 migration 순서와 DB constraint는 현재 schema와 실제 데이터 확인 후 정한다.
3. teacher assignment의 controller, service, policy, scope와 UI를 단일 `Classroom.teacher_id` 기준으로 변경하고 신규 teacher `ClassroomMembership` 생성을 제거해야 한다.
4. teacher 또는 classroom 비활성화 시 현재 assignment를 같은 transaction에서 해제하고, 재활성화 시 자동 복원하지 않도록 lifecycle 경로를 변경해야 한다.
5. classroom grade 변경은 담당 teacher의 membership grade와 충돌하면 거부하도록 서버 불변식을 추가해야 한다.
6. 같은 school의 manager membership을 최대 하나로 제한하는 model 및 DB 수준 invariant가 필요하다. 구현 전에 기존 복수 manager 데이터 유무를 확인하며 충돌이 있으면 임의 선택하지 않는다.
7. 일반 teacher의 담당 active classroom 1개 자동 진입과 manager/admin의 lifecycle 관리 UI는 후속 구현 대상이다.
8. 현재 `Classroom` delete protection을 약화하지 않고 student membership과 서비스 기록 보존 정책을 유지해야 한다.

## Acceptance criteria

1. global admin은 policy와 scope 안에서 모든 학교의 `/teachers`와 `/classrooms`를 관리할 수 있다.
2. 학교 대표 선생님은 `/teachers`에서 자기 학교 teacher만 조회·추가·수정할 수 있다.
3. 학교 대표 선생님은 `/classrooms`에서 자기 학교 classroom만 조회·추가·수정할 수 있다.
4. 학교 대표 선생님은 URL 또는 parameter 조작으로 다른 학교 teacher나 classroom을 조회·수정할 수 없다.
5. 일반 선생님은 `/teachers`와 `/admin/*` school operations endpoint에 접근할 수 없다.
6. teacher는 school에 소속되면서 `SchoolMembership.grade`와 담당 classroom이 모두 `nil`일 수 있다.
7. `SchoolMembership.grade`는 `nil` 또는 정수 1부터 6만 허용하고 `User.grade`나 별도 Grade model을 만들지 않는다.
8. teacher의 담당 classroom은 없거나 정확히 하나이고 classroom의 담당 teacher도 없거나 정확히 한 명이다.
9. 한 teacher가 두 classroom을 동시에 담당하거나 한 classroom을 두 teacher가 동시에 담당할 수 없다.
10. teacher assignment의 canonical source는 nullable `Classroom.teacher_id`이며 신규 teacher `ClassroomMembership`을 생성하지 않는다.
11. teacher와 classroom을 연결하면 양쪽 school과 grade가 각각 같아야 한다.
12. inactive teacher나 inactive classroom은 신규 assignment 대상이 될 수 없다.
13. 다른 teacher가 담당 중인 classroom을 직접 제출해도 배정할 수 없다.
14. teacher grade가 `nil`이면 classroom도 미배정이어야 한다.
15. teacher form은 school, 학년, 학급의 single-choice 흐름이며 복수 checkbox와 별도 현재 담당 학급 summary를 사용하지 않는다.
16. global admin은 valid school과 학년을 선택한 뒤에만 후보를 조회하고 manager는 자기 school의 valid 학년 범위에서만 후보를 조회한다.
17. classroom 후보는 선택 school, 선택 grade, active 상태를 만족하고 다른 teacher에게 배정되지 않은 classroom 및 edit 대상 teacher의 현재 classroom으로 제한한다.
18. teacher form의 학년 옵션은 미배정과 1학년부터 6학년만 제공하고 전체 학년은 제공하지 않는다.
19. school이나 grade가 없거나 유효하지 않으면 classroom 후보를 조회·표시하지 않는다.
20. teacher form에서 classroom을 선택하지 않고 school과 grade만 저장할 수 있으며 edit 재진입 시 persisted grade가 선택되어 있다.
21. teacher grade 변경으로 현재 classroom과 grade 불일치가 생기면 그 관계를 유지할 수 없고 새 grade classroom 또는 미배정을 명시적으로 선택해야 한다.
22. 담당 classroom 변경은 기존 `teacher_id` 해제와 새 `teacher_id` 설정을 하나의 transaction에서 처리한다.
23. 담당 teacher가 있는 classroom의 grade를 불일치 상태로 변경할 수 없으며 기본 운영에서는 먼저 assignment를 해제한다.
24. teacher를 deactivate하면 현재 classroom assignment를 해제하고 reactivation 시 자동 복원하지 않는다.
25. classroom을 deactivate하면 현재 teacher assignment를 해제하고 reactivation 시 자동 복원하지 않는다.
26. assignment 해제와 lifecycle 전환은 서비스 기록, 작성자 정보와 학생 membership을 삭제하지 않는다.
27. inactive classroom은 일반 선생님의 목록, 자동 진입과 mutation 대상에서 제외되며 manager와 global admin은 권한 범위에서 조회·재활성화할 수 있다.
28. 일반 선생님의 담당 active classroom이 하나이면 해당 classroom으로 바로 진입하고 없으면 정상 안내 상태를 표시한다.
29. 학교 대표 선생님은 자기 학교에 새 teacher를 생성할 때 최초 password를 설정할 수 있지만 기존 teacher의 password를 update할 수 없다.
30. 학교 대표 선생님은 허용된 일반 profile과 ordinary member teacher lifecycle만 관리하며 manager lifecycle·role이나 global admin 권한을 변경할 수 없다.
31. manager는 school마다 0명 또는 1명이고 두 명 이상의 manager membership을 동시에 저장할 수 없다.
32. manager 지정·교체·해제와 manager lifecycle 변경은 global admin만 수행한다.
33. manager의 canonical source는 `SchoolMembership.role`이며 `School.manager_id`를 추가하지 않는다.
34. school manager 후보는 현재 school의 active teacher만 대상으로 하며 이름, 이메일과 현재 단일 담당 classroom 정보로 구별할 수 있다.
35. school manager 후보의 grade filter는 `SchoolMembership.grade`를 사용하고 미배정은 grade가 `nil`인 상태다.
36. `/teachers` 목록은 school, `SchoolMembership.grade`, 단일 classroom과 상태를 표시하고 없는 학년 또는 학급은 미배정으로 표시한다.
37. `/classrooms` 목록은 school, 학년, 반, 단일 담당 teacher와 상태를 표시하고 teacher가 없으면 미배정으로 표시한다.
38. 기존 teacher `ClassroomMembership` 데이터는 1:1 호환 관계만 `Classroom.teacher_id`로 이전한다.
39. 기존 데이터에 다중 teacher 또는 다중 classroom 충돌이 있으면 migration이 임의 선택하지 않고 명시적 정리 후 이전한다.
40. teacher와 classroom 후보 UI는 전체 scope 데이터를 무제한으로 사전 loading하거나 숨겨서 rendering하지 않는다.
41. 후보 검색, filtering과 직접 parameter 조작은 policy scope 또는 authorization 범위를 넓히지 않는다.
42. `/admin/teachers`와 `/admin/classrooms` school operations 화면은 global admin만 접근할 수 있다.
43. `Classroom.grade`의 필수 1부터 6 데이터·표시·filter·정렬 정책은 `classroom_grade_foundation.md`를 유지한다.

## 제약

- 이 spec 단계에서는 구현, migration, route 변경 또는 기존 endpoint 삭제를 하지 않는다.
- lifecycle 구현은 학생 membership과 과거 서비스 기록을 파괴하지 않아야 한다. 현재 teacher assignment는 lifecycle 전환 시 정책에 따라 해제한다.
- 기존 Pundit 경계를 우회하는 별도 조회나 update 경로를 만들지 않는다.
- 일반 운영 책임 이동과 bulk management 구현은 단계적으로 진행할 수 있지만 최종 권한 경계는 이 문서를 따른다.

## Non-goals

- 쑥쑥교실투표 코드 직접 복사
- `/admin` bulk management 실제 구현
- teacher 또는 classroom 물리 삭제 기능 확대
- `User.grade` 추가
- teacher의 복수 classroom 담당 또는 classroom의 복수 teacher 담당
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
