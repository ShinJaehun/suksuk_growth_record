# Annual Teacher Authentication and Authority Cutover

## 목적

이 문서는 [Annual Teacher User Migration](annual_teacher_user_migration.md)의 Phase 2C
canonical implementation boundary를 정의한다. Phase 2B까지 `SchoolMembership`이
runtime source이고 annual User field는 shadow projection이다.

```text
BEFORE
SchoolMembership -> school / role / grade

AFTER
User.school_year.school -> school
User.school_role        -> school role
User.grade              -> grade
```

Shadow projection을 장기간 유지하면 두 source가 drift하고 어느 값이 권한을 결정하는지
불명확해진다. Authentication만 `login_id`로 바꾸고 authorization은
`SchoolMembership`에 남기면 인증된 annual account와 실제 school scope가 서로 다른
source에서 결정된다. 반대로 authority만 먼저 바꾸면 current email login이 planning
또는 archived account를 잘못 선택할 수 있다.

따라서 Phase 2C는 teacher authentication과 annual authority read/write source를 하나의
명시적 cutover 경계에서 전환한다. Partial cutover나 장기간 dual-authoritative 상태는
정상 runtime으로 허용하지 않는다.

## Current와 target authentication

현재는 하나의 Devise `User` table에서 teacher와 global admin이 email/password로
로그인한다. Student도 User row지만 classroom token, 학생 선택과 PIN으로 별도
인증한다.

Cutover 뒤에도 User table과 Devise password hashing/session machinery는 유지하되 세
authentication context를 섞지 않는다.

```text
Global admin -> email + password, SchoolYear 비종속
Teacher      -> School-scoped login_id + password, annual User
Student      -> classroom token + 학생 선택 + PIN
```

별도 `TeacherAccount`, `TeacherIdentity` 또는 multi-auth framework를 만들지 않는다.

## Cutover readiness와 final reconciliation

Cutover 직전 legacy runtime의 authoritative source는 여전히 `SchoolMembership`이다.
다만 reconciliation 대상은 모든 teacher User가 아니라 Phase 2B에서 mapping되어
pre-cutover SchoolMembership projection을 가진 legacy teacher cohort다.

### Legacy SchoolMembership projection reconciliation

Legacy cohort에 한해 다음을 비교한다.

- `user.school_year.school_id == user.school_membership.school_id`다.
- `user.school_role == user.school_membership.role`다.
- `user.grade == user.school_membership.grade`다.
- Membership role과 grade가 canonical 범위에 있다.

Planning year 등에 이미 순수 annual 구조로 생성되어 SchoolMembership이 없는 teacher는
legacy cohort가 아니며, missing membership을 이유로 reconciliation을 실패시키지 않는다.

Reconciliation은 값의 의미를 다음처럼 구분한다.

### Pre-cutover source에서 controlled reconciliation 가능

`school_role`과 `grade`는 cutover 직전까지 SchoolMembership이 authoritative이므로,
대상 row를 잠그고 전체 batch를 재검증하는 controlled operation에서 현재 membership
값으로 projection을 갱신할 수 있다. 갱신 결과가 manager cardinality나 DB constraint를
깨면 operation 전체를 중단한다.

### Explicit human decision 없이는 변경 금지

`school_year_id`와 `login_id`는 annual identity mapping이다. 다음을 하지 않는다.

- 현재 날짜, active/latest year, classroom, 이름 또는 email로 SchoolYear 추론
- 이름, email, avatar 또는 유사 문자열로 login ID 생성·교체
- 다른 SchoolYear mapping으로 자동 이동
- 충돌한 login ID의 자동 rename
- Ambiguous/partial identity row의 자동 overwrite

이 값이 누락되거나 충돌하면 Phase 2B의 명시적 mapping 또는 별도 승인된 controlled
correction으로 먼저 해결해야 한다.

Legacy reconciliation은 SchoolYear 단위 batch로 수행한다. 각 batch는 transaction 안에서
`SchoolYear -> User(ID 오름차순) -> SchoolMembership(ID 오름차순)` 순으로 잠그고
all-or-nothing으로 처리한다.

