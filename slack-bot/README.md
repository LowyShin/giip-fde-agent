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

### Docker (auto clone + csn/sk/login_id registration)

For a fresh environment that should set itself up in one shot (clone the repo, fill in
`.secrets/giip-accounts.json`, start this bot, and optionally the hourly-issue-scheduler),
see [`docker/`](../docker/README.md) / [`docs/60-operations/docker-deployment.md`](../docs/60-operations/docker-deployment.md).

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

> **Full custom-command list:** see **[COMMANDS.md](./COMMANDS.md)** for every command the bot responds to (the same list `!help` returns), with aliases and DM-vs-channel differences. Send `@botname !help` in a channel or `!help` in a DM to get the live list.

### When the bot responds (mention policy)

> 정본. 코드(`handlers.js` / `index.js`)는 이 절을 따른다. 바꿀 때는 **이 절을 먼저 고친다.**

봇은 **아래 세 경우에만** 응답한다.

| 경우 | 조건 |
|---|---|
| DM | 허용 사용자(`SLACK_ALLOWED_USERS`)가 보낸 DM |
| 자기 앞 멘션 | 채널에서 `<@BOT_USER_ID>` 가 본문에 있을 때 (`app_mention`) |
| 활성 태스크 후속 | 봇이 진행 중인 태스크 스레드의 후속 발화 (`isTaskReply`) |

**그 외에는 응답하지 않는다.** 특히 **다른 사람을 멘션한 메시지에 끼어들지 않는다.**

#### 봇-봇 대화는 명시적 allowlist 로만 열린다

봇끼리 대화하게 하려면 `.env` 에 상대 봇의 ID 를 **명시적으로** 등록해야 한다.

```env
# 비어 있으면(기본값) 어떤 멘션도 "다른 봇 멘션"으로 인정하지 않는다
OTHER_BOT_IDS=U01BOTAAA,U02BOTBBB
```

- **기본값은 빈 값**이고, 그때 봇은 **자기가 멘션됐을 때만** 반응한다.
- `OTHER_BOT_IDS` 에 등록된 ID 가 멘션된 경우에만 "다른 봇 멘션"으로 인정한다.
- 상대 봇이 늘어나면 이 변수에 ID 를 추가한다. 코드 변경은 필요 없다.

#### 왜 allowlist 인가 — `<@...>` 정규식은 사람과 봇을 구분하지 못한다

종전 구현은 이랬다.

```js
const mentionsOtherBot = !mentionsBot && /<@[A-Z0-9]+>/.test(msg.text);
```

Slack 의 멘션 토큰 `<@U...>` 는 **사람과 봇이 같은 형식**이다. 그래서 이 정규식은 **동료를 멘션한 일반 대화까지 "다른 봇 멘션"으로 인정**했고, 봇이 자기와 무관한 메시지에 끼어들어 잘못된 태스크를 실행할 수 있었다. 멘션 대상이 봇인지는 ID 만 보고 알 수 없으므로, **알아낼 수 없는 것을 추측하는 대신 명시적으로 등록받는다.**

같은 계열의 선행 수정이 있다 — giip-773 의 원 구현은 "자기 앞 멘션이 아니면 전부 처리"였고, 같은 채널에 동거하는 다른 봇 앞 메시지에까지 반응하는 사고로 이어져 `index.js` 에서 좁혔다. 이 절은 그 수정을 `handlers.js` 쪽까지 완성한 것이다.

"기본값은 아무에게도 반응하지 않는다" 를 택한 근거는 **오탐의 비용이 비대칭**이기 때문이다. 반응하지 않아 놓치는 것은 사람이 다시 멘션하면 끝나지만, 끼어들어 실행한 태스크는 커밋·push 까지 갈 수 있다.

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

### Per-project giip CSN routing

Register a giip issue under a specific project's **CSN** by prefixing with the project name:

```
@giipclaude myapp issue 등록 <내용>
```
→ Registers a giip issue with the CSN mapped to `myapp` in `project-csn.json`
(falls back to the account's default CSN if the project is not mapped).

Manage the mapping from Slack (no restart needed — `project-csn.json` is re-read each call):

| Command | Action |
| --- | --- |
| `giip project set <projectName> <csn>` | Add/update a name→CSN mapping |
| `giip project list` | List all mappings |
| `giip project del <projectName>` | Remove a mapping |

The name is lowercased on save. A project name works even without a matching
`PROJECTS_ROOT/<name>` folder — if it is in `project-csn.json`, the CSN still routes
(working directory then safely stays at `BASE_DIR`). Implemented in `config.js`
(`resolveProjectCsn` / `setProjectCsn` / `listProjectCsn` / `deleteProjectCsn`) and
`giip-commands.js` (`giip project`).

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
