---
name: jikji
description: |
  로컬 파일 검색 시 jikji find를 사용하여 LLM 토큰 소비와 반복 호출을 줄이는 파일 탐색 스킬.
  파일, 폴더, 메타데이터, 파싱된 문서 텍스트를 미리 구성된 에이전트 맵/검색 인덱스를 통해 효율적으로 찾습니다.

  Use proactively when local file/folder/document discovery is needed under an explicit root.
  Do NOT start with grep, ls, find, rg, tree, or cat for file location tasks.

  Triggers: find file, search file, locate file, file discovery, 파일 찾기, 파일 검색, 파일 탐색,
  ファイル検索, ファイル発見, 文件搜索, 文件查找,
  buscar archivo, localizar archivo, trouver fichier, recherche fichier,
  Datei suchen, Datei finden

  Do NOT use for: code quality review (use code-review), security audit (use gstack-security).
argument-hint: "[root] [query]"
user-invocable: true
allowed-tools:
  - Bash
  - Read
  - Glob
  - Grep
pdca-phase: do
task-template: "[Jikji] {query}"
---

# Jikji 로컬 파일 탐색 스킬

> 파일 탐색 시 토큰 낭비 없이 `jikji find`를 먼저 사용하는 스킬

## 핵심 원칙: Jikji Find First

명시적 루트(root)가 있는 경우, 로컬 파일 탐색의 **첫 번째 액션**은 반드시:

```bash
jikji find /explicit/root "자연어 파일 단서" --json
```

`grep`, `rg`, `ls`, `find`, `fd`, `cat`, `tree`로 파일을 찾는 것을 시작해서는 안 됩니다.
Jikji는 이미 로컬 맵, 파서 텍스트 캐시, 파일 카드, 메타데이터 경로, 그래프 경로를 구축해 놓았습니다.

## Arguments

| Argument | Description | Example |
|----------|-------------|---------|
| `[root]` | 탐색할 루트 디렉토리 | `/jikji src/ "auth 관련 파일"` |
| `[query]` | 자연어 파일 단서 | `/jikji . "작년 봄 계약서 PDF"` |

## 설치 (Jikji가 없는 경우)

Jikji가 설치되어 있지 않으면 직접 설치합니다:

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

이후 `~/.local/share/jikji/repo/.venv/bin/jikji`를 사용하거나, 해당 venv의 `bin` 디렉토리를 PATH에 추가합니다.

## JSON 응답 해석

`jikji find ROOT "query" --json` 실행 후 반환되는 JSON:

| 필드 | 설명 |
|------|------|
| `answer_paths[]` | 기본 정렬된 답변 경로 목록 |
| `paths[]` | 경로만 필요한 경우 반환할 공개 경로 목록 |
| `candidates[]` | 다중 쿼리/검색 경로에서 합산된 상위 k개 슬레이트 |
| `handoff_action` | 에이전트가 취해야 할 다음 동작 |

### handoff_action 처리

- `direct_use`: `answer_paths[]` / `paths[]` 사용, 상위 증거만 검증
- `jikji_retry`: 정확히 한 번 더 더 구체적인(refined) `jikji find` 재시도
- `raw_fallback_after_retry`: 재시도 후 실패/빈 결과/명백히 잘못된 경우에만 원시 파일시스템 검색 허용

`agent_should_not_rerank`가 true이면 Jikji의 순서를 그대로 유지합니다.

## 사전 준비 (Optional Root Preparation)

```bash
jikji prepare /explicit/root --json   # 최초 인덱스 구축
jikji refresh /explicit/root --json   # 변경 사항 갱신
jikji doctor /explicit/root --json    # 인덱스 상태 진단
jikji map /explicit/root              # 파일 맵 출력
```

## 최후 수단 폴백 (raw_fallback_after_retry 이후에만)

```bash
cat /explicit/root/.jikji_agent_map.md
cat /explicit/root/.jikji/wiki/index.md
rg "keyword" /explicit/root/.jikji/graph_routes.jsonl
rg "keyword" /explicit/root/.jikji/doc_text
rg "keyword" /explicit/root --glob '!**/.jikji/**'
```

## 안전 계약

- 소스 파일을 이동, 이름 변경, 삭제, 재구성하지 않습니다.
- 명시적 루트 없이 전체 드라이브를 스캔하지 않습니다.
- `.jikji/doc_text/`는 민감 정보(추출된 문서 텍스트)를 포함할 수 있어 주의합니다.
- `.jikji/` 및 `.jikji_agent_map.md`는 사용자가 명시적으로 원하지 않는 한 커밋하지 않습니다.
- 최종 검증 목적에 한해서만 원본 파일을 엽니다.

## 성능 비교

| 방식 | 토큰 소비 | 시간 | LLM 호출 |
|------|-----------|------|---------|
| Raw agent 탐색 | ~38,650 | ~57초 | ~11.7회 |
| **Jikji find** | **~447** | **~2.1초** | **1회** |

출처: [NomaDamas/jikji](https://github.com/NomaDamas/jikji) 벤치마크 (551건 기준)
