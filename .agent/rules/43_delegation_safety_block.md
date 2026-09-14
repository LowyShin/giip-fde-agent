# 43. 위임 안전 블록 (Delegation Safety Block)

> **HARD RULE** — 서브에이전트에게 커밋/push/PR 을 시키는 **모든** 위임 프롬프트에 아래 5개 문구를
> 그대로 넣는다. 하나라도 빠지면 실측된 사고가 재발한다.
> 근거 giip: #2390~#2397(worktree install 낭비) #2432 #2445 #2463(작업 중 worktree 삭제) #2442(훅 강제)
> #2476 #2487 #2497(정션 write-through 로 공유 node_modules 손상).

## 왜 "위임 프롬프트에 넣는다"가 규칙인가

서브에이전트는 위임 프롬프트에 적힌 것만 안다. 위임자가 알고 있는 안전 규칙은 **적지 않으면 전달되지
않는다.** 2026-09-14 사고들의 실제 형태는 "위임자는 규칙을 알고 있었는데 프롬프트에 안 적어서
서브에이전트가 위반한 것"이었다. 그래서 이 규칙의 대상은 서브에이전트가 아니라 **위임하는 쪽**이다.

## 복붙해서 쓰는 블록 (그대로 사용)

```
## 작업 안전 규칙 (필수 준수)
- **worktree 격리 필수**: 공유 체크아웃을 직접 수정하지 말고 자기 전용 워크트리에서 작업할 것.
  git worktree add "<워크트리 루트>/<레포>/<이슈별 고유이름>" -b <고유 브랜치명> <base>
  (origin 브랜치명은 공유자원이다 — 이전 시도가 실패했어도 같은 브랜치명을 재사용하지 말 것.
   경로는 반드시 슬래시로 쓸 것 — 백슬래시는 bash 에서 이스케이프로 먹혀 경로가 뭉개진다.)
- **worktree 안에서 pnpm install / npm install / yarn install 금지.** 의존성이 필요하면 이미 install 이
  끝난 체크아웃의 node_modules 를 정션으로 링크한다:
  cmd /c mklink /J "<worktree>\node_modules" "<이미 install 된 체크아웃>\node_modules"
  (Windows 기준. POSIX 환경이면 `ln -s` 로 대체한다. 관리자 권한은 필요 없다.)
- **링크한 뒤에도 worktree 안에서 pnpm 으로 의존성을 바꾸지 말 것.** 정션/심볼릭 링크는 write-through
  라서, worktree 에서 돌린 pnpm rebuild / prune / remove / update / dedupe / fetch / link / patch 가
  **공유 체크아웃의 node_modules 를 직접 고치거나 지운다.** 읽기/실행만 하는 pnpm exec / pnpm run /
  pnpm list 는 그대로 써도 된다. 의존성을 정말 바꿔야 하면 **메인 체크아웃에서** 실행한다.
- **`--no-verify` 금지**: 커밋 훅을 자체 판단으로 우회하지 말 것. 훅이 실패하면 원인을 고친다.
- **자기 worktree 정리(git worktree remove 등)는 시도하지 말 것.** 종료 후 경로만 보고한다.
```

## 각 문구의 근거

### 1) worktree 격리 + 브랜치명 재사용 금지
공유 체크아웃을 동시에 두 세션이 만지면 한쪽의 체크아웃이 다른 쪽의 작업 트리를 갈아엎는다.
origin 브랜치명은 공유자원이라, 실패한 이전 시도가 남긴 원격 브랜치와 충돌하면 새 시도가 조용히
남의 커밋 위에 올라탄다. 경로 구분자는 슬래시로 강제한다 — bash 에서 백슬래시는 이스케이프로
해석돼 경로가 뭉개진 채 엉뚱한 디렉터리에 worktree 가 생긴다.

### 2) worktree 안 install 금지 (giip #2390~#2397)
worktree 마다 `pnpm install` 을 다시 돌려 디스크와 시간이 소모됐고, 2026-09-08 에는 이 누적으로
시스템 드라이브가 0 바이트까지 고갈됐다. 이미 install 된 체크아웃의 `node_modules` 를 **정션으로
링크**하면 같은 결과를 0 바이트로 얻는다.

> 부수 주의: pnpm 의 `node_modules` 는 심볼릭 링크 구조다. `find -maxdepth 1` 류로 들여다보고
> "비어 있다"고 오진하지 말 것.

### 2-1) 링크한 뒤에도 worktree 안에서 pnpm 으로 의존성을 바꾸지 않는다 (giip #2476 #2487 #2497)

**링크했다고 안전해진 것이 아니다.** 정션(`mklink /J`)이나 심볼릭 링크는 바로가기가 아니라
파일시스템 레벨의 진짜 디렉터리 링크라, pnpm 이 그 너머의 **공유 체크아웃에 직접 쓴다**(write-through).
worktree 에서 실행해도 pnpm 이 만지는 것은 worktree 의 사본이 아니라 모두가 공유하는 본체다.

