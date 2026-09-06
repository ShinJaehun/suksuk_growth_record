# 학생 명단과 출석번호 정책

## 1. 목적과 범위

이 문서는 교실별 Student의 출석번호, 명단 정렬, 등록, 수정, 비활성화·복구와 일괄 편집 정책을 정리한다.

Student는 하나의 Classroom에 직접 속하는 학년도별 교실 참여자다.

학생의 영구 신원이나 학교 간·학년도 간 연결을 표현하지 않는다.

## 2. 데이터 소유권

출석번호는 `Student.student_number`에 저장한다.

Student 자체가 특정 Classroom에 종속되므로 별도의 StudentEnrollment나 ClassroomMembership을 사용하지 않는다.

`student_number`는 nullable이다.

신규 학생 등록에서도 출석번호를 비워둘 수 있다.

## 3. 출석번호 유효성

출석번호에 값이 있으면 1 이상의 정수여야 한다.

같은 Classroom의 active Student끼리는 값이 있는 출석번호가 중복될 수 없다.

DB에서도 active + non-null Student 범위의 partial unique index로 이를 보장한다.

inactive Student끼리 또는 active/inactive 사이에는 같은 번호를 허용한다.

## 4. 명단 정렬

기본 roster는 다음 순서로 정렬한다.

1. 출석번호가 있는 Student를 번호 오름차순으로 표시
2. 번호가 없는 Student를 뒤에 표시
3. 같은 조건에서는 이름과 id를 사용해 안정적인 순서를 유지

`all` 필터에서는 active Student를 먼저, inactive Student를 다음에 표시하고 각 그룹 안에서 같은 roster 순서를 적용한다.

## 5. 역할과 수정 권한

teacher/admin은 정책상 관리 가능한 Classroom의 Student를 관리할 수 있다.

학생 본인은 자기 profile에서 자신의 기본 정보를 조회할 수 있지만 출석번호를 수정할 수 없다.

다른 Classroom의 Student ID를 URL이나 parameter로 제출해 관리 범위를 확장할 수 없다.

서버는 항상 Student의 `classroom_id`를 기준으로 현재 Classroom 소속을 검증한다.

## 6. 개별 학생 등록

신규 Student는 다음 정보를 사용한다.

- 이름
- 선택적 출석번호
- gender (`boy` 또는 `girl`)
- 4자리 PIN
- gender에 맞는 preset `avatar_key`

신규 Student는 gender가 필수다. legacy migration에서 gender가 없던 Student는 관계없는 수정까지 막지 않도록 호환할 수 있다.

학생용 custom photo upload는 제공하지 않는다.

`boyXX`는 boy avatar pool, `girlXX`는 girl avatar pool에 속한다.

## 7. 여러 학생 등록

여러 학생 등록은 공통 4자리 PIN과 학생별 다음 정보를 사용한다.

- 이름
- 선택적 출석번호
- gender
- gender에 맞는 preset avatar

draft 내부의 중복 active 번호와 기존 active Student 번호 충돌을 검사한다.

active Student 최대 30명 제한은 저장 직전 Classroom lock 안에서 다시 확인한다.

전체 저장은 하나의 transaction으로 처리하며 한 Student라도 저장에 실패하면 모두 rollback한다.

`RecordInvalid`와 `RecordNotUnique`도 500 오류로 노출하지 않고 사용자 입력 오류로 처리한다.

## 8. 학생 명단 일괄 편집

명단 일괄 편집에서는 다음 정보를 수정한다.

- 이름
- 출석번호
- gender
- gender에 맞는 preset avatar

PIN, active 상태, 학생 추가·제거는 명단 일괄 편집 범위에 포함하지 않는다.

빈 출석번호는 `nil`로 저장한다.

현재 Classroom과 현재 필터에 포함된 Student만 수정할 수 있다.

다른 Classroom Student ID나 조작된 Student ID는 거부한다.

한 행이라도 오류가 있으면 전체 변경을 rollback하고 제출한 입력값과 행별 오류를 유지한다.

## 9. 번호 교환과 순환 변경