### Annual User 전체 readiness와 normalization audit

Legacy 여부와 무관하게 모든 annual teacher User에는 다음을 감사한다.

- `school_year_id`, `login_id`, `school_role`이 완전하고 grade가 `nil` 또는 `1..6`이다.
- 같은 SchoolYear의 normalized login ID가 중복되지 않는다.
- SchoolYear별 manager teacher User가 최대 한 명이다.
- Global admin과 student annual field는 비어 있다.
- Partial annual state, missing SchoolYear 또는 missing login ID가 없다.

모든 SchoolYear batch reconciliation과 전체 annual readiness audit가 통과해야 cutover를
허용한다. Audit 실패, silent skip, partial cutover 또는 일부 School만 annual source로 먼저
전환하는 것은 금지한다.

## Active SchoolYear resolution

Normal teacher login entry point는 URL의 기존 숫자 `School.id`로 School context를 먼저
확정한다. 개념적인 entry는 `/schools/:school_id/teacher_login`이며 정확한 Rails route
helper와 controller 이름은 implementation detail이다. Account lookup은 다음 순서만
사용한다.

```text
URL school_id로 resolve한 School
-> 그 School의 정확히 하나인 active SchoolYear
-> normalized login_id가 일치하는 teacher User
```

- 사용자는 normal login에서 SchoolYear를 선택하지 않는다.
- Active SchoolYear가 없으면 fail closed한다.
- Planning 또는 archived year를 fallback으로 검색하지 않는다.
- School name, 현재 날짜, 가장 최근 year 또는 teacher profile로 context를 추론하지 않는다.
- 요청에서 받은 School context 밖의 User를 인증하지 않는다.
- 다른 School로 fallback하지 않는다.

`School.id`는 authentication secret이 아니다. 다른 숫자 ID로 URL을 조작할 수 있다는
사실 자체는 취약점이 아니며, server가 resolve된 School scope 밖의 teacher를 절대
lookup하거나 인증하지 않는 것이 보안 invariant다. Global `find_by(login_id:)` lookup은
금지한다. Phase 2C에서는 별도 School slug/token/public identifier schema를 추가하지 않는다.
향후 사람이 읽기 좋은 public slug가 필요하면 별도 feature/spec으로 도입한다.

### 신규 운영 School의 initial active SchoolYear

Global admin이 운영용 School을 신규 등록할 때 School 이름과 initial 운영 연도를 함께
명시적으로 제출한다. `SchoolYear.year`는 학년도가 시작하는 연도이며, 등록 form 기본값은
3월부터 12월까지 `date.year`, 1월부터 2월까지 `date.year - 1`로 계산한다. Server는
제출값이 없을 때 이 기본값을 추론하거나 저장하지 않는다. 저장되는
`SchoolYear.year`의 canonical source는 admin이 제출한 값이다.

School과 initial SchoolYear는 하나의 transaction에서 생성한다. Initial SchoolYear는 생성된
School에 속하고 제출된 year와 `active` status를 가진다. 어느 한 record라도 유효하지 않거나
저장에 실패하면 둘 다 남기지 않는다. 이 workflow는 운영 School 등록을 위한 명시적
예외이며, 일반 `SchoolYear` 생성의 default status가 `planning`인 lifecycle 정책은 유지한다.

### 기존 운영 School의 SchoolYear 보정

위 workflow 도입 전에 생성되어 SchoolYear가 없는 기존 운영 School은 배포와 전환 전에 관리자가
실제 학년도를 확인한 뒤 명시적으로 SchoolYear를 보정한다. 현재 날짜, School 생성일 또는 다른
School에서 year를 자동 추론하지 않는다. 이 보정은 teacher User, SchoolMembership, Classroom 또는
Student를 자동 변경하지 않으며, legacy teacher annualization과 readiness는 기존의 별도 절차를
따른다.

## login_id semantics

