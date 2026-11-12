# CSN 70424 저장소·PR 레벨 정비 106차 (2026-11-13 02:35 KST)

> 세션 성격: **저장소/PR 레벨 정비**(CSN 70424 저장소 전체 스코프) — 단일 이슈 처리가 아니다.
> 규칙상 항상 도는 [0] 병합충돌 · [E] CI/검증 실패 · [F] 오판 stash · [H] 최근 코멘트 논리 재검증
> 4단계를 전부 수행했고, **별도 act 로 실제 코드 결함 1건을 찾아 고쳤다.**

## 착수 상태 점검

- 공유 체크아웃 `C:\Users\lowys\Downloads\projects\giip-fde-agent` — `git status` clean, `main` = `e734905`.
- `git fetch origin --prune` → `origin/main` = **`35d7668`** (= PR #401 머지 커밋). 공유 체크아웃이 1커밋
  뒤처져 있었으나 **커밋하지 않고** 작업은 전용 워크트리에서 진행했다.
- 전용 워크트리 `D:\temp\worktrees\giip-fde-agent\maint-106-0235`
  (브랜치 `chore/csn70424-maint106-20261113-0235`, base = `origin/main` 35d7668).
- 사전 락 불요 — 이 저장소는 CSN 70424 소관이며 lowyworkenv 자신이 아니다(104·105차 기록과 동일).

## [0] PR merge conflict — 대상 0건

- 세션 착수 시 열린 PR 은 **PR #401 1건**뿐이었고 `mergeable=MERGEABLE` · `mergeStateStatus=CLEAN`
  → 충돌 대상 아님.
- 그 사이 PR #401 이 **2026-11-12T17:23:11Z 에 LowyShin 이 머지**했고(원격 브랜치 17:23:14Z 삭제),
  `main` = `35d7668` · diffstat 6파일(+191/-57) 이 원본과 정확히 일치(별도 세션의 산출물로 단정하지 않고
  커밋·diffstat 으로 대조 확인).
- **현재 열린 PR 0건**(`gh pr list --state open` → `[]`) → 병합충돌 대상 0건 · 조치 0건.
- nested 관리 대상 레포 0건(외부 벤더 서브모듈 `.gemini/extensions/bkit` 만 존재).

## [E] 열린 PR CI/검증 실패 — 대상 0건

- PR #401 의 체크 3종(PS1 게이트 · MJS 게이트 · GitGuardian) 모두 SUCCESS 였고, 로컬에서
  `scripts/gissue/run-repo-gates.ps1` 를 **직접 재실행**해 PR 이 보고한 수치와 일치를 확인했다.
- 이번 세션 변경분도 동일 게이트로 재검증 → **ps1 36건 / mjs 7건 / 링크스캔 1 / 실패 0건, exit 0**.
- ⇒ CI 실패 PR 0건.

## [F] Orphan `auto-unblock ` stash — 대상 0건

- `git stash list` → **빈 목록**(0건). 오판 stash 0건.

## [H] 최근 코멘트 논리 재검증 — 2시간 창 22건, **정정 0건**

`listRecentCommentIssues.ps1 -Csn 70424 -HoursBack 2 -Json` → 22건. **코멘트 내용을 신뢰하지 않고
직접 재조회**해 대조했다.

| 구분 | 건수 | 재검증 내용 | 결과 |
|---|---|---|---|
| `[BUDGET]` 스케줄러 시간예산 코멘트 | 21 | 코멘트가 주장한 `isn`/`status` 와 **실제 상태** 대조 | **21건 전건 일치** |
| 상태전이 코멘트 (isn 4768) | 1 | 아래 상세 | **일치** |

- 21건 BUDGET 코멘트: 코멘트 안의 `status=XX` == API 실조회 상태 — **불일치 0건**.
- 2시간 창 **22건 전수 `cSn` = 70424** 확인(`get-issue.sh <isn> 70424` 로 직접 조회) → 작업 CSN 일치.
- isn 4768 (DONE) 코멘트가 주장한 사실 3항목을 **직접 재확인**:
  - C1 "스케줄 태스크 정상 실행" → `GIIP_Gissue_Claude` State=**Running**, Action →
    `...\lowyworkenv\scripts\gissue\run-gissue-claude.ps1` ✓
  - C2 "고아 락 0건" → **당시(00:49:47 KST) 사실** ✓ (현재는 타 CSN(<csn>) 쪽에 죽은 PID 락 1건이
    남았으나 이는 **시간이 지난 스냅샷**이고 자기치유 대상이며, 다른 CSN 런타임 상태라 손대지 않는다)
  - C3 "무소식 회복" → `check-gissue-liveness.ps1` **exit 0 · Overall=OK · Healthy=true · Silent=[]** ✓
  - 상설 이슈 4870 통합主张 → 4870 실존 + READY ✓
- ⇒ **[H] 규칙대로 조용히 통과**: 정정 코멘트 0건 · 상태 전이 0건 · 이슈 쓰기 0건.

## 별도 act — 머지판정 게이트 fail-open 결함 수정 (신규 발견·수정)

### 증상

106차 착수 전 같은 세션의 DryRun 에서 **실제 예외**가 떴다(2026-11-13 02:26:46 KST).

```
You cannot call a method on a null-valued expression.
At ...\scripts\gissue\worktree-safety.ps1:1170 char:13
+         if (-not $merged.Branches.Contains($e.Branch)) {
+     FullyQualifiedErrorId : InvokeMethodOnNull
```

`scripts/gissue/worktree-safety.ps1` 의 머지판정 게이트는 **머지된 PR 목록에 있는 브랜치의 worktree 만
자동 삭제**하는 안전장치다. 그런데 위 예외는 그 게이트를 **통째로 무너뜨렸다.**

### 원인 3단(직접 실측으로 확정)

1. **반환값 오염** — `Get-GissueMergedBranchSet` 의 `& $Log "..."` 가 로그 콜백
   (`Write-CleanupLog` → `Write-Output` = **성공 스트림 출력**)을 통해 로그 문자열을 **반환값에 섞는다**.
   `$merged = Get-GissueMergedBranchSet ...` 대입은 함수의 성공 스트림을 통째로 받기 때문.
   실측: 반환값 count=2, 타입 `String,PSCustomObject`.
2. **멤버 열거의 평탄화** — PowerShell 은 컬렉션의 `.속성` 접근 시 그 컬렉션을 **펼쳐서** 준다.
   그래서 `$merged.Branches` 는 HashSet 이 아니라 **그 안의 분기명 원소들**이 되고, **그 집합이 비어
   있으면 `$null`** 이 된다. 실측: 빈 HashSet → `arr.Branches null = True`.
3. **게이트 붕괴(fail-open)** — `$null.Contains(...)` 는 **'if' 문장 하나만 버리고** 흐름이 다음 문장으로
   넘어간다 → 링크스캔 → idle 게이트 → 삭제 보고 → **`git worktree remove`**.
   즉 **머지 확인을 한 번도 하지 않은 채 삭제**까지 간다. 실측(원본 코드 재현):
   삭제 예정 로그에 *"머지 확인"* 이라고 찍히면서 `Removed=1`.

### 왜 위험한가

`gh pr list --state merged` 실패(레이트리밋 · 인증 만료 · 일시적 네트워크)는 **일상적인 실패**다.
그 순간 머지판정은 "약한 판정" 이 아니라 **"모든 worktree 를 삭제"** 으로 뒤집힌다.
파일 자신의 명세(*"giip 2463: 판정 불가일 때 삭제로 흘러가던 fail-open 을 fail-closed 로 뒤집었다"*)와
정면으로 어긋난다 — 다른 게이트(활동시각 판정 불가 · 정션 사전검증 실패)는 이미 fail-closed 였고
**머지판정만 fail-open 으로 남아 있었다**.

### 조치 (이 PR)

1. `Get-GissueMergedBranchSet` 의 모든 `& $Log` 에 `| Out-Null` → 반환값이 **정확히 1개 객체**가 된다.
2. 머지판정 게이트 **앞에 fail-closed 가드** — 판정 결과가 없으면 `MANUAL-REVIEW(머지판정 불가)` 로 닫고
   `continue` (**삭제 경로로 가지 않는다**).
3. `Ok=$false`(조회 실패)를 '미머지' 와 **사유를 달리** 기록한다(`MANUAL-REVIEW(머지판정 조회 실패)`).
4. 같은 계열 오염(`Remove-GissueDirectoryTreeSafely` 의 폴백 경로) 도 함께 정리.
5. 회귀 테스트 `scripts/gissue/tests/test-worktree-merge-gate-failclosed.ps1` 신규(18항목).

### 대조 검증 (고친 뒤에만 green 으로 끝내지 않는다)

| 대상 | 결과 |
|---|---|
| 수정 **전** 코드에 같은 테스트 | **PASS=10 / FAIL=8 · exit 1** — 그 중 B-1 이 `removed=...wt-candidate` 로 **삭제 예약 자체를 잡아냄** (fail-open 직접 증명) |
| 수정 **후** 코드 | **PASS=18 / FAIL=0 · exit 0** |
| 저장소 전체 게이트 (`run-repo-gates.ps1`) | **ps1 36건 / mjs 7건 / 링크스캔 1 / 실패 0건 · exit 0** (신규 테스트 포함 PASS) |
| 실제 DryRun(수정본) | `InvokeMethodOnNull` **재발 0건** |

## k-layer / tKB

- `KNOW-044` 신규 — "로그 콜백이 성공 스트림에 쓰면 '값을 반환하는 함수' 의 반환값이 오염된다"
  (`.agent/k_layer/notes/KNOW-044_log_callback_pollutes_the_return_value_of_a_value_returning_function.md`)
- `INDEX.md` 행 추가(1줄).
- tKB 등록: `tkb.js sync-klayer --csn 70424` → **kbSn 7044** (created 1 / 실패 0).
  재조회 대조: 저장 본문 3468자 = 로컬 파일 3468자 **바이트 동일**(LF 동일) ✓.

> **정정(2026-11-13 107차)** — 106차 기록을 고쳐 쓰지 않고 덧붙인다.
> ① **규칙 54(범용 에이전트 — 특정 고객정보 금지) 자가점검**: 이 레포 자신의 CSN(70424)은 예외지만
>    **타 CSN 번호는 금지**다 → 타 CSN 번호가 붙은 표기 1건을 `타 CSN(<csn>)` 로 일반화했다.
>    (규칙 54 예시 grep `\b7[0-9]{4}\b` 는 번호가 식별자 뒤에 **붙어 있는** 경우를 **놓친다** — 붙어 있는 형태까지
>    보려면 `([Cc][Ss][Nn][-_ ]?)[0-9]{4,6}` 로 봐야 한다.)
> ② **규칙 60(이슈 표기) 자가점검**: 본문에서 giip 이슈 번호를 단순 언급할 때는 샵 없이 `giip 2463` 형식이다
>    (`#2463` 을 쓰면 렌더러가 이 레포의 GitHub 이슈로 자동링크한다) → KNOW-044 · 본 기록의
>    `giip #2463` → `giip 2463` 로 교정. `PR #401` 은 GitHub PR 이므로 `PR #` 형식을 유지한다.
>    (`.ps1` 테스트 파일의 주석은 원본 `worktree-safety.ps1` 명세 문장을 **그대로 인용**한 것이므로 원문 유지.)
> ③ KNOW-044 본문 1자 변경에 맞춰 tKB 는 `sync-klayer`(디렉터리 전체 재기록 — 무관 노트 CRLF 불일치 위험) 대신
>    **단건 `upsert`** 로 갱신했다 → **kbSn 7044 갱신(created 1 → updated 1 · 중복 0)**.
>    재조회 대조: 저장 본문 = 로컬 파일 3467자 **+ 서버가 덧붙이는 끝 줄바꿈 1자**(나머지 바이트 동일 · LF 동일) ✓,
>    `giip #2463` 잔존 0건.
> ④ **관찰(이번 PR 에서 조치 안 함)** — 저장소 전체에 bare `#N` 형태의 giip 이슈 참조가 수백 건 남아 있다
>    (규칙 60 기준으로는 GitHub 자동링크 대상 · `docs/WHATS_NEW.md` 2026-11-11 절 등). **이번에 쓴 텍스트는
>    규칙 60 에 맞춰 샵 없이 썼다.** 수백 건 일괄 정리는 본 PR 과 무관한 대량 diff 가 되므로 별도 세션 대상.

## 워크트리 정비

- `maint-105-0115` — 브랜치가 **머지 완료**(PR #401) + **원격 브랜치 삭제** + `git diff origin/main` 빈 상태
  라 정리 대상. **회수 완료**.
- `maint-62-2331` — 정본 도구 판정 `MANUAL-REVIEW` 보류분(사람 확인 필요) → **미접촉 유지**.
- `maint-106-0235` — 이번 세션 전용(커밋·PR 후 회수 예정).
- 타 CSN 소관 원격 ref `bot/task-giip-4804/4805/4806` — 소유 축 확인 완료: 해당 3개 이슈의 `cSn` 은
  **이 저장소 CSN(70424) 이 아님**(타 CSN · 번호는 규칙 54 에 따라 기재하지 않음) → **미접촉** 유지.

## 결과 요약

- [0] 병합충돌 0건 · [E] CI 실패 0건 · [F] 오판 stash 0건 · [H] 22건 전건 사실 주장 일치(정정 0건).
- **별도 act 1건** — 머지판정 게이트 fail-open 결함 수정 + 회귀 테스트 18항목(수정 전 코드에서 8건 FAIL
  로 회귀를 증명) + 저장소 게이트 exit 0.
- k-layer `KNOW-044` 신규 · tKB `kbSn 7044` 등록·본문 대조 완료.
- 이슈 쓰기(코멘트·상태전이) **0건** — 성역(giipApi/giipApiSk2) 미접촉, main 직접 push 없음, PR 경유.
