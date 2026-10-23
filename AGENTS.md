# Codex Rules

> **작업 시작 전 반드시 [`AI_MUST_READ.md`](AI_MUST_READ.md) 를 먼저 읽을 것** (PUBLIC 범용 레포: 고객정보 금지 / 정보 조회 순서 tPrivateKB → 사양서 → 코드).

You are an intelligent agentic AI working on this project.

## PROJECT REPOSITORY — MANDATORY
1. **CANONICAL REPOSITORY**: This project's source of truth is `LowyShin/giip-fde-agent` on GitHub, default branch `main`.
2. **GITHUB FIRST**: For repository-backed tasks, resolve and inspect `LowyShin/giip-fde-agent` through the connected GitHub integration/plugin before relying on memory or assumptions.
3. **NO REPOSITORY DRIFT**: Do not substitute another GIIP repository, backup, fork, or similarly named repository unless the user explicitly names it for the task.
4. **PROJECT CONTEXT**: Read and follow `.agent/rules/00_project_repository_scope.md`, activate `.agent/roles/project-repository-guardian.md` when repository scope matters, and use `.agent/skills/giip-fde-agent-project/SKILL.md` to initialize project context for substantial work.

## CORE INSTRUCTIONS
1. **FOLLOW RULES**: You MUST read and follow the global agent rules defined in `GEMINI.md` and `.agent/rules/`.
2. **USE SKILLS**: For complex coding tasks, you MUST use the skills located in `.agent/skills/`.
   - Use `giip-fde-agent-project` first for substantial work in this project.
   - Use `subagent-driven-development` for multi-step features.
   - Use `writing-plans` to create `implementation_plan.md` before coding.
   - Use `test-driven-development` (TDD) for reliability.
   - Use `jikji` for local file/folder/document discovery — **always use `jikji find` before `grep`, `ls`, `find`, or `rg`**.
3. **SCRIPTS**: Prefer using scripts in `.agent/scripts/` over raw commands.

## GIIP PRODUCT SCOPE — HARD RULE (revised 2026-10-15)

Changes to the giip product repositories (`giipv3`, `giipdb`, `giipfaw`, `giipprj`,
`giipAgentWin`, `giipAgentLinux`, `giipAgentAdmLinux`) may be made **from any CSN**, and are
always submitted through a **pull request** (never a direct push to `main`).

> Revised 2026-10-15 (direct user instruction). The former "under CSN 47 only" rule — and its
> duty to re-register the request under CSN 47 and close the original issue — **no longer
> applies**. The 2026-09-18 background is kept as history only.

Still in force:
1. **Stay in the working CSN** — never write issues, comments, CQE, KVS or API calls under a
   different CSN.
2. **PR, not a direct push** to `main`.
3. **CSN-agnostic changes** — a product change must work for every CSN. CSN-specific branches
   are forbidden in shared code paths; CSN-specific scripts belong in a CQE task.
4. The `giipdb` SQL rules and the agent-platform boundary rule still apply.

`giip-fde-agent` itself is **not** a giip product repository; normal work on this repo
continues under CSN 70424.

→ `.agent/rules/51_giip_product_changes_csn47_only.md`

## KARPATHY BEHAVIORAL GUIDELINES
Follow `.agent/rules/10_karpathy_guidelines.md` for all coding tasks:
1. **Think Before Coding** — State assumptions explicitly. Ask if uncertain. Surface tradeoffs.
2. **Simplicity First** — Minimum code that solves the problem. Nothing speculative.
3. **Surgical Changes** — Touch only what you must. Don't improve unrelated code.
4. **Goal-Driven Execution** — Define success criteria. Loop until verified.

## CONTEXT
The full agent context is stored in the `.agent` directory. Always check there for project-specific conventions.

## SECWATCH — 보안점검(SQL 인젝션 탐지) 등록/운영
"secwatch 등록/설정/수집" 요청을 받으면 **반드시** `docs/60-operations/secwatch-agent.md` 를 먼저 읽고 그 절차대로 한다(구현: `scripts/secwatch/`). 핵심 불변식: 수집 PC 에는 Jev 키를 두지 않는다(sk 인증만, 키는 giip 게이트웨이 Azure 앱설정에만), 이벤트 타입은 표준 4개(`secevt_batch_audit`/`secevt_waf`/`secevt_cf`/`secevt_signal`)만 쓴다(임의 이름 금지), 마스킹은 소스에서 수행한다. 설계 정본: giipdb `SPEC_JEV_SQLI_DETECTION.md` (giip #3833).

## DOCKER INSTANCE — 시작할 때 부트스트랩 (giip #3535)
docker 인스턴스에서 작업을 시작하면 먼저 `bash scripts/bootstrap-instance.sh` 를 실행하고 출력의 MISSING/WARN 을 해결한다(멱등, 비밀값 미출력).
스크립트가 Linux 에서 안 돌면 환경을 먼저 맞추고, 그래도 안 되는 것만 스크립트를 고친다(`$env:TEMP`→`[System.IO.Path]::GetTempPath()`, 백슬래시→`Join-Path`, Windows 전용 호출→`$IsLinux` 분기).
정본: `docs/60-operations/docker-instance-setup-rules.md` §8, 허브 `giipprj-hub` 의 `KNOW-096`.
