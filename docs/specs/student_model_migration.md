# Student Model Migration

## 목적

학생을 staff 인증용 `User`와 분리하고 특정 학년도의 특정 Classroom에만 속하는 최소 `Student` 모델로 이전한다. 이 starter는 장기 학적·개인 identity 시스템이 아니라 학년도별 학급 활동과 보고서를 보존하는 캐주얼한 학급 서비스를 목표로 한다.

## 현재 runtime과 목표

현재 학생은 `User(role: student)`와 student `ClassroomMembership`의 조합이다. 이름, PIN digest, gender와 avatar 정보는 User에 있고 Classroom, 출석번호와 active/inactive 상태는 ClassroomMembership에 있다. 학생 PIN 인증도 현재는 Devise User session을 사용한다.

최종 구조는 다음과 같다.

```text
User
├── global admin
└── teacher

School
└── SchoolYear
    └── Classroom
        ├── HomeroomAssignment ── teacher User
        └── Student
```

`Student`는 `belongs_to :classroom`이며 `classroom_id`, `name`, `student_number`, `active`, `student_pin_digest`와 optional `avatar_key`를 가진다. School과 SchoolYear는 Classroom을 통해 결정한다. `gender`, ActiveStorage avatar attachment와 `StudentEnrollment`는 두지 않는다.

## Identity와 lifecycle

- Student row 하나는 한 Classroom과 그 SchoolYear 안에서만 의미가 있다.
- 다음 학년도에는 새 Student를 등록하며 학년도·학교를 넘는 동일인 연결을 두지 않는다.
- 학교 이동 identity, 같은 학년도 반 이동 history와 자동 이동·복사·진급을 지원하지 않는다.
- 전출이나 운영 제외는 Student의 active/inactive로 표현한다. inactive row와 활동 기록은 삭제하지 않는다.
- `started_on`, `ended_on`, 전출 사유와 별도 학적 history 모델을 추가하지 않는다.
- SchoolYear archive는 Student.active를 변경하지 않고 하위 자료를 read-only로 만든다.
- planning SchoolYear에서는 Classroom과 명단을 준비할 수 있지만 학생 로그인은 금지한다.

## 출석번호와 roster

- `student_number`는 1 이상의 정수이며 Student가 직접 소유한다.
- 같은 Classroom의 active Student끼리 번호가 유일해야 하며 DB partial unique index를 최종 방어선으로 둔다.
- inactive Student끼리와 active/inactive 사이에는 같은 번호를 허용한다.
- 기존 번호순 roster, 번호 교환·순환, transaction과 active 최대 30명 계약을 유지한다.

## 인증 경계

Student는 Devise User가 아니며 Devise로 인증하지 않는다. 현재 URL과 UX는 유지한다.

```text
/c/:student_login_token/login
→ active School / SchoolYear / Classroom 확인
→ active Student 선택
→ 4자리 PIN 검증
→ Rails session 기반 student context 설정
```

- 로그인 성공 시 staff User session과 혼합되지 않도록 session을 reset한다.
- 구현 단계에서 `current_user`와 분리된 current Student/session context를 둔다.
- 20분 inactivity TTL과 PIN 시도 제한을 유지한다.
- 매 request에서 Student 존재·active, session Classroom 일치, Classroom active, SchoolYear active, School active를 다시 확인한다.
- lifecycle 변경으로 eligibility를 잃은 기존 session은 다음 request에서 종료한다.
- route, 학생 선택과 PIN UX는 이 migration을 이유로 재설계하지 않는다.

## 데이터 migration

기존 student ClassroomMembership마다 Student 하나를 생성한다.

- `classroom_id`, `student_number`, active/inactive는 membership에서 복사한다.
- `name`, PIN digest와 유효한 `avatar_key`는 student User에서 복사한다. legacy `gender`는 복사하지 않는다.
- 한 student User가 여러 membership을 가지면 membership마다 독립 Student를 만든다. 새 row 사이에 legacy identity 연결을 남기지 않는다.

Migration은 객관적 preflight를 먼저 수행하고 불일치를 추측하여 보정하지 않는다. 최소한 다음을 fail-fast 확인한다.

