# 쑥쑥성장기록장 / Daily Growth Log

`suksuk_growth_record`는 학생의 일일 자기평가와 성찰을 기록하는 서비스입니다.

이 저장소는 `ShinJaehun/suksuk_school_starter`의
`starter-current-year-baseline-2026-09` tag, commit `47bed6e`에서 분기했습니다.
아래 공통 학교 운영 runtime foundation은 그대로 상속합니다.

## 제공하는 기반

- School과 Classroom
- Teacher / Student `User`
- teacher의 `SchoolMembership`
- student의 `ClassroomMembership`
- `Classroom.teacher_id` 기반 Teacher ↔ Classroom 1:1 assignment
- global admin / school manager / teacher / student 권한 경계
- Teacher, Student membership, Classroom lifecycle
- teacher/admin Devise 인증
- student PIN/token 로그인과 짧은 session
- 학생 roster, 번호, PIN과 avatar 관리
- 공통 layout과 navigation
- Rails, Tailwind CSS, Devise, Pundit, ActiveStorage, PostgreSQL

## 포함하지 않는 도메인

이 starter에는 praise/compliment, coupon, message, holiday 또는 growth-specific domain을 포함하지 않습니다.

## 주요 문서

- 현재 구조: [`docs/architecture/current_system.md`](docs/architecture/current_system.md)
- 역할과 권한: [`docs/architecture/roles_and_permissions.md`](docs/architecture/roles_and_permissions.md)
- 학교 운영 lifecycle: [`docs/specs/school_operations_lifecycle.md`](docs/specs/school_operations_lifecycle.md)
- 학생 membership lifecycle: [`docs/specs/student_membership_lifecycle.md`](docs/specs/student_membership_lifecycle.md)
- Classroom grade: [`docs/specs/classroom_grade_foundation.md`](docs/specs/classroom_grade_foundation.md)

## 개발

```bash
bin/setup
bin/dev
```

검증은 프로젝트 정책에 따라 RSpec을 사용합니다.

```bash
bundle exec rspec
```

개발·테스트 demo 데이터는 필요할 때 다음 명령으로 준비합니다.

```bash
bin/rails db:seed
```
