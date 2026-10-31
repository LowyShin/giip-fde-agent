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

#### 다른 사람을 멘션한 메시지는 활성 스레드 자동 개입 대상이 아니다

활성 태스크(pending/running) 스레드의 후속 입력은 멘션 없이도 처리되지만, 봇/등록된 다른 봇이 아닌 **다른 사람을 명시적으로 멘션한** 메시지는 그 사람에게 보내는 것으로 보고 개입하지 않는다(giip 4045 결함 B). 판정은 순수 함수 `mention-engagement.js` 의 `classifyMentions()` 이며 `handlers.js` `processMessage()` 가 호출한다.

#### 회귀 테스트

```bash
node slack-bot/tools/test-mention-engagement.js   # 멘션 판정 (결함 B)
node slack-bot/tools/test-context-catalog.js       # 컨텍스트 카탈로그 루트별 상대경로 (결함 A)
```

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

## 의도 분류(task / question) 결정적 경로

Slack 메시지는 `intent.js` 에서 아래 순서로 분류된다(앞 단계가 우선, LLM 은 마지막).

1. `isForceTaskCmd` — 태스크 등록/구현·수정 명령형 등 쓰기 패턴이면 무조건 task.
2. `isConfirmationQuery` — 쓰기 동사/명령형이 **없고** 확인·조회 표지(`알려줘`/`확인 가능해?`/`어때?` 등) 또는
   읽기 전용 조회(`isReadOnlyLookup`: URL/링크/경로/주소/위치/내용 + `찾아/보여/알려/확인`)이면 LLM 없이 question(즉답).
3. 위에 해당하지 않으면 LLM 분류기(`classifyRequest`).

쓰기 의도는 명사(`파일`/`폴더`/`처리`/`등록`/`추가`/`점검`) 단독이 아니라 **쓰기 동사/명령형**(`저장`/`작성`/`수정`/`삭제`,
`등록해`/`처리해서` 등)으로 판정한다. 그래서 "처리 결과 파일의 github url 찾아서 보여줘" 같은 기존 파일 조회는 새 이슈를 만들지 않고,
"찾아서 파일로 저장해줘" 는 task 로 간다. 테스트: `node --test slack-bot/tests/intent.test.js`(LLM 미호출).

## 개인용 체크리스트 대시보드 (`SLACKBOT_DASHBOARD`, 기본 끔)

`dashboard.js` 는 봇이 처리한 요청을 레포 루트 `LOWY_ACTION_DASHBOARD.md` 의 마커 구간(`SLACKBOT-TASKS:START/END`)에
체크리스트로 갱신하고 `git add`/commit/push 한다. 개인용 기능이라 **기본은 꺼져 있다** — 환경변수
`SLACKBOT_DASHBOARD=on`(대소문자 무시)일 때만 동작하고, 미설정/그 외 값이면 파일 생성·git 호출을 전혀 하지 않는다.
공용 레포 체크아웃에서는 켜지 말 것(레포 루트가 오염된다). `node dashboard.js` CLI 수동 실행은 스위치와 무관하게 동작한다.
테스트: `node --test slack-bot/tests/dashboard.test.js`.

Jev 를 활용한 의도 분류 권장 구조(제안, 미구현): [docs/INTENT_ROUTING_JEV_SPEC.md](docs/INTENT_ROUTING_JEV_SPEC.md)

## 작업 브랜치 생성 시 untracked 충돌 자가치유

`prepareTaskBranch`(task-manager.js)는 `git checkout -B bot/task-<id> origin/<base>` 전에 `git ls-files --others --exclude-standard`(untracked 비-ignored)와 `git ls-tree -r --name-only <startPoint>`(기점의 tracked 경로)의 **교집합**을 구한다. 작업 클론이 어떤 PR 머지 이전 상태일 때 그 PR 이 새로 추적 대상으로 만든 파일(예: 봇이 계속 append 하는 `.agent/runtime/cost-usage.jsonl`)이 로컬에 untracked 로 남아 있으면 git 이 `untracked working tree files would be overwritten by checkout` 으로 거부하기 때문이다(giip 4224).

