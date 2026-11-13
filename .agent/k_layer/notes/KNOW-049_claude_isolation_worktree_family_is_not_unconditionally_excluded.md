# KNOW-049 — 격리 worktree 계열을 "무조건 제외"하면 자동 정리 경로에서 영영 사라지지 않는다

> 근거: giip 5175 (2026-11-14) · 발행: 2026-11-14 · 상태: 검증됨(직접 실측 + 회귀 테스트 고정)
>
> 관련 파일: 판정 엔진 `scripts/gissue/worktree-safety.ps1` / 진입점 `scripts/gissue/cleanup-worktrees.ps1`
> · 규칙 `.agent/rules/47_auto_cleanup_safety_requirements.md` · 역할 `.agent/roles/orchestrator.md`
> · 회귀 테스트 `scripts/gissue/tests/test-worktree-claude-session-guard.ps1`

## 요지

Claude Code 의 `isolation: worktree` 가 만드는 `<repo>/.claude/worktrees/agent-*` 계열은
정본 정리 엔진에서 **무조건 skip** 됐다("Claude Code 자체 세션 격리 메커니즘이라 완전히 별개 —
항상 제외"). 그 결과 **어떤 자동 정리 경로에도 잡히지 않아** 레포당 수십 개가 무한 누적됐다.

"정리 도구가 못 지우는 것"과 "아무도 안 지우는 것"은 다르다. 안전 요건을 태운 뒤에야 지우는
것이 정리의 정식 경로이고, 그 경로에 **아예 넣지 않은 것**은 자동 정리의 사각지대다.

## 근거 — 실측 (2026-11-13, lowyworkenv)

| 관측 | 값 |
|---|---|
| `.claude/worktrees/agent-*` 개수 | **27건** |
| `D:\temp\worktrees` 하위 잔여 | **60여 건** |
| 머지된 PR 이 붙은 브랜치 | **8건 / 27건** (PR 게이트만 쓰면 나머지 19건은 영영 남는다) |
| `settings.local.json` 하나 때문에 "미커밋 변경"으로 잡힌 것 | **26건 / 27건** (실 산출물 아님) |

두 번째 표가 중요한 이유 — **격리 산출물을 산출물로 취급하면 이 계열은 정리 대상 0건**이다.
반대로 "무조건 제외"를 그대로 두면 **모든 판정이 0건**이다. 양쪽 다 원 문제가 남는다.

## 판정 설계 — 3가지 추가 (이 계열에만)

1. **"고유 커밋 없음" 판정을 PR 게이트와 병행** — `git merge-base --is-ancestor <HEAD> origin/main`.
   참이면 "이 worktree 에 고유한 커밋이 없다"(= 내용 유실 없음) → 정리 대상 후보.
   **판정 불가(HEAD 를 못 읽음 / `origin/main` ref 없음)·미반영은 모두 삭제 금지(fail-closed)**.
   squash 머지 브랜치는 조상이 아니므로 PR 게이트와 서로를 보완한다(둘 중 하나만으로는 부족).
2. **격리 메커니즘 산출물의 dirty 제외** — `.claude/settings.local.json` **한 개만** 제외하고,
   제외 사실은 로그에 남긴다(숨기지 않는다). 그 밖의 미커밋 변경은 자동 삭제 금지.
   ⚠ 미추적 **디렉터리**는 `git status --porcelain` 기본 출력에서 `?? .claude/` 로 접히므로
   경로 매칭이 통하지 않는다 → **`-uall`** 로 개별 파일로 펼쳐야 한다.
3. **idle 임계 하한 240분** — 일반 worktree 보다 보수적으로 두어, 실행 중 에이전트를 보호한다.

## 규칙 (다음 세션이 지킬 것)

1. "메커니즘이 만든 것"이 **이유로** 정리 대상에서 제외하지 않는다 — 안전 요건을 태운 뒤 판정한다.
   제외는 "도구가 못 지우는 것"의 처리이지 "판정 대상을 늘리는 것"의 처리가 아니다.
2. 삭제 게이트를 하나만 쓰지 않는다 — PR 머지 게이트와 조상 판정 게이트를 **병행**하고,
   어느 쪽이든 확신이 없으면 fail-closed 한다.
3. "미커밋 변경"이 메커니즘 산출물뿐인지, 사람이 만든 산출물인지 구분해서 본다.
   구분 없이 전부 dirty 취급하면 정리 도구는 아무것도 지우지 못하고, 구분 없이 전부 무시하면
   사람의 산출물을 지운다.
4. 미추적 디렉터리가 있는 worktree 를 판정할 때는 `git status --porcelain -uall` 을 쓴다.
5. 서브에이전트가 만든 worktree 의 정리는 **위임자(오케스트레이터)** 가 한다
   (`.agent/roles/orchestrator.md` §"서브에이전트 worktree 정리 책임"). 서브에이전트는 자기
   worktree 를 지우지 않고 경로만 보고한다.
