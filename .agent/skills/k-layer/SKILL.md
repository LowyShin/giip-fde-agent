---
name: k-layer
description: |
  에이전트 작업 결과로부터 자동으로 source-linked claim을 생성하고, 지식 위키(K-Layer)에 축적합니다.
  카파시 다이어그램 패턴: Raw Sources → LLM Processing → Curated Wiki → Outputs
  
  다음 상황에서 사용합니다:
  - 반복 작업에서 패턴을 발견했을 때 (예: 특정 API 오류가 반복됨)
  - 실험/시도의 결과를 지식으로 전환할 때
  - 이전 작업의 교훈을 다음 작업에 반영할 때
  - "/k-layer" 명령어가 명시적으로 언급될 때

  트리거 키워드: k-layer, knowledge, 지식, 학습, 패턴 발견, 교훈, claim, wiki
---

# K-Layer: 에이전트 자동 지식 생성 시스템

카파시 다이어그램의 핵심 원리를 에이전트에 적용합니다.
**사람이 위키를 쓰는 게 아니라, 에이전트가 데이터를 읽고 위키를 씁니다.**

## 🔑 핵심 원칙

```
Raw Traces/Results → LLM Analysis → Source-Linked Claims → K-Layer Wiki → Next Task Context
```

1. **Source-linked claims**: 모든 주장에 원본 근거(파일명, trace_id, 커밋 해시) 링크 필수
2. **Immutable append-only**: Claim 삭제 금지. `invalidated_at` 필드로만 무효화
3. **자기강화 루프**: 새 작업 시작 전 관련 K-Layer 노트 참조 필수
4. **Raw는 보존**: K-Layer는 raw 위에 올라가는 정제 계층. raw를 대체하지 않음

---

## 📥 1단계: K-Layer 노트 참조 (작업 시작 전)

새 작업 시작 시, 관련 K-Layer 노트가 있는지 확인합니다:

```powershell
# 관련 키워드로 지식 노트 검색
Get-ChildItem ".agent/knowledge/notes/" -Recurse | 
  Select-String -Pattern "관련_키워드" | 
  Select-Object Filename, LineNumber, Line
```

참조한 claim이 있으면 작업 컨텍스트에 명시적으로 포함:
> "K-Layer 참조: CLAIM-003 (source: notes/api-errors.md#claim-003) — Azure Function cold start는 30초 이상 소요됨"

---

## 📤 2단계: Claim 생성 (작업 완료 후)

작업 결과에서 재사용 가능한 패턴/교훈을 발견하면 claim으로 변환합니다.

### Claim 형식

```markdown
## [주제 제목]

CLAIM-{NNN}: {관찰된 사실 또는 패턴}
- **evidence**: {구체적 수치나 관측값}
- **source**: {파일명#라인번호 또는 trace_id#step}
- **observed_at**: {YYYYMMDD}
- **invalidated_at**: null  ← 항상 null로 시작, 무효화 시만 날짜 기입
- **confidence**: high|mid|low
```

### 예시

```markdown
## API 오류 패턴

CLAIM-001: GIIP API는 Authorization 헤더 없이 호출 시 401이 아닌 403 반환
- **evidence**: 3회 관측 (20260129, 20260201, 20260204)
- **source**: giipfaw/giipIssues/run.ps1#L23, traces/20260129_auth_fix.json#step-3
- **observed_at**: 20260204
- **invalidated_at**: null
- **confidence**: high

CLAIM-002: Azure Function cold start는 첫 호출 시 평균 25-35초 지연 발생
- **evidence**: 테스트 5회 측정 평균 28.4초
- **source**: traces/20260204_cold_start_test.json#step-7
- **observed_at**: 20260204
- **invalidated_at**: null
- **confidence**: mid
```

---

## 💾 3단계: 지식 노트 저장

저장 경로: `.agent/knowledge/notes/{topic}.md`

### 주제별 파일 분류

| 파일명 | 내용 |
|--------|------|
| `api-patterns.md` | API 호출 패턴, 오류 코드 |
| `deployment-gotchas.md` | 배포 시 주의사항, 환경 이슈 |
| `db-schema-facts.md` | DB 스키마 관련 발견사항 |
| `agent-performance.md` | 에이전트 실행 성능 데이터 |
| `ui-ux-observations.md` | UI/UX 관련 사용자 반응 패턴 |
| `debug-patterns.md` | 반복되는 버그 패턴 및 해결책 |

---

## 🔄 4단계: 자기강화 루프

```
새 작업 요청
    ↓
K-Layer 노트 검색 (관련 topic 키워드)
    ↓
관련 claim 발견? → 컨텍스트에 포함
    ↓
작업 실행
    ↓
새로운 패턴/교훈 발견?
    ├── Yes → Claim 생성 → K-Layer 노트에 append
    └── No  → 기존 claim 신뢰도 갱신 (evidence 보강)
```

---

## ⚡ 빠른 실행 명령어

### `/k-layer search {키워드}` — 관련 knowledge 검색
```powershell
Select-String -Path ".agent/knowledge/notes/*.md" -Pattern "{키워드}"
```

### `/k-layer add {topic}` — 새 claim 추가
현재 작업 결과를 분석하여 `.agent/knowledge/notes/{topic}.md`에 claim 생성

### `/k-layer invalidate {topic} {CLAIM-NNN}` — claim 무효화
```powershell
# CLAIM-001의 invalidated_at을 오늘 날짜로 업데이트
(Get-Content ".agent/knowledge/notes/{topic}.md") -replace '(CLAIM-001.*\r?\n.*invalidated_at): null', '$1: 20260415' | 
  Set-Content ".agent/knowledge/notes/{topic}.md"
```

### `/k-layer summary` — 전체 knowledge 현황 요약
```powershell
$notes = Get-ChildItem ".agent/knowledge/notes/" -Filter "*.md"
$total = ($notes | Get-Content | Select-String "^CLAIM-").Count
$active = ($notes | Get-Content | Select-String "invalidated_at: null").Count
Write-Host "총 Claim: $total | 활성: $active | 무효화: $($total - $active)"
```

---

## 📋 GEMINI.md 통합 규칙

이 스킬은 다음 상황에서 **자동으로** 트리거됩니다:

1. **반복 오류 발견 시**: 동일 오류가 2회 이상 발생하면 K-Layer에 기록
2. **작업 완료 후**: 새로운 기술적 사실이 발견되면 claim 생성
3. **새 작업 시작 전**: 관련 topic의 K-Layer 노트 조회

---

## ⚡ Optimization Integration
When using this skill for critical tasks, please run it within a /native-trace context to capture performance data for self-improvement via /aioptimize.