- **치우기**: 충돌 파일을 `os.tmpdir()/giipclaude-preserve-<taskId>-<timestamp>/`(원 경로 구조 유지)에 복사한 뒤에만 삭제한다. 백업 경로는 로그(`console.error`)에 출력하고 반환 ctx 의 `preserved: { dir, files }` 에 담는다(충돌이 없으면 `null`).
- **복원/병합**: `.agent/tasks/<id>.md`(태스크 파일)는 현재 요청(untracked)본으로 덮어쓴다(기존 동작 유지). `.agent/runtime/` 아래 `.jsonl`/`.log` 는 checkout 된 tracked 줄 + 로컬에만 있던 줄(줄 단위 중복 제거, 순서 보존)로 병합해 기록 유실을 막는다. 그 외 파일은 tracked 버전을 유지하고 로컬본은 백업 폴더에만 남는다.
- **checkout 실패 시**: 치웠던 파일을 원위치로 복원(stash 복원 전)하고 `{ ok:false, error, conflictFiles }` 를 반환한다. `conflictFiles` 는 git stderr 의 `would be overwritten by checkout:` 아래 경로 목록이다.
- **재시도 중단**(handlers.js): 브랜치 생성 실패 시 오류 서명(`conflictFiles` 집합, 없으면 오류 문자열)을 `lastBranchFailSig` 로 저장하고, 다음 시도가 **같은 서명으로 실패하면 남은 재시도(`MAX_BRANCH_FAIL_RETRIES`)를 소진하지 않고 즉시 중단**해 충돌 파일 목록과 수동 조치를 Slack 에 보고한다(`taskBranchFailSameCause`). `lastBranchFailSig` 가 없는 기존 상태는 기존 횟수 기반 동작과 같다. 판정 로직은 `branch-collision.js`.

테스트: `node --test slack-bot/tests/branch-collision.test.js`(로컬 bare 원격 + 작업 클론으로 실제 git 재현, LLM·네트워크 없음).

## 런타임 경로 커밋 제외 + 산출물 없는 PR 억제 (giip 4300)

작업 브랜치 커밋이 `git add -A` 면 봇/세션이 쓰는 `.agent/runtime/**`(checkpoints/evidence/receipts/progress/cost-usage 등)까지 올라가, 실제 산출물이 없는 "런타임 전용" PR 이 열리고 머지되는 사고가 난다. `runtime-artifact-guard.js` 가 두 겹으로 막는다.

- **스테이징 제외**(`stageDeliverables`): task-manager.js 의 모든 커밋 지점(`gitPushResult`, `gitPushResultAndPR`, `commitAndPRChangedRepos` 의 두 경로)이 `git add -A -- . ':(exclude).agent/runtime'` 로 스테이징하고, 이미 index 에 올라가 있던 런타임 경로는 index 에서만 뺀다(작업트리 파일은 보존).
- **PR 억제**(`branchHasDeliverables`): `ensurePR` 이 PR 생성 직전에 `origin/<base>...<branch>` 변경 파일을 보고, 전부 `.agent/runtime/**` 면 PR 을 열지 않고 `null` 을 반환한다(호출부는 `skipped`/`failed` 에 사유를 기록). git 판정 자체가 실패하면 기존 동작(PR 생성)을 유지한다(fail-open).
- 저장물 없음(커밋/PR 의 **미생성**이 결과). 소비처는 `commitAndPRChangedRepos` 의 `skipped[]` 사유 → Slack 완료 보고.
- 참고: 이 가드는 PR 이 **열리는 것**을 막을 뿐, 열린 PR 이 **누구에 의해 머지되는지**(저장소의 auto-merge / 브랜치 보호 설정)는 코드 밖이다. 저장소 측에서 브랜치 보호와 auto-merge 설정을 확인해야 한다.

테스트: `node --test slack-bot/tests/runtime-artifact-guard.test.js`(임시 git 저장소로 실제 재현, LLM·네트워크 없음).

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
