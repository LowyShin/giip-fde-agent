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

### [paperthin](https://github.com/LilMGenius/paperthin)
- **一言紹介**: アーティファクトを「クリーンかつ真実（clean & true）」に保つエージェント非依存の低レベルMarkdownスキル集（re0/shower/factchk/ssotchk/hateなど）。DRY・エゴレスプログラミング・fail-fastといったエンジニアリングの知恵を、エージェントが自ら手を伸ばす反射動作に変えます。
- **導入状況**: 本レポの `.agent/skills/` に14種を移植済み（出典・一覧: [`.agent/skills/PAPERTHIN_NOTICE.md`](../../.agent/skills/PAPERTHIN_NOTICE.md)）

### [keep-codex-fast](https://github.com/vibeforge1111/keep-codex-fast)
- **一言紹介**: Codexのローカル状態（古いチャット・ワークツリー・ログ・肥大化したSQLiteメタデータ）を**バックアップ優先**で点検・整理し、パフォーマンスを維持するスキルです。inspect/maintain/repairの3モードと「削除せずアーカイブ、ハンドオフを先に」の原則に従います（MIT）。
- **導入状況**: 本レポの `.agent/skills/keep-codex-fast/` に移植済み（`codex-maintenance` ワークフロー付き、月1回の原本確認を推奨）

### [LLM Wiki](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f) ([分析レポート](../../docs/70-LowyOpinion/capacydiagram.md))
- **一言紹介**: Andrej Karpathyが提唱した、AIエージェントによる継続的な知識蓄積とウィキ管理のパターン（K-Layerの原型）です。

### [SkillOpt](https://github.com/microsoft/SkillOpt)
- **一言紹介**: 重みの微調整なしで、ミニバッチ、学習率（テキスト編集予算）、検証ゲートを通じて、エージェントの指示ファイル（SKILL.md）をテキスト空間上で最適化するスキル学習フレームワークです。

## 🎨 デザイン・ドキュメントツール

### [Open Design](https://github.com/nexu-io/open-design) ([紹介ページ](../../docs/50-technical/open-design-intro_ja.md))
- **一言紹介**: Claude DesignのオープンソースAlternativeで、Claude Code・Codex・Cursor・CopilotなどのAIエージェントとMCPで連携し、150のブランドDESIGN.mdシステムと261プラグインを提供するエージェントネイティブなデザインワークスペースです。

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
*作業履歴: 20260618: open-designをデザインツールセクションに追加（Issue #19）*
*作業履歴: 20260706: paperthinを追加し、スキル14種を `.agent/skills/` に移植*
*作業履歴: 20260706: keep-codex-fastをメンテナンスツールセクションに登録（スキルは既に移植済み）*
