# 55. 정보 조회 순서(tPrivateKB → 사양서 → 코드)와 tPrivateKB 환류

> **HARD RULE** — 정보를 찾아야 하는 모든 AI 세션(대화형·Slack 봇·무인 스케줄러)에 적용된다.
> 근거: 사용자 지시(2026-10-22): "필요한 정보를 조회할 때 tPrivateKB 를 최우선, 그 다음 사양서, 그 다음 코드 순으로",
> "tPrivateKB 에 없고 다른 데서 찾았다면 작업 후 유사 질문은 tPrivateKB 에서 찾을 수 있게 업데이트",
> "tPrivateKB 와의 통신은 이 레포에 적힌 API 를 이용해야만 한다". 첫 진입점은 [`AI_MUST_READ.md`](../../AI_MUST_READ.md).

## 1. 조회 순서

1. **tPrivateKB** — 작업 CSN 의 비공개 지식
2. **사양서·README·docs**
3. **코드**

이 순서는 **탐색 순서**이지 사실 판정의 우선순위가 아니다. 상위 문서가 코드·실측과 다르면
**코드·실측을 기준**으로 삼고, 틀린 문서는 발견 즉시 정정한다.

## 2. tPrivateKB 통신 — 이 레포의 클라이언트만

통신은 [`scripts/privatekb/privatekb.py`](../../scripts/privatekb/privatekb.py)(`giipApiSk3` → `pApiKb*bySk`)로만 한다.
직접 DB 접근, 임의 HTTP 호출, 다른 경로는 금지다. 상세·함정은
[`scripts/privatekb/README.md`](../../scripts/privatekb/README.md) 가 정본이다(인터프리터는 README 표기를 따르되 환경에 맞는 python 3 를 쓴다).

```bash
python3 scripts/privatekb/privatekb.py list --csn <csn> --search <키워드>
python3 scripts/privatekb/privatekb.py get  --csn <csn> --kbsn <n>
```

- **SK 는 자동 탐색**(env `GIIP_SK` → `giipAgent.cfg|.cnf`)한다. **사용자에게 되묻지 않고, 어떤 출력·로그·코멘트·파일에도 남기지 않는다.**
- 응답의 `debug` 블록에 SK 가 그대로 들어 있으니 응답을 그대로 로그에 남기지 않는다(클라이언트가 제거한다).
- 검색어의 `[` 는 `[[]` 로 escape 한다(클라이언트가 처리).
- **tPrivateKB 는 `/kb`(공개 기술 아티클)와 다르다.** `/kb` 는 건드리지 않는다.

## 3. 환류 — 없던 지식은 작업 후 tPrivateKB 에 남긴다

tPrivateKB 에 **없던** 재사용 가능한 사실을 사양서/코드에서 확인했다면, 작업 후 유사 질문이 tPrivateKB 에서
바로 찾아지도록 **자기 작업 CSN 의 tPrivateKB 에** 등록한다.

1. 등록 전 `list` 로 이미 있는지 확인한다(`put` 은 title 기준 upsert).
2. `put` 으로 등록한다. 내용에는 **질문 키워드, 답, 근거 출처(파일·문서), 확인 방법**을 넣는다.
3. 등록 후 `get`/`list` 로 들어갔는지 확인한다(응답 파싱 실패 시 재시도 전에 `list` 부터 — 중복 방지).

금지: 비밀(SK 등)·개인정보·**다른 CSN 의 데이터**를 내용에 넣는 것. **작업 CSN 이 확정되지 않았으면 환류하지
않고** 그 사실을 보고에 밝힌다.

환류 대상은 **tPrivateKB 이지 이 레포 문서가 아니다.** 고객별 지식을 이 레포에 쓰는 것은
[54_generic_agent_no_customer_info.md](54_generic_agent_no_customer_info.md) 위반이다.

## 관련

- [`AI_MUST_READ.md`](../../AI_MUST_READ.md)
- [54_generic_agent_no_customer_info.md](54_generic_agent_no_customer_info.md)
- [`29_tool_usage_and_verification.md`](29_tool_usage_and_verification.md) — 확인 없는 추정 금지
