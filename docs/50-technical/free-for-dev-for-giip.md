# free-for.dev 기반 무료 서비스 추천 목록 (GIIP 사용자용)

`https://free-for.dev/`에 정리된 서비스 중, **이 저장소 사용자(에이전트 중심 개발/운영)**에게 바로 도움이 되는 항목을 우선 선별한 문서입니다.

> 원문(전체 목록): [free-for.dev](https://free-for.dev/)  
> 본 문서는 빠른 의사결정을 위한 큐레이션이며, 무료 정책/한도는 수시로 변경될 수 있습니다.

## 1) LLM/에이전트 개발 & 관측

| 서비스 | 용도 | free-for.dev 기준 핵심 포인트 |
| :--- | :--- | :--- |
| [Langfuse](https://langfuse.com/) | LLM 트레이싱/분석 | 월 50k observations 무료 |
| [Langtrace](https://langtrace.ai) | LLM 추적/디버깅 | 월 50k traces 무료 |
| [Braintrust](https://www.braintrustdata.com/) | LLM eval/prompt 관리 | 주당 1,000 private eval rows |
| [Future AGI](https://futureagi.com) | LLM 앱 평가/시뮬레이션 | 무료 티어(스토리지/eval 크레딧 포함) |
| [OpenRouter](https://openrouter.ai/models?q=free) | 무료 모델 API 접근 | 여러 무료 모델 제공(속도/쿼터 제한) |

## 2) 코드 품질/리뷰/CI

| 서비스 | 용도 | free-for.dev 기준 핵심 포인트 |
| :--- | :--- | :--- |
| [CodeRabbit](https://coderabbit.ai) | AI 코드리뷰 | 무료 티어 제공, OSS 프로젝트 무료 |
| [Codecov](https://codecov.io/) | 커버리지 리포트 | OSS 무료 |
| [DeepSource](https://deepsource.io/) | 정적 분석 | 무료 티어 제공 |
| [CircleCI](https://circleci.com/) | CI/CD | 월 무료 실행 시간 제공 |
| [Buildkite](https://buildkite.com) | CI 파이프라인 | 월 무료 job minutes 제공 |
| [Mergify](https://mergify.com) | PR 자동화/머지 큐 | Public GitHub 저장소 무료 |

## 3) 보안/시크릿/컴플라이언스

| 서비스 | 용도 | free-for.dev 기준 핵심 포인트 |
| :--- | :--- | :--- |
| [Dependabot](https://dependabot.com/) | 의존성 취약점 업데이트 | 자동 의존성 업데이트 |
| [GitGuardian](https://www.gitguardian.com) | 시크릿 유출 탐지 | 개인/소규모 팀 무료 |
| [Doppler](https://doppler.com/) | 시크릿 관리 | 기본 무료 플랜 제공 |
| [Datree](https://www.datree.io/) | K8s 정책 검사 | 오픈소스 CLI |
| [aikido.dev](https://www.aikido.dev) | AppSec 통합 스캔 | 무료 플랜 제공 |

## 4) 모니터링/운영 안정성

| 서비스 | 용도 | free-for.dev 기준 핵심 포인트 |
| :--- | :--- | :--- |
| [Grafana Cloud](https://grafana.com/products/cloud/) | 메트릭/로그/알림 | 무료 티어(대시보드/알림/로그 저장) |
| [Better Stack](https://betterstack.com/better-uptime) | 업타임/인시던트 | 모니터/상태페이지 무료 범위 제공 |
| [Checkly](https://checklyhq.com) | API/E2E 모니터링 | 개발자용 무료 플랜 제공 |
| [healthchecks.io](https://healthchecks.io) | Cron/백그라운드 잡 모니터링 | 무료 checks 제공 |
| [cronitor.io](https://cronitor.io/) | 작업/엔드포인트 모니터링 | 무료 티어 제공 |

## 5) 저장소/배포/인프라

| 서비스 | 용도 | free-for.dev 기준 핵심 포인트 |
| :--- | :--- | :--- |
| [GitHub](https://github.com/) | 코드 저장소/협업 | private/public 저장소 무료 |
| [GitLab](https://about.gitlab.com/) | 저장소 + CI/CD | 무료 티어 제공 |
| [Codeberg](https://codeberg.org/) | OSS 중심 저장소/CI | 무료/오픈소스 친화 플랜 |
| [Pulumi](https://www.pulumi.com/) | IaC | 무료 사용 구간 제공 |
| [Deno Deploy](https://deno.com/deploy) | 엣지 배포 | 무료 요청/트래픽 한도 제공 |
| [appwrite](https://appwrite.io) | BaaS | 무료 티어(프로젝트 단위 리소스) |

## 6) API 개발/테스트 보조

| 서비스 | 용도 | free-for.dev 기준 핵심 포인트 |
| :--- | :--- | :--- |
| [Beeceptor](https://beeceptor.com) | API mocking/debugging | 일 요청 무료 한도 제공 |
| [Apify](https://www.apify.com/) | 데이터 수집/자동화 | 월 크레딧 제공 |
| [BrowserCat](https://www.browsercat.com) | Headless browser API | 월 무료 요청 제공 |
| [Colab](https://colab.research.google.com) | 실험/프로토타입 | 무료 GPU 노트북 환경 |
| [Cloudmersive](https://cloudmersive.com/) | 유틸리티 API 묶음 | 월 무료 호출 한도 제공 |

## 빠른 적용 제안 (이 레포 기준)

1. **LLMOps 기본 세트**: Langfuse + Braintrust  
2. **보안 기본 세트**: Dependabot + GitGuardian  
3. **운영 기본 세트**: Grafana Cloud + healthchecks.io  
4. **API 개발 세트**: Beeceptor + BrowserCat

---
*작업 이력: 20260629 08:25:49: free-for.dev 기반 GIIP 사용자용 무료 서비스 큐레이션 문서 추가 (이슈 #27)*