Phase 2C canonical은 case-insensitive login과 lowercase canonical storage다.

- 새 login input은 `strip.downcase`로 normalize한다.
- Blank 결과는 거부한다.
- 저장값은 lowercase다.
- 같은 SchoolYear에서 case-insensitive하게 unique다.
- 다른 SchoolYear에서는 같은 normalized login ID를 사용할 수 있다.

DB semantics도 authentication과 일치해야 한다. 기존 case-sensitive composite unique
index만 신뢰하지 않고, canonical lowercase를 DB CHECK로 보장하거나 동등한
case-insensitive DB constraint를 사용한다. `(school_year_id, normalized login_id)`의
경쟁 조건 안전한 uniqueness를 유지한다.

Phase 2B 값은 먼저 case-fold collision을 감사한다. 서로 다른 User의 `Tara`/`tara`가
충돌하면 자동 선택이나 rename 없이 cutover를 중단한다. 충돌이 없다면 기존 `Tara`를
`tara`로 바꾸는 것은 identity remapping이 아니라 승인된 representation normalization으로
controlled하게 수행하며 User별 별도 승인을 요구하지 않는다. 다른 login ID로 rename하거나
SchoolYear mapping을 바꾸는 것은 explicit decision 없이는 금지한다.

Phase 2B가 whitespace를 거부했으므로 stored login ID의 leading/trailing whitespace는
조용히 strip하지 않고 integrity failure로 처리한다. 이는 새 login input에 적용하는
`strip.downcase` normalization과 구분한다. Allowed character와 최대 length는 authentication
implementation spec에서 정하되 DB와 application normalization을 다르게 만들지 않는다.

## Teacher email

Teacher email은 cutover 뒤 authentication identifier가 아니라 optional contact/profile
data다. 기존 teacher email은 자동 삭제하거나 login ID로 복사하지 않는다.

- Global admin: email required, email/password authentication 유지
- Teacher: email optional, authentication에 사용하지 않음
- Student: 기존 credential clearing와 PIN/token flow 유지

같은 User model에서 `email_required?`와 email authentication eligibility를 role-aware하게
분리한다. Devise global `authentication_keys`를 teacher와 admin에게 동일하게 적용해
teacher email fallback을 남기지 않는다. Existing `/users/sign_in`의 admin entry와
School-scoped teacher entry는 명확히 분리한다. `User.email`은 teacher authentication
lookup source가 아니며 global-admin email flow는 teacher User를 인증하지 않는다.
Teacher session은 School-scoped login ID flow로만 만든다. Login ID가 우연히 email
형태여도 login ID로 처리할 뿐 `User.email` fallback은 아니다.

## Teacher account readiness invariant

Cutover 뒤 runtime teacher User는 최소한 다음 invariant를 만족한다.

```text
role == "teacher"
school_year_id present
login_id present and canonical
school_role in member | manager
grade nil or 1..6
```

Global admin과 student는 teacher annual authority field를 갖지 않는다. Shared users
table이므로 이를 role-dependent model validation과 DB CHECK로 보호한다. DB는
`school_year_id`, `login_id`, `school_role` column 전체를 전역 `NOT NULL`로 만들지
않는다.

`User.active`와 `SchoolYear.status`는 별개다. Normal teacher runtime authority는 다음
조건을 모두 요구한다.

- User가 teacher이고 active다.
- Annual field가 완전하다.
- User의 SchoolYear가 active다.
- 그 SchoolYear의 School이 active다.

Planning/archived 상태 때문에 `User.active`를 자동 변경하지 않는다. Inactive teacher는
annual mapping이 완전해도 로그인하거나 운영 권한을 얻지 못한다.

이 eligibility는 로그인 시점에만 확인하지 않는다. Normal teacher application request마다
teacher role, User active, SchoolYear 존재와 active 상태, School active 상태를 확인한다.
하나라도 잃으면 fail closed하고 기존 session의 stale authority를 계속 사용하지 않는다.
`password_change_required == true`이면 forced password change와 sign-out 외 일반
application access를 허용하지 않는다. 정확한 controller callback 이름은 implementation
detail이다.

