# Slack App Setup Guide — giipclaude Bot

This bot runs in **Socket Mode** (no public Request URL needed).

---

## 1. Create a Slack App

1. Open [https://api.slack.com/apps](https://api.slack.com/apps)
2. **Create New App** → **From scratch**
3. Enter an App Name (e.g. the value you set in `BOT_NAME`, default `giipclaude Bot`) and pick your Workspace → **Create App**

---

## 2. Add Bot Token Scopes

**OAuth & Permissions** → **Scopes** → **Bot Token Scopes**:

| Scope | Purpose |
|---|---|
| `chat:write` | Send messages |
| `app_mentions:read` | Receive `@bot` mentions |
| `channels:history` | Read public channel messages |
| `channels:read` | Read channel info |
| `groups:history` | Read private channel messages |
| `groups:read` | Read private channel info |
| `im:history` | Read DM messages |
| `im:read` | Read DM info |
| `im:write` | Send DMs |
| `users:read` | Resolve display names (show real speaker names in thread summaries; optional) |

> **About `users:read`**: thread reading/summarizing works without it — only the speaker
> labels differ. Without it, thread-summary speakers show as Slack user IDs (e.g. `UM8P5UALQ`);
> with it, they show real display names. Used together with `conversations.replies`
> (thread fetch) + `users.info` (name resolution).

> **About reading other threads by URL** (Method 2): if a message contains a Slack
> permalink (`https://<ws>.slack.com/archives/<channel>/p<ts>`), the bot reads that
> channel/thread via `conversations.replies` and adds it to the answer's context.
> It uses the same `channels:history` / `groups:history` scopes above (no extra scope),
> but **the bot must be a member of the referenced channel** (`/invite @botname`).
> If it is not a member or lacks the scope, it says "could not read" and continues.

> After adding/changing scopes you **must Reinstall** the app (see §5).

---

## 3. Enable Socket Mode

1. Left menu **Socket Mode** → **Enable Socket Mode**
2. Generate an **App-Level Token**:
   - Token Name: anything (e.g. `socket-mode-token`)
   - Scope: check `connections:write`
   - **Generate** → copy the token starting with `xapp-`

---

## 4. Enable Event Subscriptions

**Event Subscriptions** → **Enable Events**, then **Subscribe to bot events**:

| Event | Purpose |
|---|---|
| `app_mention` | @mentions in channels |
| `message.im` | DM messages |
| `message.channels` | Public channel thread replies |
| `message.groups` | Private channel thread replies |

> In Socket Mode no Request URL is required — leave the URL field empty.

---

## 5. Install to Workspace

**OAuth & Permissions** → **Install to Workspace** → **Allow**.

After install, copy the **Bot User OAuth Token** (starts with `xoxb-`).

---

## 6. Invite the Bot to Channels

In each channel you want the bot to watch:

```
/invite @<your bot name>
```

To find a channel ID: right-click the channel → **View channel details** → the `C0XXXXXXXXX` ID is at the bottom.

---

## 7. Configure `.env`

```bash
cp .env.example .env
```

```env
SLACK_BOT_TOKEN=xoxb-...                    # Bot User OAuth Token from §5
SLACK_APP_TOKEN=xapp-...                    # App-Level Token from §3
SLACK_CHANNEL_IDS=C0XXXXXXXXX,C0YYYYYYYYY   # channel IDs from §6 (comma-separated; optional — DMs always work)
WORKSPACE_DIR=/absolute/path/to/your/project

# Optional
# BOT_NAME=My Team Bot
# PROJECTS_ROOT=/absolute/path/to/projects
# GITHUB_TOKEN=ghp_...                      # GitHub PAT (repo scope) for the !issues command
# GITHUB_REPO=your-org/your-repo
```

Then start it:

```bash
npm install
node index.js
# or with pm2:  pm2 start index.js --name giipclaude-bot && pm2 logs giipclaude-bot
```

A successful start logs that Socket Mode connected.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `missing_scope` | Scope not granted | Add the scope in §2, then **Reinstall** (§5) |
| `invalid_auth` / `token_revoked` | Wrong/expired token | Re-copy tokens; do not mix the Bot Token (`xoxb-`) and App-Level Token (`xapp-`) |
| DMs not received | Missing DM scope/event | Add `im:history` + `im:read` and Reinstall; confirm `message.im` in Event Subscriptions |
| No reaction to channel mentions | Bot not invited / channel not listed | `/invite @<bot>`; ensure the channel ID is in `SLACK_CHANNEL_IDS` |
| Works on one PC but not another | Env not set for that machine | Each machine needs its own `.env` (tokens + `WORKSPACE_DIR`); the bot serves whatever workspace `WORKSPACE_DIR` points to |
