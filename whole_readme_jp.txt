# GIIP Agent System: 自律型マルチエージェントフレームワーク 🤖

[English](readme_en.md) | [한국어](README.md)

[![License: Apache 2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](http://makeapullrequest.com)
[![Korean Support](https://img.shields.io/badge/Language-Korean-blue.svg)](#-コア原則)
[![AI Powered](https://img.shields.io/badge/AI-Gemini-orange.svg)](https://aistudio.google.com/app/apikey)

> **🚀 AI開発ツールが初めてですか？**  
> [**クイックスタートガイド**](QUICK_START.md) (韓国語) で親切なステップバイステップのガイドをご確認ください！  
> [AIツールダウンロードリンク集](TOOLS_DOWNLOAD.md) | [Antigravity使用ガイド](ANTIGRAVITY_USAGE_GUIDE.md)

**GIIP Agent System**は、複雑なソフトウェア開発およびタスク自動化のために設計された**自律型マルチエージェントフレームワーク (Autonomous Multi-Agent Framework)** のみを独立して抽出して作成されたエージェントです。

皆さんのノウハウや用途に応じてロールの内容を修正して使用することで、自分だけのエージェントシステムを構築できます。

基本的には、Google Gemini APIを活用してオーケストレーター (Orchestrator) と専門のサブエージェントが協調する最先端のAIワークフローを提供します。
Google Gemini APIを使用しない場合は、手動で安価に使用できます。また、他のAPIを使用したい場合は、オーケ스트レーターに指示するだけで、皆さんの環境に合わせていくらでも変更してくれます。

このフレームワークは、**Claude Codeのskills**や**OpenCode**に類似した**ロールベースのサブエージェント (Role-based Sub-Agents)** の概念を採用しており、複雑なタスクを精巧に分担して解決します。

特に **Antigravity Tool**に最適化されて設計されており、別途のサードパーティツールのインストールなしに、既存の開発ツールとPowerShell環境だけで即座に稼働します。Electronベースのターミナル環境でも優れた安定性と互換性を提供します。

韓国の開発者エコシステム (Korean Developer Ecosystem) に最適化されており、すべてのプロセスとドキュメント化は **Korean-First** (韓国語優先) 原則に従います。


## ✨ 主な機能 (Key Features)

- **Multi-Agent Collaboration**: Claude Code/OpenCodeスタイルのロールベースの協調。
- **Superpowers Native**: Plan、TDD、Systematic Debuggingなどの高度なエンジニアリングスキルを内蔵。
- **Multi-Platform Ready**: Cursor、GitHub Copilot、Claudeなど、さまざまなAIツールと即座に互換。
- **Autonomous Development**: 要件分析から実装、検証まで、自律的なタスク遂行。
- **Antigravity Optimized**: Antigravityツールとの完璧な同期および最適化されたワークフロー。
- **Zero-Tool Setup**: 追加のツール設定なしに、既存のPowerShell環境で即座に使用可能。
- **Environment Stability**: ElectronベースのPowerShell環境で完璧に動作。
- **Gemini API Native**: 最新のGoogle Geminiモデルを活用した高性能な推論およびコード生成。
- **Korean-First Workflow**: 韓国語ベースのドキュメント化およびエージェント相互作用の最適化。
- **React Best Practices**: VercelのReact Best Practices Rulesを適用し、最適化されたフロントエンドコードを生成。
- **Bkit Vibecoding Kit**: PDCAメソドロジーに基づいた体系的な開発と自動化レポートを提供。

このリポジトリは、GIIP AIエージェントシステムの設定、役割定義、およびワークフローを管理するためのスペースです。

実際に使用するサブエージェント用のロールの定義や、必要な機能のみを `.agent` フォルダに集めているため、既存のプロジェクトにこのリポジトリの内容をそのまま上書きしても、既存のプロジェクトは影響を受けません。

作業しているフォルダにこのリポジトリのファイルとディレクトリをコピーした後、antigravityを起動してください。そして、次のようにチャットを入力すれば準備は完了です。

```
あなたはオーケストレーターです。自分のロールを確認し、以下の業務を分析して、各担当者に作業を委任してください。
もし委任する適切なロールがない場合は、ロールを新規に作成して担当ロールに委任してください。

-- 業務内容 --

```

これで、現在のチャット画面から業務指示ができるようになります。

## 🤝 互換性 (Compatibility)

このプロジェクトは、さまざまなAIエージェント環境をサポートしています。
- **Antigravity**: `GEMINI.md` 自動認識
- **Cursor / Windsurf**: `.cursorrules` 自動認識
- **GitHub Copilot**: `COPILOT_INSTRUCTIONS.md` 自動認識
- **Claude / OpenCode**: `SETUP_AGENTS.md` ガイドによる簡単設定

## 🛠️ 事前準備事項 (Prerequisites)

このシステムを使用するために、以下のツールがインストールされている必要があります。

1. **PowerShell 7+**: [インストールガイド](https://learn.microsoft.com/ja-jp/powershell/scripting/install/installing-powershell-on-windows)
2. **Node.js**: [公式サイト](https://nodejs.org/)でLTSバージョンを推奨します。
3. **Gemini CLI** (自動化使用時のオプション): バックグラウンドでの自動化セッション実行に必要です。
   ```powershell
   npm install -g @google/gemini-cli
   ```

## ⚙️ 初期設定 (Setup & Configuration)

### 1. 設定ガイド
GIIP Agentは、標準で**手動モード (クリップボードハンドオフ)**と**自動モード (Gemini CLI)**をサポートしています。

- **手動モード**: API Keyの設定なしで、すぐに使用を開始できます。 ([手動開始方法](#2-手動開始-クリップボードハンドオフ) を参照)
- **自動モード**: バックグラウンドでエージェントに自動で作業を行わせるには、Gemini API Keyの設定が必要です。 ([自動化設定](#-自動化設定-gemini-cli使用時---オプション) を参照)

## 📁 ディレクトリ構造 (Directory Structure)

```text
.agent/
├── roles/          # 各エージェント (Developer, Testerなど) のペルソナと責任の定義
├── dispatch/       # タスク定義ファイル (TASK_YYYYMMDD-ID.md)
├── scripts/        # [システム運用のためのPowerShellスクリプトツール](./.agent/scripts/README.md)
├── work_history/   # 作業履歴の記録 (ルール遵守)
└── README.md       # システム詳細ガイド (英文)
```

## 🚀 主な使用法 (Basic Usage)

命令を下した後に、バックグラウンドでサブエージェントセッションを開始する2つの方法があります。2つのうちいずれかを実行すると、各役割のサブエージェントが作業を開始します。

### 1. 自動開始 (gemini-cli 使用時)
保留中のタスクを自動的に検出し、適切な役割で `gemini-cli` セッションを即座に開始します。
```powershell
.\.agent\scripts\launch_subsession.ps1
```

- 定期的な自動実行 (バッチファイルを使用)
エージェントを5分ごとに自動的に確認して、作業を実行するように設定できます。
```cmd
.\auto_agent.bat
```
このスクリプトは実行中のウィンドウを維持し、5分 (300秒) 間隔で `launch_subsession.ps1` を繰り返し呼び出しします。

### 2. 手動開始 (クリップボードハンドオフ)
`gemini-cli` なしでエージェントマネージャなどの環境で新Microsoftの [Agent Lightning](https://github.com/microsoft/agent-lightning) の強力なトレーシングおよび最適化の概念がこのリポジトリに統合されました。

- **Agent Tracing**: エージェントのすべての実行ステップ、ツール使用、プロンプトをタイムラインとして記録し、分析可能。
- **Prompt Optimization**: 収集されたフィードバックに基づいて、プロンプトテンプレートを自動的に改善。
- **Self-Improvement**: 継続的な学習ループにより、エージェントが時間の経過とともにさらに賢くなります。

> [!TIP]
> **このリポジトリは、WSL2やLinux環境なしでも同様の機能を完璧に実行します！**
> 
> Microsoftの元のAgent Lightningは **Linux (WSL2)** 環境が必須であり、`/agl-init` や `/agl-trace` コマンドが必要ですが、このリポジトリでは **Windowsネイティブ環境** でそのまま **`/native-trace`** と **`/aioptimize`** コマンドを使用するだけで、同様の（あるいはより最適化された）自己改善ループを駆動できます。別途の仮想環境設定なしで即座に使用可能なことが、このシステムの最大の優位性です。
��의 進行状況と、現在実行中のバックグラウンドプロセスを確認します。
```powershell
.\.agent\scripts\check_status.ps1
```

### 3. 作業履歴の確認
エージェントのすべての作業内容は、`work_history` ディレクトリに日付別に記録されます。

## 🚨 コア原則 (Core Principles)
すべてのエージェントは、以下のルールを厳格に遵守します。
1.  **Evidence First**: 技術的な根拠は常にマークダウンファイルへのリンクとして提示します。
2.  **Korean First**: すべての成果物とドキュメントは韓国語で作成することを原則とします。
3.  **Clean Code**: 読みやすくメンテナンスが容易なコードを作成し、不要な重複を排除します。

## 🔄 エージェントワークフロー (Agent Workflow)

```mermaid
graph TD
    A[ユーザーリクエスト] --> B[Orchestrator: タスク生成]
    B --> C[launch_subsession.ps1 実行]
    C --> D[専門エージェント: 作業遂行]
    D --> E[作業結果の検証と完了]
    E --> F[Orchestrator: 最終報告]
```

1.  **オーケストレーター**がリクエストを分析し、`dispatch` ディレクトリにタスクを作成します。
2.  ユーザーまたはシステムが `launch_subsession.ps1` を実行します。
3.  **サブエージェント** (例: Developer, Tester) が作業を遂行し、ステータスを `Completed` に更新します。
4.  **オーケストレーター**が最終成果物を検証します。

## 📦 Bkit Vibecoding Kit Integration

**Bkit**は、PDCA (Plan-Design-Do-Check-Act) メソドロジーをエージェントワークフローに結合し、開発効率と品質を最大化するVibecoding Kitです。

- **PDCA Loop**: `/pdca plan`、`/pdca design`、`/pdca analyze` などのコマンドによる体系的な開発プロセス管理。
- **Gap Analysis**: 実装内容と設計内容の差分を自動的に分析し、品質を確保。
- **自動化されたレポート**: すべての作業結果に対する標準化されたレポートを提供。

詳細な使用方法は、[.gemini/README.md](.gemini/README.md) または [GEMINI.md](GEMINI.md) を参照してください。

## 📚 追加ドキュメントとガイド

- **[Antigravity 使用ガイド](ANTIGRAVITY_USAGE_GUIDE.md)**: Antigravityスキルとbkit方法論を効果的に活用する方法を詳しく説明します。PDCAサイクル、システマティックなデバッグ、TDDなど、高度な開発パターンを取り扱います。
- **[プロンプト例](prompt_example.md)**: エージェントを効率的に活用するための様々なプロンプト例を提供します。
- **[有用なエージェントリンク](links.md)**: エージェントの開発および運用に役立つ外部リソースとツールのコレクションです。

> [!TIP]
> **簡単な翻訳**: これらのドキュメントを母国語で読みたい場合は、AIアシスタント（ChatGPT、Claude、Geminiなど）に翻訳を依頼するだけです。例えば：「このドキュメントを[あなたの言語]に翻訳してください」。これにより、あなたが快適に感じる任意の言語でコンテンツに簡単にアクセスできます。

## 🦸 Superpowers Integration

このフレームワークは、[Superpowers](https://github.com/obra/superpowers) システムを内蔵しており、エージェントが単なるコーディングマシンではなく、**責任感のある技術者**のように行動するように設計されています。

- **Subagent Driven Development**: 1つの複雑なタスクを「実装」->「仕様検討」->「コード品質検討」の3段階のパイプラインで処理します。
- **Writing Plans**: コードを触る前に `implementation_plan.md` を作成して設計を検証します。
- **Test Driven Development (TDD)**: `Red` -> `Green` -> `Refactor` サイクルを通じて欠陥のないコードを作成します。
- **Systematic Debugging**: 無造作な修正ではなく、仮説検証型のデバッグで根本原因を解決します。

## 🛡️ Gstack Integration

[Gstack (garrytan/gstack)](https://github.com/garrytan/gstack)の強力な特化スキルが統合され、エージェントの思考能力と安全性が大幅に強化されました。

- **Office Hours & CEO Review**: 実装前に製品の本質を再考し（Founder Mode）、ユーザー体験を最優先する計画レビュー。 (`/office-hours`, `/ceo-review`)
- **Staff Engineer Audit**: N+1クエリ、レースコンディション、データ信頼境界など、熟練したエンジニアレベルの深層コードレビュー。 (`/code-review` 強化)
- **Security CSO**: STRIDEおよびOWASPベースの脅威モデリングと独立した脆弱性分析。 (`/cso`)
- **Safety Guardrails**: 破壊的なコマンド実行前の警告（`/careful`）および作業範囲を特定のフォルダに制限（`/freeze`）することで事故を防止。

## 🛠️ Custom Workflows & Native Optimization

リナックスの依存関係なしに、ローカル環境で直接動作するネイティブエージェントの最適化ループです。

### **1. 実行トレース (`/native-trace`)**
エージェントのすべての実行ステップ（ツール呼び出し、プロンプト、推論プロセス）を自動的に記録します。将来のパフォーマンス向上のためのデータを収集します。
- **使用法**: タスク要求の前に `/native-trace` を付けて実行します。
- **結果**: 詳細な実行履歴が `.agent/traces/` フォルダにJSONとして保存されます。

### **2. 自己最適化 (`/aioptimize`)**
収集された実行履歴を分析して、エージェントの内部スキルとプロンプトを自動的に改善します。
- **使用法**: `/aioptimize` ワークフローを実行します。
- **コマンド**: `python scripts/prompt_optimization/native_optimizer.py`
- **ロジック**: 報酬スコアが低い（< 0.8）タスクを分析して失敗の原因を特定し、関連するスキルのMarkdown指示を最適化して提案します。

### **3. 報酬システム (Reward System)**
トレースされたタスクの完了後、0.0から1.0の間のスコアを提供してエージェントをガイドします。0.8未満のスコアは、 `/aioptimize` ステップでの改善対象として分類されます。

## ⚡ Agent Tracing & Optimization (Trace & Improve)

[Microsoft Agent Lightning](https://github.com/microsoft/agent-lightning)の強力なトレーシングおよび最適化機能が統合されました。 (Linux/WSL2専用)

[Microsoft Agent Lightning](https://github.com/microsoft/agent-lightning)の強力なトレーシングおよび最適化機能が統合されました。

- **Agent Tracing**: エージェントのすべての実行ステップ、ツール使用、プロンプトをタイムラインとして記録し、分析可能。
- **Prompt Optimization**: 収集されたフィードバックに基づいて、プロンプトテンプレートを自動的に改善。
- **Visual Dashboard**: ダッシュボードを通じてエージェントのパフォーマンス変化を視覚的に監視。
- **Self-Improvement**: 継続的な学習ループにより、エージェントが時間の経過とともにさらに賢くなります。

> [!IMPORTANT]
> Agent Lightningは **Linux (WSL2)** 環境で最適に動作します。 `/agl-init` コマンドで環境を初期化し、 `/agl-trace` でタスクを追跡してください。

## 🌐 GIIP Enterprise Managed Service

より強力で安定したシステム運用が必要ですか？ **GIIP**は、インフラの自動管理およびセキュリティ脅威の検出のために、専門家とAIのコラボレーションモデルを提供します。

- **インフラ自動化**: 反復的な運用業務をAIが代行します。
- **セキュリティ脅威検出**: リアルタイムで脅威を感知し、迅速に対応します。
- **専門家コラボレーション**: AIの効率性と専門家の判断力を組み合わせて、最高の品質を保証します。

複雑な管理は専門家に任せ、ビジネスの本質に集中してください。

👉 [GIIP公式ホームページを訪問する](https://giip.littleworld.net/) または contact@littleworld.net へお問い合わせください。（サーバー・インフラ設定のAI支援が可能です）

## ⚙️ 自動化設定 (Gemini CLI使用時 - オプション)

バックグラウンドでエージェントが自動的にタ스크を検知して作業を行うようにするには(`launch_subsession.ps1` 使用時)、API Keyの設定が必要です。

まず、antigravityツールにエージェントスクリプトを分析させて `settings.json` のサンプルファイルを作成させるか、以下の手順に従ってください。

1. [Google AI Studio](https://aistudio.google.com/app/apikey)でAPI Keyを発行します。
2. プロジェクトルートの `.agent/settings.json.sample` ファイルを同じフォルダに `settings.json` としてコピーします。
3. コピーした `settings.json` ファイルを開き、`"YOUR_GEMINI_API_KEY_HERE"` の部分を発行された実際のキーに置き換えます。

> [!NOTE]
> `launch_subsession.ps1` ス크립트는、プロジェクト内の `.agent/settings.json` を最初に確認し、ない場合はユーザーのホームディレクトリ (`~/.gemini/settings.json`) を参照します。

## 🙏 Special Thanks

このプロジェクトを助けてくださった方々に感謝します。

- [Roy Koo](https://www.linkedin.com/in/roykoo99/)
  - multi api key のアイデア
- [코드깎는노인 (コードを削る老人)](https://www.youtube.com/@%EC%BD%94%EB%93%9C%EA%B9%8E%EB%8A%94%EB%85%B8%EC%9D%B8)
  - react用検査ロジック
- [superpowers](https://github.com/obra/superpowers)
  - 開発検証ロジックを強化
- [bkit Vibecoding Kit](https://github.com/popup-studio-ai/bkit-claude-code) (Licensed under Apache 2.0)
  - PDCAメソドロジーに基づいた開発の最適化
- [gstack](https://github.com/garrytan/gstack)
  - 製品中心の思考、安全ガードレール、セキュリティ監査ロジックの統合

