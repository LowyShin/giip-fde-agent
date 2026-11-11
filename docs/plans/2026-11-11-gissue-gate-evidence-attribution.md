# gissue 게이트 오판 근본 해결 — 증거 기반 PR 귀속 + 체크리스트 게이트 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** REVIEW→READY 되돌림의 근거를 "기대 브랜치(`bot/task-giip-<isn>`) 미탐지"에서
"증거 기반 PR 귀속 실패 + 의뢰 체크리스트 판정 미충족(UNFULFILLED)"으로 바꾼다.

**Architecture:**
1. **귀속(attribution)**: Node 정본(`lib/pr-lookup.mjs`)에 증거 4면(브랜치명·PR 제목/본문·커밋 메시지·이슈 코멘트 PR 링크) 탐색을 추가하고, PowerShell(`gissue-audit-lib.ps1`)은 그 결과를 1차 판정에 편입한다.
2. **되돌림 게이트**: 구룰(PR-gate/scope-gate/comment-gate)이 되돌림을 *제안*하면, 되돌리기 **전에** 의뢰 체크리스트 판정을 수행하고 **UNFULFILLED(미충족 항목 있음)일 때만** 되돌린다. 판정 근거는 체크리스트 코멘트로 남긴다(코멘트 없는 전이 금지).
3. **비교 가능성**: 구룰 결론과 신룰 결론을 기존 `logs/checklist-shadow.jsonl` 같은 형식으로 함께 기록 → 기존 `compare-checklist-vs-legacy.ps1` 로 비교 가능.

**Tech Stack:** PowerShell 5.1(Windows) / Node 18+ / `gh` CLI / `claude` CLI(판정 LLM).

---

## Task 1: 증거 기반 귀속 규칙(Node 정본)

**Files:**
- Modify: `scripts/gissue/lib/pr-lookup.mjs`
- Test: `scripts/gissue/tests/test-pr-lookup.mjs`

**Step 1: Write the failing test** — `test-pr-lookup.mjs` 에 순수 단위 케이스를 추가한다.
- `prDeclaresIsn(pr, isn)` — 브랜치/제목이 이 isn 을 선언하면 true / 다른 isn 만 선언하면 false
- `commitMatchesIsn(msg, isn)` — `giip #4840` / `giip-4840` / `#4840` 매칭, `giip 48401` 불매칭
- `branchMatchesIsn(branch, isn)` — `fix/giip-4840-x` 매칭, `fix/giip-48401` 불매칭

**Step 2: Run it** → FAIL(함수 없음).

**Step 3: Implement** — 위 3개 순수 함수를 `pr-lookup.mjs` 에 추가한다.

**Step 4: Run it** → PASS.

## Task 2: 조직 전 레포 탐색(Node 정본) + CLI 확장

**Files:**
- Modify: `scripts/gissue/lib/pr-lookup.mjs`, `scripts/gissue/lib/pr-lookup-cli.mjs`
- Test: `scripts/gissue/tests/test-pr-lookup-org.mjs` (신규, fake `gh` 로 오프라인)

**Step 1: Write the failing test** — 임시 폴더에 fake `gh` 를 만들어 PATH 앞에 두고 `pr-lookup-cli.mjs` 를 실행한다.
- 조직 전 PR 제목/본문 경로: `gh search prs --owner TestOrg` 결과 중 isn 을 선언한 PR 만 후보가 된다.
- 커밋 메시지 경로: `gh search commits` 로 찾은 커밋 → `gh api .../commits/<sha>/pulls` → PR.
- 브랜치명 경로: `gh api repos/TestOrg/r/branches` → isn 을 담은 브랜치 → `gh search prs --owner TestOrg -- head:<branch>`.
- 반대로, isn 을 담지 않은 PR 은 후보가 되지 않는다(오탐 방지).

**Step 2: Run it** → FAIL.

