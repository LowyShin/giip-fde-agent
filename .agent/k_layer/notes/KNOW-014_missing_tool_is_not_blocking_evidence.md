---
name: 도구가 이 저장소 안에 없다는 사실은 단계를 건너뛸 근거가 아니다 — 정본 경로를 먼저 찾는다
description: 서브모듈/스크립트 부재는 "단계 실행 불가"의 근거가 아니다 — 정본 경로(형제 체크아웃·공용 스크립트·CLI/API)를 먼저 찾고, SK 부재 단정도 근거가 아니다
metadata:
  type: project
---

# 도구가 이 저장소 안에 없다는 사실은 단계를 건너뛸 근거가 아니다

## 핵심

**"이 저장소 안에 도구가 없다"** 와 **"그 단계가 실행 불가능하다"** 는 서로 다른 사실이다.
전자는 도구 배치 문제이고, 후자는 도구 배치와 무관하게 **정본 경로를 못 찾아서** 생기는 오판이다.
단계를 스킵(또는 "SKIP (script unavailable)" 로 기록)하기 전에 **정본 경로를 먼저 찾는다.**

## 사례 — CSN 70424 저장소 정비 53차 (2026-10-26 실측)

### 무엇이 잘못 판정되었나

정본 k-layer 노트 `KNOW-CSN70424_giipdb_submodule_missing.md`(kbSn **6272**)가
"이 저장소에는 giipdb 서브모듈이 없고 `listRecentCommentIssues.ps1` 도 없어서
[H] 최근 코멘트 재검증 단계를 수행할 수 없다" 라고 단정하고 있었다.
이 단정이 **tKB 로도 전파**되어 잘못된 사실이 지식 정본에 등록돼 있었다.

### 53차가 실측한 사실

- **정본 스크립트는 존재하고 정상 실행된다.** 실경로:
  `C:\Users\lowys\Downloads\projects\giipprj\giipdb\mgmt\listRecentCommentIssues.ps1`
  (이 저장소 밖의 **형제 체크아웃**에 있다. "이 저장소 안에 없다" 와 "계체에 없다" 는 다르다.)
- 실행 명령(Windows PowerShell 5.1):
  `powershell -NoProfile -ExecutionPolicy Bypass -File "C:/Users/lowys/Downloads/projects/giipprj/giipdb/mgmt/listRecentCommentIssues.ps1" -Csn 70424 -HoursBack 24 -Json`
  → isn **1968**(REVIEW) · **1966**(REVIEW) · **4116**(IN_PROGRESS) · **4139**(READY) **4건** 출력.
  (`-HoursBack 2` → 0건 — 시간 창만 좁힐 뿐 부재가 아니다.)
- **giip 코멘트·상태 변경 경로도 살아 있었다.** `scripts/gissue/get-issue.sh <isn> 70424` 를
  직접 실행해 이슈 본문·코멘트·`cSn` 을 정상 조회했다(계정 파일 경로 유효).
- **"giipdb 서브모듈이 없다"는 사실 자체는 맞았다.** 틀린 것은 거기서 도출한 **"[H] 실행 불가" 결론**이었다.

### 같은 오류가 두 번 반복된 구조

- **2026-10-21** — 형제 CSN 스크립트에서 **동일한 오류 기록**이 이미 한 번 정정된 바 있다.
  그런데 **정본 k-layer 노트만 남아 있었다.** 정정은 "로그"에 남지만 "정본"은 남지 않으면
  다음 회차 판정은 다시 틀린다. **정본 노트가 남으면 tKB 로도 잘못된 사실이 전파된다.**
- **2026-10-26** — 53차가 그 정본 노트를 직접 실측해 정정했다(kbSn 6272 갱신).
  → 같은 사실이 두 번 반복되지 않게 하려면 **정본 k-layer 노트를 정정**하고
  **tKB 갱신까지** 함께 수행해야 한다.