## Planning teacher boundary

Planning SchoolYear에는 teacher User와 credential을 준비할 수 있다. 새 temporary
credential과 `password_change_required`도 미리 설정할 수 있다. 그러나 planning
teacher는 normal runtime login 대상이 아니다.

- Active login lookup은 planning account를 검색하지 않는다.
- Active account가 없거나 credential이 틀려도 planning account로 fallback하지 않는다.
- SchoolYear가 global-admin-only rollover로 active가 된 뒤에만 normal login 후보가
  된다.

Planning teacher bootstrap UI와 bulk operation은 후속 phase지만 이 authentication
boundary는 Phase 2C에서 server-side로 보장한다.

## Archived teacher boundary

Normal active login은 archived User를 검색하거나 fallback으로 사용하지 않는다.
Archived authentication은 explicit School과 SchoolYear context를 가진 별도 entry에서만
가능하다.

Phase 2C는 active login에서 archived User를 검색/fallback하지 않고 archived account에
active school-operation mutation을 부여하지 않는 경계를 마련한다. Architecture에 정의된
credential reissue authorization도 유지한다. Archived authentication에는 향후 explicit
School과 SchoolYear context가 필요하지만 controller, route와 UI 구현은 다음을 포함해 후속
historical phase로 남긴다.

- Historical navigation과 전체 read-only UI
- HomeroomAssignment를 이용한 ordinary teacher의 당시 classroom scope
- Archived school-wide report/export surface

이 세부 scope가 안전하게 구현되기 전에는 archived account에 일반 active application
surface를 개방하지 않는다. 장기 canonical의 archived login 가능성은 유지하지만,
Phase 2C acceptance는 normal active login이 archived account를 확실히 배제하는 것까지
요구한다.

## password_change_required lifecycle

Phase 2C는 teacher credential state로 `password_change_required`를 도입한다.

- 새 temporary password 발급 또는 재발급 성공 시 `true`다.
- Temporary credential로 최초 인증에 성공하면 정상 application보다 forced password
  change flow로 이동한다.
- Forced state에서는 password change와 sign-out 외 일반 application action을 허용하지
  않는다.
- Password 변경 성공 뒤 `false`로 바꾸고 session을 rotate한다.
- 일반 profile update와 forced password change endpoint를 분리한다.
- Planning teacher는 credential 준비가 가능하지만 normal runtime login은 불가하다.

Phase 2B에서 기존 password로 운영 중인 mapped teacher는 cutover 때 자동으로 temporary
password로 바꾸지 않는다. 별도 재발급을 받지 않은 기존 teacher의
`password_change_required` 초기값은 `false`로 두어 current credential continuity를
유지한다.

## Post-cutover active teacher 생성

Cutover 뒤 active-year 개별 teacher 생성은 email과 operator가 고른 initial password를
사용하지 않는다.

- Target active SchoolYear와 canonical login ID를 명시한다.
- System이 충분히 random한 temporary password를 생성한다.
- `password_change_required = true`로 저장한다.
- 평문 temporary password는 성공 시 한 번만 표시한다.
- Initial issuance도 `TeacherCredentialEvent` 감사 대상이다.
- Email은 optional contact/profile field다.

Current active-year manager는 자기 School의 current active SchoolYear에 ordinary member
teacher만 생성할 수 있으며 manager role을 지정할 수 없다. Manager 지정은 계속 global
admin만 수행한다. 이를 위한 기존 individual teacher form/auth field 변경은 2C의 필수 auth
migration이지만 planning bulk bootstrap과 unrelated UI redesign은 후속 범위다.

## Temporary password 발급과 재발급

