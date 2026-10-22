## 요약

장기간 원격에만 방치돼 있던 `feat/ant-verification-gate` 브랜치(2026-09-10~11 커밋, PR 없음)의 내용을
현재 `main` 위에 올려 리뷰 가능한 PR로 구조했습니다. 내용 변경 없이 **브랜치 구조 + 검증 결과 첨부**만 합니다.

## 이 PR에 들어 있는 것 (원본 브랜치의 Task 1 분량)

- `slack-bot/task-verifier.js` — 결정론적 완료 판정기(순수 함수)
  - 소스 변경이 있는데 테스트 성공 기록이 없으면 완료로 판정하지 않음
  - 같은 명령의 과거 실패 뒤 최신 성공이면 완료로 판정
  - 미해결 blocked 항목·결과 파일 부재는 완료로 판정하지 않음
  - 소스 변경이 없으면 테스트 기록 없이 완료 가능
- `slack-bot/tools/test-cost-optimization.js` — 위 판정기에 대한 회귀 테스트 추가
- `docs/plans/2026-09-10-ant-verification-gate.md` — 원본 구현 계획

## 포함되지 않은 것 (원본 브랜치에도 없음)

- **Task 2: 실행 완료 경로 연결**(`task-manager.js` 가 판정기를 호출하도록 배선) — 미구현
- Task 3: 참조·이력 문서화 / Task 4: 검토·배포

즉 이 PR은 **Task 1 분량만**이며, 머지 후 `task-manager` 배선은 별도 후속 작업입니다.
배선을 붙이면 "프로세스 종료 코드 0 만으로 실패한 작업이 완료 처리되는 문제"가 실제로 막힙니다.

## 검증 (실행 결과)

```
node slack-bot/tools/test-cost-optimization.js
→ 통과 109 / 실패 0 (전부 통과)

node --check slack-bot/task-verifier.js
→ exit 0
```

`main`(58d1874) 을 병합한 상태에서 위 명령을 다시 실행해 통과를 확인했습니다.

## 병합 방법

원격 `feat/ant-verification-gate` 브랜치에 `origin/main` 을 병합했습니다
(`git merge-tree` 사전 확인 결과 자동 병합 가능 → 충돌 없음).

## 참고

- 원본 브랜치 커밋: `32b8e5f`(계획) / `7eda100`(판정기) / `f94c24f`(테스트)
- `scripts/gissue/merge-standing-prs.ps1` 자동 머지 대상 저장소에 이 레포는 포함되어 있지 않아
  자동 머지되지 않습니다. 리뷰 후 머지 여부는 사람이 결정하면 됩니다.
