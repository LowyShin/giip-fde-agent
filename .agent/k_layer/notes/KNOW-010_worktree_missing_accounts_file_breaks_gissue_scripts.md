# KNOW-010: 워크트리(2차 체크아웃)에는 계정 파일이 없어 gissue 스크립트가 죽는다 — 이슈 조회·큐 조회는 공유 체크아웃에서 실행

- 작업 CSN: 70424
- 관련 파일: `scripts/gissue/list-issues.js`(계정 파일 해석부) · `.gitignore`(`slack-bot/.secrets/*`) ·
  `slack-bot/.secrets/giip-accounts.json`(gitignore 대상, 공유 체크아웃에만 존재)
- 근거: 2026-10-25 CSN 70424 저장소 정비 47차 세션 실측 (work_history `20261025_192500_csn70424_repo-maintenance.md`)
- 상호링크: [KNOW-009](KNOW-009_cleanup_onlypath_separator_silent_zero.md)(정리 도구 인자 표기 함정 축),
  [KNOW-006](KNOW-006_repo_gates_not_wired_to_ci.md)(로컬 게이트 단일 진입점 축)

## 1. 현상

저장소 정비 세션은 규칙상 **전용 워크트리**(`D:\temp\worktrees\giip-fde-agent\maint-NN-HHMM`)에서 작업한다.
그런데 그 워크트리에서 이슈 목록 스크립트를 실행하면 계정 파일을 못 찾아 **stdout 으로만 실패하고 종료**한다.

```
$ cd D:/temp/worktrees/giip-fde-agent/maint-47-1925
$ node scripts/gissue/list-issues.js --csn 70424 --status PENDING,READY
❌ 계정 파일을 찾을 수 없습니다: D:\temp\worktrees\giip-fde-agent\maint-47-1925\slack-bot\.secrets\giip-accounts.json
```

같은 저장소·같은 커밋인데 **공유 체크아웃**(`C:\Users\lowys\Downloads\projects\giip-fde-agent`)에서는 정상 동작한다.

```
$ cd C:/Users/lowys/Downloads/projects/giip-fde-agent
$ node scripts/gissue/list-issues.js --csn 70424 --status PENDING,READY,REVIEW,IN_PROGRESS
isn=2855 status=PENDING ... (정상 출력)
```

## 2. 원인

- `scripts/gissue/list-issues.js:71` 은 계정 파일을 **스크립트 위치 기준**으로 해석한다.
  `path.join(SCRIPT_DIR, '..', '..', 'slack-bot', '.secrets', 'giip-accounts.json')`
  → 계정 파일은 **저장소 루트 기준**으로 결정된다.
- `.gitignore:19` 가 `slack-bot/.secrets/*` 를 무시하고(`.sample.json` 만 예외),
  `git check-ignore -v slack-bot/.secrets/giip-accounts.json` →
  `.gitignore:19:slack-bot/.secrets/*	slack-bot/.secrets/giip-accounts.json` 으로 **확인된다**.
- 따라서 `git worktree add` 로 만든 2차 체크아웃에는 계정 파일이 **존재하지 않는다**
  (git 이 추적하지 않으므로 체크아웃해도 복원되지 않는다).
- `get-issue.sh` 도 같은 계정 파일을 쓴다(스크립트 주석상 "SK 출처: get-issue.sh 와 동일").

## 3. 조치 (이번 세션이 지킨 것)

- **이슈 조회·큐 조회·주석 등록 같은 계정 파일 의존 작업은 공유 체크아웃 cwd 에서 실행한다.**
  워크트리는 **코드 커밋·PR** 용도로만 쓴다(커밋 대상 파일은 워크트리 안에 있고, 실행 cwd 만 공유 체크아웃).
- 계정 파일이 필요해 보여도 **워크트리에 복사·링크해 넣지 않는다** — 기밀 파일을 2차 체크아웃으로
  퍼뜨리는 것이고, 워크트리는 `git clean` 대상이 되기 때문이다.
- 이번 세션 실측: 워크트리에서 `list-issues.js` 실행 → 위 오류 → **공유 체크아웃**에서 동일 인자로 재실행 →
  정상 출력(7건). 워크트리에서 실행 가능한 **읽기 전용 게이트**(`scripts/gissue/run-repo-gates.ps1`)는
  계정 파일을 쓰지 않으므로 워크트리에서 문제없이 exit 0 으로 통과했다.

## 4. 재발 방지

- "워크트리에서 gissue 스크립트가 죽는다"는 증상을 보면 **버그로 단정하지 말고 계정 파일 존재부터 확인한다**
  (`ls <worktree>/slack-bot/.secrets/`). 워크트리에는 없는 것이 정상이다.
- 세션 기록(작업 기록·k-layer 노트)에는 **어느 cwd 에서 어떤 명령을 실행했는지**를 함께 적는다.
  "이슈 조회 0건" 같은 결과는 실행 cwd 와 함께 남겨야 다른 회차에서 오판하지 않는다.
- 계정 파일 경로를 워크트리 경로로 하드코딩하는 변경은 하지 않는다 — 계정 파일은
  **공유 체크아웃 한 곳**에만 두고, 스크립트는 기준(저장소 루트) 해석만 쓴다.

## 5. 결과 저장처 / 소비처

- 수정 파일(코드 변경 없음 — 정찰 결과만 기록):
  `.agent/k_layer/notes/KNOW-010_worktree_missing_accounts_file_breaks_gissue_scripts.md`(이 파일 — 신규) ·
  `.agent/k_layer/notes/INDEX.md`(색인 1행 추가)
- 작업 기록: `.agent/work_history/20261025_192500_csn70424_repo-maintenance.md`
- 소비처: 다음 회차의 저장소 정비 세션(계정 파일 의존 명령의 실행 cwd 선택) · `[H]` 재검증 단계

## 6. 관련 규칙

29(도구 사용·검증) · 42(실행 근거로만 완료 판정) · 47(자동 정리 안전) · 48(single source) ·
50(봇 PR 범위) · 55(정보 조회 순서·환경 사실) · 61(k-layer 은 커밋으로 성립)
