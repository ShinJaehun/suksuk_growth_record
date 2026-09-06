# 학생 명단과 출석번호 정책

## 목적

학생 출석번호, 명단 정렬, 등록과 일괄 편집의 현행 계약 및 Student 전환 후 보존할 동작을 정의한다.

## 현재 runtime

현재 학생 정보는 `User(role: student)`, 소속·출석번호·상태는 student `ClassroomMembership`에 저장한다. legacy 호환을 위해 번호 column은 nullable이지만 신규 학생 등록에서는 필수다.

### 번호와 정렬

- 출석번호는 값이 있으면 1 이상의 정수다.
- 같은 Classroom의 active student membership끼리 non-null 번호가 유일하며 DB partial unique index가 경쟁 조건을 방어한다.
- inactive끼리와 active/inactive 사이에는 같은 번호를 허용한다.
- 기본 roster는 번호가 있는 학생을 번호 오름차순으로 먼저, 번호가 없는 학생을 뒤에 둔다. 이후 이름, user id, membership id로 안정적으로 정렬한다.
- `all` 필터는 active 그룹 다음 inactive 그룹을 두고 각 그룹 안에서 같은 순서를 사용한다.

### 권한과 개별 등록·수정

- teacher/admin은 policy상 관리 가능한 Classroom에서 번호를 수정하거나 비울 수 있다.
- 학생은 번호를 읽을 수 있지만 수정할 수 없고 PIN 요청에 섞인 번호 parameter도 반영하지 않는다.
- 명단 편집은 현재 Classroom과 필터 대상 membership만 허용하며 다른 Classroom이나 조작된 id를 거부한다.
- 개별 등록은 출석번호, 이름, 성별, 기본 썸네일과 4자리 PIN을 입력하며 출석번호와 PIN이 필수다.
- teacher/admin 편집에서는 legacy 학생 번호를 지정·변경하거나 빈 값으로 되돌릴 수 있다.

### 여러 학생 등록

- 학생 수와 공통 4자리 PIN으로 draft를 만들고 각 행의 번호, 이름, 성별과 기본 썸네일을 입력한다.
- draft 내부 중복과 기존 active 번호 충돌을 검사한다.
- 저장 직전 Classroom lock 안에서 active 학생 최대 30명을 다시 확인한다.
- 전체 transaction으로 저장하며 한 학생이라도 실패하면 모두 rollback한다.
- `RecordInvalid`와 `RecordNotUnique`는 500이 아닌 입력 오류로 처리한다.

### 명단 일괄 편집과 번호 교환

- 일괄 편집은 번호, 이름, 성별과 기본 썸네일을 수정한다. PIN, 상태, 추가·삭제와 업로드 이미지는 포함하지 않는다.
- 빈 번호는 `nil`로 저장하고 현재 active 학생의 최종 번호 상태를 검증한다.
- 한 행 오류 시 전체 rollback하고 제출값과 행별 오류를 유지한다.
- 두 학생 번호 교환과 셋 이상 순환 변경을 지원한다.
- 최종 상태가 유효하면 변경 대상 active 번호를 transaction 안에서 임시 `nil`로 만든 뒤 최종 번호를 저장한다.
- User와 membership 변경은 같은 transaction에 포함한다.

### 비활성화와 복구

- 비활성화할 때 번호를 지우지 않는다.
- 복구 시 active 번호 유일성과 active 최대 30명을 Classroom lock 아래 다시 검증한다.
- 충돌하면 복구하지 않고 기존 inactive 상태를 유지한다.

### gender와 avatar compatibility

- 기본 avatar는 성별별 허용 pool을 사용하며 성별 변경에 맞춰 avatar와 preview를 갱신한다.
- 유효하지 않은 gender/avatar 조합은 새로 저장하지 않는다.
- legacy gender/avatar 불일치는 이름이나 번호만 수정할 때 자동 정리하거나 수정 자체를 막지 않는다.
- 성별이 그대로인데 다른 잘못된 avatar를 제출하면 오류로 처리한다.
- 성별 변경 후 기존 avatar가 유효하면 유지하고, 아니면 결정적인 fallback을 배정한다.
- 업로드 avatar attachment는 명단 편집 과정에서 detach하거나 purge하지 않는다.

## 승인된 target

Student가 Classroom에 직접 속고 `student_number`, 이름, active 상태와 optional `avatar_key`를 직접 소유한다. 위 product behavior를 가능한 그대로 유지한다.

- 신규 Student의 번호는 필수인 1 이상의 정수다.
- 같은 Classroom의 active Student 번호는 DB partial unique index로 유일하고 inactive 번호 중복은 허용한다.
- 정렬은 번호, 이름, Student id의 안정적인 순서를 사용한다.
- 개별·여러 학생 등록, 일괄 편집, 번호 교환·순환, 전체 rollback과 Classroom lock 재검증을 유지한다.
- active 최대 30명과 inactive 복구 충돌 처리를 유지한다.
- 권한은 Student와 Classroom scope를 기준으로 동일하게 fail closed한다.
- Student는 gender를 저장하지 않는다. 신규 avatar는 성별 구분 없이 전체 허용 student preset pool에서 선택한다.
- 기존 `boyXX`/`girlXX` key는 cosmetic preset key로 사용할 수 있지만 성별 정보로 해석하지 않는다.
- 유효한 legacy `avatar_key`는 이전한다. Student에는 custom avatar upload를 두지 않으며 legacy attachment가 있으면 migration을 fail-fast한다.

## Migration acceptance criteria

- active 번호 중복 차단과 inactive 번호 중복 허용
- 번호와 상태 그룹별 안정적인 roster ordering
- 학생 본인의 번호 수정 차단
- 여러 학생 등록의 30명 제한과 전체 rollback
- 일괄 편집 오류의 전체 rollback과 입력 보존
- 번호 교환·순환 변경
- 다른 Classroom·조작된 Student 차단
- 복구 시 번호/30명 충돌
- DB 경쟁 조건의 rollback과 사용자 오류 응답
- legacy preset avatar 이전과 custom attachment fail-fast 계약
