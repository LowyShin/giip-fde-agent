# 53. 고객 웹 레포 push 전 순수 소스 가드 테스트 강제

> **HARD RULE** — 고객 웹 레포(Django 앱: `vgt-smart-order-system`, `vgt-smart-stock` 등)에
> 커밋을 push 하기 **직전에**, 그 레포의 순수 소스 가드 테스트를 반드시 실행하고 **FAIL 이면
> push 하지 않는다.**
> 근거 giip: #3773(= #3748 복수행 `{# #}` 코멘트 누출 재발 4회차).

## 배경 — 가드는 있었는데 push 전에 돌지 않았다

`app/main_system/tests_template_comment_syntax.py`(복수행 `{# ... #}` 가 화면에 본문으로
새는 것을 잡는 가드)는 레포에 **이미 존재**했다. 그런데 어느 CI/훅에도 결선돼 있지 않아,
giip-3748 에서 이 테스트가 **FAIL 인 채로 push → deploy 까지 그대로 통과**했고 같은 누출이
4회 재발했다(이 규칙군의 1번 교훈과 동일: "문서/테스트가 있어도 자동 실행·차단되지 않으면
지켜지지 않는다").

가장 강력한 재발 방지는 **고객 레포의 서버사이드 CI**(`.github/workflows/`)로 push/PR 마다
가드를 돌려 FAIL 시 빨강으로 막는 것이다. 다만 `.github/workflows/` 경로의 추가·변경은
GitHub 토큰에 `workflow` scope 를 요구하며, 무인 세션 토큰에는 그 scope 가 없어 자동으로는
결선할 수 없다(사람이 scope 를 부여하거나 GitHub 에서 직접 파일을 만들어야 함). 그 서버사이드
층이 들어오기 전까지, **에이전트 자신이 push 하기 전에 가드를 돌려 스스로 막는** 클라이언트
사이드 층을 이 규칙으로 강제한다. 둘은 배타가 아니라 보완 관계다.

## 규칙

1. 고객 웹 레포(위 목록 및 동류의 Django 앱)에 `git push` 를 하기 **직전에** 아래를 실행한다.

   ```sh
   sh .agent/scripts/pre-push-pure-source-guard.sh <그 레포의 체크아웃 경로>
   ```

   - 스크립트는 그 레포의 순수 소스 가드 테스트(기본:
     `app.main_system.tests_template_comment_syntax`,
     `app.main_system.tests_fc_token_route_order` — Django setup/DB 불요)를 실행한다.
   - **종료코드 0 일 때만 push 한다.** 1(=가드 FAIL)이면 push 하지 말고 원인을 고친 뒤
     다시 돌린다. 2(=python 미발견)이면 환경을 먼저 맞춘다.
   - 가드 모듈이 없는 레포(비대상)는 스크립트가 스킵(exit 0)하므로, 모든 레포에 대고 돌려도
     안전하다. 검사 모듈을 바꿔야 하면 `GUARD_MODULES` 환경변수로 덮어쓴다.

2. 가드 FAIL 을 `--no-verify` 나 scope 우회로 넘기지 않는다(이 규칙군 43 의 커밋 훅 우회 금지와
   동일 취지). FAIL 은 "막힌 것"이 아니라 "재발을 막은 것"이다.

3. 서버사이드 CI(`.github/workflows/` 의 가드 job)를 넣을 수 있게 되면(토큰 `workflow` scope
   확보 또는 사람이 직접 생성) 그것을 정식 enforcement 로 삼고, 이 클라이언트사이드 가드는
   보조로 유지한다. 둘 중 하나로 줄이지 않는다.

## 검증(이식/수정 시)

[`42_completion_by_execution_evidence.md`](42_completion_by_execution_evidence.md) 대로 두 입력을
모두 실행해 두 출력을 확보한다.

- 정상(clean) 체크아웃 → 스크립트 exit 0.
- 임의 템플릿에 복수행 `{# 1행\n 2행 #}` 를 심은 상태 → 스크립트 exit 1, offender 의 `경로:행`
  출력, 제거하면 다시 exit 0.

(giip-3773 에서 `vgt-smart-order-system` 체크아웃에 대해 위 3단계를 실측: clean=12 tests OK
exit 0 / 심음=FAILED exit 1 / 제거=OK exit 0.)

## 관련 규칙

- [`43_delegation_safety_block.md`](43_delegation_safety_block.md) — 커밋 훅 우회(`--no-verify`) 금지.
- [`35_commit_push_per_task.md`](35_commit_push_per_task.md) — 작업마다 커밋·push. 이 규칙은 그
  push 직전 게이트를 더한다.
- [`41_issue_session_safety_index.md`](41_issue_session_safety_index.md) — 이 규칙군 색인.
