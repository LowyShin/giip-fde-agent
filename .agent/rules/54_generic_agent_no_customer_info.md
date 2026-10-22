# 54. 범용 에이전트 — 특정 고객정보를 이 레포에 넣지 않는다

> **HARD RULE** — 어느 PC, 어느 AI 도구, 어느 세션이든 이 레포를 수정할 때 적용된다.
> 근거: README 의 "`giip-fde-agent`는 **public 레포지토리**" 서술, 라이선스(Apache-2.0), 사용자 지시(2026-10-22:
> "giip-fde-agent는 범용 에이전트니까 특정 고객정보 넣지마라"). 첫 진입점은 [`AI_MUST_READ.md`](../../AI_MUST_READ.md).

## 핵심

`giip-fde-agent` 는 **누구나 볼 수 있는 PUBLIC 레포**이며, 고객 PC 에 설치되는 **범용 제품**이다.
따라서 문서·코드·노트·`work_history`·예제·테스트·커밋 메시지·PR 본문 **어디에도 특정 고객 정보를 쓰지 않는다.**

## 특정 고객 정보란

- 고객/조직의 이름(약칭·로마자 표기·별칭 포함), 담당자명
- **CSN 번호**(고객/프로젝트 식별 번호) 및 고객별 식별자
- 고객 환경의 호스트명·IP·계정·리소스 이름·저장소 이름·URL
- 고객의 업무 내용, 고객별 설정값, 고객별 스크립트
- 위가 직접 적혀 있지 않아도 **어느 고객의 사례인지 식별할 수 있는 서술**

## 허용 / 금지

| 구분 | 예시 |
|---|---|
| 허용 | 범용 지식, 일반화된 절차, `<csn>` `<host>` `<customer>` 같은 플레이스홀더, 제품 자체의 식별자(레포·스크립트·함수명) |
| 금지 | 실제 CSN 숫자, 고객명, 고객 서버·계정·URL, "A 사에서는 이렇게 했다"처럼 식별 가능한 사례 |

작성 예: `python3 scripts/privatekb/privatekb.py list --csn <csn> --search <키워드>` (O) /
실제 번호를 넣은 같은 명령 (X).

## 고객별 지식은 어디에 두는가

해당 고객 **CSN 의 tPrivateKB** 에 둔다([55_information_lookup_order_and_feedback.md](55_information_lookup_order_and_feedback.md)).
이 레포 문서가 아니다. k-layer 노트도 마찬가지다.

## 위반을 발견하면

발견한 **그 처리 단위에서** 고친다("나중에"는 없다). 고객 특정 부분을 일반화·삭제하고, 고객별로 남길
가치가 있는 내용은 해당 CSN 의 tPrivateKB 로 옮긴 뒤 이 레포에서 지운다. 과거 기록을 고쳐 쓰는 것이
부담되면 식별 부분만 `<csn>` 등으로 치환한다.

## 작업 전 자가 검사

변경한 파일에 대해 **추가한 줄**에서 CSN 형태 숫자·고객 문자열이 0건인지 확인한 뒤 커밋한다.

```bash
git diff --cached -U0 | grep -E '^\+' | grep -nE '\b[0-9]{2,5}\b' | grep -iE 'csn'
git grep -nE '\b7[0-9]{4}\b' -- <변경한 파일>
```

(고객명은 알고 있는 후보 문자열로 같은 방식 검사. 훅·스크립트로 자동 강제되지 않으므로 사람/AI 가 직접 한다.)

## 예외 — 이 레포 자신의 전용 CSN

이 레포(`giip-fde-agent`) **자신의 전용 CSN** 은 고객정보가 아니다. 그 CSN 으로 남긴 이 레포 자신의 정비 기록
(`.agent/work_history/` 등)은 이 규칙의 위반으로 분류하지 않는다. 단 **이 규칙 문서와 필독 파일 본문에는
번호 대신 플레이스홀더**(`<csn>`)를 쓴다.

## 현황 — 정리 대기 중인 알려진 위반 후보

이 레포 자신의 CSN 을 제외하고도, 다른 CSN 번호나 고객 프로젝트 매핑·고객 사고 사례가 든 추적 파일이
소수 남아 있다(운영 문서, `scripts/gissue/`, 슬랙봇 프로젝트 매핑 파일 등). 이 규칙 PR 은 이들을 수정하지
않으며, 별도 후속 정리 대상이다. 새로 만드는 기록은 이 규칙을 따른다. git 이력에 남은 과거 내용의 처리는
별도 판단 사항이다.

## 관련

- [`AI_MUST_READ.md`](../../AI_MUST_READ.md) — 모든 AI 세션의 필독 파일
- [55_information_lookup_order_and_feedback.md](55_information_lookup_order_and_feedback.md) — 고객별 지식의 올바른 저장처
- [`39_conduct_toward_customers.md`](39_conduct_toward_customers.md), [`35_commit_push_per_task.md`](35_commit_push_per_task.md)