- 평문 temporary password를 DB나 audit record에 저장하지 않는다.
- 기존/current password나 digest를 조회·표시하지 않는다.
- 충분히 예측하기 어려운 random password를 생성한다.
- 생성된 평문은 성공 응답에서 한 번만 표시하고 이후 다시 볼 수 없다.
- 새 credential 저장이 성공한 뒤에만 평문을 표시한다.
- 재발급 즉시 이전 password credential을 무효화한다.
- 발급/재발급 뒤 `password_change_required = true`다.
- 실패한 transaction은 새 평문을 성공 결과처럼 노출하지 않는다.

Authorization은 다음과 같다.

### Global admin

모든 School의 active, planning 및 archived annual teacher User에 발급/재발급할 수 있다.

### Current active-year manager

자신이 active User이고, active SchoolYear에서 `school_role == "manager"`이며 School이
active인 경우에만 자기 School의 active, planning 및 archived teacher User credential을
발급/재발급할 수 있다. 다른 School의 account에는 접근할 수 없다.

Manager가 credential을 관리할 수 있다는 사실은 manager role 지정 권한을 주지 않는다.
Archived credential reissue는 historical data 접근을 다시 가능하게 하는 민감 action이므로
동일한 own-School scope와 audit를 반드시 적용한다.

## Credential audit

Temporary credential 발급과 재발급은 append-only 성격의 좁은 audit record로 남긴다.
최소 개념 schema는 다음과 같다.

```text
TeacherCredentialEvent
actor_user_id
teacher_user_id
action: temporary_password_issued | temporary_password_reissued
created_at
```

Actor와 target은 User foreign key로 식별한다. Update/delete UI는 제공하지 않는다.
이 record에는 평문 password, 기존 password, encrypted password/digest 또는 password
parameter를 저장하거나 log하지 않는다. Generic audit-event framework나 arbitrary
payload column을 만들지 않는다.

Credential mutation과 audit insert는 하나의 transaction이어야 한다. Audit 저장이
실패하면 credential mutation도 실패한다.

## Credential reissue와 existing session

새 password는 이전 password credential을 즉시 무효화해야 한다. 재발급 전에 존재한
authenticated/remembered teacher session도 정상 application authority를 계속 유지할 수
없어야 한다.

이는 결과 invariant이며 특정 schema mechanism을 미리 요구하지 않는다. 구현에서는 먼저
기존 Devise password/session semantics가 이를 만족하는지 targeted verification한다. 기본
동작만으로 충족되지 않아 persistent revocation state가 필요하다는 사실이 확인되면 임의로
새 schema를 추가하지 않고 canonical spec과 human approval로 돌아온다.

## Rate limiting

현재 `UserPasswordAttemptLimiter`는 normalized email과 remote IP를 하나의 key로 사용한다.
Cutover 뒤 credential 종류별 key namespace를 분리한다.

```text
Global admin: normalized email + remote_ip
Active teacher: school_id + normalized login_id + remote_ip
```

Teacher limiter는 School-scoped lookup과 같은 normalization을 사용한다. 같은 login ID를
다른 School에서 사용하는 account의 실패 횟수를 섞지 않는다. Admin limiter는 기존
email semantics를 유지한다. 성공 시 해당 credential context의 key만 reset한다.
향후 archived authentication limiter는 explicit SchoolYear context를 포함해야 하지만,
그 구현은 full archived authentication flow와 함께 후속 phase에서 정한다.

구현은 현재 limiter의 digest/cache pattern을 작고 명확하게 재사용할 수 있지만 generic
credential framework로 확장하지 않는다. Student PIN limiter는 변경하지 않는다.

## Runtime authority cutover

Cutover 순간부터 teacher annual authority의 single source는 다음이다.

```text
School      = user.school_year.school
School role = user.school_role
Grade       = user.grade
```

다음 runtime 영역에서 SchoolMembership read/write를 제거한다.

- Teacher authentication과 account lookup
- Pundit policy와 policy scope
- Navigation context와 landing-path 결정
- Teacher create/update/lifecycle 및 assignment service
- School manager 판정과 own-School scope
- Annual role/grade mutation
- School scope resolution과 teacher 목록 filtering

