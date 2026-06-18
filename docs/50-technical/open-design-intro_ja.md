# Open Design - エージェントネイティブなオープンソースデザインワークスペース

Open Design（OD）は、AnthropicのClaude Designに対応する**ローカルファースト・オープンソースのデザインツール**です。すでにインストール済みのClaude Code、Codex、Cursor、GitHub Copilot、Gemini CLIなど21以上のコーディングエージェントCLIをMCP経由で連携し、ブラウザなしでローカルデスクトップで動作します。

## 🚀 主な機能

- **エージェントネイティブ**: インストール済みのClaude Code、Codex、Cursor、Copilot、Gemini CLIなど21以上のCLIを実行エンジンとして使用
- **150のブランドDESIGN.mdシステム**: Stripe、Vercel、Appleなどのプロレベルデザインシステムをすぐに適用
- **261のプラグイン**: 豊富な機能拡張
- **100以上のスキル**: すぐに使えるエージェントスキルを内蔵
- **多様なアーティファクト生成**: Web/デスクトップ/モバイルプロトタイプ、ライブダッシュボード、スライドデッキ、画像、HyperFramesモーショングラフィックス
- **マルチモデル対応**: AMR（Agentic Model Router）でGPT・Claude・Gemini・DeepSeekなど20以上のモデルを利用
- **エクスポート形式**: HTML、PDF、PPTX、MP4

## 🔌 エージェントMCP連携

ODは`od`CLIでエージェントへのMCPサーバー接続を1行で実現します：

```bash
od mcp install claude      # Claude Code
od mcp install codex       # Codex CLI
od mcp install cursor      # Cursor
od mcp install copilot     # VS Code + GitHub Copilot
od mcp install gemini      # Gemini CLI
od mcp install antigravity # Google Antigravity
```

## 🛠️ インストール・クイックスタート

### Docker（推奨）
```bash
cd deploy
cp .env.example .env
# OD_API_TOKENを設定（openssl rand -hex 32 で生成）
docker compose up -d
# http://localhost:7456 でアクセス
```

### 開発モード（Node.js 24 + pnpm 10.33.x）
```bash
corepack enable
pnpm install
pnpm tools-dev run web
```

## 🎯 giip-dev-agentとの活用

- `.agent/skills/open-design/SKILL.md`スキルを使ってエージェントがOpen DesignのDESIGN.mdシステムを自動適用
- プロトタイプ・スライドデッキ・ダッシュボード生成ワークフローに統合可能
- `DESIGN.md`をチーム共有のブランド契約書として管理

## 🔗 関連リンク

- **GitHubリポジトリ**: [nexu-io/open-design](https://github.com/nexu-io/open-design)
- **公式ウェブサイト**: [open-design.ai](https://open-design.ai)
- **AMR（モデルルーター）**: [open-design.ai/amr](https://open-design.ai/amr/)
- **Discord**: [discord.gg/9ptkbbqRu](https://discord.gg/9ptkbbqRu)
- **ライセンス**: Apache 2.0

---
*作業履歴: 20260618: Open Design紹介ページ作成（Issue #19）*