**Step 3: Implement** —
- `findIssuePrsInOrg(org, isn, opts)` — PR 검색(open/closed) + 커밋 검색 + 브랜치 열거(상한 적용).
- `findIssuePrsByBranchInRepo(slug, isn, opts)` — 레포 1개의 브랜치명 탐색.
- CLI: `--org <org>`(반복 가능), `--org-max-repos`, `--org-limit` 인자 추가. 기존 호출(위치 인자만) 호환 유지.
- **대표 PR 선택 정정(#4840)**: 브랜치/제목으로 이 isn 을 *선언한* PR 을 먼저, 그다음 MERGED>OPEN>CLOSED, 그다음 PR 번호 내림차순.

**Step 4: Run it** → PASS.

## Task 3: PowerShell 귀속 결합 + 1차 판정 편입

**Files:**
- Modify: `scripts/gissue/gissue-audit-lib.ps1`
- Test: `scripts/gissue/tests/test-pr-attribution-evidence.ps1` (신규)

**Step 1: Write the failing test** —
- `Get-AttributionOrgs` — `slug:OWNER/REPO`/로컬 경로에서 조직을 뽑는다, `$repos` 가 비면 조직도 비어 있다(네트워크 0).
- `Get-IssuePrAttribution` — node 결과 + 이슈 코멘트 PR 링크 결과를 합치고 중복을 제거한다, `HasPr/HasMerged/Sources/Candidates/Text` 를 채운다.
- `Get-ChecklistPrEvidence` — 귀속 결과의 PR 목록을 증거 텍스트에 싣는다.
- `Test-IssueHasPr` / `Test-IssueHasMergedPr` — 증거 경로(조직 전 탐색)까지 반영한다.

**Step 2: Run it** → FAIL.

**Step 3: Implement** —
- `Get-AttributionOrgs($repos)` — `GISSUE_GH_ORGS` 환경변수 + `$repos` 의 origin/slug 에서 유도(기본값 없음 → 네트워크 0).
- `Get-IssuePrAttributionViaNode($isn, $repos, $Orgs)` — CLI 호출(실패 시 `$null`).
- `Get-IssuePrAttribution($isn, $repos, $LinkTexts, $Orgs)` — node + 코멘트 링크 + PS 폴백 병합, 프로세스 캐시.
- `Test-IssueHasPr` / `Test-IssueHasMergedPr` — 기존 3경로 뒤에 증거 경로 추가.
- `Get-ChecklistPrEvidence` — 귀속 결과 기반(PR 목록·상태·변경 파일).

**Step 4: Run it** → PASS.

## Task 4: 되돌림 게이트(체크리스트 UNFULFILLED 일 때만)

**Files:**
- Modify: `scripts/gissue/gissue-audit-lib.ps1`, `scripts/gissue/pr-gate-sweep.ps1`, `scripts/gissue/review-done-audit.ps1`
- Test: `scripts/gissue/tests/test-pr-gate-revert-gate.ps1` (신규)

**Step 1: Write the failing test** — 순수 함수로 검증한다.
- `Get-GatedRevertDecision` : 판정 실패(`Ok=false`) → `skip`(전이 없음) / `KEEP` → `keep`(되돌리지 않음) / `HOLD` → `hold`(코멘트만) / `REVERT` → `revert`(체크리스트 코멘트 + READY).
- 되돌림 시 코멘트 본문에 `## 의뢰 체크리스트 판정` 과 `[REVIEW-AUDIT:CHECKLIST-REVERT]` 가 있고, 구룰 마커(`[PR-GATE-REVERT]` 등)는 없다(카운팅 오염 방지).
- 회차 초과/동일 미충족 반복 → `escalate`(NEEDS_DECISION).

**Step 2: Run it** → FAIL.

**Step 3: Implement** —
- `Get-GatedRevertDecision` (gissue-audit-lib.ps1, 순수 함수).
- `pr-gate-sweep.ps1` — `-PrGateMode`(Gated 기본|Shadow|Legacy) + `GISSUE_PR_GATE_MODE`. Gated 모드에서 구룰의 되돌림 제안은 체크리스트 게이트를 거쳐야만 실행된다. Shadow 모드는 구룰이 결정하고 신룰结论만 기록(비교용). Legacy 는 종전 동작.
- `review-done-audit.ps1` — DONE/REVIEW 되돌림에도 같은 게이트를 적용하고, `Get-ChecklistPrEvidence` 에 이슈 본문/코멘트 텍스트를 넘긴다.

**Step 4: Run it** → PASS.

## Task 5: 오판 사례 회귀 테스트 + 전체 게이트

**Files:**
- Create: `scripts/gissue/tests/test-pr-gate-falsepositive-regression.ps1`
- Modify: `scripts/gissue/run-repo-gates.ps1` (기대 ps1 테스트 수 갱신), `docs/WHATS_NEW.md`

**Step 1: Write the failing test**
- **giip #4840 재현**: 판정 대상이 아닌 PR(본문 참조만)이 대표 PR 로 뽑히지 않고, 이 isn 을 선언한 PR 이 대표가 된다. 그 대표 PR 로 scope 판정을 하면 무관한 diff 로 MISMATCH 가 나지 않는다.
- **giip #4839 재현**: 진행 코멘트 *형식* 때문에 되돌림이 proposal 될 수 있지만, 체크리스트 판정이 KEEP 이면 되돌리지 않는다(코멘트 0건). 체크리스트가 REVERT 면 체크리스트 코멘트와 함께 되돌린다.

**Step 2: Run it** → FAIL(수정 전에는 되돌림이 발생).

**Step 3: Implement** — Task 1~4 의 수정으로 통과.

**Step 4: Run all** — `run-repo-gates.ps1` 로 전수 실행(신규 테스트 포함), 기대 건수 갱신, `docs/WHATS_NEW.md` 갱신.

---

## 검증 명령

```bash
# 회귀 테스트 전수
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gissue/run-repo-gates.ps1
# 개별
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gissue/tests/test-pr-attribution-evidence.ps1
node scripts/gissue/tests/test-pr-lookup-org.mjs
```

## 위험과 롤백

- 새 판정 경로는 **기본 Gated**(체크리스트 게이트 적용). 되돌림이 안 되는 방향으로만 실패한다(근거 부족 → 보류).
- 즉시 롤백: `-PrGateMode Legacy` 또는 `GISSUE_PR_GATE_MODE=legacy` (종전 동작 그대로).
- 비교: `-PrGateMode Shadow` — 구룰 결론과 신룰 결론을 `logs/checklist-shadow.jsonl` 에 함께 기록.
