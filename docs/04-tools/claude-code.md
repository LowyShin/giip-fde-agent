# Claude Code ⌨️

## 📋 개요
**Claude Code**는 Anthropic에서 개발한 CLI(Command Line Interface) 기반의 에이전틱 코딩 도구입니다. 터미널에서 직접 대화하며 코드를 수정하고, 테스트를 실행하며, 복잡한 리팩토링 작업을 수행할 수 있습니다.

## ✨ 주요 특징
- **터미널 네이티브**: 개발자의 워크플로우를 방해하지 않고 쉘 내에서 즉시 상호작용합니다.
- **강력한 모델 지원**: 최신 업계 표준인 Claude 3.7 Sonnet 등의 모델을 사용하여 높은 정확도의 코드 생성을 지원합니다.
- **실행 권한 부여**: 에이전트가 직접 명령어를 실행하고 파일 시스템을 조작하며 결과를 확인할 수 있는 루프(Loop) 기능을 제공합니다.
- **컨텍스트 최적화**: 대용량 코드베이스를 효율적으로 읽고 필요한 부분만 추출하여 작업합니다.

## 🔗 공식 리소스 및 설치
- **공식 사이트**: [claude.ai](https://claude.ai/)
- **공식 문서**: [docs.anthropic.com](https://docs.anthropic.com)
- **설치 명령어**:
  ```bash
  npm install -g @anthropic-ai/claude-code
  ```

## 🧠 Karpathy 행동 지침

GIIP Agent System은 Claude Code 사용 시 LLM 코딩 실수를 방지하기 위해 [Karpathy 행동 지침](../../.agent/rules/10_karpathy_guidelines.md)을 따릅니다.

1. **Think Before Coding** — 가정을 명시적으로 밝히고, 불확실하면 질문합니다.
2. **Simplicity First** — 문제를 해결하는 최소한의 코드만 작성합니다.
3. **Surgical Changes** — 반드시 필요한 것만 수정합니다.
4. **Goal-Driven Execution** — 시작 전에 검증 가능한 성공 기준을 정의합니다.

> 전체 내용: [`.agent/rules/10_karpathy_guidelines.md`](../../.agent/rules/10_karpathy_guidelines.md) | [원본 레포](https://github.com/forrestchang/andrej-karpathy-skills)

---
*GIIP Agent System은 Claude의 강력한 추론 능력을 활용하여 복잡한 엔지니어링 문제를 해결합니다.*
