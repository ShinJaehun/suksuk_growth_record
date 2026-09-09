# Student Portal Phase 1

## 목적

공유 태블릿 환경에서 student가 교실별 PIN/token으로 안전하게 로그인하고 자기 정보에만 접근하는 starter 공통 흐름을 정의한다.

## 인증과 진입

- student는 일반 teacher/admin 로그인 화면을 사용하지 않는다.
- 교실별 token URL에서 학생을 선택하고 PIN으로 로그인한다.
- 로그인 시 active Student, 해당 Classroom과 PIN을 서버에서 확인한다.
- 성공 시 기존 session을 reset하고 `student_id`, classroom context와 last-seen 기반의 별도 Student session을 설정한다.
- student session은 짧은 TTL과 마지막 활동 시각으로 관리한다.
- token 재발급 후 기존 URL과 QR은 사용할 수 없다.

### Token 재발급과 기존 Student session 경계

- 재발급 전 Student session만으로 재발급된 새 token을 응답 본문·link·redirect(Location)에서 얻을 수 없어야 한다. Logout, TTL 만료와 eligibility 상실도 같은 비노출 경계를 따른다. Old token URL/QR은 GET·POST 모두 재발급 후 사용할 수 없으며 새 token으로 자동 연결하지 않는다.
- Token 재발급 자체는 이미 PIN 인증을 마친 기존 Student session의 authority를 종료하지 않는다. 기존 session은 Student/Classroom/SchoolYear/School eligibility와 TTL이 유효한 동안 계속 사용할 수 있다. 다만 이 session에 새 token을 제공하지 않는다.
- Logout, TTL 만료 또는 eligibility 상실로 session을 종료할 때는 classroom의 현재 token을 조회해 redirect하지 않고 token 없는 공통 Student 로그인 진입점 `/student_login`으로 안내한다.
- Classroom 비활성, SchoolYear non-active(planning/archived), School 비활성으로 eligibility를 잃은 session은 기존대로 종료하며 사용할 수 없는 classroom token URL로 redirect하지 않는다.
- Token generation 저장 방식 등 별도 session/token framework를 구현 계약으로 요구하지 않는다.

## 권한

- student는 자기 정보와 자신이 직접 속한 active Classroom만 조회한다.
- 다른 학생, 다른 classroom과 관리 endpoint에 접근할 수 없다.
- URL이나 parameter 조작으로 classroom 또는 user scope를 넓힐 수 없다.
- inactive Student는 로그인과 현재 교실 운영 대상에서 제외한다.
- policy, scope와 controller validation이 최종 권한 경계다.

## 학생 페이지

- 학생에게 필요한 자기 정보와 현재 classroom 문맥을 간결하게 표시한다.
- student와 teacher/admin용 관리 화면의 책임을 분리한다.
- 학생 본인은 관리용 profile parameter나 다른 학생 정보를 수정할 수 없다.
- PIN 변경처럼 허용된 self-service 값만 별도 strong parameters로 처리한다.

## Avatar

- student avatar는 `avatar_key` 기반 기본 이미지를 사용한다.
- boy/girl role·gender pool과 기존 fallback 정책을 유지한다.
- student 자신에게 teacher/admin avatar 선택 권한을 주지 않는다.
- token 로그인 학생 선택 화면에서 이름과 avatar를 함께 표시할 수 있다.

## Teacher/Admin 학생 관리

- 담당 teacher와 admin은 허용 classroom 안에서 학생 명부, profile과 PIN을 관리한다.
- Student.active lifecycle과 row/기록 보존 정책을 따른다.
- 다른 classroom Student id를 제출해도 변경하지 않는다.
- bulk edit은 한 행 실패 시 전체 rollback하고 정원과 출석번호 invariant를 저장 직전에 다시 확인한다.

## Acceptance criteria

1. active Student는 자기 Classroom의 유효 token과 PIN으로 로그인할 수 있다.
2. inactive Student, 잘못된 PIN 또는 만료 token은 로그인할 수 없다.
3. 로그인 성공 시 이전 session이 재사용되지 않는다.
4. student는 자기 정보와 현재 classroom만 볼 수 있다.
5. 다른 student/classroom URL 조작은 권한 범위를 넓히지 않는다.
6. student용 strong parameters는 허용된 self-service 값으로 제한된다.
7. teacher/admin 학생 관리는 담당 classroom과 policy scope 안에서만 가능하다.
8. student PIN, token과 avatar 기존 정책을 유지한다.
9. 재발급 후 old token URL의 GET·POST 로그인은 거부되며 새 token URL로 redirect하지 않는다.
10. Old token으로 로그인한 session이 있는 상태에서 token을 재발급한 뒤 logout, TTL 만료, ineligibility 경로를 각각 요청해도 응답 본문·link·Location에 새 token이 노출되지 않는다.
11. Token 재발급만으로 기존 Student session을 종료하지 않는다. 기존 eligibility와 TTL이 유효한 session은 계속 사용할 수 있다.
12. Logout, TTL 만료 또는 Classroom/SchoolYear/School lifecycle로 session을 종료할 때 classroom token URL로 redirect하지 않고 `/student_login`을 사용한다.

## Non-goals

- 제거된 service-specific domain
- Student용 Devise 모델 또는 범용 인증 프레임워크 추가
- 학생의 학교 전역 membership
- 학생 domain 전면 재설계
- Student PIN/rate-limit 정책 변경
- DB migration 또는 generic token/session framework의 선제 도입
