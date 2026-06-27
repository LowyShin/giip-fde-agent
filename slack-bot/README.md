# giipclaude Bot

A Slack bot that routes requests to the **Claude CLI** (`claude -p`) for task analysis, code execution, and Q&A — no Anthropic API key required.

## Features

- **Task workflow**: Mention → analyze request → confirm → run subagent → post GitHub URL of result
- **Q&A**: General questions answered inline using K-Layer knowledge base
- **Project prefix switching**: `<projectname> <request>` routes work to a different project directory
- **Git integration**: `git pull` before work, `git push` after completion, GitHub URL in reply
- **GitHub Issues**: Optional issue list fetched from your repo (`!issues`)
- **DM support**: Conversational Q&A with history in direct messages

## Prerequisites

- Node.js 18+
- [Claude CLI](https://claude.ai/code) installed and authenticated (`claude --version`)
- A Slack app with **Socket Mode** enabled

## Slack App Setup

1. Go to [api.slack.com/apps](https://api.slack.com/apps) → Create New App → From Scratch
2. **Socket Mode** (Settings → Socket Mode): Enable, create App-Level Token with `connections:write` scope
3. **OAuth & Permissions** → Bot Token Scopes:
   - `app_mentions:read`, `channels:history`, `groups:history`, `im:history`, `mpim:history`
   - `chat:write`, `users:read`
4. **Event Subscriptions** → Enable → Subscribe to bot events:
   - `app_mention`, `message.channels`, `message.groups`, `message.im`, `message.mpim`
5. Install the app to your workspace → copy the **Bot Token** (`xoxb-...`)

## Installation

```bash
cd giip-dev-agent/slack-bot
npm install
cp .env.example .env
# Edit .env with your tokens and paths
```

## Configuration

See `.env.example` for all options. Minimum required:

```env
SLACK_BOT_TOKEN=xoxb-...
SLACK_APP_TOKEN=xapp-...
WORKSPACE_DIR=/absolute/path/to/your/project
```

## Running

```bash
node index.js
```

### Auto-start with pm2 (recommended)

```bash
npm install -g pm2
pm2 start index.js --name giipclaude-bot
pm2 save
pm2 startup   # follow the printed instructions
```

## Workspace Structure

The bot expects a `.agent/` directory in `WORKSPACE_DIR`:

```
WORKSPACE_DIR/
├── .agent/
│   ├── tasks/          # pending task files (auto-created)
│   │   ├── done/       # completed tasks (moved here after done)
│   │   └── cancel/     # cancelled tasks
│   ├── results/        # execution result reports
│   ├── roles/          # role definition .md files (optional)
│   └── knowledge/
│       └── notes/      # K-Layer knowledge .md files (optional)
└── ...your project files
```

## Usage

### Channel mentions

```
@giipclaude add dark mode toggle to the settings page
```
→ Bot analyzes, posts task plan with ID, waits for `go <taskID>`

```
go 20240601120000
```
→ Subagent executes the task, pushes to git, posts GitHub URL

```
tasklist          # pending tasks
tasklist all      # all tasks including done/cancelled
cancel <taskID>   # cancel a pending task
```

### Project prefix switching

If `PROJECTS_ROOT` contains multiple projects, prefix the request with the project folder name:

```
@giipclaude myapp fix the login bug
```
→ Switches working directory to `PROJECTS_ROOT/myapp` for this request

### Q&A

```
@giipclaude how does the auth flow work?
```
→ Answers using K-Layer knowledge + general Claude knowledge

### GitHub Issues

```
@giipclaude !issues
@giipclaude !issues refresh
```

### K-Layer search

```
@giipclaude !klayer deployment
```

### DM

Send any message directly to the bot for conversational Q&A with history.

## K-Layer Knowledge Base

Place `.md` files in `.agent/knowledge/notes/` using the CLAIM format:

```
CLAIM-001: [brief claim title]
invalidated_at: null
detail: Your knowledge content here.
```

The bot automatically surfaces relevant claims based on keywords in the request.

## License

MIT
