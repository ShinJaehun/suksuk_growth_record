# School And Classroom Boundaries

## 목적

학교는 조직·권한·운영 lifecycle의 상위 경계이며 교실과 교실 운영 기록은 그 아래에 속한다.

```text
School
└── SchoolYear
    └── Classroom
        ├── HomeroomAssignment (current and history)
        ├── student ClassroomMembership
        └── 운영 기록
```

## 교실 경계

- 모든 `Classroom`은 생성 시 하나의 `SchoolYear`를 가져야 하며 학교는 `classroom.school_year.school`로 결정한다.
- 저장된 `Classroom.school_year_id`는 운영 기록이나 구성원의 유무와 관계없이 변경할 수 없다.
- 학교를 잘못 선택한 빈 교실은 다른 학교로 이동하지 않고 삭제한 뒤 다시 만든다.
- 교실에 귀속된 학생 소속과 공통 운영 기록은 다른 학교로 옮기거나 재해석하지 않는다.

## 교사 소속과 담당 교실

```text
SchoolYear 1 ─ N Teacher
Teacher 0..1 ─ 0..1 Classroom
```

현재 담당 교사는 `ended_on IS NULL`인 HomeroomAssignment로 표현하며 다음을 모두 만족해야 한다.

- 연결된 `User.role`이 `teacher`다.
- 교사와 Classroom의 `school_year_id`가 같다.
- 교사의 `User.grade`와 `Classroom.grade`가 같다.
- 교사와 교실이 모두 active다.
- 한 교사는 최대 한 교실, 한 교실은 최대 한 교사와 연결된다.

정상 teacher는 SchoolYear에 속하며 SchoolYear가 없는 teacher는 교실 담당자로 배정할 수 없다. `ClassroomMembership`은 학생의 교실 소속에 사용한다.

teacher assignment는 `ended_on IS NULL`인 HomeroomAssignment, `users` foreign key와 null이 아닌 값에 대한 unique index로 1:1 관계를 보장한다. `ClassroomMembership`은 student membership에만 사용한다.

## 학생의 학교

학생의 학교는 active student `ClassroomMembership`이 연결하는 `classroom.school_year.school`을 통해 결정한다.

## 학교 비활성화

학교 비활성화는 기록 삭제가 아니다. 기존 교실과 운영 기록을 보존하면서 신규 로그인과 운영 접근을 차단한다.

## 데이터 감사

다음 명령으로 학교·교실·교사 소속의 기존 데이터 무결성을 확인한다.

```bash
bin/rails school_structure:audit
```

이 task는 데이터를 수정하거나 자동 복구하지 않는 읽기 전용 감사 도구다. 발견된 문제는 보고하고 비정상 종료한다.
