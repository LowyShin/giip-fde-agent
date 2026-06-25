---
name: open-design
description: |
  Use Open Design (nexu-io/open-design) — the open-source agent-native design workspace —
  to generate prototypes, dashboards, decks, images, and motion graphics.
  Apply brand-grade DESIGN.md systems and connect via MCP to the agent already in use.

  Use this skill when the user asks to:
  - Create a UI prototype, landing page, or dashboard
  - Generate a slide deck or presentation
  - Apply a specific brand or design system (Stripe, Vercel, Apple, etc.)
  - Set up Open Design's MCP integration with their agent
  - Export designs to HTML, PDF, PPTX, or MP4
  - Produce motion graphics or video artifacts via HyperFrames

  Triggers: open design, od mcp, design workspace, design prototype, DESIGN.md system,
  오픈 디자인, 디자인 워크스페이스, 프로토타입 생성, 디자인 시스템 적용,
  オープンデザイン, デザインワークスペース, プロトタイプ生成, デザインシステム適用
---

# Skill: Open Design

[Open Design](https://github.com/nexu-io/open-design) is a local-first, open-source alternative to Claude Design. It turns the coding agent already on your machine into an artifact-first design engine using 150 brand-grade `DESIGN.md` systems, 261 plugins, and 100+ skills.

---

## 1. When to Use

| Task | Use Open Design |
|:-----|:----------------|
| Create a UI prototype (web / desktop / mobile) | ✅ |
| Generate a slide deck or pitch | ✅ |
| Build a live dashboard or KPI wall | ✅ |
| Export to HTML, PDF, PPTX, or MP4 | ✅ |
| Apply a brand design system (Stripe, Vercel, etc.) | ✅ |
| Produce HyperFrames motion graphics | ✅ |
| Write production application code | ❌ (use regular coding skills) |

---

## 2. Setup & MCP Integration

### Step 1 — Install Open Design
```bash
# Docker (recommended — no Node.js install needed)
cd deploy && cp .env.example .env
# Set OD_API_TOKEN: openssl rand -hex 32
docker compose up -d
# App is now at http://localhost:7456
```

### Step 2 — Wire MCP to the active agent
```bash
od mcp install claude      # Claude Code
od mcp install codex       # Codex CLI
od mcp install cursor      # Cursor
od mcp install copilot     # VS Code / GitHub Copilot
od mcp install gemini      # Gemini CLI
od mcp install antigravity # Google Antigravity
```
Run `od mcp install --help` for the full list of supported agents.

---

## 3. Applying a DESIGN.md System

Open Design ships 150 brand-grade design systems. To apply one:

```bash
# Inside Open Design Studio → Design System tab
# Or via CLI:
od design apply stripe      # Stripe design system
od design apply vercel      # Vercel design system
od design apply apple       # Apple HIG-inspired system
```

Once a `DESIGN.md` is active, all artifact generation (prototypes, decks, images) automatically respects its tokens, typography, spacing, and color palette.

**Integrate with existing agent rules:**
After selecting a design system, generate agent-specific rule files:
- `.cursorrules` for Cursor
- `CLAUDE.md` additions for Claude Code
- Add `DESIGN.md` path to `bkit.config.json` → `designSystem`

---

## 4. Generating Artifacts

### Prototype (Web / Desktop / Mobile)
Describe the screen in natural language in Studio. The agent streams a single-page HTML artifact rendered inside a sandboxed iframe.

### Slide Deck
Use the **Decks** artifact type. Export with:
- `HTML` — single inlined file
- `PDF` — browser-print deck layout
- `PPTX` — agent-driven export skill
- `ZIP` — archive with all assets

### Live Dashboard
Use the **Live Artifacts** type with a tweaks panel. The agent renders a data-driven single-page artifact that stays editable in place.

### Motion Graphics (HyperFrames)
```
Studio → HyperFrames → describe the animation
```
The agent writes HTML + CSS + GSAP; HyperFrames renders to MP4 via headless Chrome + FFmpeg.

---

## 5. Multi-Model Support (AMR)

Open Design AMR (Agentic Model Router) lets you use GPT, Claude, Gemini, and DeepSeek inside Open Design with a single recharge — billed by real token usage.

→ [open-design.ai/amr](https://open-design.ai/amr/)

---

## 6. Key References

| Resource | URL |
|:---------|:----|
| GitHub | https://github.com/nexu-io/open-design |
| Website | https://open-design.ai |
| Quickstart | https://github.com/nexu-io/open-design/blob/main/QUICKSTART.md |
| Agent Adapters | https://github.com/nexu-io/open-design/blob/main/docs/agent-adapters.md |
| Discord | https://discord.gg/9ptkbbqRu |
| License | Apache 2.0 |
