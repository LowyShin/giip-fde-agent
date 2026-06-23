# Jikji 🔍

## 📋 개요
**Jikji**는 AI 에이전트가 로컬 파일을 찾을 때 발생하는 과도한 토큰 소비와 반복적인 LLM 호출을 줄여주는 비파괴적 로컬 파일 탐색 레이어입니다. 파일 하나를 찾을 때 Raw 에이전트 탐색 대비 최대 **86배 이상** 토큰을 절약할 수 있습니다.

| 방식 | 토큰 소비 | 처리 시간 | LLM 호출 횟수 |
|------|-----------|-----------|--------------|
| Raw agent 탐색 | ~38,650 | ~57초 | ~11.7회 |
| **Jikji find** | **~447** | **~2.1초** | **1회** |

*출처: NomaDamas/jikji 벤치마크 (551건 기준)*

## ✨ 주요 특징
- **비파괴적**: 소스 파일을 이동, 삭제, 재구성하지 않습니다. `.jikji/` 하위에 생성된 맵과 캐시만 관리합니다.
- **사전 파싱**: PDF, HWP/HWPX, Office, HTML 등을 사전에 파싱하여 검색 시 재파싱 루프를 없앱니다.
- **다중 경로 탐색**: 경로, 파일명, 폴더, 확장자, 본문 텍스트, 메타데이터 등을 분리 인덱싱합니다.
- **지식 그래프**: 소스, 폴더, 용어, 의도, 중복 노드를 사전 구성하여 저토큰 후보 라우팅을 지원합니다.
- **에이전트 맵**: `.jikji_agent_map.md`로 복잡한 디렉토리 트리를 에이전트가 읽기 쉬운 파일 맵으로 변환합니다.

## 🔗 공식 리소스 및 설치
- **GitHub**: [NomaDamas/jikji](https://github.com/NomaDamas/jikji)
- **설치 명령어**:
  ```bash
  mkdir -p ~/.local/share/jikji
  if [ ! -d ~/.local/share/jikji/repo/.git ]; then
    git clone https://github.com/nomadamas/jikji.git ~/.local/share/jikji/repo
  fi
  cd ~/.local/share/jikji/repo
  git pull --ff-only
  python3 -m venv .venv
  .venv/bin/pip install -e .
  .venv/bin/jikji --help
  ```

## 🚀 에이전트 스킬 연동

Jikji는 이 레포지토리의 `.agent/skills/jikji/SKILL.md` 스킬로 통합되어 있습니다.
에이전트는 파일 탐색 작업 시 자동으로 이 스킬을 활성화합니다.

### 기본 사용법

```bash
# 루트 디렉토리에서 자연어로 파일 찾기
jikji find /project/root "인증 관련 설정 파일" --json

# 루트 인덱스 최초 구축 (선택 사항)
jikji prepare /project/root --json

# 변경 사항 갱신
jikji refresh /project/root --json

# 인덱스 상태 진단
jikji doctor /project/root --json
```

### 에이전트 스킬 자동 설치

```bash
# 모든 지원 에이전트에 스킬 설치
jikji agent-skill-install --agent all --json

# Claude Code 전용
jikji claude-skill-install --json

# Codex 전용
jikji codex-skill-install --json
```

## 📐 에이전트 통합 규칙

1. **Jikji First**: 파일 탐색 시 **Jikji를 먼저 사용합니다**. `grep`, `ls`, `find`, `rg`, `tree`, `cat`은 Jikji 폴백 이후에만 사용합니다.
2. **JSON 계약 준수**: `handoff_action` 값에 따라 동작합니다.
   - `direct_use` → `answer_paths[]` / `paths[]` 사용
   - `jikji_retry` → 정확히 1회 재시도
   - `raw_fallback_after_retry` → 재시도 실패 후에만 원시 탐색 허용
3. **안전 계약**: `.jikji/` 및 `.jikji_agent_map.md`는 커밋하지 않습니다 (`.gitignore`에 추가 권장).

## 🧠 Karpathy 행동 지침과의 연계

Jikji는 Karpathy 행동 지침의 **Simplicity First** 원칙을 직접 구현합니다.
불필요한 반복 탐색 대신 최소한의 호출로 파일을 찾아 토큰과 시간을 절약합니다.

> 전체 Karpathy 지침: [`.agent/rules/10_karpathy_guidelines.md`](../../.agent/rules/10_karpathy_guidelines.md)

---
*본 에이전트 시스템은 Jikji를 통해 파일 탐색 효율을 극대화합니다.*