- membership의 User와 Classroom 존재
- membership role과 User role이 모두 student
- 필수 이름과 유효한 PIN digest 존재
- student_number가 신규 필수/범위 규칙을 만족
- active 번호 중복과 active Student 30명 제한 위반 없음
- legacy student User에 ActiveStorage custom avatar attachment가 없음
- 현재 starter 밖의 서비스가 student User를 참조한다면 integration 시 Student 참조로 전환할 수 있음

Student runtime 전환과 검증 뒤 User의 student role, student용 ClassroomMembership과 legacy 학생 인증 경로를 제거한다. 더 이상 참조되지 않는 legacy student User data는 별도 검증 후 제거하며 dual source를 장기간 유지하지 않는다.

## Avatar와 개인정보

- Student는 gender를 저장하지 않는다.
- optional `avatar_key`는 preset 학생 avatar를 표시하기 위한 cosmetic 정보이며 identity가 아니다.
- 기존 `boyXX`/`girlXX` key와 asset은 사용할 수 있지만 Student는 이를 성별로 해석하지 않는다.
- 신규 Student는 전체 허용 student preset pool에서 avatar를 선택할 수 있다.
- Student에는 ActiveStorage custom avatar upload 기능을 두지 않는다.
- legacy student User에 custom avatar attachment가 있으면 migration preflight가 fail-fast한다. 조용히 삭제하거나 무시하지 않고 실제 데이터의 별도 정리·보존 결정 후 migration한다.
- 이름 외 생년월일, 주소, 연락처, 보호자·학적 식별자 등 profile 개인정보를 추가하지 않는다.

## SchoolYear lifecycle

- 학년도 전환은 날짜로 자동 실행하지 않는다.
- 향후 global admin의 명시적 operation이 active를 archived로, planning을 active로 전환한다.
- 전환 시 기존 Classroom, Student, HomeroomAssignment와 활동 row를 이동·복사하거나 일괄 수정하지 않는다.
- 학년도 전환 service와 UI 자체는 이 spec의 구현 범위가 아니다.

## Acceptance criteria

1. Student는 정확히 하나의 Classroom에 직접 속한다.
2. Student와 staff User 인증 경계가 분리되고 Student는 Devise를 사용하지 않는다.
3. 이름, 번호, active 상태와 PIN digest의 source는 Student 하나다.
4. active 번호는 Classroom 안에서 유일하고 inactive 번호 중복은 허용한다.
5. 기존 roster ordering, 번호 교환·순환과 active 최대 30명 계약을 유지한다.
6. inactive Student와 활동 기록을 보존하고 로그인·mutation을 막는다.
7. 매 학생 request에서 Student와 Classroom, SchoolYear, School eligibility를 재검증한다.
8. planning/archived 학생 로그인을 막고 archived 자료는 read-only로 보존한다.
9. legacy membership 하나를 독립 Student 하나로 fail-fast 이전한다.
10. 전환 뒤 student User와 ClassroomMembership을 runtime authority로 사용하지 않는다.
11. 학년도 간 동일 학생 identity나 StudentEnrollment를 만들지 않는다.
12. gender는 이전하지 않고 유효한 preset avatar_key만 이전하며 custom avatar attachment가 있으면 fail-fast한다.

## Non-goals

- 장기 학생 identity, NEIS identifier와 개인정보 확장
- `StudentEnrollment` 또는 별도 학적 history
- 학교·학년도 간 학생 연결과 같은 학년도 반 이동 history
- 자동 진급, 학생·Classroom 자동 복사
- 학년도 전환 service/UI와 archived historical UI
- student `ClassroomMembership` 장기 유지
- Devise 기반 Student 인증
- 새 gem

## 구현 순서

1. legacy custom avatar attachment를 preflight한다.
2. Student table과 DB invariant를 추가하고 preflight 뒤 membership별 데이터를 backfill한다.
3. roster와 학생 관리 read/write를 Student로 전환한다.
4. PIN login과 request session context를 staff Devise session에서 분리한다.
5. lifecycle, authorization, reporting과 archived read-only 경계를 검증한다.
6. legacy student User/ClassroomMembership 참조가 없음을 확인한 뒤 관련 role, association과 data를 제거한다.
