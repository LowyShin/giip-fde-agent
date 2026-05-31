# OpenAI Codex ⚡

## 📋 개요
**OpenAI Codex**는 OpenAI가 개발한 AI 코딩 에이전트로, 터미널·브라우저·모바일 환경에서 코드 생성·실행·파일 조작을 자율적으로 수행합니다. 자연어 명령만으로 복잡한 개발 작업을 처리할 수 있는 에이전틱(Agentic) 플랫폼입니다.

## ✨ 주요 특징
- **멀티 환경 지원**: Windows·Mac·Linux·모바일에서 일관된 경험 제공
- **플러그인(Tool Calling) 지원**: 외부 도구·API·에이전트 워크플로우와 연동
- **자율 실행 루프**: 명령 실행 → 결과 확인 → 재시도의 에이전트 루프
- **컨텍스트 이어받기**: 모바일 등 다른 환경에서도 작업 맥락 유지
- **문서 자동 생성**: 작업 결과를 구조화된 문서로 자동 제작

## 🔗 공식 리소스 및 설치
- **공식 사이트**: [openai.com](https://openai.com/)
- **공식 문서**: [platform.openai.com/docs](https://platform.openai.com/docs)

## 🚀 Agentic Framework 적용 및 사용법

### 1. 프로젝트 이식 (Transplantation)
Codex가 에이전트 시스템의 지능을 갖게 하려면 아래 파일들을 프로젝트 루트로 복사하세요.

- **복사할 항목**:
    - `.agent/`: 핵심 엔진 (규칙, 스킬, 워크플로우)
    - `CODEX.md`: Codex 전용 지침 파일 (에이전트 페르소나 및 규칙 설정)

### 2. 사용 방법 (Usage)
Codex 세션을 시작한 후, 에이전트 명령어를 사용합니다.

- **명령 예시**:
    ```
    현재 태스크 현황을 요약해줘
    새로운 기능 구현을 위해 설계 프로세스를 시작해줘
    Use $keep-codex-fast to inspect my Codex local state
    ```

### 3. 정상 작동 확인 (Validation)
Codex가 에이전트 규칙을 인식하는지 확인하려면 다음을 실행하세요.
- **실행**: `당신의 역할과 현재 태스크 목록을 알려주세요`
- **기대 결과**: "Agent Orchestrator"로서의 정체성을 밝히고, `.agent/rules/`를 참조한 할 일 목록 제시

### 4. 최신 버전 업데이트 (Update)
에이전트 시스템의 최신 스킬과 규칙을 반영하려면 Codex에게 다음과 같이 요청하세요.

> **업데이트 프롬프트**:
> `에이전트 규칙 저장소의 최신 .agent 폴더와 CODEX.md 파일을 참조하여, 현재 프로젝트의 에이전트 시스템을 최신 상태로 갱신해줘.`

## 🧹 Codex 성능 유지 (keep-codex-fast)

Codex를 오래 사용하면 채팅·워크트리·로그·프로젝트 이력이 쌓여 속도가 느려질 수 있습니다.
본 프레임워크에 내장된 **keep-codex-fast** 스킬로 안전하게 정리할 수 있습니다.

### 빠른 시작
```
Use $keep-codex-fast to inspect my Codex local state and recommend a safe maintenance plan.
```

### 핵심 원칙
> 핸드오프 먼저. 아카이브로 이동(삭제 금지). 준비가 됐을 때만 적용.

### 상세 사용법
- **스킬 문서**: [`.agent/skills/keep-codex-fast/SKILL.md`](../../.agent/skills/keep-codex-fast/SKILL.md)
- **유지보수 워크플로우**: [`.agent/workflows/codex-maintenance.md`](../../.agent/workflows/codex-maintenance.md)
- **원본 레포**: [vibeforge1111/keep-codex-fast](https://github.com/vibeforge1111/keep-codex-fast)

## 🧠 Karpathy 행동 지침

본 프레임워크는 Codex 사용 시 LLM 코딩 실수를 방지하기 위해 [Karpathy 행동 지침](../../.agent/rules/10_karpathy_guidelines.md)을 따릅니다.

1. **Think Before Coding** — 가정을 명시적으로 밝히고, 불확실하면 질문합니다.
2. **Simplicity First** — 문제를 해결하는 최소한의 코드만 작성합니다.
3. **Surgical Changes** — 반드시 필요한 것만 수정합니다.
4. **Goal-Driven Execution** — 시작 전에 검증 가능한 성공 기준을 정의합니다.

> 전체 내용: [`.agent/rules/10_karpathy_guidelines.md`](../../.agent/rules/10_karpathy_guidelines.md)

---

## 초보자 온보딩 가이드

Codex를 처음 사용하는 분들을 위한 시작 체크리스트:

- [ ] Codex 설치 (Mac / Windows 환경별 확인)
- [ ] 최초 실행 후 설정 화면 주요 항목 확인
- [ ] 첫 프롬프트 입력 테스트
- [ ] `CODEX.md` 파일을 프로젝트에 복사
- [ ] `.agent/` 폴더를 프로젝트에 복사
- [ ] "당신의 역할을 알려줘" 명령으로 에이전트 활성화 확인
- [ ] keep-codex-fast 스킬로 초기 상태 점검

---
*본 에이전트 시스템은 Codex의 에이전틱 능력을 활용하여 복잡한 엔지니어링 문제를 해결합니다.*