Teacher management write는 annual User field만 변경한다. SchoolMembership sync callback,
dual-write service 또는 SchoolMembership fallback을 추가하지 않는다. Compatibility table과
association은 당분간 남지만 runtime authority, historical fallback 또는 오류 복구 source로
사용하지 않는다.

Current `Classroom.school_id`와 `Classroom.teacher_id`는 유지한다. Classroom assignment는
teacher의 `school_year.school_id`와 Classroom school이 같고 teacher와 SchoolYear가
active일 때만 허용한다. Classroom을 SchoolYear에 귀속하거나 HomeroomAssignment를
도입하지 않는다.

## Manager authority boundary

Current active-year manager는 `User.school_role == "manager"`와
`user.school_year.school`로 판정하며 자기 School 전체의 허용된 annual operation을
수행한다.

- 다른 School 접근 금지
- `/admin/*` 접근 금지
- Global admin 권한 획득 금지
- Manager 지정, 승격, 교체 또는 해제 금지
- 자기 자신을 현재/다음 manager로 지정하는 self-successor 권한 없음

Manager designation은 계속 global-admin-only다. Global admin manager operation도
SchoolMembership이 아니라 target SchoolYear의 teacher User `school_role`을 변경하며
SchoolYear별 manager 최대 한 명 invariant를 지킨다.

동일인 추론으로 successor를 판정하지 않는다. 이름, email, login ID 또는 avatar가 같은
다음 연도 User도 별개 account다. Self-successor 금지는 사람 identity 비교가 아니라
manager에게 designation authority를 전혀 주지 않는 policy로 보장한다.

Manager용 active/planning operation은 own-School의 일반 operation surface에서 제공한다.
Manager의 school-wide authority를 이유로 global-admin-only `/admin/*` namespace를 열지
않는다.

## Annual SchoolYear immutability

Cutover 뒤 persisted teacher User의 `school_year_id`는 일반 profile/teacher management
operation에서 변경할 수 없다. SchoolYear가 teacher annual identity와 School scope를
동시에 결정하므로 이를 바꾸면 login namespace와 historical meaning이 함께 변경된다.

같은 학년도 중 다른 School로 이동해야 한다면 destination SchoolYear에 별도의 annual
teacher User를 명시적으로 만들고 기존 account lifecycle을 별도로 처리한다. Existing
User의 SchoolYear를 자동 교체하거나 SchoolMembership 기반 school move를 유지하지
않는다. Destination account creation/transfer workflow는 Phase 2C non-goal이며, 이름,
email, login ID 또는 avatar로 동일인을 추론하거나 destination User를 자동 생성하지 않는다.

## Cutover ordering

안전한 logical ordering은 다음과 같다.

1. Legacy cohort의 SchoolYear별 reconciliation과 모든 annual User readiness audit를
   dry-run한다.
2. Explicit correction이 필요한 SchoolYear/login ID conflict를 해결한다.
3. SchoolYear별 lock order를 지킨 atomic final reconciliation을 모두 실행하고 전체 annual
   readiness가 완전함을 확인한다.
4. Login normalization, role-dependent DB constraint와 credential/audit schema를 배포한다.
5. School-scoped teacher login, admin email login 분리, rate limiting과 forced password
   change flow를 준비한다.
6. Policy, scope, navigation, landing 및 teacher management read/write를 annual User로
   전환한다.
7. 한 배포 경계에서 teacher authentication과 authority source cutover를 활성화한다.
8. Legacy SchoolMembership write path와 runtime fallback이 호출되지 않음을 확인한다.
9. Post-cutover integrity, auth/authorization 경계와 operational smoke scenario를 검증한다.

Step 7 전에는 SchoolMembership이 authoritative이고, 성공한 Step 7 이후에는 annual
User만 authoritative다. 두 source가 절반씩 적용된 상태를 정상 serving mode로 남기지
않는다. 배포 방식은 maintenance window 또는 동등한 request 차단 경계를 사용해
partial cutover traffic을 막아야 한다.

