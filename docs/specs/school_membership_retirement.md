# SchoolMembership Retirement

## 목적

Annual teacher authority cutover 뒤 compatibility residue로 남은 `SchoolMembership`
model, association과 table을 제거한다. Teacher의 현재 권한과 운영 동작은 바꾸지 않고,
student `ClassroomMembership`을 포함한 다른 학년도 전환 작업은 섞지 않는다.

## Current canonical

Teacher User 하나는 정확히 한 SchoolYear의 annual account다.

- school: `user.school_year.school`
- school role: `user.school_role`
- grade: `user.grade`
- manager: `user.school_role == "manager"`
- current classroom assignment: `Classroom.teacher_id`

정상 persisted teacher는 `school_year_id`, canonical `login_id`와 `school_role`을 반드시
가지며 grade는 `nil` 또는 `1..6`이다. `SchoolMembership`은 authentication,
authorization, teacher management 또는 오류 복구 source가 아니다.

이 retirement 구현으로 compatibility model, association과 current table을 제거한다.

## Inventory 결과

Controller, policy, authentication/session과 teacher save service에는
`SchoolMembership` data read/write가 없다. Admin manager controller가 사용하는
`school_memberships.errors.inactive_manager` locale key는 이름만 legacy이며 manager
판단과 mutation은 `User.school_role`을 사용한다.

제거 전에 다음 direct residue를 annual source로 교정해야 한다.

- `app/views/classrooms/_form.html.erb`의 manager 분기:
  `current_user.school_membership` 대신 annual manager predicate를 사용한다.
- `app/views/admin/teachers/_edit_content.html.erb`의 role 표시:
  membership role 대신 `User.school_role`을 사용한다.
- `app/views/schools/teachers/_edit_content.html.erb`의 role 표시:
  `@school_membership` 대신 `User.school_role`을 사용한다.
- `db/seeds.rb`의 membership 생성: annual teacher User만 생성하고 compatibility row를
  더 만들지 않는다.
- `SchoolStructure::IntegrityAudit`의
  `invalid_school_membership_user_role`: table residue만 검사하므로 table과 함께 제거한다.

`User#school`을 teacher school authority로 읽는 runtime 호출과 `School#teachers`를 teacher
목록 source로 읽는 runtime 호출은 없다. 후자는 association 자체와 model spec에만 남아
있다. Teacher 목록은 School의 해당 SchoolYear teacher Users로 조회할 수 있다.

Specs의 membership row 생성과 assertion은 다음 세 종류다.

- `SchoolMembership` model 및 `School#teachers` through association 자체 검증: 제거한다.
- membership이 annual authority를 바꾸지 않음을 확인하는 request/policy/service spec:
  최종 annual authority, cross-School scope와 manager boundary spec이 같은 보안 책임을
  이미 검증하므로 compatibility row assertion만 제거한다.
- integrity audit의 invalid membership residue 검증: residue audit과 함께 제거한다.

## 제거 대상

- `SchoolMembership` model과 factory
- `User#school_membership` 및 membership-through `User#school`
- `School#school_memberships` 및 membership-through `School#teachers`
- `school_memberships` table, 현재 schema 항목과 관련 current index/constraint
- membership-only model/association specs와 compatibility-only fixture/assertion
- `invalid_school_membership_user_role` audit issue, query와 전용 spec
- membership model에만 필요한 locale
- development seed의 membership 생성

표시 문구의 의미가 여전히 유효하면 annual teacher 문맥의 key로 옮기거나 기존 annual
key를 재사용한다. Legacy 이름의 locale key를 새 runtime dependency로 유지하지 않는다.

`SchoolMembership`의 member/manager role, grade, teacher별 한 school, school별 한 manager와
active-manager validation은 각각 `User.school_role`, `User.grade`, `User.school_year`와
SchoolYear별 manager unique constraint가 담당하는 final annual invariant와 중복된다.
특히 legacy school별 manager uniqueness는 학년도별 manager를 표현하지 못하므로 annual
authority와 함께 유지하지 않는다.

## 유지 대상

- 모든 기존 migration 파일: 과거 schema를 순서대로 재현하기 위해 삭제하지 않는다.
- 새 drop migration 이전에 존재하는 schema history
- `SchoolYear`, annual teacher User fields와 관련 model/DB constraints
- `Classroom.school_id`, `Classroom.teacher_id`와 teacher assignment audit
- student `ClassroomMembership`, student membership audit와 현재 학생 session 흐름
- annual authority, authorization, cross-School 차단과 manager cardinality regression specs
- 과거 cutover 절차와 정책을 기록한 canonical 문서 및 git history

## DB/data precondition

Drop migration은 실행 초기에 모든 existing `school_memberships` row를 annual User와
비교하고 하나라도 다음에 해당하면 fail-fast해야 한다.

- 연결 User가 teacher가 아니다.
- `membership.school_id != user.school_year.school_id`다.
- membership enum role의 의미가 `user.school_role`과 다르다.
- `membership.grade`와 `user.grade`가 SQL의 null-safe equality 기준으로 다르다.

Foreign key가 보장하는 User/School 존재도 전제로 재확인한다. 검사에는 legacy table과
`users`, `school_years`의 직접 join이면 충분하며 generic service나 장기 audit framework를
만들지 않는다. 불일치가 있으면 migration은 SchoolYear, role 또는 grade를 추측하거나
backfill하지 않고 중단한다. 운영자가 원인을 확인해 별도 승인된 data correction을 한 뒤
다시 실행한다.

Cutover/readiness 완료와 final teacher DB CHECK를 전제로 하므로 membership이 없는 annual
teacher는 오류가 아니다. `SchoolMembership`에는 유효 기간이 없고 annual User가 school,
role과 grade를 보존하므로 membership row 또는 timestamps에만 남는 canonical historical
의미는 없다.

## Acceptance criteria

1. Teacher school, role과 grade authority에 `SchoolMembership`을 사용하지 않는다.
2. 제거 완료 뒤 normal runtime에 `SchoolMembership` read/write가 없다.
3. `User#school_membership`, teacher용 membership-through `User#school`,
   `School#school_memberships`와 `School#teachers`를 제거한다.
4. SchoolMembership role, grade와 manager constraints를 annual User invariant와 중복해
   유지하지 않는다.
5. `invalid_school_membership_user_role` residue audit을 table과 함께 제거한다.
6. Annual teacher assignment audit과 student `ClassroomMembership` audit은 유지한다.
7. Historical migrations는 보존하고 새 migration으로 current table만 drop한다.
8. Drop 전에 모든 legacy row의 school, role과 grade projection mismatch를 fail-fast한다.
9. Migration과 runtime은 mismatch를 자동 보정하거나 membership fallback을 만들지 않는다.
10. Existing annual authority, manager, cross-School와 teacher lifecycle behavior를 유지한다.
11. Current specs의 meaningful security assertions는 annual source 기준으로 유지한다.

## Non-goals

- `Classroom.school_year_id` 또는 `class_label`
- `HomeroomAssignment` 도입이나 `Classroom.teacher_id` 제거
- `Classroom.school_id` 제거
- Student model 분리, `StudentEnrollment` 또는 student `ClassroomMembership` 제거
- planning bootstrap, rollover 또는 archived historical UI
- credential reissue 변경
- teacher cross-School transfer workflow
- generic reconciliation/audit service, automatic backfill 또는 새 gem