두 Student의 번호 교환과 세 Student 이상의 번호 순환 변경을 지원한다.

예:

- 1 ↔ 2
- 1 → 2, 2 → 3, 3 → 1

최종 번호 상태가 유효하면 변경 대상 번호를 transaction 안에서 임시로 `nil` 처리한 뒤 최종 번호를 저장해 partial unique index와의 중간 충돌을 방지한다.

## 10. 비활성화

학생 제거는 physical delete가 아니라 `Student.active = false`로 처리한다.

비활성화할 때 출석번호, 이름, PIN, avatar 등 기존 Student 데이터는 보존한다.

inactive Student는 학생 PIN login을 할 수 없다.

SchoolYear archive는 Student를 일괄 inactive로 변경하지 않는다.

## 11. 복구

inactive Student를 복구할 때 다음 조건을 다시 검증한다.

- School active
- SchoolYear active
- Classroom active
- active Student 최대 30명
- `student_number`가 있으면 active 번호 중복 없음

조건을 만족하지 않으면 Student를 active로 변경하지 않는다.

Student의 Classroom을 복구 과정에서 변경하지 않는다.

## 12. PIN 관리

학생 PIN의 canonical source는 `Student.student_pin_digest`다.

학생 본인은 Student self-service에서 자신의 PIN을 변경할 수 있다.

teacher/admin도 관리 가능한 Student의 PIN을 변경할 수 있다.

교사 관리에서 변경한 PIN과 학생 로그인에서 사용하는 PIN은 항상 동일한 Student row를 사용한다.

PIN 입력을 비워둔 일반 Student 정보 수정에서는 기존 PIN을 유지한다.

관리 화면과 응답에서 PIN digest를 노출하지 않는다.

## 13. avatar 정책

Student는 preset `avatar_key`만 사용한다.

허용 가능한 key 전체는 `Student::AVATAR_KEYS`, gender별 key는 `Student.avatar_keys_for(gender)`가 정의한다.

신규 등록과 명시적 avatar 변경에서는 gender와 avatar pool이 일치해야 한다. 성별 변경 뒤 기존 avatar가 새 pool에 맞지 않으면 결정적인 fallback을 배정할 수 있다.

legacy gender/avatar 불일치는 이름·번호처럼 관계없는 수정에서 자동 정리하거나 수정 자체를 막지 않는다. 같은 gender에서 다른 mismatched avatar를 새로 제출하면 거부한다.

Student에 ActiveStorage custom avatar를 추가하지 않는다.

legacy 데이터 backfill에서는 유효한 preset `avatar_key`만 복사한다.

legacy student User에 custom ActiveStorage avatar가 존재하면 migration preflight에서 fail-fast한다.

## 14. transaction과 경쟁 조건

개별 등록, 여러 학생 등록, 복구, 번호 변경처럼 active 인원 수나 번호 유일성에 영향을 주는 operation은 필요한 경우 Classroom lock 아래 최종 상태를 검증한다.

application validation뿐 아니라 DB constraint도 최종 안전망으로 유지한다.

경쟁 조건으로 `RecordInvalid` 또는 `RecordNotUnique`가 발생해도 부분 저장하지 않고 전체 transaction을 rollback한다.

## 15. 테스트 불변식

다음 동작을 핵심 회귀 대상으로 유지한다.

- active + non-null 출석번호 중복 차단
- inactive 번호 중복 허용
- nullable 출석번호
- 출석번호와 active 상태에 따른 안정적인 roster 정렬
- 다른 Classroom Student 격리
- active Student 최대 30명
- 여러 학생 등록의 atomic rollback
- 번호 교환과 순환 변경
- 잘못된 Student ID와 다른 Classroom ID 조작 차단
- 개별·일괄 수정의 atomicity
- 비활성 Student 로그인 차단
- 복구 시 인원 제한과 번호 충돌 재검증
- teacher/admin 관리 PIN과 실제 Student 로그인 PIN의 일치
- PIN digest 비노출
- gender 값과 gender/avatar pool 일치 검증
- legacy gender/avatar mismatch의 관계없는 수정 호환
- School, SchoolYear, Classroom lifecycle 경계