가장 위험한 것은 **조용히 망가진다는 점**이다. `pnpm rebuild` 는 경고 한 줄 없이 rc=0 으로 끝나면서
공유 `node_modules/.modules.yaml` 의 `virtualStoreDir` 를 worktree 경로로 덮어쓴다. 그 순간부터
pnpm **자신의** 안전장치(`ERR_PNPM_UNEXPECTED_VIRTUAL_STORE`)가 무력화되고, 다음에 누가
`pnpm remove` 나 `pnpm install` 을 돌리면 공유 `node_modules` 가 통째로 recreate 되면서 `.bin` shim 과
패키지가 날아간다.

이것이 giip #2476(스토어/가상스토어 손상)과 giip #2487(`.bin` shim 33개 → 3개)의 **공통 근본원인**이다.
두 번 다 사후에 `.bin` 이 비어서야 발견됐다.

2026-09-14 실측(giip #2497, pnpm 10.33.2 / Windows / 임시 레포+임시 정션으로 재현):

| 구분 | 명령 |
|---|---|
| 위험 (공유 node_modules 실제 변경/삭제 확인) | `install` `i` `ci` `add` `rebuild` `prune` `remove` `rm` `update` `up` `dedupe` `fetch` `link` `unlink` `patch` `import` `deploy` |
| 안전 (무변화 확인) | `--version` `exec` `run` `test` `list` `why` `outdated` `licenses list` `root` `bin` `dlx` |

> `dedupe` / `fetch` / `link` 가 공유 node_modules 전체 purge 를 "시도"만 하고 멈춘 것은 대화형 TTY 가
> 없어서다(`ERR_PNPM_ABORTED_REMOVE_MODULES_DIR_NO_TTY`). **`CI=true` 환경에서는 중단되지 않고
> 실제로 지운다.** 스케줄러/CI 컨텍스트에는 `CI` 가 흔히 있으므로 "no-TTY 라서 안전하다"에 기대면 안 된다.

정직하게 덧붙이면, 최초 가설이던 "`pnpm exec` / `pnpm run` 이 write-through 한다"는 **재현되지 않았다**
(의존성 일치 / package.json 드리프트 / `verify-deps-before-run=true` 세 조건 모두 무변화).
그래서 exec·run 은 금지 목록에 넣지 않았다 — 넣었다면 `pnpm exec tsc --noEmit` 같은 읽기 전용 작업이
막혔을 것이다.

> lowyworkenv 에는 이것을 기계적으로 막는 PreToolUse 훅
> (`.claude/hooks/check-worktree-install.sh`)과 드리프트 탐지 스크립트
> (`scripts/check-pnpm-store-drift.mjs`)가 있다. 상세 정본은 그쪽
> `.agent/rules/58_worktree_pnpm_write_through.md`.

### 3) `--no-verify` 금지
훅은 이 환경에서 **실제로 지켜진 유일한 강제 수단**이다(giip #2442 — 규칙을 만든 세션 본인이 자기
훅에 차단당해 규칙이 작동함을 실증). 서브에이전트가 "훅이 오탐인 것 같다"는 자체 판단으로
`--no-verify` 를 쓰면 그 강제가 통째로 무력화된다. 훅이 실제로 오탐이면 훅을 고치는 것이 작업이다.

### 4) 자기 worktree 정리 금지 (giip #2432 #2445 #2463)
서브에이전트가 끝났다고 판단한 시점 이후에도 위임자는 CI 확인·머지·코멘트·문서갱신을 한다.
자기 worktree 를 지우면 그 후속 작업의 기반이 사라진다. 정리는 위임자 또는 별도 정리 로직의
몫이며, 그 정리 로직 자체의 안전 요건은
[`47_auto_cleanup_safety_requirements.md`](47_auto_cleanup_safety_requirements.md) 에 있다.

## 문구를 훅으로 강제하려면 (권장, 이식 선택사항)

문구를 프롬프트에 넣는 것만으로는 "넣는 것을 잊는" 실패가 남는다. 원본 배포는 위임 도구 호출을
가로채는 **PreToolUse 훅**으로 이 4개 문구의 존재를 검사한다(giip #2442). 이식할 때는:

- 훅 스크립트와, 훅이 비교 기준으로 삼는 **문구 정본 파일의 경로**를 함께 복사한다.
- 훅의 판정 결과는 `ask` 가 아니라 `deny` 여야 실제로 차단된다 — 무인 모드에서 `ask` 는
  차단되지 않고 통과한다(실측).
- 훅을 넣었으면 [`42_completion_by_execution_evidence.md`](42_completion_by_execution_evidence.md)
  대로 "차단돼야 할 위임문"을 실제로 넣어 차단 출력을 확보한 뒤에만 완료로 본다.

## 관련 규칙

- [`35_commit_push_per_task.md`](35_commit_push_per_task.md) — 작업마다 커밋·push(위임된 쪽도 동일).
- [`41_issue_session_safety_index.md`](41_issue_session_safety_index.md) — 이 규칙군 색인.
