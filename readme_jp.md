# GIIP Agent System: 自律型マルチエージェントフレームワーク 🤖

[한국어](README.md) | [English](readme_en.md)

[![License: Apache 2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![Korean Support](https://img.shields.io/badge/Language-Korean-blue.svg)](#-핵심-규칙)
[![AI Powered](https://img.shields.io/badge/AI-Gemini-orange.svg)](https://aistudio.google.com/app/apikey)
[![Bkit Integration](https://img.shields.io/badge/Methodology-PDCA-brightgreen.svg)](https://github.com/popup-studio-ai/bkit-claude-code)

**GIIP Agent System**は、複雑なソフトウェア開発とタスク自動化のために設計された**自律型マルチエージェントフレームワーク**です。単なるコーディングアシスタントを超え、自ら計画し（Plan）、検証し（Check）、継続的に自己最適化する（AI-Optimize）「思考する開発チーム」を、あなたのプロジェクトに即座に投入できます。

---

## 🎯 導入の入り口 (Gateway)

> **🚀 はじめてですか？**  
> [**クイックスタートガイド**](QUICK_START.md)で、5分で最初のエージェントを稼働させてみましょう！  
> [ツールダウンロード](TOOLS_DOWNLOAD.md) | [Antigravity使用法](ANTIGRAVITY_USAGE_GUIDE.md) | [便利なリンク](links.md)

---

## 🛠️ サポートされているツール (Supported Tools)

GIIP Agent Systemは、以下の最新AI開発ツールと完璧に互換性があります。各ツールの詳細ガイドとダウンロード情報はリンクを参照してください。

| ツール | 説明 | 詳細ガイド |
| :--- | :--- | :--- |
| **Antigravity** | Google Geminiベースのプロフェッショナル向けエージェントプラットフォーム | [詳細を見る](docs/04-tools/antigravity.md) |
| **Claude Code** | AnthropicのCLIベース・エージェンティック・コーディングツール | [詳細を見る](docs/04-tools/claude-code.md) |
| **Cursor** | コードベース全体を理解するAIネイティブエディタ | [詳細を見る](docs/04-tools/cursor.md) |
| **Gemini CLI** | 最速かつ軽量なターミナル用AIユーティリティ | [詳細を見る](docs/04-tools/gemini-cli.md) |
| **Windsurf** | フロー (Flow) 中心のインテリジェント・エージェンティックIDE | [詳細を見る](docs/04-tools/windsurf.md) |
| **VS Code** | Autopilot自律モードをサポートする標準エディタ | [詳細を見る](docs/04-tools/vscode.md) |
| **OpenClaw** | エージェントをメッセンジャー (Slack等) と接続するゲートウェイ | [詳細を見る](docs/04-tools/openclaw_ja.md) |

---

## 👥 対象ユーザー (Target Audience)

- **AIネイティブ開発者**: ペアプログラミングを超えて、エージェントチーム全体を管理したい方。
- **スタートアップ & MVPチーム**: 最小限の人数で、高品質なコードと体系的なドキュメントを同時に確保したいチーム。
- **複雑なレガシー管理者**: Systematic DebuggingとTDDを通じて、安全にコードをリファクタリングしたい方。
- **自動化マニア**: 繰り返しの運用業務を信頼できるエージェントに委任したい方。

---

## ✨ なぜ GIIP Agent System なのか？ (Key Strengths)

1.  **Zero-Tool Setup**: 追加のサードパーティツールをインストールすることなく、PowerShellと既存のAI開発ツール（Cursor、Antigravityなど）だけで即座に起動します。
2.  **Korean-First Workflow**: 韓国の開発エコシステムに最適化されており、韓国語のドキュメント化と相互作用において圧倒的なパフォーマンスを発揮します。
3.  **Advanced Engineering DNA**: Bkit (PDCA)、Superpowers (TDD/Debugging)、Gstack (セキュリティ/安全性) など、実証済みのフレームワークの精髄を一つに統合しました。
4.  **Native Optimization**: LinuxやWSL2なしで、Windows環境で完全な実行追跡（Trace）および自己プロンプト最適化（AI-Optimize）をサポートします。
5.  **Unobtrusive Transplant**: 既存のプロジェクトフォルダに `.agent` フォルダをコピーするだけで、即座にエージェントシステムが活性化されます。

---

## 🚀 既存プロジェクトに即座に適用する

プロジェクトフォルダに移動し、以下のコマンドを実行して GIIP Agent システムを有効にします (** .git フォルダは除く**)。

### Windows (PowerShell)
```powershell
# 必須ファイルのコピー (giip-dev-agentフォルダ内で実行、または相対パスを指定)
Copy-Item -Path ".agent", "GEMINI.md", ".cursorrules", "COPILOT_INSTRUCTIONS.md" -Destination "あなたのプロジェクトパス" -Recurse -Force
```

### Mac/Linux
```bash
# 必須ファイルのコピー (rsync推奨)
rsync -av --exclude='.git' .agent GEMINI.md .cursorrules COPILOT_INSTRUCTIONS.md あなたのプロジェクトパス/
```

> [!TIP]
> 適用後、AIツール（Antigravity、Cursorなど）に次のように指示してみてください：**「君はオーケストレーターだ。GEMINI.mdを読んで、現在のタスクを分析してくれ。」**

---

## 🧠 コアコンセプトとワークフロー

GIIP Agent Systemは、**オーケストレーター (Orchestrator)** が全体の戦略を立て、**サブエージェント (Sub-Agents)** がそれぞれの専門分野でタスクを実行する構造です。

```mermaid
graph TD
    A[ユーザーリクエスト] --> B{Orchestrator}
    B -- 計画策定 --> C[dispatch/*.task.md 作成]
    C -- 実行命令 --> D[launch_subsession.ps1]
    D -- ロール遂行 --> E[専門エージェント/Dev/Test/Sec]
    E -- 結果報告 --> F[Trace & History 記録]
    F -- 検証 --> B
    B -- 最終完了 --> G[ユーザー報告]
```

---

## 📂 エージェントシステムの構成要素 (System Architecture)

GIIP エージェントフレームワークを構成する4つの主要要素に関する詳細ガイドです。

- [**構成要素の概要**](docs/02-design/agent-components/overview.md)
- [**ロール (Roles)**](docs/02-design/agent-components/role.md): エージェントのペルソナと責任の定義
- [**ルール (Rules)**](docs/02-design/agent-components/rule.md): 強制指針および品質管理の原則
- [**スキル (Skills)**](docs/02-design/agent-components/skill.md): ツール使用法および専門知識パッケージ
- [**ワークフロー (Workflows)**](docs/02-design/agent-components/workflow.md): 複雑な作業手順とカスタムコマンドの作成

---

## 🛠️ 強力なエコシステム統合 (Advanced Capabilities)

GIIP Agent Systemは、単なるプロンプトの集まりではなく、世界クラスのエージェントテクノロジーの集大成です。

### 1. Bkit Vibecoding Kit (PDCA)
- **Plan-Design-Do-Check-Act**: 実装前に設計 (Design) と分析 (Analyze) の段階を経ることで、「作りながら考える」ミスを防ぎます。
- **`/pdca` コマンド**: 体系的なレポーティングとギャップ分析を自動化します。

### 2. Superpowers Engineering
- **Subagent-Driven**: 一つのタスクを `設計` -> `実装` -> `検証` のパイプラインに分断。
- **Strong Skills**: TDD (Test Driven Development)、Systematic Debugging、Brainstormingスキルが内蔵されています。

### 3. Gstack (Safety & Security)
- **Founder Mode**: `/office-hours` や `/ceo-review` を通じて、製品の本質とUXを再定義します。
- **Guardrails**: 破壊的なコマンドの前の警告 (`/careful`) や作業範囲の制限 (`/freeze`) により、安全な開発環境を提供します。
- **Security Audit**: `/cso` コマンドで STRIDE/OWASP ベースのセキュリティ検査を実行します。

### 4. Native Optimization & Tracing
- **`/native-trace`**: AIの推論過程とツール呼び出し履歴のすべてを自動で記録します。
- **`/aioptimize`**: 収集されたデータを基に、エージェントが自らプロンプトを修正し、より賢くなります。

### 5. K-Layer Knowledge System (Karpathy Diagram)
- **Source-linked Knowledge**: エージェントの作業履歴から再利用可能なパターンと教訓を `Claim` 単位で自動抽出し、蓄積します。
- **自己強化ループ**: すべての知識は元の証拠（Trace/Source）と紐付けられており、次の作業時にエージェントがこれを参照することで、より賢く行動します。
- [K-Layerの仕組み](.agent/skills/k-layer/SKILL.md) | [ナレッジベース](.agent/knowledge/README.md)

### 5-1. Andrej Karpathy 行動ガイドライン
- **Think Before Coding**: 実装前に仮定を明示し、不確かな場合は質問し、複数の解釈がある場合は提示します。
- **Simplicity First**: 問題を解決する最小限のコードのみを書きます。未要求の機能・抽象化・柔軟性は追加しません。
- **Surgical Changes**: 必要なものだけを修正します。無関係なコード・コメント・フォーマットには触れません。
- **Goal-Driven Execution**: 検証可能な成功基準を最初に定義し、達成されるまで反復します。
- [Karpathy ガイドライン](.agent/rules/10_karpathy_guidelines.md) | [原典リポジトリ](https://github.com/forrestchang/andrej-karpathy-skills)

### 6. マルチソース・デザイン探索 (design-md)
- **統合デザイン探索**: `designmd.ai`、`designmd.app`、`getdesign.md`、`designmd.me` の4つの主要プラットフォームを統合し、最適なデザインシステムを発掘します。
- **ブランドの複製と自動生成**: StripeやVercelなどの有名ブランドのスタイルを即座に移植したり、特定のURLからデザイン・マークダウンを自動生成したりできます。
- [デザイン探索および統合ガイド](docs/DESIGN_DISCOVERY_GUIDE.md)

### 7. メッセンジャー制御 (OpenClaw)
- **メッセンジャーベースの遠隔制御**: Slack、Discord、Telegramを通じて、いつでもどこでもレポジトリの情報を照会し、作業を指示できます。
- **ポケットの中のエージェント**: モバイルデバイスからプロジェクトのナレッジベース (K-Layer) にアクセスし、リアルタイムでの質疑応答が可能です。
- [OpenClaw メッセンジャー連動ガイド](docs/50-technical/openclaw-slack-integration_ja.md)

### 8. 投資/トレーディング統合 (Vibe Investing)
- **安全な機能移植**: 外部の投資レポジトリを5軸（活性度・成熟度・学習曲線・市場適合性・ライセンス）で評価し、GIIP の role/rule/skill/workflow へ最小変更で統合します。
- **リスク優先チェックリスト**: バックテストのバイアス、実行現実性（スリッページ/流動性/手数料）、規制/コストのガードレールを標準で適用します。
- [投資スキル](.agent/skills/vibe-investing/SKILL.md) | [投資ワークフロー](.agent/workflows/investment-evaluation.md)

---

## ⚙️ 運用と使用法 (Quick Guide)

| タスク | コマンド (PowerShell) | 説明 |
| :--- | :--- | :--- |
| **自動実行** | `.\.agent\scripts\launch_subsession.ps1` | 待機中のタスクを検知し、バックグラウンドセッションを開始 |
| **手動ハンドオフ** | `.\.agent\scripts\launch_role.ps1` | タスクのコンテキストをクリップボードにコピー（他のチャット用） |
| **状態確認** | `.\.agent\scripts\check_status.ps1` | 進行中の全タスクとバックグラウンドプロセスを監視 |
| **自動モニタリング** | `.\auto_agent.bat` | 5分間隔で待機タ스크をチェックし、自動実行 |

> [!IMPORTANT]
> **API Keyの設定 (自動化に必要)**:  
> `.agent/settings.json.sample` ファイルを `settings.json` にコピーし、発行された Gemini API Key を入力してください。

---

## 🌐 GIIP Enterprise & Support

専門的なサーバー構築やAIベースのインフラ管理が必要ですか？
- **公式ホームページ**: [giip.littleworld.net](https://giip.littleworld.net/)
- **お問い合わせ**: contact@littleworld.net

---

## 🙏 Special Thanks

このシステムは、以下のプロジェクトからインスピレーションを受けて構築されました：
- **[Superpowers](https://github.com/obra/superpowers)** (Engineering Rigor)
- **[Bkit](https://github.com/popup-studio-ai/bkit-claude-code)** (PDCA Methodology)
- **[Gstack](https://github.com/garrytan/gstack)** (Product Thinking & Safety)
- **[Agent Lightning](https://github.com/microsoft/agent-lightning)** (Tracing & APO)

---
© 2026 GIIP Agent System. Optimized for Antigravity & AI-Native Builders.
