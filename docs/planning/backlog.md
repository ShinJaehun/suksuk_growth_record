# Backlog

## 문서 사용 원칙

- 쑥쑥성장기록장 prototype 이후의 active product work만 기록한다.
- 확정 정책은 canonical spec과 architecture 문서로 이동한다.
- starter에서 상속한 foundation의 향후 roadmap은 성장기록장 우선순위로 간주하지 않는다.

## P0

- Daily Growth Log MVP는 [`daily_growth_log_mvp.md`](../specs/daily_growth_log_mvp.md)를 따른다.

## P1

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

- Grade model
- teacher의 복수 classroom 담당
- classroom의 복수 teacher 담당
- school별 복수 manager

## Upstream starter future work

아래 항목은 `suksuk_school_starter`의 향후 과제이며 현재 성장기록장 prototype 범위 밖이다.

- planning/archived SchoolYear full operation
- rollover와 실패·복구 절차
- `/admin/teachers` planning-year bulk bootstrap
- `/admin/classrooms` planning-year bulk configuration
