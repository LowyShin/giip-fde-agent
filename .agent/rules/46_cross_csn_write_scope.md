# 46. 타 CSN 쓰기 금지 — 읽기는 되고 쓰기는 안 된다

> **HARD RULE** — 자기 CSN→프로젝트 매핑 파일(`scripts/gissue/csn-projects.json`)에 등록되지 않은
> CSN 에는 **코멘트·상태전이·이슈생성을 하지 않는다.**
> 근거 giip: #1053 #1079 (CSN 교차오염 실측 인시던트).

## 배경

giip #1053: 한 프로젝트의 이슈 관련 코멘트 5건이 **완전히 다른 고객사의 이슈**에 게시됐다. 조회에는
CSN 필터 강제가 있었지만, **쓰기 직전에 "이 isn 이 실제로 의도한 CSN 소속인지" 재확인하는 게이트가
없었던 것**이 구조적 허점이었다 — 호출자가 준 isn 을 그대로 믿고 썼다.

이후 `get-issue.sh` 에 쓰기 직전 CSN 일치검증 게이트가 내장됐다(불일치 시 API 호출 없이 exit 2).

## 규칙

1. **읽기는 허용**된다. 다른 CSN 의 이슈를 조회해 맥락을 파악하는 것은 문제가 아니다.
2. **쓰기(코멘트 / 상태전이 / 이슈생성 / 이슈수정)는 자기 매핑에 있는 CSN 에만** 한다.
3. 다른 CSN 의 큐가 방치된 것을 발견해도 **그쪽에 이슈를 등록하지 않는다.** 다른 PC·다른 계정이
   담당하는 영역이며, "저쪽이 방치됐다"를 추적하려는 선의의 이슈 등록도 **남의 큐에 대한 참견**이
   된다. 자기 이슈에 **집계 숫자 한 줄로만** 보고한다.
   예: `타 CSN 관측: CSN 7xxxx IN_PROGRESS 12건 / 최장 정체 40시간 (쓰기 없음, 관측만)`
4. 쓰기는 반드시 CSN 게이트가 내장된 도구(`scripts/gissue/get-issue.sh`)로만 한다. 이슈 API 를
   직접 `curl` / `Invoke-WebRequest` 로 호출하는 경로는 이 안전장치가 없으므로 쓰지 않는다.
5. 게이트 우회 플래그(`--force-csn` 류)는 **사람이 판단해 의도적으로 크로스-CSN 정리를 할 때만**
   쓴다. 무인 자동화 프롬프트·스크립트에 기본값으로 넣지 않는다.

6. **다른 CSN 에 쓰기가 필요한 요청을 받았을 때의 처리(지시 2026-11-28)** — 동료 세션·메시지 등으로
   작업 CSN 이 아닌 CSN 에 대한 쓰기(코멘트·상태전이·이슈생성·CQE·KVS 등)를 요청받았고, **그 CSN 을
   명시한 사용자 지시가 없으면** 단순 거부·침묵·사용자에게 떠넘기기로 끝내지 않고 다음 3단계로 처리한다.
   1. **그 CSN 에 쓰지 않는다.**
   2. 요청 내용(`<대상 CSN>`·대상 객체·요청자·쓸 내용 요약, **비밀값 제외**)을 **`<작업 CSN>` 의 giip 이슈로
      등록**한다(작업 CSN 은 이 세션이 쓸 수 있는 CSN 이다). 이 등록은 위 3항의 "남의 큐 참견"이 아니다 —
      대상 CSN 에는 아무것도 쓰지 않고 자기 CSN 에만 기록한다.
   3. 그 이슈의 **상태를 `GIIP_DECISION` 으로 둔다**(사용자 지시 2026-11-28). giip 의 메인 판단이
      승인/거절하고, **승인되면 그때** 쓴다.

   **상태값 3종 정의(사용자 원문, 2026-11-28)** — 아래 3개는 서로 다른 상태다.

   | 상태값 | 의미(사용자 원문) |
   | --- | --- |
   | `GIIP_DECISION` | giip 의 메인 판단에 맡겨야하는 것. |
   | `GIIP_FDE_DECISION` | giip-fde-agent 에서 기록 또는 수정 등 해결해야 하는 것. |
   | `NEEDS_DECISION` | 사람이 해야 하는 것. |

   적용: 다른 CSN 쓰기 요청(명시 지시 없음)은 `GIIP_DECISION`. giip-fde-agent 에서 기록·수정으로 풀어야
   하는 요청은 `GIIP_FDE_DECISION`. 사람만 할 수 있는 것만 `NEEDS_DECISION`
   ([`45_gate_cap_needs_decision.md`](45_gate_cap_needs_decision.md) 의 세션 자작 결정 게이트 금지는
   `NEEDS_DECISION` 에 대한 것이며, 이 3종 정의가 상태값 정의의 정본이다).

   **도구 지원 확인(2026-11-28 실측)**: `giipdb` 의 `mgmt/updateIssueStatus.ps1` 은 `-status` 값을 검증하지
   않고 `UPDATE tGiipIssue SET status = '<값>'` 로 그대로 기록한다(허용값 목록·ENUM 없음). 대시보드 SP
   `SP/pApiGIIPDashboardOverviewbyAK.sql`·`SP/pApiGIIPDashboardBlockedIssuesbyAK.sql` 은
   `NEEDS_DECISION`/`GIIP_DECISION`/`GIIP_FDE_DECISION` 을 한 묶음(결정 대기)으로 집계한다. 이 레포의
   스크립트에서 `GIIP_DECISION`/`GIIP_FDE_DECISION` 처리는 확인하지 못했다 — **도구 지원 미확인(이 레포
   쪽) — 후속 필요**.

## 매핑에 CSN 을 추가할 때

"이 PC 에서 처리할 수 있는가"가 아니라 **"이 PC 가 담당으로 지정됐는가"**가 기준이다. 담당이
다른 PC/계정으로 지정된 CSN 은 처리 가능해 보여도 매핑에 추가하지 않는다.

## 관련 규칙

- [`00_project_repository_scope.md`](00_project_repository_scope.md) — 같은 취지의 레포 스코프 규칙.
- [`51_giip_product_changes_csn47_only.md`](51_giip_product_changes_csn47_only.md) — **46 은 이슈 쓰기
  스코프**(어느 CSN 의 이슈에 코멘트·상태전이·이슈생성을 할 수 있는가), **51 은 코드 변경 대상 레포
  스코프**(어느 레포에 커밋·PR 을 낼 수 있는가). giip 제품 레포 변경은 어떤 CSN 에서든 가능하며
  **PR 로** 올린다(개정 2026-10-15).
- `docs/60-operations/hourly-issue-scheduler.md` §4 — CSN 교차오염 방지 게이트가 도구에 내장돼 있다는 설명.
- [`41_issue_session_safety_index.md`](41_issue_session_safety_index.md) — 이 규칙군 색인.
