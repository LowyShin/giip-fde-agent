# Open Design - Agent-Native Open-Source Design Workspace

Open Design (OD) is a **local-first, open-source alternative to Anthropic's Claude Design**. It integrates with coding agents already on your laptop (Claude Code, Codex, Cursor, GitHub Copilot, Gemini CLI, and more) via MCP and runs entirely on your local machine without a browser.

## 🚀 Key Features

- **Agent-native**: Uses your installed Claude Code, Codex, Cursor, Copilot, Gemini CLI (21+ coding agent CLIs) as the execution engine
- **150 brand-grade DESIGN.md systems**: Apply pro-level design systems (Stripe, Vercel, Apple, etc.) instantly
- **261 plugins**: Broad feature extension support
- **100+ skills**: Ready-to-use agent skills built in
- **Multiple artifact types**: Web/desktop/mobile prototypes, live dashboards, slide decks, images, HyperFrames motion graphics
- **Multi-model support**: GPT, Claude, Gemini, DeepSeek and 20+ models via AMR (Agentic Model Router)
- **Export formats**: HTML, PDF, PPTX, MP4

## 🔌 Agent MCP Integration

OD connects MCP servers to agents in a single command via the `od` CLI:

```bash
od mcp install claude      # Claude Code
od mcp install codex       # Codex CLI
od mcp install cursor      # Cursor
od mcp install copilot     # VS Code + GitHub Copilot
od mcp install gemini      # Gemini CLI
od mcp install antigravity # Google Antigravity
```

## 🛠️ Installation & Quick Start

### Docker (Recommended)
```bash
cd deploy
cp .env.example .env
# Set OD_API_TOKEN (generate with: openssl rand -hex 32)
docker compose up -d
# Access at http://localhost:7456
```

### Dev Mode (Node.js 24 + pnpm 10.33.x)
```bash
corepack enable
pnpm install
pnpm tools-dev run web
```

## 🎯 Usage with giip-dev-agent

- The `.agent/skills/open-design/SKILL.md` skill lets agents automatically apply Open Design's DESIGN.md systems
- Integrate into prototype, slide deck, and dashboard generation workflows
- Use `DESIGN.md` as a team-shared brand contract

## 🔗 Related Links

- **GitHub Repository**: [nexu-io/open-design](https://github.com/nexu-io/open-design)
- **Official Website**: [open-design.ai](https://open-design.ai)
- **AMR (Model Router)**: [open-design.ai/amr](https://open-design.ai/amr/)
- **Discord**: [discord.gg/9ptkbbqRu](https://discord.gg/9ptkbbqRu)
- **License**: Apache 2.0

---
*Work History: 20260618: Created Open Design intro page (Issue #19)*
