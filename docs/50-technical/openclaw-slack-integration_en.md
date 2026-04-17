# OpenClaw Slack Messenger Integration Guide 💬

This document describes how to use **OpenClaw** to control and query the knowledge of the GIIP Agent System through the Slack messenger. After completing this setup, you will be able to check repository information and issue commands from your mobile device or the Slack app on your PC.

---

## 🛠️ Prerequisites

Before following this guide, ensure the following are installed:
1. **Node.js**: v18 or higher (LTS recommended)
2. **GIIP Agent System**: This repository must exist on your local PC.

---

## 🏗️ Step 1: Slack App Setup

OpenClaw uses Slack's **Socket Mode**, so it operates safely behind a firewall without the need for port forwarding or a public IP.

### 1.1 Create Slack App
1. Visit the [Slack API Dashboard](https://api.slack.com/apps) and click **"Create New App"**.
2. Select **"From an app manifest"**.
3. Select the **Workspace** where you want to install the app.
4. Copy and paste the YAML manifest below (you can change the name if you like).

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

### 1.2 Issue Tokens
Two key tokens are required once the app is created.
1. **App Level Token**: Create this in `Settings > Basic Information > App-Level Tokens`.
   - Name: `OpenClawToken`
   - Scope: Add `connections:write`
   - Copy the generated token (`xapp-...`).
2. **Bot User OAuth Token**: Created after clicking **"Install to Workspace"** in `Features > OAuth & Permissions`.
   - Copy the generated token (`xoxb-...`).

---

## 🚀 Step 2: OpenClaw CLI Installation and Onboarding

By installing OpenClaw on your frequently used PC, you can save and manage all conversation history locally. If you wish to protect your privacy, setting up a VM or a clean separate PC and copying only necessary information is a good approach.
This allows your agent to continuously learn and evolve into your own specialized professional agent.

### 2.1 CLI Installation

Run the following command in your terminal (PowerShell or Bash).

```powershell
npm install -g @openclaw/cli@latest
```

### 2.2 Run Onboarding
After installation, enter the command below to start the setup wizard.

```powershell
openclaw onboard
```

- **Select Provider**: Choose your LLM (Gemini, Claude, etc.) and enter your API Key.
- **Configure Slack**: Enter the **App Token (xapp-...)** and **Bot Token (xoxb-...)** you copied earlier.
- **Workspace Path**: Enter the absolute path to this repository.

---

## 🧠 Step 3: Connect Repository Knowledge

To make OpenClaw understand the `.agent` knowledge of this repository, you must specify this project folder as the OpenClaw workspace.

1. Open `~/.openclaw/config.json` (or `openclaw.json` in the project root) and verify that the `workspace` path is correct.
2. OpenClaw can basically search for files within the workspace.
3. **Knowledge Query Example**: Try asking the agent on Slack:
   - `@GIIP_Agent Summarize the core rules (GEMINI.md) of the current repository.`
   - `/ask "What are the recent updates to the K-Layer?"`

---

## 🏃 Step 4: Launch and Test

### 4.1 Start Service
Run the command below in the terminal to bring the agent online.

```powershell
openclaw start
```

### 4.2 Verify on Slack
1. Open the Slack app and find the **GIIP Agent** in the app list.
2. Send "Hello" to the agent or ask repository-related questions.
3. Verify if the agent generates answers using tools like `ripgrep` or file reading.

---

## ⚠️ Notes and Tips
- **Security**: Slack conversation history is sent to the LLM configured via OpenClaw. Be careful not to include sensitive data.
- **Background Execution**: To keep OpenClaw running, it's recommended to use `pm2` or the Windows Task Scheduler.
- **Command Control**: OpenClaw can also have file modification permissions. If you are concerned, please limit the scope to read-only.

---
> [!TIP]
> Now you can check your project's status and command simple code changes even when you're away!
