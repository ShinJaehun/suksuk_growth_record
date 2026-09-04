# Testing Targets

## 목적
이 문서는 현재 starter에서 테스트 우선순위가 높은 핵심 규칙을 정리한다.

---

## 최우선 테스트 대상

- school, grade와 lifecycle 불변식
- teacher와 classroom의 1:1 assignment
- student membership lifecycle과 roster
- PIN/token 로그인과 session
- teacher/admin/student 권한 분기
- 핵심 request 응답(Turbo/HTML)

---

## 리팩토링 전에 고정할 것

- assignment와 lifecycle transaction
- student membership 상태 전이
- 주요 policy 분기
- PIN과 roster endpoint 동작

---

## 나중으로 미뤄도 되는 것

- 세세한 뷰 구조
- 자주 바뀌는 UI 문구
- low-value 시스템 테스트
