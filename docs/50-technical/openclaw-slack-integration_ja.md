# OpenClaw Slackメッセンジャー連携ガイド 💬

このドキュメントでは、**OpenClaw**を使用してGIIP Agent Systemの知識をSlackメッセンジャーから制御および照会できるように設定する方法を説明します。この設定を完了すると、外出先からでもモバイルやPCのSlackアプリを通じてレポジトリの情報を確認し、作業を指示できるようになります。

---

## 🛠️ 事前準備 (Prerequisites)

このガイドに従う前に、以下がインストールされている必要があります：
1. **Node.js**: v18以上 (LTS推奨)
2. **GIIP Agent System**: このレポジトリがローカルPCに存在していること

---

## 🏗️ ステップ1: Slackアプリの設定 (Slack App Setup)

OpenClawはSlackの**Socket Mode**を使用するため、特別なポートフォワーディングや固定IPなしで、ファイアウォールの内側から安全に動作します。

### 1.1 Slack Appの作成
1. [Slack APIダッシュボード](https://api.slack.com/apps)にアクセスし、**「Create New App」**をクリックします。
2. **「From an app manifest」**を選択します。
3. アプリをインストールする**Workspace**を選択します。
4. 以下のYAMLマニフェストをコピーして貼り付けます（名前は自由に変更可能です）。

```yaml
display_information:
  name: GIIP Agent
  description: Autonomous Agent for Repository Control
  background_color: "#1a1a1a"
features:
  bot_user:
    display_name: GIIP Agent
    always_online: true
  slash_commands:
    - command: /ask
      description: Ask the agent a question about the repo
      usage_hint: "[question]"
      should_localize: false
oauth_config:
  scopes:
    bot:
      - chat:write
      - commands
      - im:history
      - app_mentions:read
      - groups:history
      - channels:history
settings:
  event_subscriptions:
    bot_events:
      - app_mention
      - message.im
  interactivity:
    is_enabled: true
  socket_mode_enabled: true
```

### 1.2 トークン(Token)の発行
アプリの作成が完了すると、2つの主要なトークンが必要になります。
1. **App Level Token**: `Settings > Basic Information > App-Level Tokens`で生成します。
   - 名前: `OpenClawToken`
   - スコープ: `connections:write` を追加
   - 生成されたトークン(`xapp-...`)をコピーしておきます。
2. **Bot User OAuth Token**: `Features > OAuth & Permissions`で**「Install to Workspace」**をクリックした後に生成されます。
   - 生成されたトークン(`xoxb-...`)をコピーしておきます。

---

## 🚀 ステップ2: OpenClaw CLIのインストールとオンボーディング

よく使うPCにOpenClawをインストールすると、AIとの対話履歴をすべてPCに保存して管理できます。個人情報を読み取られたくない場合は、VMやクリーンな別のPCを用意して、必要な情報だけをコピーしておくのも良い方法です。
これにより、あなたのエージェントは継続的に学習し、あなただけの専門エージェントへと発展することができます。

### 2.1 CLIのインストール

ターミナル（PowerShellまたはBash）で以下のコマンドを実行します。

```powershell
npm install -g @openclaw/cli@latest
```

### 2.2 オンボーディングの実行
インストール完了後、以下のコマンドを入力して設定ウィザードを開始します。

```powershell
openclaw onboard
```

- **Select Provider**: 使用しているLLM（Gemini、Claudeなど）を選択し、API Keyを入力します。
- **Configure Slack**: 先ほどコピーした **App Token (xapp-...)** と **Bot Token (xoxb-...)** を入力します。
- **Workspace Path**: このレポジトリの絶対パスを入力します。

---

## 🧠 ステップ3: レポジトリ知識の接続

OpenClawがこのレポジトリの `.agent` の知識を理解できるようにするには、OpenClawのワークスペースをこのプロジェクトフォルダに指定する必要があります。

1. `~/.openclaw/config.json`（またはプロジェクトルートの `openclaw.json`）ファイルを開き、 `workspace` パスが正しいか確認します。
2. OpenClawは基本的にワークスペース内のファイルを検索できます。
3. **知識照会の例**: Slackでエージェントに次のように聞いてみてください。
   - `@GIIP_Agent 現在のレポジトリのコアルール(GEMINI.md)について要約して。`
   - `/ask "最近行われたK-Layerのアップデート内容は何？"`

---

## 🏃 ステップ4: 起動とテスト

### 4.1 サービスの開始
ターミナルで以下のコマンドを実行すると、エージェントがオンラインになります。

```powershell
openclaw start
```

### 4.2 Slackで確認
1. Slackアプリを開き、アプリ一覧から作成した **GIIP Agent** を探します。
2. エージェントに「こんにちは」と送るか、レポジトリに関する質問を投げてみてください。
3. エージェントが `ripgrep` やファイル読み取りツールを使用して回答を生成するか確認します。

---

## ⚠️ 注意事項とヒント
- **セキュリティ**: Slackの会話内容はOpenClawを通じて設定されたLLMに送信されます。機密情報が含まれないよう注意してください。
- **バックグラウンド実行**: OpenClawを常時起動させておくには、 `pm2` やWindowsタスクスケジューラを使用することをお勧めします。
- **コマンド制御**: OpenClawはファイルの修正権限も持つことができます。不安な場合は読み取り専用スコープに制限してください。

---
> [!TIP]
> これで外出先からでもプロジェクトの状態をチェックし、簡単なコード修正を指示できるようになります！
