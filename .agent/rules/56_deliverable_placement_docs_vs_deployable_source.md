# 56. 결과물 배치 — 문서는 `docs/` 하위, 소스는 GitHub Actions 로 배포되는 위치

> **HARD RULE** — 의뢰자(사용자)의 요청에 대한 결과물을 만들 때, 어느 PC·AI 도구·세션이든 적용된다.
> 근거: 사용자 직접 지시(2026-10-27: "의뢰자가 뭔가 요청할 때 결과물이 문서면 docs 하위로, 소스면 git action 에서
> 디플로이 가능한 위치로 해야 하는 거 적혀 있나 체크하고 없으면 agent 가 제대로 읽을 수 있는 위치에 적어줘").
> 사전 조사: `docs/` 폴더 체계는 [22_documentation_standards.md](22_documentation_standards.md) 에 있으나, "의뢰 결과물의
> 종류별 배치"는 어떤 규칙에도 없었다([53_pre_push_pure_source_guard.md](53_pre_push_pure_source_guard.md) 는 배포 워크플로를
> 언급하지만 배치 규칙이 아니다). 관련 giip 이슈 번호: 근거 미상. 기계 강제는 없고 문서 정본이다.
> 첫 진입점은 [`AI_MUST_READ.md`](../../AI_MUST_READ.md) §3.

## 56-1. 문서 결과물

분석·보고·설계·가이드·매뉴얼·RCA 등 **문서**는 작업 대상 레포의 `docs/` 하위에, [규칙 22](22_documentation_standards.md)
의 번호 체계(`01-plan`, `02-design`, `03-analysis`, `50-technical`, `90-reports`, `assets` 등)에 맞춰 둔다.
레포 루트, `.agent/tasks`, 임시 폴더에 두지 않는다.

## 56-2. 소스 결과물

코드·스크립트·IaC·사이트 등 **배포 대상 소스**는 작성 전에 작업 대상 레포의 `.github/workflows/*.yml` 을 읽는다.
확인할 것: 트리거 브랜치, `paths:` 필터, 빌드/배포 디렉터리(`working-directory`, `app_location`, 산출 폴더 등).
그리고 **그 워크플로가 실제로 트리거·배포하는 위치**에 둔다. push/PR 후 해당 워크플로가 실제로 돌았는지 확인한다.

- 워크플로가 없거나 위치를 특정할 수 없으면 **추측해서 만들지 말고**, 그 사실을 보고에 밝히고 사용자에게 확인한다.
- `.github/workflows/` 추가·변경은 GitHub 토큰에 `workflow` scope 가 필요할 수 있다([규칙 53](53_pre_push_pure_source_guard.md) 참조).

## 56-3. 혼합 결과물

문서와 소스가 함께 나오면 둘을 나눠 각각 56-1, 56-2 대로 둔다.

## 56-4. 완료 보고

완료 보고에 **결과물 경로 전부**를 적고, 소스라면 **배포를 맡는 워크플로 파일명**도 적는다
([37_repo_url_in_report.md](37_repo_url_in_report.md) 와 정합).
