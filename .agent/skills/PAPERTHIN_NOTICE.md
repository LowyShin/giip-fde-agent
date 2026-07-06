# Paperthin 스킬 이식 출처 (Attribution)

이 디렉토리의 아래 스킬들은 **[LilMGenius/paperthin](https://github.com/LilMGenius/paperthin)** (MIT License, Copyright © 2026 LilMGenius) 에서 이식(verbatim)했습니다. paperthin은 "아티팩트를 깨끗하고 참되게(clean & true)" 유지하는 에이전트-불문 저수준 스킬 모음입니다.

## 이식한 스킬 (14)

| 스킬 | 한줄 설명 | 유형 |
|---|---|---|
| `re0` | 표류한 아티팩트를 패치가 아닌 깨끗한 v0로 재작성 | model |
| `shower` | 컨텍스트 없는 서브세션으로 콜드리드 — 홀로 서는가? | model |
| `factchk` | 주장을 양방향으로 소스 대조 검증 (허구는 제외) | model |
| `mandela` | eval·지표의 누수(leakage) 감사 — 외부 ground-truth가 실제로 들어오는가 | model |
| `autobahn` | 위험 인접 범위를 사전 분리, 안전한 나머지를 클린룸에서 전력 실행 | model |
| `sip` | 산출물 직후 레포 자체 clean-and-true 체크로 자가검증 | model |
| `hate` | 계획을 죽일 단 하나의 반론 + 가장 싼 반증 실험 | user |
| `dedash` | em-dash 및 유사문자 제거 (역할별 문장부호 선택) | user |
| `re0-git` | 완료된 커밋 메시지를 `git log`만으로 핸드오프되게 정리 | user |
| `ssotchk` | 하나의 사실이 흩어진 곳을 찾아 정본을 지정 (읽기전용) | model |
| `ssotize` | 흩어진 사실을 하나의 정본으로 통합하고 나머지는 참조로 | model |
| `re0-work` | 검증된 교훈만 보존하며 v0에서 재시작 | model |
| `flywheel` | build→QA→retro→re0-work 루프로 코드가 아닌 학습을 누적 | model |
| `nba` | 현재 사이클 상태를 읽어 단 하나의 다음 최선 행동 반환 (읽기전용) | model |

## 이식하지 않은 스킬

- **`retro`** — 이 레포에는 이미 gstack + K-Layer 통합형 `retro`가 존재하여 덮어쓰지 않았습니다. `flywheel`의 retro 단계는 기존 `retro`가 담당합니다.
- **`ppt-upgrade`** — paperthin의 `npx skills` 설치 재조정 전용이라 이 환경과 무관하여 제외했습니다.

## MIT 라이선스 고지

```
MIT License — Copyright (c) 2026 LilMGenius
The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.
```

paperthin 자체가 [mattpocock/skills](https://github.com/mattpocock/skills) (MIT, © 2026 Matt Pocock)의 아키텍처·철학을 채택하고 있습니다.
