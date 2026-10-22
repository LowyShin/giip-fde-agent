# Pi-Inspired Multilingual Token Budgeting Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** `pi`의 컨텍스트 예산 관리 원칙을 GIIP Slack 실행 프롬프트에 맞게 적용해 한글·일본어에서도 초기 및 재개 프롬프트가 실제 토큰 예산을 넘지 않도록 한다.

**Architecture:** 기존의 선택 컨텍스트, 체크포인트 재개, 고정 prefix 구조는 유지한다. 의존성 없는 `token-budget.js`가 다국어 텍스트의 보수적 토큰 수를 추정하고 예산에 맞는 안전한 절단을 제공하며, `prompt-templates.js`의 기존 우선순위 축약기가 문자 상한과 토큰 상한을 동시에 적용한다.

**Tech Stack:** Node.js CommonJS, 내장 `assert`, 기존 `slack-bot/tools/test-cost-optimization.js` 회귀 테스트.

---

## 이해된 내용

`earendil-works/pi`를 그대로 포함하거나 GIIP를 독립 LLM 런타임으로 재작성하는 작업이 아니다. 두 저장소의 실제 구현을 비교해 현재 Slack→CLI 구조에 직접 효과가 있는 토큰 효율 기능만 최소 범위로 이식한다.

## 비교 결과와 범위

| Pi 기능 | GIIP 현재 상태 | 결정 |
|---|---|---|
| 임계치 기반 compaction | 체크포인트와 재개 전용 프롬프트로 동일 목적 달성 | 유지 |
| 최근 메시지 보존 + 구조화 요약 | 완료/미완료 단계, 변경 파일, 오류, 재개 컨텍스트로 구현됨 | 유지 |
| tool result 2,000자 제한 | progress event 출력 2,000자, 오류 1,500자로 구현됨 | 유지 |
| 누적 read/modified 파일 추적 | progress JSONL과 checkpoint에 구현됨 | 유지 |
| 고정 prefix와 일회성 요약의 cache-write 억제 | 고정 prefix는 구현됨, provider cache 제어는 CLI에서 불가 | prefix 유지 |
| 세션 트리와 branch summary | GIIP issue 작업은 선형 실행이고 세션 런타임을 소유하지 않음 | 미도입 |
| 토큰 단위 context threshold | GIIP는 문자 수 ÷ 4만 사용해 CJK를 과소 추정 | 도입 |

### Task 1: 다국어 토큰 예산 유틸리티

**Files:**
- Create: `slack-bot/token-budget.js`
- Modify: `slack-bot/tools/test-cost-optimization.js`

**Step 1: Write the failing test**

다음 동작을 테스트한다.

```javascript
assert.strictEqual(tokenBudget.estimateTokens('a'.repeat(400)), 100);
assert.ok(tokenBudget.estimateTokens('한'.repeat(100)) >= 100);
assert.ok(tokenBudget.truncateToTokens('한'.repeat(100), 20).tokens <= 20);
```

**Step 2: Run test to verify it fails**

Run: `node slack-bot/tools/test-cost-optimization.js`

Expected: FAIL because `slack-bot/token-budget.js` does not exist.

**Step 3: Write minimal implementation**

ASCII 문자 묶음은 4자당 약 1토큰, 한글·가나·한자 등 CJK 문자는 문자당 1토큰, 그 외 비ASCII 문자는 2자당 1토큰으로 보수적으로 계산한다. 절단은 Unicode code point 경계를 지키고 이진 탐색으로 가장 긴 prefix를 찾는다.

**Step 4: Run test to verify it passes**

Run: `node slack-bot/tools/test-cost-optimization.js`

Expected: all tests pass.

**Step 5: Commit**

```bash
git add slack-bot/token-budget.js slack-bot/tools/test-cost-optimization.js
git commit -m "feat(slack-bot): add multilingual token budgeting"
git push -u origin feat/pi-token-budgeting
```

### Task 2: 초기·재개 프롬프트에 토큰 상한 적용

**Files:**
- Modify: `slack-bot/model-config.js`
- Modify: `slack-bot/prompt-templates.js`
- Modify: `slack-bot/tools/test-cost-optimization.js`

**Step 1: Write the failing test**

한글 대용량 컨텍스트로 만든 초기·재개 프롬프트가 각각 `initialMaxTokensEstimated`, `resumeMaxTokensEstimated` 이하이고, 안전 규칙·프로토콜·동적 상태를 보존하는지 검증한다.

**Step 2: Run test to verify it fails**

Run: `node slack-bot/tools/test-cost-optimization.js`

Expected: FAIL because existing `fitParts()` enforces characters only.

**Step 3: Write minimal implementation**

`fitParts(parts, charBudget, trimOrder, tokenBudget)`로 확장한다. 기존 우선순위대로 가변 파트를 줄인 뒤, 마지막 방어 절단도 `truncateToTokens()`로 수행한다. 고정 파트만으로 예산을 넘는 경우에는 고정 파트를 훼손하지 않고 경고와 측정값을 남긴다.

**Step 4: Run test to verify it passes**

Run: `node slack-bot/tools/test-cost-optimization.js`

Expected: all tests pass and both budgets are satisfied for test fixtures.

**Step 5: Commit**

```bash
git add slack-bot/model-config.js slack-bot/prompt-templates.js slack-bot/tools/test-cost-optimization.js
git commit -m "feat(slack-bot): enforce token-aware prompt limits"
git push
```

### Task 3: 비교 근거와 운영 지식 기록

**Files:**
- Create: `docs/03-analysis/pi-comparison-token-efficiency.analysis.md`
- Create or Modify: `.agent/knowledge/notes/agent-performance.md`
- Modify: `docs/WHATS_NEW.md`

**Step 1: Write the comparison report**

Pi commit `b2602be77cb7b0de45dd616407fd210daa48aa75`와 GIIP 기준 commit `4c946f6`의 비교 범위, 도입·미도입 결정, 라이선스(MIT), 검증 결과를 기록한다.

**Step 2: Add a source-linked K-Layer claim**

다국어 문자 예산이 CJK 토큰을 과소 추정한다는 관찰과 새 회귀 테스트를 source로 연결한다.

**Step 3: Update What's New**

최근 7일 규칙을 지키며 기능 항목과 분석 문서 링크를 추가한다.

**Step 4: Run final verification**

Run: `node slack-bot/tools/test-cost-optimization.js`

Expected: all tests pass, exit code 0.

Run: `git diff --check`

Expected: no output, exit code 0.

**Step 5: Commit**

```bash
git add docs/03-analysis/pi-comparison-token-efficiency.analysis.md .agent/knowledge/notes/agent-performance.md docs/WHATS_NEW.md
git commit -m "docs: record pi token-efficiency integration"
git push
```

## 반대 관점 검토

- 가장 큰 실패 가능성은 토큰 추정기가 실제 tokenizer와 다르다는 점이다. 공급자별 tokenizer 의존성을 추가하지 않고 보수적 상한으로만 사용하며, 기존 문자 상한도 함께 유지한다.
- 가장 싼 검증은 ASCII와 CJK가 섞인 대형 fixture에서 최종 추정 토큰과 필수 section 보존을 동시에 검사하는 것이다.
- 토큰 절감과 지시 보존이 충돌하면 안전 규칙·프로토콜·동적 상태를 우선하고, 선택 컨텍스트·과거 출력부터 줄인다.

