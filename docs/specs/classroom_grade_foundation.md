# Classroom Grade Foundation

## 목적

- `grade`를 `Classroom`의 공식 학년 분류 값으로 사용한다.
- 학교·교실 운영 UI에서 사용자가 학년을 일관되게 이해할 수 있게 한다.
- `/classrooms` 교실 목록에서 학년별 필터를 제공한다.

## 현재 전제

- `Classroom`은 `School`에 속하며 `classrooms.grade` 컬럼이 이미 존재한다.
- `Classroom`은 `grade`를 1 이상 6 이하의 정수로 검증한다.
- `/classrooms`는 `policy_scope(Classroom)` 결과를 기준으로 목록을 만든다.
- global admin은 권한 범위 안의 학교를 대상으로 기존 `school_id` 필터를 사용할 수 있다.
- student가 `/classrooms`에 접근하면 자신의 페이지로 이동한다.

## 요구사항과 정책

### 학년 데이터 정책

- 별도 `Grade` 모델이나 테이블을 만들지 않는다.
- 학년은 `Classroom#grade` 속성으로 유지한다.
- 초등학교 기준 1학년부터 6학년까지만 허용한다.
- 새 교실에는 `grade`가 필수이며 정수 `1..6` 이외의 값은 저장할 수 없다.
- 이 정책은 현재 `Classroom`의 numericality validation을 그대로 공식화하며, 충돌하거나 중복되는 별도 검증 체계를 추가하지 않는다.

### 표시 정책

- 교실 식별에 학년 정보가 필요한 문맥에서는 `4학년 1반`처럼 학년과 교실명을 함께 표시한다.
- 기존 `classroom_display_name` helper를 공통 표시 규칙으로 우선 재사용한다.
- 현재 helper 의미에 따라 교실명이 해당 학년 표기(예: `4학년`)로 이미 시작하면 학년을 다시 붙이지 않는다.
- 이번 작업은 `/classrooms` 목록과 직접 관련된 표시를 보장하는 범위이며, 모든 view의 교실 표시를 광범위하게 리팩터링하지 않는다.

### 교실 목록 학년 필터

- `/classrooms`는 GET query parameter `grade`를 사용한다.
- UI는 `전체 학년`, `1학년`부터 `6학년`까지의 단순한 선택지를 제공한다.
- 서버가 필터 값으로 인정하는 값은 정수 형식의 `1`부터 `6`까지다.
- `grade`가 없거나 빈 값이면 학년 제한을 적용하지 않는다.
- 범위 밖 숫자, 숫자가 아닌 값 또는 혼합 문자열은 유효하지 않은 값으로 보고 학년 제한을 적용하지 않는다. 예외를 발생시키거나 접근 범위를 넓히는 별도 fallback 조회를 하지 않는다.
- grade 조건은 반드시 `policy_scope(Classroom)`으로 권한 범위를 확정한 뒤 그 relation에 추가한다.
- UI에 표시되는 새 문구는 locale key로 관리한다.

### 학교 필터와 조합

- global admin은 기존 `school_id` 필터와 `grade` 필터를 동시에 적용할 수 있다. 예를 들어 특정 학교의 4학년 교실만 조회할 수 있다.
- 한 필터를 변경하거나 제출할 때 다른 필터의 유효한 query parameter를 보존한다.
- 기존 `school_id`의 허용 범위, 검증 방식과 권한 정책은 변경하지 않는다.
- teacher와 school manager도 `policy_scope(Classroom)`이 반환한 자신의 범위 안에서 grade 필터를 사용할 수 있다.
- grade 필터의 적용 여부나 값에 따라 policy scope 밖 교실이 노출되어서는 안 된다.

### 정렬

- 현재 `Classrooms::IndexContext`의 `created_at DESC` 의미를 같은 학년 안에서 유지한다.
- 목록은 `grade ASC`, 그다음 `created_at DESC`로 정렬해 1학년부터 6학년까지 자연스럽게 모이게 한다.
- 이름의 숫자를 해석하는 natural sort 등 별도 정렬 기능은 추가하지 않는다.

### 빈 상태

- 선택한 유효 학년에 접근 가능한 교실이 없으면 기존 목록 empty state를 정상적으로 표시한다.
- 결과가 없는 상태를 오류나 잘못된 요청으로 처리하지 않는다.

## 제약과 불변식

- grade 필터는 조회 조건일 뿐 인증·인가 판단을 대신하지 않는다.
- `School`과 `Classroom`의 소속 관계 및 기존 school filter 권한 경계를 유지한다.
- 기존 교실 생성·수정 권한과 student의 `/classrooms` 접근 redirect를 변경하지 않는다.
- 구현은 기존 controller, `Classrooms::IndexContext`, helper와 locale 구조를 우선 활용하고 새 계층이나 과도한 추상화를 만들지 않는다.

## Acceptance criteria

1. `Classroom#grade`는 정수 1부터 6까지만 허용되고 새 교실에 필수다.
2. `/classrooms` 목록의 교실명에서 학년을 식별할 수 있으며, 이미 해당 학년 표기로 시작하는 이름에는 학년이 중복 표시되지 않는다.
3. `grade=4`이면 로그인 사용자의 policy scope 안에 있는 4학년 교실만 표시된다.
4. global admin은 유효한 `school_id`와 `grade`를 조합해 특정 학교의 특정 학년을 조회할 수 있다.
5. teacher와 school manager는 grade 필터를 사용해도 자신의 policy scope 밖 교실을 조회할 수 없다.
6. 잘못된 `grade` 값은 500 오류를 일으키지 않으며 기존 권한 범위를 넘어서는 결과를 만들지 않는다.
7. `grade`가 없거나 전체 학년을 선택하면 학년 제한 없이 기존 policy scope와 유효한 school filter 범위의 교실이 표시된다.
8. 선택한 유효 학년에 교실이 없어도 정상 응답과 기존 empty state가 표시된다.
9. 목록은 학년 오름차순으로 모이고 같은 학년 안에서는 기존처럼 생성 시각 내림차순으로 정렬된다.
10. global admin의 유효한 학교 선택과 유효한 학년 선택은 다른 필터를 변경·제출한 뒤에도 함께 유지된다.

## 검증 기대사항

- model spec은 grade의 필수 여부, 정수 여부와 `1..6` 경계를 확인한다.
- request spec은 grade 필터, 잘못된 값, 전체 학년, school/grade 조합과 역할별 policy scope 경계를 확인한다.
- helper 또는 동등한 저비용 검증은 일반 이름과 이미 학년 표기로 시작하는 이름의 표시 결과를 확인한다.
- 선택 결과가 없을 때 정상 응답과 empty state가 제공되는지 확인한다.
- 정렬은 학년 간 순서와 같은 학년 내 기존 생성 시각 순서를 확인한다.

## Non-goals

- `Grade` model 또는 table
- 학년 관리자 또는 학년장
- 학년 단위 권한
- 학년별 통계 또는 집계
- 학년별 서비스 설정
- 학년 단위 학생 이동 또는 진급
- 졸업 또는 학년도(academic year) 관리
- 쑥쑥교실투표의 학년별 투표 기능 복제
- 서비스 도메인별 기능 추가
- 성장기록 기능
- 이번 범위와 무관한 view의 교실명 표시 전면 정리