## Failure와 rollback boundary

### Preflight/reconciliation 실패

Cutover를 시작하지 않는다. SchoolMembership이 계속 authoritative이며 explicit mapping
또는 controlled correction 후 audit를 다시 수행한다.

### Schema migration 실패

Application cutover flag/배포를 활성화하지 않는다. Migration의 transaction/rollback
가능 범위에서 복구하고 기존 runtime source를 유지한다.

### Cutover 배포 실패

Partial application version을 정상 serving하지 않는다. 이전 application/schema 조합으로
되돌릴 수 있는 사전 검증된 operational procedure가 필요하다. Data write가 새 source로
시작된 뒤에는 단순 deploy rollback으로 SchoolMembership authority를 자동 복구하지
않는다.

### Cutover 뒤 integrity 문제

Traffic 또는 affected operation을 fail closed하고 원인을 감사한다. SchoolMembership
fallback이나 dual-write를 자동으로 다시 켜지 않는다. Source of truth를 되돌리는 작업은
새 annual User write와 legacy state를 명시적으로 reconcile하는 controlled operation이며
별도 승인과 검증이 필요하다.

## Existing structures retained

Phase 2C에서도 다음은 유지한다.

- `Classroom.school_id`
- `Classroom.teacher_id`
- Student User와 student ClassroomMembership
- Student classroom token/선택/PIN session flow
- Current Classroom lifecycle
- SchoolMembership table와 association 자체

SchoolMembership은 compatibility residue일 뿐 teacher runtime source나 fallback이 아니다.

## Acceptance Criteria

1. Legacy reconciliation은 Phase 2B-mapped cohort만 SchoolMembership과 비교한다.
2. Planning annual teacher가 SchoolMembership이 없다는 이유만으로 reconciliation에
   실패하지 않는다.
3. Legacy batch는 SchoolYear별 atomic transaction이며 `SchoolYear -> User ID ->
   SchoolMembership ID` lock order를 지킨다.
4. `school_role/grade`만 controlled reconciliation하고 SchoolYear/login ID는 explicit
   decision 없이 변경하지 않는다.
5. 모든 legacy batch와 annual readiness audit가 통과하지 않으면 partial cutover 없이
   중단한다.
6. Collision 없는 uppercase stored login ID는 lowercase canonical representation으로
   normalize되고, case-fold collision은 자동 rename 없이 cutover를 중단한다.
7. Explicit School context의 active SchoolYear에서 normalized login ID/password login이
   성공하며 다른 School의 같은 ID와 혼동하지 않는다.
8. `User.email`은 teacher lookup source가 아니고 admin email login은 teacher를 인증하지
   않는다. Email 형태 login ID도 login ID로만 처리한다.
9. Active SchoolYear가 없거나 account가 planning/archived면 normal login을 fail closed한다.
10. Global admin email/password와 student token/선택/PIN flow는 유지된다.
11. 새 active teacher는 explicit active year/login ID, system-generated temporary credential,
    `password_change_required = true`와 issuance audit로 생성된다.
12. Temporary credential 인증 뒤 forced password change와 sign-out 외 일반 access를
    금지하고, 변경 성공 뒤 state를 해제하며 session을 rotate한다.
13. Reissue 후 이전 password와 기존 authenticated/remembered session은 정상 application
    authority를 유지하지 못한다.
14. Plaintext/digest credential은 DB, audit 또는 application log에 노출되지 않고 credential
    event는 actor, target, action과 timestamp를 남긴다.
15. Current manager는 own-School current active year의 ordinary member만 생성할 수 있고
    credential/teacher operation도 own-School로 제한된다.
16. Cross-School URL/parameter 조작은 거부되고 manager는 `/admin/*`, manager designation과
    global admin operation에 접근할 수 없다.
17. Persisted teacher SchoolYear는 일반 runtime operation에서 변경할 수 없다.
18. Existing session도 매 request에 active teacher User + present/active SchoolYear + active
    School 조건을 잃으면 stale authority를 유지하지 못한다.
