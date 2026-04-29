# Documentation Standards

All documents must follow the standard folder structure and naming conventions defined below.

## 📄 Folder Structure

| 코드 | 폴더명 | 내용 |
| :--- | :--- | :--- |
| **01** | `docs/01-plan/` | 프로젝트 기획서, 요구사항 정의서, 마일스톤 |
| **02** | `docs/02-design/` | 시스템 아키텍처, API 명세서, DB 스키마 설계 |
| **03** | `docs/03-analysis/` | 코드 리뷰 결과, 갭 분석서, 회고록 (Retrospective) |
| **50** | `docs/50-technical/` | 기술 블로그, 트러블슈팅 가이드, RCA 보고서 |
| **90** | `docs/90-reports/` | 최종 완료 보고서, 주간/월간 리포트 |
| **-** | `docs/assets/` | 문서에 포함된 이미지, 다이어그램, 기타 리소스 |

## 🛠️ Rules & Principles

- **SoR (Single Source of Truth) 원칙 준수**:
  1. Codebase (실제 작동하는 코드가 최우선 기준)
  2. `GEMINI.md` / 규칙 가이드
  3. `docs/` 내 설계서 및 명세서
- **언어 (Language)**: 모든 기술 문서와 로그는 특별한 사유가 없는 한 **한국어**로 작성하는 것을 원칙으로 합니다.
- **작업 이력**: 모든 문서의 히스토리 섹션이나 `GEMINI.md`의 작업 이력 섹션에는 작업 일시(`YYYYMMDD HH:mm:SS`)와 작업 내용을 명확히 기록해야 합니다.
