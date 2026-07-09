# giip FDE Agent 🤖📦

**A Forward-Deployed AI engineering team that installs onto your PC**

> 🆕 **[What's New](docs/WHATS_NEW.md)** · updates from the last 7 days.

[![한국어](https://img.shields.io/badge/lang-한국어-lightgrey.svg)](README.md)
[![日本語](https://img.shields.io/badge/lang-日本語-lightgrey.svg)](readme_jp.md)
[![English](https://img.shields.io/badge/lang-English-0A66C2.svg)](readme_en.md)

> [!TIP]
> If you have downloaded this repository and find that documentation in your language is missing (only Korean is available), please ask your AI assistant (Antigravity, Cursor, etc.) to translate it for you.

[![License: Apache 2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![Type: Forward Deployed Engineer](https://img.shields.io/badge/Type-Forward%20Deployed%20Engineer-8A2BE2.svg)](https://en.wikipedia.org/wiki/Forward_Deployed_Engineer)
[![AI Powered](https://img.shields.io/badge/AI-Gemini-orange.svg)](https://aistudio.google.com/app/apikey)
[![Methodology: PDCA](https://img.shields.io/badge/Methodology-PDCA-brightgreen.svg)](https://github.com/popup-studio-ai/bkit-claude-code)

---

## What is the FDE Agent?

A **Forward Deployed Engineer (FDE)** is an engineer who, instead of supporting from afar, is **embedded directly at the customer's site** to solve that organization's problems alongside them. Coined by Palantir, the role owns the full lifecycle — requirements analysis, design, implementation, integration, and deployment — right next to the customer. ([Wikipedia](https://en.wikipedia.org/wiki/Forward_Deployed_Engineer))

**giip FDE Agent** brings this concept to life as an AI agent. Instead of people, an **AI engineering team lives on your PC (the "site")** — transplanted via a single `.agent` folder — and instantly deploys a **"thinking agent team"** that plans (Plan), implements (Do), verifies (Check), and self-optimizes (Act). Your data and context never leave your local machine.

This agent is the executor of the [**giip FDE Box**](https://giip.littleworld.net/docs/plans/AIFDEOpsProposalen.html), which packages giip's FDE capability — AI-driven full-cycle development and enterprise operations — into one box. From infrastructure ops to AI-native development, it runs the entire enterprise-ops lifecycle in your local environment.

---

## 🚀 First time here? (Gateway)

> Check out the [**Quick Start Guide**](QUICK_START_EN.md) to launch your first agent in 5 minutes!
>
> [Tools Download](TOOLS_DOWNLOAD.md) · [Antigravity Usage](ANTIGRAVITY_USAGE_GUIDE.md) · [90-min Onboarding](docs/00-onboarding/README.md) · [Operations Governance](docs/60-operations/README.md) · [Slack Bot Setup](slack-bot/SLACK_APP_SETUP.md) · [Useful Links](links.md)

---

## 💻 Install the FDE Agent onto your PC — Bring up the Slack bot first

`giip-fde-agent` is a **public repository**. So instead of working inside this repo folder directly,
the fastest and safest start is to **get the repo → copy the needed files into a folder you'll use as your main workspace → run the Slack bot with that folder as the workspace.**
This way, when you pull the repo again for updates, it won't mix with your own work.

Follow the steps below to reach a state where you can **assign work to the FDE Agent from Slack via `@bot <request>`**.

### Prerequisites

- **Node.js 18+** (`node -v`)
- **Claude CLI** installed and logged in — the bot drives the `claude -p` CLI directly, no Anthropic API Key needed.
  `claude --version` must work and you must have logged in once (run `claude` and authenticate). → [Claude Code](https://claude.ai/code)
- **Slack workspace admin rights** (you must be able to install an app)

---

### Step 1. Get the repo & copy into your main work folder

First clone the repo, create **a folder you'll use as your main workspace** (e.g. `C:\work\my-project`), and copy the agent files there (**excluding the `.git` folder**).

#### Windows (PowerShell)
```powershell
# 1) Clone the repo (any location)
git clone https://github.com/LowyShin/giip-fde-agent.git

# 2) Create your main work folder (path is up to you)
New-Item -ItemType Directory -Force "C:\work\my-project"

# 3) Copy agent + slack-bot files into your work folder
cd giip-fde-agent
Copy-Item -Path ".agent", "GEMINI.md", ".cursorrules", "COPILOT_INSTRUCTIONS.md", "slack-bot" -Destination "C:\work\my-project" -Recurse -Force
```

#### Mac/Linux
```bash
# 1) Clone the repo
git clone https://github.com/LowyShin/giip-fde-agent.git

# 2) Create your main work folder
mkdir -p ~/work/my-project

# 3) Copy agent + slack-bot files (excluding .git)
cd giip-fde-agent
rsync -av --exclude='.git' .agent GEMINI.md .cursorrules COPILOT_INSTRUCTIONS.md slack-bot ~/work/my-project/
```

> From here on, do all work in the **copied work folder** (`C:\work\my-project`). Keep the original `giip-fde-agent` folder only for receiving updates.

---

### Step 2. Create a Slack app (Socket Mode)

The bot runs in **Socket Mode** (no public URL needed). Create an app at [api.slack.com/apps](https://api.slack.com/apps) and issue the two tokens below.

1. **Create New App → From scratch**
2. Enable **Socket Mode** → generate an App-Level Token (scope `connections:write`) → copy `xapp-...`
3. **OAuth & Permissions → Bot Token Scopes**: `chat:write`, `app_mentions:read`, `channels:history`, `channels:read`, `groups:history`, `im:history`, `im:read`, `im:write`, `users:read`
4. Enable **Event Subscriptions** → Subscribe to bot events: `app_mention`, `message.im`, `message.channels`, `message.groups`
5. **Install to Workspace** → after install, copy the **Bot User OAuth Token** `xoxb-...`

> For a screenshot-level detailed guide, see [`slack-bot/SLACK_APP_SETUP.md`](slack-bot/SLACK_APP_SETUP.md).

---

### Step 3. Install slack-bot & configure `.env`

Go into `slack-bot` inside your work folder, install dependencies, and fill in `.env`.

```powershell
cd C:\work\my-project\slack-bot
npm install
Copy-Item .env.example .env   # (Mac/Linux: cp .env.example .env)
```

Fill in at least three values in `.env`:

```env
SLACK_BOT_TOKEN=xoxb-...                 # Bot Token copied in Step 2-5
SLACK_APP_TOKEN=xapp-...                 # App-Level Token copied in Step 2-2
WORKSPACE_DIR=C:\work\my-project         # the work folder from Step 1 (where .agent lives)

# Optional
# SLACK_CHANNEL_IDS=C0123456789          # channel IDs the bot listens to (DMs always work if omitted)
# BOT_NAME=My Team Bot
# GITHUB_TOKEN=ghp_...                    # GitHub PAT (repo scope) for the !issues command
# GITHUB_REPO=your-org/your-repo
```

> `WORKSPACE_DIR` must point to the **work folder containing `.agent/`**. The bot processes tasks and runs git push relative to this folder.

---

### Step 4. Run the bot

```powershell
node index.js
```

A `Socket Mode connected` log means success. To keep it always on, running it under **pm2** is recommended.

```powershell
npm install -g pm2
pm2 start index.js --name giipclaude-bot
pm2 save
pm2 logs giipclaude-bot     # check logs
```

---

### Step 5. Invite to a channel and use it

Invite the bot to the channel you want, then mention it.

```
/invite @<bot name>

@<bot name> add a dark mode toggle to the settings page
→ The bot analyzes the request and posts a task plan (with an ID)

go 20240601120000
→ A subagent executes, runs git push, and replies with the result's GitHub URL
```

Other commands: `tasklist` (pending tasks), `cancel <taskID>`, `!issues`, or DM the bot for a direct conversation.
See [`slack-bot/README.md`](slack-bot/README.md) for the full usage.

---

> [!TIP]
> If you'd rather use it **directly with AI tools (Antigravity, Cursor, etc.)** without the Slack bot, the copy in Step 1 alone is enough.
> Tell your AI tool:
> **"You are the Orchestrator. Read GEMINI.md and analyze the current task."**

> [!IMPORTANT]
> **Gemini API Key Setup** (required for `.agent` automation such as image generation, not needed for manual work):
> Copy `.agent/settings.json.sample` to `settings.json` and enter your issued Gemini API Key.
> (The Slack bot's task execution itself uses the Claude CLI, so it works even without this key.)

---

## 🧠 How It Works

The FDE Agent works with an **Orchestrator** setting the overall strategy and **Sub-Agents** executing tasks in their specialized fields.

```mermaid
graph TD
    A[User Request] --> B{Orchestrator}
    B -- Planning --> C[Create dispatch/*.task.md]
    C -- Execute Order --> D[launch_subsession.ps1]
    D -- Role Execution --> E[Specialized Agents/Dev/Test/Sec]
    E -- Result Reporting --> F[Record Trace & History]
    F -- Verification --> B
    B -- Final Completion --> G[User Report]
```

For details on the four core components (Roles, Rules, Skills, Workflows),
👉 see the [**System Architecture Guide**](docs/02-design/agent-components/overview.md).

---

## ✨ Why the FDE Agent? (Key Strengths)

1. **Zero-Tool Setup**: Works out-of-the-box with PowerShell and existing AI development tools (Cursor, Antigravity, etc.) — no extra third-party installs.
2. **Local-First / Forward-Deployed**: The agent lives on-site (your PC) and works right next to your code, infrastructure, and docs.
3. **Korean-First Workflow**: Optimized for the Korean development ecosystem, with peerless Korean documentation and interaction.
4. **Advanced Engineering DNA**: Integrates the essence of Bkit (PDCA), Superpowers (TDD/Debugging), and Gstack (Security/Safety).
5. **Native Optimization**: Supports full Execution Tracing and Self-Prompt Optimization (AI-Optimize) natively on Windows — no Linux or WSL2 required.

### 👥 Target Audience
- **AI-Native Developers**: Those who want to move beyond pair programming and manage an entire agent team.
- **Startups & MVP Teams**: Teams securing high-quality code and systematic documentation with minimal headcount.
- **Complex Legacy Managers**: Those refactoring safely with Systematic Debugging and TDD.
- **Automation Enthusiasts**: Those delegating repetitive operational tasks to reliable agents.

---

## 🛠️ Supported Tools

The FDE Agent is perfectly compatible with the following state-of-the-art AI development tools.

| Tool | Description | Detailed Guide |
| :--- | :--- | :--- |
| **Antigravity** | Professional agent platform based on Google Gemini | [Details](docs/04-tools/antigravity.md) |
| **Claude Code** | Anthropic's CLI-based agentic coding tool | [Details](docs/04-tools/claude-code.md) |
| **Codex** | OpenAI's agentic coding platform (multi-environment) | [Details](docs/04-tools/codex.md) |
| **Cursor** | AI-native editor with full codebase understanding | [Details](docs/04-tools/cursor.md) |
| **Gemini CLI** | Fastest and lightest terminal AI utility | [Details](docs/04-tools/gemini-cli.md) |
| **Windsurf** | Flow-centric intelligent agentic IDE | [Details](docs/04-tools/windsurf.md) |
| **VS Code** | Standard editor supporting Autopilot autonomous mode | [Details](docs/04-tools/vscode.md) |
| **OpenClaw** | Gateway connecting agents to messengers (Slack, etc.) | [Details](docs/04-tools/openclaw_en.md) |

---

## ⚙️ Operations & Usage (Quick Guide)

| Task | Command (PowerShell) | Description |
| :--- | :--- | :--- |
| **Auto Launch** | `.\.agent\scripts\launch_subsession.ps1` | Detects pending tasks and starts background sessions |
| **Manual Handoff** | `.\.agent\scripts\launch_role.ps1` | Copies task context to clipboard (for other chat windows) |
| **Check Status** | `.\.agent\scripts\check_status.ps1` | Monitors all ongoing tasks and background processes |
| **Auto Monitoring** | `.\auto_agent.bat` | Checks pending tasks every 5 mins for auto-execution |

---

## 🧩 Capabilities at a Glance

The FDE Agent consolidates the essence of proven frameworks. For each capability's detailed principles and commands,
👉 see the [**Advanced Capabilities Guide (CAPABILITIES_en.md)**](docs/CAPABILITIES_en.md).

| # | Capability | Summary |
| :-: | :--- | :--- |
| 1 | **Bkit PDCA** | The `/pdca` cycle designs & analyzes before building, preventing 'think-while-making' mistakes |
| 2 | **Superpowers** | Design→Implement→Verify pipeline + built-in TDD & Systematic Debugging |
| 3 | **Gstack Safety/Security** | `/careful` & `/freeze` guardrails, `/cso` STRIDE/OWASP security audits |
| 4 | **Native Trace/Optimize** | `/native-trace` records reasoning, `/aioptimize` self-improves prompts |
| 5 | **K-Layer Knowledge** | Extracts reusable patterns as `Claim` units — a self-reinforcing loop |
| 6 | **design-md Discovery** | Integrates 4 platforms, instantly transplants famous brand styles |
| 7 | **OpenClaw Messenger** | Remote query & task orders via Slack/Discord/Telegram |
| 8 | **Vibe Investing** | Safely grafts external investing repos after a 5-axis evaluation |
| 9 | **Agency Expert Team** | Expert personas like Workflow Architect + premium UI/UX |
| 10 | **keep-codex-fast** | Inspects & cleans Codex local state to prevent slowdowns |

> Pre-coding behavioral principles (Think Before Coding / Simplicity First / Surgical Changes / Goal-Driven)
> follow the [Karpathy Guidelines](.agent/rules/10_karpathy_guidelines.md).

---

## 🌐 GIIP Enterprise & Support

Need professional server setup or AI-based infrastructure management?
- **giip FDE Box proposal**: [한국어](https://giip.littleworld.net/docs/plans/AIFDEOpsProposalko.html) · [日本語](https://giip.littleworld.net/docs/plans/AIFDEOpsProposalja.html) · [English](https://giip.littleworld.net/docs/plans/AIFDEOpsProposalen.html)
- **Official Website**: [giip.littleworld.net](https://giip.littleworld.net/)
- **Contact Email**: contact@littleworld.net

---

## 🙏 Special Thanks

This system was built with inspiration from the following projects:
- **[Superpowers](https://github.com/obra/superpowers)** (Engineering Rigor)
- **[Bkit](https://github.com/popup-studio-ai/bkit-claude-code)** (PDCA Methodology)
- **[Gstack](https://github.com/garrytan/gstack)** (Product Thinking & Safety)
- **[Agent Lightning](https://github.com/microsoft/agent-lightning)** (Tracing & APO)

---
© 2026 giip FDE Agent. Optimized for Antigravity & AI-Native Builders.
