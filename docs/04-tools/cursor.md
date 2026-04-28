# Cursor (커서) 🚀

## 📋 개요
**Cursor**는 VS Code를 포크(Fork)하여 AI 기능을 엔진 레벨에서 통합한 차세대 코드 에디터입니다. 기존 VS Code의 편리함은 유지하면서도, AI가 코드베이스 전체를 이해하고 작업할 수 있도록 설계되었습니다.

## ✨ 주요 특징
- **전체 코드베이스 인덱싱**: 프로젝트의 모든 파일을 학습하여 "어디에 무엇이 있는지" 정확히 파악하고 질문에 답합니다.
- **네이티브 프롬프트 입력**: `Ctrl+K`(코드 생성/수정), `Ctrl+L`(채팅)을 통해 편집기 내에서 흐름 끊김 없이 AI와 대화합니다.
- **Composer 모드**: 여러 파일에 걸친 복잡한 작업을 한 번에 수행할 수 있는 멀티 에이전트 기능입니다.
- **VS Code 기반**: 기존의 모든 VS Code 확장 프로그램과 테마를 그대로 사용할 수 있습니다.
- **.cursorrules 지원**: 프로젝트 단위의 코딩 규칙을 에이전트에게 강제할 수 있습니다.

## 🔗 공식 다운로드
- **공식 사이트**: [www.cursor.com](https://www.cursor.com/)
- **공식 문서**: [docs.cursor.com](https://docs.cursor.com/)

## 🧠 Karpathy 행동 지침

GIIP Agent System은 Cursor 사용 시 LLM 코딩 실수를 방지하기 위해 [Karpathy 행동 지침](../../.agent/rules/10_karpathy_guidelines.md)을 따릅니다. 관련 설정은 `.cursorrules`에 포함되어 있으며 Cursor에서 자동으로 적용됩니다.

1. **Think Before Coding** — 가정을 명시적으로 밝히고, 불확실하면 질문합니다.
2. **Simplicity First** — 문제를 해결하는 최소한의 코드만 작성합니다.
3. **Surgical Changes** — 반드시 필요한 것만 수정합니다.
4. **Goal-Driven Execution** — 시작 전에 검증 가능한 성공 기준을 정의합니다.

> 전체 내용: [`.agent/rules/10_karpathy_guidelines.md`](../../.agent/rules/10_karpathy_guidelines.md) | [원본 레포](https://github.com/forrestchang/andrej-karpathy-skills)

---
*GIIP Agent System의 `.cursorrules` 설정은 Cursor 에디터에서 자동 적용되어 최적의 경험을 제공합니다.*
