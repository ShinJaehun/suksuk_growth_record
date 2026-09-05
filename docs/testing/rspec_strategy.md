# RSpec Strategy

## 목적

starter의 인증, 학교·교실 경계, teacher assignment, 학생 membership, PIN과 avatar 정책을 안전하게 변경할 수 있는 테스트 원칙을 정의한다.

## 스타일 원칙

- coverage 수치보다 핵심 불변식과 회귀 방지 confidence를 우선한다.
- readable한 example을 사용하고 과도한 shared context와 추상화를 피한다.
- model invariant, policy scope, request 흐름과 transaction rollback을 우선 검증한다.
- brittle한 전체 HTML 비교보다 의미 있는 selector와 저장 결과를 검증한다.
- system spec은 핵심 happy path와 JavaScript 상호작용에 한정한다.

## 우선순위 1

### 인증과 세션

- admin·teacher Devise 로그인과 inactive user 차단
- student PIN/token 로그인, session reset과 TTL
- 만료·재발급 token 및 inactive student membership 차단

### 권한

- global admin, school manager, 일반 teacher와 student scope
- 다른 school/classroom/user id parameter 조작 차단
- UI 노출과 무관한 policy/controller server-side 방어
- manager 0..1 및 manager lifecycle 권한

### School과 Classroom

- classroom school 불변성과 grade 1..6
- classroom active/inactive lifecycle
- teacher와 classroom의 0..1 대 0..1 cardinality
- 같은 school·grade 및 active 상태 assignment invariant
- teacher 비활성화 시 assignment 해제와 재활성화 시 미복원
- classroom 비활성화 시 assignment와 student membership 보존 및 운영 차단
- 기존 teacher membership의 1:1 migration과 충돌 데이터 거부

### Student membership과 roster

- student active membership 최대 하나
- inactive membership 보존과 복구
- active classroom만 신규 배정 가능
- 정원과 active 출석번호 uniqueness
- 명단 일괄 편집 transaction과 rollback
- 학생 PIN 일괄 재설정 범위
- role/gender별 avatar validation과 fallback

## 테스트 레벨

### Model / service spec

- validation과 association cardinality
- lifecycle 상태 전이
- assignment transaction과 rollback
- 직접 parameter 조작으로 우회할 수 없는 domain invariant

### Policy spec

- role별 scope
- manager own-school 경계
- 일반 teacher 담당 classroom 경계
- student 본인 및 active membership 경계

### Request spec

- 정상 create/update/deactivate/reactivate 흐름
- 권한 밖 record의 403, redirect 또는 404 처리
- invalid parameter의 500 방지와 오류 응답
- DB persisted value와 membership 보존 여부

### System spec

- student PIN 로그인 핵심 흐름
- school, grade, 단일 classroom teacher form
- avatar preview처럼 JavaScript가 필수인 대표 상호작용

## 검증 순서

1. 변경한 model/service spec
2. 직접 관련 policy/request spec
3. 필요한 최소 system spec
4. 사용자가 전체 RSpec과 browser smoke 검증
5. `git diff --check`

Codex는 사용자의 명시적 요청 없이 테스트, migration, commit, push 또는 merge를 수행하지 않는다.

## 수동 Smoke Checklist

- global admin과 manager의 school scope가 올바른지 확인한다.
- 일반 teacher가 담당 active classroom으로 진입하고 미담당 상태에서 정상 안내를 보는지 확인한다.
- teacher form의 school, grade와 단일 classroom 선택이 서버 결과와 일치하는지 확인한다.
- student PIN/token 로그인과 logout/session expiry를 확인한다.
- 학생 roster, PIN과 avatar 변경이 role 및 classroom 범위를 넘지 않는지 확인한다.

## 피해야 할 테스트

- 구현 세부 메서드 호출 횟수만 고정하는 테스트
- 전체 HTML 문자열 snapshot
- 실제 권한 경계를 검증하지 않는 버튼 존재 여부만의 테스트
- 같은 정책을 여러 계층에서 중복 검증하는 저가치 example
- 제거된 service-specific domain을 전제로 한 spec