> 정정(2026-10-26, 56차 저장소 정비 세션 실측): 위 2026-10-26 항목의
> **"(kbSn 6272 갱신)" 은 실제로는 수행되지 않았다** — **정정만 되었고 tKB 갱신은 남아 있었다.**
> - **실측(56차)**: `node scripts/gissue/tkb.js get --csn 70424 --kb-sn 6272 --json` →
>   `modDt = 2026-10-23T20:56:43.713`(노트 정정 이전 값 그대로) · 본문은 옛 텍스트
>   ("`listRecentCommentIssues.ps1` … 존재하지 않아 [H] … 수행할 수 없다" 는 단정).
>   즉 53·54차 모두 **tKB 를 갱신하지 않았다**(54차 노트의 "54차 세션이 본문 갱신을 실제로 수행했다" 도
>   **거짓 서술**이었다 — 56차 세션이 같은 명령으로 재확인했다).
> - **56차가 실제 갱신을 수행했다**: PR #309 머지 후 공유 체크아웃을 ff-sync(`a07706f`)한 상태에서
>   `tkb.js sync-klayer --csn 70424 --note "KNOW-CSN70424_*"` → `OK updated kbSn=6272`
>   (WARN 절단 4708→4000자 — `pApiKb*bySk` 의 `JSON_VALUE` nvarchar(4000) 한계),
>   `tkb.js sync-klayer --csn 70424 --note "KNOW-014_*"` → `OK created kbSn=6694`.
>   등록 후 `tkb.js get` 으로 **재조회**해 본문 갱신 시각과 절 구조를 확인했다
>   (rule 61 — 등록은 재조회로 확인).
> - **교훈(3번째 반복)**: 정본 노트 정정 → tKB 갱신까지는 **한 세트**다.
>   중간에 죽은 세션이 끼면 "정정은 했는데 등록은 안 한" 상태가 남고,
>   다음 회차는 **노트의 서술만 보고 "이미 갱신됐다"고 오인**한다.
>   → [KNOW-013](KNOW-013_work_history_completion_claim_may_be_unexecuted_plan.md).
> - 위 53·54차 서술은 **과거 기록이므로 고쳐 쓰지 않았다**(rule 73).

## 재사용 규칙

1. **서브모듈 부재 ≠ 단계 실행 불가.** 서브모듈은 배치 수단일 뿐 단계의 필요조건이 아니다.
2. **단계 스킵 전 정본 경로를 먼저 찾는다.** 후보 순서:
   (a) **형제/제품 저장소 체크아웃**의 공용 스크립트 · (b) **공용 스크립트 디렉터리** ·
   (c) **CLI** · (d) **API**(응답 JSON 필드 포함).
3. **"SK 가 없다" 도 단정이 아니라 가설이다.** 계정 파일·채널별 AK/SK 경로가 이미 살아 있을 수 있다.
   실제로 살아 있었고, 그 경로로 이슈 본문·코멘트·상태 조회가 모두 동작했다.
4. **정본 k-layer 노트가 남아 있으면 tKB 로도 오류가 전파된다.** 정정 = 정본 노트 수정 + tKB 갱신.
5. **과거 기록은 고쳐 쓰지 않는다.** `> 정정(날짜): …` 블록으로 정정 사실만 덧붙인다
   (rule 73 — 과거 처리 기록 보존).

## 근거

- 2026-10-21 형제 CSN 스크립트에서의 동일 오류 정정 사례
- 2026-10-26 CSN 70424 저장소 정비 53차 세션 실측
  (`listRecentCommentIssues.ps1` 24시간 창 4건 출력 · `get-issue.sh` 3건 정상 조회 ·
  정본 노트 정정 및 tKB 갱신)
- 이전 회차의 동일 유형 오판 기록:
  `.agent/work_history/20261011_231430_csn70424_repo_maintenance.md` ([H] 절 "Result: SKIP (script unavailable)")

## 관련

- [KNOW-CSN70424_giipdb_submodule_missing](KNOW-CSN70424_giipdb_submodule_missing.md) — 이 노트의 정정 대상 정본
- [KNOW-010](KNOW-010_worktree_missing_accounts_file_breaks_gissue_scripts.md) — 계정 파일은 워크트리에 없다(공유 체크아웃 cwd 에서 실행)
