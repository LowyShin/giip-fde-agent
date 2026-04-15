# K-Layer Knowledge Base — README

> 카파시 다이어그램 기반 자동 지식 축적 시스템

## 구조

```
.agent/knowledge/
├── README.md          ← 이 파일
├── notes/             ← 주제별 지식 노트 (source-linked claims)
│   ├── api-patterns.md
│   ├── deployment-gotchas.md
│   ├── db-schema-facts.md
│   ├── agent-performance.md
│   ├── debug-patterns.md
│   └── ui-ux-observations.md
└── index.md           ← 전체 claim 인덱스 (자동 생성)
```

## 핵심 원칙

1. **Append-only**: 내용을 삭제하지 않음. `invalidated_at`으로만 무효화
2. **Source-linked**: 모든 claim은 원본 파일 또는 trace 링크를 가짐
3. **에이전트가 작성**: 사람이 직접 쓰지 않음. 에이전트가 작업 후 자동 생성

## 사용법

에이전트는 새 작업 시작 전 관련 노트를 검색합니다:

```powershell
Select-String -Path ".agent/knowledge/notes/*.md" -Pattern "키워드"
```

## 통계

- 첫 생성일: 20260415
- 총 Claim 수: (자동 집계)
