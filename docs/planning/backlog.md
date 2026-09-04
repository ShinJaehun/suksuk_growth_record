# Backlog

## 문서 사용 원칙

- 현재 starter의 공통 학교·교실·사용자·학생 운영 범위만 기록한다.
- 확정 정책은 canonical spec과 architecture 문서로 이동한다.
- 제거된 service-specific 도메인은 신규 backlog로 유지하지 않는다.

## P0

### Teacher와 Classroom 단일 담당 전환

상태: Canonical migration pending

- 기존 teacher `ClassroomMembership` 데이터의 1:1 호환 여부 감사
- 다중 assignment 충돌의 명시적 데이터 정리
- nullable `Classroom.teacher_id`, users foreign key와 non-null unique index 추가
- controller, service, policy, scope와 UI를 단일 assignment로 변경
- teacher 또는 classroom 비활성화 시 assignment 해제
- 신규 teacher `ClassroomMembership` 생성 제거

### School manager 단일화

- 같은 school의 manager membership 0..1 invariant
- 기존 복수 manager 데이터 감사
- global admin 전용 manager 지정·교체·해제

## P1

### Teacher 운영 영역 정리

- `/teachers`를 canonical 개별 teacher 관리 endpoint로 유지
- compatibility `/admin/teachers`와 nested school teacher endpoint 후속 정리
- school, grade, 단일 classroom form과 server validation 정리
- manager own-school scope와 lifecycle 권한 회귀 점검

### Classroom lifecycle UI

- manager와 global admin의 deactivate/reactivate 동작
- inactive classroom의 관리 목록 표시
- 일반 teacher scope와 직접 진입에서 inactive classroom 제외

### Student 운영 안정성

- student membership 이동 정책
- roster bulk edit 경쟁 조건과 오류 안내
- PIN/token 로그인 및 재발급 UX
- role/gender별 avatar 일관성

## P2

### 운영 화면 확장성

- school scope 확정 후 후보 조회
- server-side filtering과 필요 시 pagination
- 전체 school/classroom/user 데이터 preload 방지
- N+1 query 점검

### 접근성과 문구

- form label, 오류와 empty state locale 점검
- keyboard navigation과 focus 흐름
- Turbo/HTML 오류 응답 일관성

## 범위 밖

- 제거된 service-specific domain 재도입
- Grade model 또는 `User.grade`
- teacher의 복수 classroom 담당
- classroom의 복수 teacher 담당
- school별 복수 manager
- `/admin` bulk management 실제 구현
