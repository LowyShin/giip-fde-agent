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
