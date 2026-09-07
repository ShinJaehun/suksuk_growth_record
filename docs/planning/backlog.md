# Backlog

## 문서 사용 원칙

- 현재 starter의 공통 학교·교실·사용자·학생 운영 범위만 기록한다.
- 확정 정책은 canonical spec과 architecture 문서로 이동한다.
- 제거된 service-specific 도메인은 신규 backlog로 유지하지 않는다.

## P0

### SchoolYear 운영 확장

- planning SchoolYear 준비와 activation 운영 흐름
- archived SchoolYear read-only 조회 경계
- 명시적인 rollover와 실패·복구 절차

## P1

### Future admin bulk management

- `/admin/teachers` planning-year bulk bootstrap
- `/admin/classrooms` planning-year bulk configuration
- 현재 canonical credential과 SchoolYear operation 재사용

### Student 운영 안정성

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
- Grade model
- teacher의 복수 classroom 담당
- classroom의 복수 teacher 담당
- school별 복수 manager
