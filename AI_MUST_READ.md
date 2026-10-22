# AI 필독 — 이 레포에서 작업하기 전에 가장 먼저 읽으십시오

> **어느 PC, 어느 AI 도구(Claude / Codex / Gemini / Copilot …)든 이 레포를 수정하는 모든 세션의 첫 번째 읽을 거리**입니다.
> 아래는 요약이며, 상세 정본은 링크된 규칙 파일입니다. 규칙 본문을 다른 곳에 복제하지 마십시오.

## 1. 이 레포는 PUBLIC 범용 에이전트입니다 — 특정 고객정보 금지

`giip-fde-agent` 는 누구나 볼 수 있는 공개 레포이며 고객 PC 에 설치되는 범용 제품입니다.
문서·코드·노트·work_history·예제·테스트·커밋·PR 어디에도 다음을 쓰지 않습니다.

- 고객/조직명, **CSN 번호**, 고객 환경의 호스트·계정·리소스 이름·URL, 고객 업무 내용·설정값, 고객을 식별할 수 있는 사례 서술

| 허용 | 금지 |
|---|---|
| 범용 지식, 일반화된 절차, `<csn>` `<host>` 같은 플레이스홀더, 제품 자체의 식별자 | 실제 CSN 숫자, 고객명, 고객 서버·URL, 식별 가능한 사례 |

이 레포 자신의 전용 CSN 은 고객정보가 아닙니다(단 이 문서·규칙 본문에는 번호 대신 `<csn>` 을 씁니다).
고객별 지식은 **해당 고객 CSN 의 tPrivateKB** 에 둡니다. 위반을 발견하면 **그 처리 단위에서 즉시 정정**합니다.
→ [`.agent/rules/54_generic_agent_no_customer_info.md`](.agent/rules/54_generic_agent_no_customer_info.md)

## 2. 정보 조회 순서: tPrivateKB → 사양서 → 코드

- 순서는 **탐색 순서**입니다. 문서가 코드·실측과 다르면 코드·실측이 기준이고 문서를 정정합니다.
- tPrivateKB 통신은 이 레포의 [`scripts/privatekb/privatekb.py`](scripts/privatekb/privatekb.py)(상세 [README](scripts/privatekb/README.md))로만 합니다.
- SK 는 자동 탐색하며 **사용자에게 되묻지 않고 어떤 출력·로그에도 남기지 않습니다.**
- tPrivateKB 에 없던 재사용 가능한 사실을 사양서/코드에서 찾았다면, 작업 후 **자기 작업 CSN 의 tPrivateKB 에 등록**(환류)합니다. 이 레포 문서에 쓰는 것이 아닙니다.
→ [`.agent/rules/55_information_lookup_order_and_feedback.md`](.agent/rules/55_information_lookup_order_and_feedback.md)

## 3. 작업 전 체크리스트

1. **공유 체크아웃을 직접 수정하지 않습니다.** 다른 세션이 쓰는 경우가 많으므로 전용 worktree/브랜치에서 작업합니다. 이 레포는 public 이라 레포 폴더 안에서 바로 작업하지 않는 것이 원칙입니다([README](README.md)).
2. **main 에 직접 push 하지 않고 PR 로 올립니다**([`35_commit_push_per_task.md`](.agent/rules/35_commit_push_per_task.md)).
3. 커밋 전, 변경(추가)한 줄에 CSN 번호·고객 문자열이 0건인지 `git grep`/`git diff` 로 확인합니다.
4. 의미 있는 변경은 [`docs/WHATS_NEW.md`](docs/WHATS_NEW.md) 를 갱신합니다([`36_whats_new_maintenance.md`](.agent/rules/36_whats_new_maintenance.md)).
5. 나머지 규칙은 [`GEMINI.md`](GEMINI.md) 의 규칙 목록과 `.agent/rules/` 를 따릅니다.
