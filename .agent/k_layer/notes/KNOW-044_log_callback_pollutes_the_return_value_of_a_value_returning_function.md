# KNOW-044 — 로그 콜백이 성공 스트림에 쓰면 "값을 반환하는 함수" 의 반환값이 오염된다

> 근거: 2026-11-13 CSN 70424 저장소 정비 106차 세션 실측 · 발행: 2026-11-13 · 상태: 검증됨(직접 실측)

## 요지

`& $Log "..."` 로 진행 로그를 남기는 함수가 **값을 반환**하면, 로그 콜백이 **성공 스트림**에
쓰는 한 그 로그 문자열이 **반환값에 섞인다** — `$x = Foo` 대입은 Foo 의 성공 스트림을 통째로 받기
때문이다(`cleanup-worktrees.ps1` 의 `Write-CleanupLog` → `Write-Output` 이 정확히 그 형태다).

그리고 PowerShell 의 **멤버 열거**는 컬렉션 프로퍼티를 **펼쳐서** 준다. 그래서 섞인 반환값에서
`$x.Branches` 를 읽으면 HashSet 이 아니라 **그 안의 원소들**이 나오고, **그 집합이 비어 있으면
`$null`** 이 된다.

⇒ 규칙 2가지
1. **값을 반환하는 함수는 로그를 성공 스트림에 쓰지 않는다** — 모든 `& $Log` 에 `| Out-Null`.
2. **그 결과가 `$null` 이면 파괴 동작(삭제)으로는 흘러가면 안 된다** — fail-closed.

## 실측 (2026-11-13 106차)

`scripts/gissue/cleanup-worktrees.ps1 -DryRun` 실행 중 02:26:46 KST 에 실제 예외가 떴다:

```
You cannot call a method on a null-valued expression.
At ...\scripts\gissue\worktree-safety.ps1:1170 char:13
+         if (-not $merged.Branches.Contains($e.Branch)) {
+     FullyQualifiedErrorId : InvokeMethodOnNull
```

### 원인 3단

| # | 층위 | 내용 |
|---|---|---|
| ① | 반환값 오염 | `Get-GissueMergedBranchSet` 의 `& $Log "..."` 가 로그 콜백(성공 스트림 출력)을 통해 **로그 문자열을 반환값에 섞는다** → `$merged` = `@(String, PSCustomObject)` (실측: count=2, 타입 `String,PSCustomObject`) |
| ② | 멤버 열거 | `$merged.Branches` 는 멤버 열거로 **HashSet 을 펼친 결과**(원소 배열)가 된다. **집합이 비면 아무 값도 없어 `$null`** (실측: `arr.Branches null = True`) |
| ③ | 게이트 붕괴 | `$null.Contains(...)` 는 **'if' 문장 하나만 버리고** 흐름이 다음 문장으로 넘어간다 → 링크스캔 → idle 게이트 → 삭제 보고 → **`git worktree remove`**. 즉 **머지 확인을 한 번도 하지 않은 채 삭제** (실측: 삭제 예정 로그에 *"머지 확인"* 이라고 찍히면서 `Removed=1`) |

### 왜 위험한가

`gh pr list --state merged` 실패(레이트리밋 · 인증 만료 · 일시적 네트워크)는 **일상적인 실패**다.
그 순간 머지판정은 "약한 판정" 이 아니라 **"모든 worktree 를 삭제"** 으로 뒤집힌다.
파일 자신의 명세(*"giip 2463: 판정 불가일 때 삭제로 흘러가던 fail-open 을 fail-closed 로 뒤집었다"*)와
정면으로 어긋난다 — 다른 게이트(활동시각 판정 불가 · 정션 사전검증 실패)는 이미 fail-closed 였고
**머지판정만 fail-open 으로 남아 있었다**.

### 조치 (106차, PR 로 반영)

1. `Get-GissueMergedBranchSet` 의 모든 `& $Log` 에 `| Out-Null` → 반환값은 **정확히 1개 객체**.
2. 머지판정 게이트 **앞에 fail-closed 가드** 추가 — 판정 결과가 없으면 `MANUAL-REVIEW(머지판정 불가)` 로
   닫고 `continue` (**삭제 경로로 가지 않는다**).
3. `Ok=$false`(조회 실패) 를 '미머지' 와 **사유를 달리** 기록한다.
4. 같은 계열 오염(`Remove-GissueDirectoryTreeSafely` 의 폴백 경로) 도 함께 정리.
5. 회귀 테스트 `scripts/gissue/tests/test-worktree-merge-gate-failclosed.ps1` (18항목) —
   **수정 전 코드에 붙이면 8건 FAIL / exit 1**, 수정 후 18건 PASS / exit 0 을 실측 대조.

## 규칙

1. **"로그를 남기는 함수" 와 "값을 반환하는 함수" 를 한 몸으로 만들지 않는다.** 로그를 내보낼
   경로(성공 스트림)와 결과를 내보낼 경로를 분리한다 — `| Out-Null` 로 로그만 삼킨다.
2. **호출자는 반환값을 방어적으로 다룬다.** 결과가 `$null` 이면 "판정 불가" 이며, 파괴 동작의
   **선행 조건으로 삼지 않는다**(fail-closed). `$null` 검사는 방어적 코드가 아니라 **게이트** 다.
3. **"판정 불가" 와 "미머지" 는 결론은 같지만 사유가 다르다.** 사유를 다르게 남겨야 운영자가
   "조회가 실패한 것" 과 "실제로 PR 이 없는 것" 을 구분한다.
4. **회귀 테스트는 고친 코드뿐 아니라 고치기 전 코드에도 붙여 본다.** "고친 뒤 green" 은
  不足以 회귀를 증명하지 않는다 — **수정 전 코드에서 FAIL 하는 것** 이 진짜 회귀 테스트다.

## 관련

- [KNOW-003](KNOW-003_worktree_safety_dotsource_pitfall.md) — 같은 정리 엔진의 다른 fail-open
  (dot-source 실패 → 링크 선검사 없이 삭제 진행)
- [KNOW-008](KNOW-008_cleanup_worktrees_classification_and_builtin_idle_gate.md) — 정리 도구 판정 Status 5종
- [KNOW-009](KNOW-009_cleanup_onlypath_separator_silent_zero.md) — `-OnlyPath` 경로 구분자 정규화 누락
- [KNOW-035](KNOW-035_powershell_5_1_convertfrom_json_does_not_enumerate_json_arrays.md) — PS 5.1 의
  `ConvertFrom-Json` 이 JSON 배열을 전개하지 않는 것과 **같은 계열**(컬렉션이 평탄화되는 PS 동작)의 다른 축
- `.agent/rules/55_destructive_cleanup_incident_gate.md`
- work_history: `.agent/work_history/20261113_0235_csn70424_repo-maintenance.md`
