# Fix Plan (Work Items)

PRD에서 자동 생성된 WI 체크리스트입니다.
`/wi:start` 실행 시 PRD 분석 결과로 이 파일이 채워집니다.

## 형식
```
- [ ] WI-001-feat 작업명 | L1:도메인 > L2:모듈 > L3:기능
- [x] WI-002-feat 완료된 작업 | L1:도메인 > L2:모듈 > L3:기능
- [ ] WI-A2a-refactor 영숫자 ID 예시 | L1:도메인 > L2:모듈 > L3:기능
- [ ] WI-001-1-fix 서브넘버링 후속 fix | L1:도메인 > L2:모듈 > L3:기능
```
WI ID는 `[0-9A-Za-z]+(-[0-9]+)?` 패턴 — 숫자(`001`/`015`) / 영숫자(`A2a`/`C3code`/`E1`) / 서브넘버링(`001-1`) 모두 허용 (rules/wi-global.md 참조).

## Work Items
<!-- /wi:start 실행 시 PRD에서 자동 생성 -->
