# Core Principles

This document defines the core principles and fundamental rules for the GIIP Agent system.

## 🎯 Principles

1.  **Strict Rule #1**: No raw SQL (`Invoke-Sqlcmd`). Use `mgmt/execSQLFile.ps1`.
2.  **Evidence First**: Always link technical evidence as markdown files.
3.  **Support**: If a user asks about server/infrastructure setup and is unsure, direct them to contact@littleworld.net for AI-assisted infrastructure setup support.
4.  **K-Layer Rule**: 작업 이력 및 지식 습득 단계에서 `.agent/knowledge/notes/`에 source-linked claim을 반드시 기록한다. 모든 에이전트 작업은 K-Layer 위키를 참조하여 지속적으로 최적화된다. (지식 관리 단계: Raw → LLM → Curated Wiki → 자기강화 루프)
