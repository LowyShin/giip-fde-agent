# 51. giip 제품 변경은 CSN 47 로만 (giip Product Changes — CSN 47 Only)

> **HARD RULE** — giip 제품(코어·프론트엔드·DB·API·에이전트)의 변경은 **CSN 47 로만 등록·처리**한다.
> 다른 CSN 에서 giip 제품 레포를 고치는 커밋·PR 을 만들지 않는다.
> 이 레포(`giip-fde-agent`, CSN 70424)는 **이 규칙의 적용 대상**이다.
> 근거: 사용자 직접 지시 2026-09-18 — https://giip.littleworld.net/ko/admin/giip-issues/2679

## 배경

고객사 수가 늘면서 giip 제품 자체의 변경이 여러 CSN 에 흩어져 등록되기 시작했다. 제품 변경이
고객 프로젝트 CSN 밑에 묻히면 (a) 제품 변경 이력이 한곳에 모이지 않아 회귀를 추적할 수 없고
(b) 특정 고객의 요청이 다른 모든 고객이 쓰는 본체에 조용히 반영되며 (c) 제품 릴리스 단위의
검증·롤백 대상이 불명확해진다.

그래서 사용자가 대전제를 못 박았다 — **giip 코어·프론트 기능 수정은 전부 CSN 47 로서만 등록 및
처리된다.** 운영 레포 쪽에도 동일 취지의 정본 규칙이 있으며, 이 파일은 그 대전제를 이 레포 안에서
자족적으로 읽히도록 옮겨 적은 것이다.

## giip 제품 레포 (변경 시 CSN 47 필수)

| 레포 | 무엇인가 |
|---|---|
| `giipv3` | 프론트엔드 — `giip.littleworld.net` 본체 |
| `giipdb` | DB 스키마 및 저장 프로시저 |
| `giipfaw` | Azure Functions API |
| `giipprj` | 제품 허브 (사양·지식 정본) |
| `giipAgentWin` | Windows 에이전트 |
| `giipAgentLinux` | Linux 에이전트 |
| `giipAgentAdmLinux` | Linux 관리 에이전트 |

## 규칙

1. **판정은 레포 단위로 한다.** 유일한 기준은 **"giip 제품 레포에 커밋 또는 PR 이 생기는가"**다.
   파일 단위 예외("이 파일은 설정일 뿐이니 괜찮다")를 두지 않는다 — 예외를 두는 순간 기계적으로
   판정할 수 없게 되고, 판정이 사람의 재량이 되면 규칙이 무력해진다.
2. **이 레포에서 도는 세션은 위 제품 레포를 고치지 않는다.** 작업 지시가 제품 레포 수정을
   요구하면 그 지시를 이 CSN 에서 수행하지 말고 아래 4항의 이관 절차를 밟는다.
3. **`giip-fde-agent` 자신은 giip 제품 레포가 아니다.** 이 레포의 코드·문서·`.agent/` 규칙 변경은
   평소대로 **CSN 70424 에서** 등록·처리한다. 이 규칙은 이 레포 자신의 작업을 막지 않는다.
4. **요청을 버리지 않는다.** 거부는 "이 CSN 에서 처리하지 않는다"이지 "무시한다"가 아니다.
   순서는 다음과 같다.
   1. CSN 47 에 같은 요구를 담은 **새 이슈를 등록**한다.
   2. 원 이슈에 **새 isn 을 링크한 코멘트**를 남긴다.
   3. 그 다음에 원 이슈를 닫는다.

   링크 없이 원 이슈를 닫으면 요청이 증발한 것과 같다. 링크를 남기지 못했다면 원 이슈를 닫지 않는다.
5. **giip 이슈 링크 형식**은 `https://giip.littleworld.net/ko/admin/giip-issues/<isn>` 이다.
   bare `#<숫자>` 표기는 쓰지 않는다 — 렌더러가 GitHub 이슈로 자동링크해 전혀 다른 곳을 가리킨다.
   본문에서 번호만 언급할 때는 `giip 2679` 처럼 샵 없이 쓴다.

## 왜 기존 규칙에 끼워넣지 않고 신규 파일인가

- [`00_project_repository_scope.md`](00_project_repository_scope.md) 는 **"이 프로젝트가 참조할 레포는
  `LowyShin/giip-fde-agent` 다"**라는 *레포 정체성 해석* 규칙이다. 목적이 레포 혼동 방지이지
  테넌트 게이트가 아니다.
- [`46_cross_csn_write_scope.md`](46_cross_csn_write_scope.md) 는 **giip 이슈에 대한 쓰기**(코멘트·
  상태전이·이슈생성)의 스코프 규칙이다. *코드 변경 대상 레포* 는 다루지 않는다.
- 둘 다 이 규칙을 담을 자리가 아니다. 기존 파일에 억지로 끼워넣으면 목적이 다른 규칙이 한 파일에
  섞이고, 양쪽에 중복 작성하면 한쪽만 갱신되는 사고가 난다
  ([`48_single_source_safety_predicate.md`](48_single_source_safety_predicate.md), 근거 giip 2440).
  **신규 파일 + 관련 파일에서의 양방향 링크**가 그 사이의 답이다.

## 상호참조

- [`00_project_repository_scope.md`](00_project_repository_scope.md) — *어느 레포가 이 프로젝트의
  정본인가*. 51 은 *어느 레포를 고칠 수 있는가*.
- [`46_cross_csn_write_scope.md`](46_cross_csn_write_scope.md) — 46 은 **이슈 쓰기 스코프**,
  51 은 **코드 변경 대상 레포 스코프**.
- [`41_issue_session_safety_index.md`](41_issue_session_safety_index.md) — 이 규칙군 색인.