19. Policy, scope, navigation, landing과 teacher service가 annual User field를 사용하고,
    SchoolMembership read/write/fallback은 runtime path에 남지 않는다.
20. Admin/student annual field absence와 teacher annual field completeness를 role-dependent
    model/DB invariant가 보호한다.
21. Rate limiter는 admin email context와 active teacher School/login ID context를 분리한다.
22. Global admin의 신규 운영 School 등록은 명시적으로 제출된 운영 연도로 정확히 하나의
    active SchoolYear를 School과 같은 transaction에서 생성한다.
23. 운영 연도 form 기본값은 3월부터 12월까지 현재 calendar year, 1월부터 2월까지 직전
    calendar year다. Blank/invalid 제출을 server가 이 기본값으로 보정하지 않으며, initial
    SchoolYear 저장 실패 시 School도 남지 않는다.
24. 기존 운영 School에 SchoolYear가 없으면 배포와 전환 전에 관리자가 실제 학년도를 확인해
    명시적으로 보정하며, year나 관련 teacher/Classroom/Student data를 자동 추론·변경하지 않는다.

## Verification expectations

구현 후 사람이 다음을 검증한다.

- Focused User/model, reconciliation, credential 및 rate-limiter specs
- Active/planning/archived teacher authentication success/failure request specs
- Global admin email/password regression specs
- Student token/PIN/session regression specs
- Manager own-School, cross-School와 `/admin/*` policy/request specs
- Forced password change, session rotation과 reissue specs
- Credential audit record와 plaintext 비저장 검증
- Final reconciliation의 drift/collision/fail-closed specs
- Legacy cohort 제외, lock order와 SchoolYear별 atomicity 검증
- Uppercase canonical normalization, case-fold collision과 stored whitespace anomaly 검증
- 신규 active teacher temporary issuance와 forced-change 검증
- Inactive User/SchoolYear/School로 바뀐 existing session의 fail-closed 검증
- Admin email flow가 teacher email을 lookup하지 않는 검증
- Reissue 뒤 old credential과 authenticated/remembered session authority 차단 검증
- Policy/navigation/service의 SchoolMembership residue search
- Full RSpec
- Browser에서 active login, forced change, admin login과 manager boundary 확인
- `git diff --check`

## Non-goals

- Permanent Teacher identity 또는 별도 TeacherAccount
- Generic/multi-auth 또는 credential abstraction framework
- Generic audit-event framework
- SchoolMembership dual-write callback이나 runtime fallback
- SchoolMembership table 삭제
- Classroom `school_year_id`와 `class_label` migration
- HomeroomAssignment
- Student model 분리와 StudentEnrollment
- Automatic promotion/rollover
- Full archived historical UI/reporting
- Cross-School transfer/destination account creation workflow
- Manager용 `/admin/*` 개방
- Unrelated UI, authorization 또는 view refactor
- Downstream service-specific domain

## Confirmed human-review decisions

이번 human review에서 다음을 확정했다.

1. Login ID는 case-insensitive authentication과 lowercase canonical storage를 사용한다.
2. 기존 credential을 유지하는 mapped teacher는
   `password_change_required = false`로 시작한다.
3. Credential audit은 actor/target/action/created_at의 최소 `TeacherCredentialEvent`로 둔다.
4. Persisted annual teacher User의 SchoolYear는 일반 operation에서 변경하지 않는다.
5. Credential reissue 뒤 old credential과 existing session이 정상 authority를 유지하지
   못하는 것은 outcome invariant다. Persistent revocation schema는 미리 확정하지 않는다.

## Open Questions

현재 Phase 2C product-policy 수준의 미해결 질문은 없다. Password random format/length,
limiter 수치와 cache key 이름, 정확한 Rails route helper/controller 이름은 승인된 contract
안에서 implementation spec이 정할 세부사항이다. Devise 기본 semantics가 session revocation
outcome을 충족하지 못하면 persistent state 설계 전에 human approval로 돌아온다.
