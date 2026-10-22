# 배포 및 설정 이슈 (Deployment Gotchas)

> 카파시 K-Layer: 에이전트 시스템 설정 및 배포 과정에서 발견된 주의사항
> 모든 claim은 source-linked. 삭제 금지, invalidated_at으로만 무효화.

---

## 에이전트 워크플로우 설정

CLAIM-001: `.agent/workflows/` 디렉토리에 추가된 커스텀 워크플로우(`.md`)는 반드시 유효한 YAML frontmatter(---로 시작)를 포함해야 시스템 공식 목록에 등록된다.
- **evidence**: `/gaupdate` 및 `investment-evaluation` 파일이 존재함에도 목록에서 누락됨 확인. 헤더 추가 후 즉시 인식됨.
- **source**: `.agent/workflows/gaupdate.md`, `.agent/workflows/investment-evaluation.md`, 작업 기록 20260516 13:55:10
- **observed_at**: 20260516
- **invalidated_at**: null
- **confidence**: high

CLAIM-002: PowerShell 환경에서 `ls` 또는 `head`와 같은 리눅스 기반 별칭(alias)은 예상과 다르게 동작하거나 없을 수 있으므로, 복잡한 파이프라인에서는 `Get-ChildItem`, `Get-Content` 등 네이티브 명령어를 사용하는 것이 안전하다.
- **evidence**: `head -n 5` 실행 실패 및 `ls` 인코딩 깨짐 현상 다수 관측
- **source**: 작업 기록 20260516 13:55:25
- **observed_at**: 20260516
- **invalidated_at**: null
- **confidence**: high

## PROD 공개 도메인 라우팅 / 稼働 이미지 신선도 (giip-3787)

CLAIM-387: vgt-smart-order-system 에서 "DEV/STG 는 표시되는데 PROD 만 특정 UI 가 안 보인다"는 증상은, main 브랜치 소스·CI deploy 가 모두 green 이어도 재현될 수 있다. 공개 도메인 `smart-order.online` 이 feature 를 가진 App Service(`vgt-smart-order-prod.azurewebsites.net`)가 아니라 다른 Azure ASE 슬라이스로 라우팅되거나, 可変 태그 `:prod` 가 config 差分 제로로 재 pull 되지 않는(CLAIM-355) 경우다.
- **evidence**: giip-3089 年切替버튼 소스가 main/stg/dev 모두 `so-tesk-ynav`×5 로 동일 존재(`main..dev=0`), main deploy run 38410349540 가 headSha `e9fe269b` 로 success(2026-10-13T14:09:39Z). App Service `vgt-smart-order-prod` 는 `/static/css/screens/tesk-yearnav.css`=200(bogus css=404 로 검증). 그러나 공개 `smart-order.online`(132.220.38.112, 証明書 CN `*.msha-slice-7-am2-1-ase.p.azurewebsites.net`)은 `/health/` 포함 전 경로 404.
- **source**: `.agent/tasks/giip-3787.md`, giip isn 3787, 작업 기록 2026-10-13
- **observed_at**: 20261013
- **invalidated_at**: null
- **confidence**: medium

CLAIM-388: PROD 未反映 검출은 "브랜치 소스 존재" 와 "공개 도메인 실배포" 를 분리해 확인해야 한다. 소스 존재는 `git grep -c <marker> refs/tmp/main -- <file>` + `git rev-list --count main..dev`(=0 이면 포함) 로, 실배포는 App Service 직 URL(`*.azurewebsites.net`)의 정적 자산 HTTP 코드와 공개 도메인의 HTTP 코드를 나란히 비교해 불일치를 찾는다. `az` 不在 환경에서는 이미지 태그/도메인 binding 확인이 보류되므로, 보류 항목을 명시한 뒤 人手 az 확인을 요청한다.
- **evidence**: isn 3787 조사에서 `az` 가 bash(`which az`)·PowerShell(`az version`) 양쪽에서 "not recognized" 실측 → 이미지 digest/hostname binding 확인 불가로 보류 처리.
- **source**: `.agent/tasks/giip-3787.md`, giip isn 3787
- **observed_at**: 20261013
- **invalidated_at**: null
- **confidence**: high

CLAIM-389: CLAIM-387/388 의 증상·분리 절차는 [1/2](isn 3787) PR #149 가 main 에 머지된(2026-10-13T16:47Z) **이후 시점(17:17Z)에도 그대로 성립**함을, 兄弟 [2/2](isn 3788)에서 독립 재실측으로 확인했다. 즉 공개 도메인 라우팅/稼働 이미지 신선도 가설은 시간 경과·昇格 鎖 완결과 무관하게 지속되는 "配信層" 문제이지, 추가 昇格으로 해소되는 "소스 미반영" 문제가 아니다.
- **evidence**: isn 3788 재실측 — `bc16f815`(giip-3089)=main 祖先(`git merge-base --is-ancestor` 참), `main..dev=0`/`dev..main=1621`, `so-tesk-ynav` main/stg/dev 모두 5, main deploy run 38410349540 headSha=`e9fe269b` success. App Service `vgt-smart-order-prod` tesk-yearnav.css=200(bogus=404 검증)·/health/=200. 공개 `smart-order.online` 既定 SNI=000(証明書 불일치)·`-k`=404(`/`·`/health/`·css 전부). `tesk.html` 에 tenant/feature_flag/env_settings/getattr(settings) 出し分け grep=0. `az` 는 bash·pwsh 양쪽 재시도 "not recognized"로 보류.
- **source**: `.agent/tasks/giip-3788.md`, giip isn 3788, [[CLAIM-387]], [[CLAIM-388]]
- **observed_at**: 20261013
- **invalidated_at**: null
- **confidence**: medium
