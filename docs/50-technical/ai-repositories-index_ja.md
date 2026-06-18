# 外部AIツール・リポジトリ一覧 (External AI Repositories)

AIエージェントシステムと連携したり、活用したりできる便利な外部リポジトリおよびツールのコレクションです。

## 🤖 AIエージェント・メンテナンスツール

### [ClawSweeper](https://github.com/openclaw/clawsweeper) ([紹介ページ](../../docs/50-technical/clawsweeper-intro_ja.md))
- **一言紹介**: 大規模なGitHubリポジトリのIssueやPRをAIで自動分析・整理するメンテナンスボットです。

### [awesome-agents](https://github.com/kyrolabs/awesome-agents)
- **一言紹介**: AIエージェントのフレームワーク、ツール、関連研究リソースを厳選したキュレーションリストです。

### [figaro](https://github.com/byt3bl33d3r/figaro)
- **一言紹介**: Claude Codeなどのエージェントを多様な環境でオーケストレーション・管理するツールです。

### [claude-squad](https://github.com/smtg-ai/claude-squad)
- **一言紹介**: 複数のAIターミナルエージェントを同時に管理し、並列作業を可能にするアプリケーションです。

### [cmux](https://github.com/craigsc/cmux)
- **一言紹介**: 複数のClaudeエージェントを効率的に並列実行・管理するためのツールです。

### [gstack](https://github.com/garrytan/gstack) ([分析レポート](../../docs/50-technical/gstack-analysis.md))
- **一言紹介**: Garry Tanによる23の専門的なエージェントツールセットで、CEO、デザイナー、セキュリティ担当者など、多様な役割の遂行を支援します。

### [LLM Wiki](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f) ([分析レポート](../../docs/70-LowyOpinion/capacydiagram.md))
- **一言紹介**: Andrej Karpathyが提唱した、AIエージェントによる継続的な知識蓄積とウィキ管理のパターン（K-Layerの原型）です。

### [SkillOpt](https://github.com/microsoft/SkillOpt)
- **一言紹介**: 重みの微調整なしで、ミニバッチ、学習率（テキスト編集予算）、検証ゲートを通じて、エージェントの指示ファイル（SKILL.md）をテキスト空間上で最適化するスキル学習フレームワークです。

## 🎨 デザイン・ドキュメントツール

### [designmd.ai](https://designmd.ai)
- **一言紹介**: AI開発用の高品質なDESIGN.mdファイルとCLIツールを提供するプラットフォームです。

## 🔬 科学・研究専用スキル（選択的ダウンロード）

> ⚠️ **このセクションのスキルは、科学・研究関連プロジェクトでのみ選択的にダウンロードしてください。**
> 一般的な開発プロジェクトには含めないでください。

### [scientific-agent-skills](https://github.com/K-Dense-AI/scientific-agent-skills)
- **一言紹介**: がんゲノミクス、創薬標的結合、分子動力学、RNAベロシティ、地理空間科学、時系列予測、78以上の科学データベースなどを含む、147個の科学・研究専用エージェントスキル集です。
- **対象プロジェクト**: 生物学、化学、医学、地球科学など、科学・研究に関連するプロジェクト
- **対応ツール**: Cursor、Claude Code、Codex、Google Antigravityなど、Agent Skills標準をサポートするすべてのAIエージェント
- **ダウンロード方法**: プロジェクトルートで `git clone https://github.com/K-Dense-AI/scientific-agent-skills` を実行後、必要なスキルファイルのみ `.agent/skills/` にコピー

---
*作業履歴: 20260429 01:24:45: 外部AIリポジトリ一覧ページ作成*
*作業履歴: 20260618: scientific-agent-skillsを科学・研究専用セクションに追加（Issue #17）*
