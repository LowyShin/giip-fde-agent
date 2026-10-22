## 요약

장기간 원격에만 방치돼 있던 `feat/pi-token-budgeting` 브랜치(2026-09-08 커밋, PR 없음)의 내용을
현재 `main` 위에 병합해 리뷰 가능한 PR로 구조했습니다.

브랜치가 만들어질 당시 `main` 이 아니었던 관계로, 병합 과정에서 **`main` 이 그 이후 새로 넣은 내용을
되돌리는(롤백하는) 형태**로 충돌이 났습니다. 이 PR에서는 **`main` 쪽 내용을 모두 보존**하고
브랜치의 기능(다국어 토큰 예산)만 합쳤습니다.

## 들어 있는 것

- `slack-bot/token-budget.js` (신규) — 의존성 없는 다국어 토큰 추정·안전 절단 유틸
  - ASCII 중심의 기존 `문자수 ÷ 4` 추정을 기본값으로 유지하되, 한글·일본어·한자는 과소 추정되지 않게 보정
  - 절단 시 Unicode 경계(서로게이트 쌍)를 지키고, 절단 여부를 `truncated` 로 알림
- `slack-bot/prompt-templates.js` — 축약 로직을 **문자 상한 + 토큰 상한** 이중 예산으로 확장
  - `fitParts()` 가 문자 예산과 토큰 예산을 동시에 적용
  - 값 필드(`project`/`working_directory`/`base_branch`/`response_language`)는 `promptValue()` 로 토큰 상한 절단
  - 토큰 예산 초과 시 `overflow` 로 초과량을 남기고 경고 로그 출력
- `slack-bot/model-config.js` — 클래스별 토큰 상한(`PROMPT_INITIAL_TOKENS_BY_CLASS` / `PROMPT_RESUME_TOKENS_BY_CLASS`)
  추가. 환경변수 `PROMPT_INITIAL_MAX_TOKENS` / `PROMPT_RESUME_MAX_TOKENS` 로 조정 가능
- `slack-bot/tools/test-cost-optimization.js` — 토큰 예산 회귀 테스트 추가
- `docs/plans/2026-09-08-pi-token-budgeting.md`, `docs/51-features/WORKFLOW-pi-token-budgeting.md`,
  `docs/03-analysis/pi-comparison-token-efficiency.analysis.md`, `.agent/knowledge/notes/agent-performance.md`

## 충돌 해소 내용 (내용 보존 게이트)

| 파일 | 해소 방법 |
|------|-----------|
| `slack-bot/prompt-templates.js` (최초 프롬프트) | `main` 의 보호 구간 예산 하한(`protectedChars + 100`)을 **유지**하고, 그 위에 브랜치의 토큰 예산을 추가 적용. 축약 대상 목록은 `main` 의 4개 구간을 그대로 씁니다(브랜치가 `resume_legacy` 도 축약 대상으로 넣었으나 `main` 은 그 절을 보호하고 있음 → `main` 의 보호를 우선). |
| `slack-bot/prompt-templates.js` (재개 프롬프트) | `main` 의 `protectedChars` 산출과 "지시 보존 우선" 경고·예산 상향을 **유지**하고 `fitParts()` 에 토큰 예산 인자만 추가. `main` 의 `RESUME_TRIM_ORDER` 를 그대로 사용. |
| `docs/HISTORY.md` | `main` 쪽 기록(20260910~20261006 등 9개 줄)을 **유지**. 브랜치 쪽은 2026-07-01~07-06 구간을 `main` 이 이미 축약 통합한 형태라 이중 기재하지 않았습니다. 피처 자체의 기록(2026-09-08)은 `HISTORY.md` 항목으로 남겼습니다. |
| `docs/WHATS_NEW.md` | `main` 쪽 롤링 페이지(기준일 2026-10-22)를 **유지**. 규칙 36상 이 페이지는 최근 7일만 유지하므로 2026-09-08 항목은 `HISTORY.md` 로 옮겼습니다. |

병합 후 `git diff origin/main HEAD` 기준 **삭제된 `main` 내용 없음**(차이는 위 표의 해소 결과뿐)임을 확인했습니다.

## 검증 (실행 결과)

```
node slack-bot/tools/test-cost-optimization.js   → 통과 112 / 실패 0
node slack-bot/tools/test-ant-input-contract.js  → PASS (exit 0)
node slack-bot/tools/test-k-layer-scope.js       → PASS (exit 0)
node slack-bot/tools/test-task-evidence.js       → PASS (exit 0)
node .agent/tests/windows-hook-doctor.test.js    → 8 passed, 0 failed
node --check slack-bot/prompt-templates.js        → exit 0
node --check slack-bot/token-budget.js           → exit 0
```

## 다른 PR과의 관계

- PR #205 (`bot/rescue-ant-verification-gate`) 와 **같은 파일** `slack-bot/tools/test-cost-optimization.js` 를
  각각 수정합니다. 둘 다 머지하면 해당 파일에서 충돌이 납니다 — 한쪽을 먼저 머지한 뒤 나머지分支을
  rebase 하는 순서가 필요합니다(본 PR 에서는 `main` 기준이라 아직 서로 충돌하지 않습니다).
- `scripts/gissue/merge-standing-prs.ps1` 자동 머지 대상 저장소에 이 레포는 포함되어 있지 않아 자동 머지되지 않습니다.
