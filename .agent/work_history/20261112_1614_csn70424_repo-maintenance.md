# CSN 70424 Repo Maintenance — 2026-11-12 16:14 (저장소 정비 100차)

## 세션 정체

- 작업 CSN: **70424** · 프로젝트: `giip-fde-agent` (`C:\Users\lowys\Downloads\projects\giip-fde-agent`)
- **100차 저장소 정비 세션** — 2026-11-12 16:14 KST 시작. 이슈별 세션이 아니라 CSN 저장소 전체
  스코프의 [0]/[E]/[F]/[H] 4단계 정비(giip 1472 계열).
- 직전 회차 = **99차**(2026-11-04 19:15 KST · PR #380 머지 `6bbe5a0`). 그 뒤 2026-11-06 17:46 에
  규칙 신설 기록(rule 57) 1건이 있고, **2026-11-04 21:00:27 → 2026-11-12 16:14:08 (7일 19시간 13분 41초)**
  동안 이 CSN 의 스케줄러가 무소식이었으나 이번 회차에 복귀했다
  (`scripts/gissue/logs/gissue_csn70424.log` — 이전 마지막 줄 `2026-11-04 21:00:27`, 이번 `START 2026-11-12 16:14:08`).
- 작업 워크트리: `D:\temp\worktrees\giip-fde-agent\maint-100-1640` (**신규 생성** · 기준 `origin/main` = `ca9c35c`)
- 작업 브랜치: `chore/csn70424-maint100-20261112-1640`
- 공유 체크아웃은 **커밋·스테이징 없이** 읽기 전용으로만 사용(게이트 재실행 제외 — 실행만, 산출물 없음).
- 적용 role: `.agent/roles/orchestrator.md` · 적용 rule: `.agent/rules/36_no_md_in_nongit.md`,
  `.agent/rules/47_no_premature_completion.md`, `.agent/rules/48_single_safety_predicate.md`,
  `.agent/rules/52_conduct_admit_fault_and_ai_rights.md`,
  `.agent/rules/55_destructive_cleanup_incident_gate.md`,
  `.agent/rules/60_giip_issue_link_format.md`, `.agent/rules/61_klayer_registration_must_be_committed.md`,
  `.agent/rules/72_klayer_in_project_tkb_via_sk.md`, `.agent/rules/73_fix_wrong_docs_on_discovery.md`,
  `.agent/rules/74_no_install_first_find_zero_install_path.md`, `.agent/rules/75_agent_repo_platform_boundary.md`,
  `.agent/rules/76_keep_working_csn.md`, `.agent/rules/77_encoding_corruption_fix_on_discovery.md`,
  `.agent/rules/78_giipagentlinux_must_be_csn_agnostic.md`, `.agent/rules/79_qna_read_repo_readme_first.md`,
  `.agent/rules/80_lookup_order_privatekb_spec_code.md`,
  `.agent/rules/81_fde_agent_generic_no_customer_info.md`, `.agent/rules/82_session_start_reads_and_directives_in_files.md`,
  `.agent/rules/85_recoverable_work_proceed_unrecoverable_ask.md`

### 저장소 락 — 획득 시도 · **미획득**(해제 불필요)

- 실행 프롬프트가 "[0]/[F] 의 첫 git 명령 **전에** 락을 잡고, 처리 대상 없음 확정 시 동일 Holder 로
  `-Release` 하라" 고 명시했으므로 지시대로
  `scripts/repo-lock.ps1 -Acquire -Holder "gissue-csn70424:maintenance" -KeepAlive -WaitMinutes 15` 를 시도했다.
- 결과: 락 보유자가 **`gissue-csn33:maintenance`** (살아 있는 PID)로 이미 잡혀 있어 **획득에 실패**했다.
  락 파일(`scripts/../.agent/locks/lowyworkenv-repo.lock`)은 그대로이고, **내 락은 애초에 획득되지 않았으므로
  `-Release` 하지 않는다**(해제하면 남의 락을 풀어 버린다).
- 본 세션은 lowyworkenv 저장소 파일을 **하나도 쓰지 않았다**(읽기만). 락이 필요한 이유(동시 수정 방지)가
  실제로 발현하지 않았던 것은 락 미획득과 무관하다 — 그래도 지시대로 시도·기록한다.

## [0] PR merge conflict — 대상 0건

- `gh pr list --repo LowyShin/giip-fde-agent --state open` → **0건**(세션 시작 시점 = 0건 · 현재 = 0건).
  직전 PR #390 은 2026-11-12 15:03 KST 에 이미 머지되었다. → `mergeable=CONFLICTING` 판정 대상 없음.
- nested git 레포 **없음** — 관리 대상 0건.
- `git fetch origin --prune` → stale 추적 ref 0건.
- `git ls-remote --heads origin` → `main` + **타 CSN 이슈용 3건**(아래 "인계" 참고).

## [E] 열린 PR CI/검증 실패 — 대상 0건 · main CI 1건 이력 확인

- 열린 PR 0건 → CI 실패 PR 0건.
- 보완 검증 ① **main CI**: `gh run list --limit 12` → 현 main 머지(`ca9c35c`) push run
  **43176590062 = success** · PR run **43176299575 = success** · GitGuardian = SUCCESS.
- 이력에서 **main push run 42974397469(2026-11-11 06:43:12Z, sha `22bc20b`) 가 PS1·MJS 게이트 실패**한 적이
  있다. 실패 원인은 `test-pr-lookup-org.mjs` (PR 탐색 org 회귀 테스트) 로, 바로 다음 커밋 `ca492c1`
  (PR #388 — "회귀 테스트를 Windows CI 안전하게") 머지 후 push run 42974407970 이 **success** 로 회복됐다.
  ⇒ **현행 main 은 green**, 조치 불필요(재발 여부는 아래 인계 참조).
- 보완 검증 ② **로컬 게이트**: `scripts/gissue/run-repo-gates.ps1` 를 **공유 체크아웃(main = `origin/main`)** 에서
  재실행 → exit 0 (아래 "검증" 절).

## [F] Orphan auto-unblock stash — 대상 0건

- `git stash list` → **0건**(저장소 공용 `.git` · 워크트리 간 공유) → `auto-unblock ` 이관 대상 없음.
- `git worktree list`(세션 시작 시점): 공유 체크아웃 + `entrypoint-recovery`(본 세션이 만든 회수 워크트리)
  + `maint-62-2331`(보존) → 종료 시점에는 **`maint-62-2331` 1건만 남고 `entrypoint-recovery` 는 회수 완료**.
  - `maint-62-2331`(branch `chore/csn70424-maint64-20261102-0250`, tip `b10cf06`) — 미커밋 변경 보유.
    정본 도구 판정 **MANUAL-REVIEW**(미머지) → **미접촉 보존**(repo `KNOW-023` · rule 48).

## [H] 최근 코멘트 논리 재검증 — **정정 0건 · 전이 0건**

- `listRecentCommentIssues.ps1 -Csn 70424 -HoursBack 2 -Json` → **2시간 창 0건**(JSON 결과 없음 = 해당 없음).
  (세션 종료 시점 재측정 → **5건**: 4870 + 4879·4888·4890·4900 — 5건 모두 **이번 세션이 직접 쓴 코멘트**이므로
  "자기 코멘트 제외" 규칙에 따라 재검증 대상 0건.)
- `-HoursBack 24` → **24시간 창 4건**: 4879 · 4888 · 4890 · 4900 — 4건 모두 **자동 생성된
  `[OPS] gissue 처리 무소식 감지` 이슈**이고, 각 이슈의 마지막 활동 시각은 `regdate` 와 동일
  (= **코멘트 0건**). → **검증 대상 코멘트가 없어 [H] 정정 대상 0건 · 상태 전이 0건.**
- 아래 "별도 act" 에서 확인한 사실(예: giip 4900 본문의 `CSN 70424: SILENT — 처리 로그 183.61h`)은
  **직접 재계산해 참**임을 확인했다(등록 시각 2026-11-12 03:37:01 UTC − 로그 최종 갱신 2026-11-04 12:00:27 UTC
  = 183.61h). 오류主張 없음 → 정정 코멘트 없음.

## 별도 act 1 — PR #391: 죽은 세션 산출물(원격에 남은 PR 없는 브랜치) 회수 + 규칙 81 정정

- **대상**: 원격에 남아 있던 `fix/entrypoint-dirty-repo-no-crashloop`.
  `gh pr list --state all --head fix/entrypoint-dirty-repo-no-crashloop` → **0건**, `git ls-remote --heads origin` 에는
  해당 ref 만 살아 있었음 → 이전 세션이 커밋·push 까지만 하고 PR 생성 전에 끝난 상태(repo `KNOW-015`).
- **회수 절차**: 전용 워크트리 `D:/temp/worktrees/giip-fde-agent/entrypoint-recovery` 에 체크아웃 →
  로컬 검증 → 추가 커밋 → push → PR 생성.
- **기술 내용(이미 있던 커밋 `92cec98`)**: ① `safe_update_repo` — `set -euo pipefail` 아래에서 보호 없이
  실행되던 `git fetch/checkout/merge --ff-only` 를 `if` 로 감싸 갱신 실패가 entrypoint 를 죽이지 않게 함
  (실패 시 `[entrypoint] WARN:` 블록 + 0 반환, `reset/clean/stash/checkout -f` 없음) ② `agent_cron_line` —
  `/etc/cron.d/giip-agent` 매분 cron 줄에 `flock -n /dev/shm/giipAgent3.lock` 단일 인스턴스 가드
  (flock 부재 시 기존 줄 유지, 잠금 파일은 tmpfs `/dev/shm`).
- **rule 81 정정(본 PR 의 1커밋 `7556fc7`)**: 사양서 `docs/60-operations/docker-entrypoint-spec.md` 에 들어간
  **고객 환경 식별자 4곳**을 일반 명사로 바꿈(컨테이너 식별자 2 · 환경 이름 1 · 호스트 측 재적용 방식 서술 1).
  기술 내용(증상·원인·대응·검증·적용 시점)은 그대로 유지했고, 커밋 메시지·PR 본문에도 식별자를 넣지 않았다.
- **검증(로컬, push 전)**: `bash docker/tests/test-agent-cron-line.sh` **ALL PASSED**(exit 0) ·
  `bash docker/tests/test-safe-update-repo.sh` **ALL PASSED**(exit 0) ·
  `powershell -File scripts/gissue/run-repo-gates.ps1` **exit 0**(ps1 33건 / mjs 5건 / 링크스캔 md 596 ·
  링크 1216 · 상대 825 · 스캐폴딩 21 · **실제 결함 0건**).
- **CI**: PR run 43176299575 — PS1 gates **success** · MJS gates **success** · GitGuardian **success**.
- **머지**: 2026-11-12 16:37 KST squash merge → `ca9c35c`. main push run 43176590062 **success**.
  원격 브랜치 삭제 완료. 공유 체크아웃 `git merge --ff-only origin/main` → `git rev-list --left-right --count
  origin/main...main` = `0 0`.
- **워크트리 회수**: `cleanup-worktrees.ps1 -RepoPath <repo> -OnlyPath "D:\temp\worktrees\giip-fde-agent\entrypoint-recovery"
  -MinIdleMinutes 0` — **DryRun 먼저**(제거 대상 1건) → 실제 실행 **Removed 1건**. 원격 브랜치도 정리됨.

## 별도 act 2 — 무소식 감지 중복 이슈 4건 정리(CSN 70424 이슈 대행)

- **배경**: 2026-11-11 05:42 UTC 에 Lowy 님이 giip 4870(https://giip.littleworld.net/ko/admin/giip-issues/4870)을
  **무소식 감지의 상설 이슈**로 지정("이후 감지는 새 이슈를 만들지 않고 이 이슈에 코멘트로 누적하고,
  처리가 회복되면 회복 코멘트와 함께 DONE으로 닫습니다"). 그런데 그 뒤에도 **동일 감지 보고가 4건 더 등록**됐다
  (giip 4879 / 4888 / 4890 / 4900 · 각각 6시간 간격 = `check-gissue-liveness.ps1` 의 `-CooldownHours 6` 기본값).
- **원인(실측)**: 중복 방지 장치가 **정본에만 있고 이 PC 가 실제로 실행하는 이식본에는 없다**.
  | | 정본 `giip-fde-agent` | 이식본 `lowyworkenv` (이 PC 의 :07 스케줄러가 실행) |
  |---|---|---|
  | `scripts/gissue/lib/liveness-ops-issue.js` | 있음(find/comment/close/register) | **없음** |
  | `check-gissue-liveness.ps1` 의 "에피소드" 관련 코드 | **23건** | **0건** |
  | 마지막 커밋 | `22bc20b` (PR #389, 2026-11-11) | `0e0e7266` (PR #1062, 에피소드 수정 이전) |
  ⇒ 정본 수정이 이식본에 이식되지 않은 상태(repo `KNOW-036` — 이식 여부 판정은 커밋이 아니라 **파일 단위 대조**).
  **이식본은 타 CSN(lowyworkenv) 소관이라 이번 세션은 수정하지 않고 사실만 기록**했다.
- **조치**: 중복 4건에 "상설 이슈 = giip 4870" 안내 코멘트를 남기고 **중복 정리 차원에서 DONE 으로 종료**
  (`updateIssueStatus.ps1 -ExpectedCsn 70424 -Actor gissue-agent -Reason …` → 상태전이 코멘트 자동 동반).
  감지 보고 원문은 각 이슈 본문과 코멘트에 그대로 남아 정보 유실 없음.
- **상설 이슈(4870)는 상태 전이하지 않았다** — 회복 판정은 무소식 대상 12개 CSN 전체 기준이므로,
  지시대로 "회복 코멘트와 함께 DONE" 시점을 지켜야 한다. 2026-11-12 16:14 에 대상 12개 CSN 로그가 모두
  다시 갱신되어 신선도 기준(3h)상 현재는 무소식이 아니다.
- **재발 가능성**: 이식본이 갱신되기 전까지 6시간마다 같은 중복이再生된다(직전 등록 2026-11-12 12:37 KST →
  다음 등록 가능 시각 2026-11-12 18:37 KST 이후).

## 인계 / 남은 것

- **보존(미접촉) 워크트리 1건** — `maint-62-2331`(미커밋 변경 보유, 정본 도구 MANUAL-REVIEW).
  정비 세션이 손대지 않는다(repo `KNOW-023`).
- **타 CSN 이슈용 원격 브랜치 3건** — `bot/task-giip-4804` / `bot/task-giip-4805` / `bot/task-giip-4806`.
  커밋 메시지가 가리키는 이슈 4804·4805·4806 은 `i.csn = 70418` 로 실측 확인됐고(READY 3건),
  작성자도 다른 운영자다 → **rule 76(남의 CSN 에 쓰지 않기)** 로 **미접촉**, 사실만 기록.
  PR 없는 원격 브랜치로 남은 것은 구조적으로 회수 대상이나(=`KNOW-015`), 소유 CSN 이 달라 이번 회차는 손대지 않는다.
- **이식본 드리프트(본 저장소 밖)** — lowyworkenv 쪽 `scripts/gissue/check-gissue-liveness.ps1` 이 정본보다 뒤처진
  상태(에피소드 관리 없음). 정본 수정은 이미 머지되어 있고(PR #389), **이식만 남았다**. 처리 주체는
  lowyworkenv(타 CSN) 정비 세션이며, 대조 절차는 k-layer `KNOW-036` 에 있다.

## 검증 (공유 체크아웃 main = `origin/main` 재실행)

- `powershell -File scripts/gissue/run-repo-gates.ps1` → **exit 0** (ps1 **35**건 / mjs **7**건 / 마크다운 링크 스캔
  md **598** · 링크 **1219** · 상대 **828** · 스캐폴딩 21 · **실제 결함 0건**). "워크트리 green ≠ main green" 배제.
  (PR #391 머지 전 워크트리 측정치 ps1 33 / mjs 5 / md 596 과의 차이는 main 에 먼저 머지된 PR #388·#389·#390 이
  추가한 테스트·문서 때문이다 — 기준 브랜치가 다르면 개수가 달라진다.)

## self-check (rule 54/81 — PUBLIC 저장소 식별자)

- 이번 커밋의 **추가 줄** 전수 대조: CSN 식별자(`CSN <숫자>` · `cSn=<숫자>`) 패턴이 함께 등장하는 줄을 뽑아
  숫자를 하나씩 확인 → **자기 CSN(70424) 과 이식본 소관 CSN(33) 이외 0건**(타 고객 CSN 번호 미기재).
- bare `#<숫자>` 형태의 GitHub 이슈 자동링크 **0건**(giip 이슈 번호는 `giip NNNN` · PR 은 `PR #NNN` 로 표기).
- 파일 경로에 `csn70424` 가 들어가지만 이는 **99차까지 이어진 저장소 자체 기록 관례**(파일명 규칙)를 따른 것이고,
  본문에는 타 고객의 CSN 번호·환경 이름·업무 내용을 넣지 않았다.
