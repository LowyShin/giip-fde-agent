/**
 * giipclaude Bot — Task workflow mode
 *
 * Channel mention flow:
 *   1. Receive mention → analyze request via claude → ask for confirmation in Slack
 *   2. User replies "go" → run subagent (claude -p)
 *   3. Complete → append report to task file → move to done/ → post GitHub URL to Slack
 *
 * DM:
 *   General Q&A (claude -p)
 *
 * Project prefix:
 *   "<projectname> <request>" → switches working dir to PROJECTS_ROOT/<projectname>
 */

require('dotenv').config();

const https = require('https');
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');
const { searchKLayer } = require('./k-layer');
const { getIssues, refreshIssues, getCacheAge } = require('./github-issues');
const tm = require('./task-manager');
const { SocketModeClient } = require('@slack/socket-mode');

// ── 設定 ─────────────────────────────────────────────────────────────────────
const BOT_TOKEN      = process.env.SLACK_BOT_TOKEN;
const CHANNEL_IDS    = (process.env.SLACK_CHANNEL_IDS || '').split(',').map(s => s.trim()).filter(Boolean);
const SLACK_APP_TOKEN = process.env.SLACK_APP_TOKEN;
const BOT_NAME       = process.env.BOT_NAME || 'giipclaude Bot';

const BASE_DIR         = process.env.WORKSPACE_DIR ? path.resolve(process.env.WORKSPACE_DIR) : path.join(__dirname, '..');
const PROJECTS_ROOT    = process.env.PROJECTS_ROOT || path.dirname(BASE_DIR);
const HISTORY_FILE     = path.join(__dirname, '.conversations.json');
const TASK_STATE_FILE  = path.join(__dirname, '.task-state.json');
const BOT_THREADS_FILE = path.join(__dirname, '.bot-threads.json');

let BOT_USER_ID = null;

// ── プロジェクトプレフィックス検出 ──────────────────────────────────────────
function parseProjectPrefix(text) {
  const words = text.trim().split(/\s+/);
  if (words.length < 2) return { workDir: BASE_DIR, cleanText: text };
  const candidate = words[0].toLowerCase();
  const projectDir = path.join(PROJECTS_ROOT, candidate);
  try {
    if (fs.statSync(projectDir).isDirectory()) {
      console.log(`[Bot] project switch: ${projectDir}`);
      return { workDir: projectDir, cleanText: words.slice(1).join(' ') };
    }
  } catch {}
  return { workDir: BASE_DIR, cleanText: text };
}

// ── JSON I/O ─────────────────────────────────────────────────────────────────
function loadJSON(file, def) {
  try { return JSON.parse(fs.readFileSync(file, 'utf8')); } catch { return def; }
}
function saveJSON(file, data) {
  try { fs.writeFileSync(file, JSON.stringify(data, null, 2)); } catch {}
}

// ── ボットが返答したスレッドを追跡 ───────────────────────────────────────────
function markThreadEngaged(channelId, threadTs) {
  if (!threadTs) return;
  const threads = loadJSON(BOT_THREADS_FILE, {});
  const key = `${channelId}:${threadTs}`;
  threads[key] = Date.now();
  const cutoff = Date.now() - 7 * 24 * 60 * 60 * 1000;
  for (const k of Object.keys(threads)) {
    if (threads[k] < cutoff) delete threads[k];
  }
  saveJSON(BOT_THREADS_FILE, threads);
}

function isBotEngagedThread(channelId, threadTs) {
  if (!threadTs) return false;
  const threads = loadJSON(BOT_THREADS_FILE, {});
  return !!threads[`${channelId}:${threadTs}`];
}

// ── Slack API ─────────────────────────────────────────────────────────────────
function slackGet(method, params = {}) {
  return new Promise((resolve) => {
    const qs = new URLSearchParams(params).toString();
    const req = https.get({
      hostname: 'slack.com',
      path: `/api/${method}${qs ? '?' + qs : ''}`,
      headers: { 'Authorization': `Bearer ${BOT_TOKEN}`, 'User-Agent': 'giipclaude-bot/1.0' },
    }, (res) => {
      let d = ''; res.on('data', c => { d += c; }); res.on('end', () => {
        try { resolve(JSON.parse(d)); } catch { resolve({ ok: false }); }
      });
    });
    req.on('error', () => resolve({ ok: false }));
    req.setTimeout(10000, () => { req.destroy(); resolve({ ok: false }); });
  });
}

function slackPost(method, body) {
  return new Promise((resolve) => {
    const payload = JSON.stringify(body);
    const req = https.request({
      hostname: 'slack.com', path: `/api/${method}`, method: 'POST',
      headers: {
        'Authorization': `Bearer ${BOT_TOKEN}`,
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(payload),
        'User-Agent': 'giipclaude-bot/1.0',
      },
    }, (res) => {
      let d = ''; res.on('data', c => { d += c; }); res.on('end', () => {
        try { resolve(JSON.parse(d)); } catch { resolve({ ok: false }); }
      });
    });
    req.on('error', () => resolve({ ok: false }));
    req.write(payload); req.end();
  });
}

async function postMessage(channel, text, thread_ts) {
  const body = { channel, text };
  if (thread_ts) body.thread_ts = thread_ts;
  const res = await slackPost('chat.postMessage', body);
  if (!res.ok) console.error(`[Bot] postMessage error: ${res.error}`);
  if (res.ok && res.ts) markThreadEngaged(channel, thread_ts || res.ts);
  return res;
}

async function postLong(channel, text, thread_ts) {
  const MAX = 3800;
  if (text.length <= MAX) { await postMessage(channel, text, thread_ts); return; }
  let remaining = text;
  while (remaining.length > MAX) {
    let cut = remaining.lastIndexOf('\n', MAX);
    if (cut < MAX * 0.6) cut = MAX;
    await postMessage(channel, remaining.slice(0, cut), thread_ts);
    remaining = remaining.slice(cut).trimStart();
  }
  if (remaining) await postMessage(channel, remaining, thread_ts);
}

// ── リポジトリ push 状況チェック ──────────────────────────────────────────────
// REPOS_TO_CHECK=name:relpath:branch,name2:relpath2:branch2 (optional env)
// Falls back to auto-detecting git repos in BASE_DIR
function getReposToCheck() {
  if (process.env.REPOS_TO_CHECK) {
    return process.env.REPOS_TO_CHECK.split(',').map(entry => {
      const parts = entry.trim().split(':');
      const name = parts[0];
      const relpath = parts[1] || '';
      const branch = parts[2] || 'main';
      return { name, dir: relpath ? path.join(BASE_DIR, relpath) : BASE_DIR, branch };
    });
  }
  // Auto-detect git repos in BASE_DIR
  const repos = [{ name: path.basename(BASE_DIR), dir: BASE_DIR, branch: 'main' }];
  try {
    fs.readdirSync(BASE_DIR, { withFileTypes: true })
      .filter(d => d.isDirectory() && !d.name.startsWith('.') && fs.existsSync(path.join(BASE_DIR, d.name, '.git')))
      .forEach(d => repos.push({ name: d.name, dir: path.join(BASE_DIR, d.name), branch: 'main' }));
  } catch {}
  return repos;
}

function checkAllRepoStatus() {
  const repos = getReposToCheck();
  const lines = ['*📊 Repository push status check*', ''];
  let hasIssues = false;

  for (const repo of repos) {
    if (!fs.existsSync(repo.dir)) continue;
    const unpushed = spawnSync('git', ['log', `origin/${repo.branch}..HEAD`, '--oneline'], {
      cwd: repo.dir, encoding: 'utf8', timeout: 10000, windowsHide: true,
    });
    const unpushedLines = (unpushed.stdout || '').trim().split('\n').filter(Boolean);
    const dirty = spawnSync('git', ['status', '--short'], {
      cwd: repo.dir, encoding: 'utf8', timeout: 10000, windowsHide: true,
    });
    const dirtyLines = (dirty.stdout || '').trim().split('\n').filter(Boolean);

    if (unpushedLines.length === 0 && dirtyLines.length === 0) {
      lines.push(`✅ \`${repo.name}\` — clean`);
    } else {
      hasIssues = true;
      lines.push(`⚠️ \`${repo.name}\`:`);
      if (unpushedLines.length > 0) {
        lines.push(`  • Unpushed commits: ${unpushedLines.length}`);
        unpushedLines.slice(0, 3).forEach(l => lines.push(`    \`${l.slice(0, 72)}\``));
        if (unpushedLines.length > 3) lines.push(`    …and ${unpushedLines.length - 3} more`);
      }
      if (dirtyLines.length > 0) lines.push(`  • Uncommitted changes: ${dirtyLines.length} files`);
    }
  }

  lines.push('');
  lines.push(hasIssues ? '🔧 Unpushed changes detected.' : '✅ All repos up to date');
  return lines.join('\n');
}

function isPushFailureNotice(text) {
  return /git\s*push\s*(失敗|failed|エラー|error)/i.test(text)
    || /push\s*(失敗|failed)/i.test(text);
}

// ── 既存タスクID（14桁）をメッセージから抽出 ────────────────────────────────
function extractExistingTaskIds(text) {
  const candidates = text.match(/\b(\d{14})\b/g) || [];
  return candidates.filter(id => {
    return [
      path.join(BASE_DIR, '.agent', 'tasks', `${id}.md`),
      path.join(BASE_DIR, '.agent', 'tasks', 'done', `${id}.md`),
      path.join(BASE_DIR, '.agent', 'tasks', 'cancel', `${id}.md`),
    ].some(f => fs.existsSync(f));
  });
}

// ── 類似 pending タスクを検索 ──────────────────────────────────────────────
function findSimilarPendingTasks(requestText) {
  const taskDir = path.join(BASE_DIR, '.agent', 'tasks');
  let files;
  try { files = fs.readdirSync(taskDir).filter(f => /^\d{14}\.md$/.test(f)); }
  catch { return []; }

  const bracketM = requestText.match(/\[([^\]]{4,})\]/);
  const bracketKey = bracketM ? bracketM[1].slice(0, 20) : null;
  const words = [...new Set(
    requestText.replace(/[^\w가-힣ぁ-んァ-ン一-龯a-zA-Z0-9]/g, ' ')
      .split(/\s+/).filter(w => w.length >= 4)
  )];

  const similar = [];
  for (const file of files) {
    try {
      const content = fs.readFileSync(path.join(taskDir, file), 'utf8');
      const statusM = content.match(/^status:\s*(.+)$/m);
      if ((statusM ? statusM[1].trim() : 'pending') !== 'pending') continue;
      const reqLine = (content.match(/request:\s*"?([^\n"]{1,300})/) || [])[1] || '';
      const titleLine = (content.match(/# TASK:\s*(.+)/) || [])[1] || '';
      const combined = reqLine + ' ' + titleLine;
      let matched = (bracketKey && combined.includes(bracketKey)) ||
        (words.length >= 2 && words.filter(w => combined.includes(w)).length / words.length >= 0.5);
      if (matched) similar.push({ taskId: file.replace('.md', ''), title: titleLine || reqLine.slice(0, 50) });
    } catch {}
  }
  return similar;
}

// ── 確認コマンド判定 ──────────────────────────────────────────────────────────
const GO_WORDS = ['go', 'start', '시작', '실행', '진행', 'ok', 'yes', '예', '응', '開始', 'はい', 'よし', '実行', '進める'];
const CANCEL_WORDS = ['cancel', '취소', 'no', '아니', '중단', 'stop', 'キャンセル', '中断', 'やめ'];

function isGoCmd(text) {
  const t = text.trim().toLowerCase();
  return GO_WORDS.some(w => t === w || t.startsWith(w + ' '));
}
function isCancelCmd(text) {
  const t = text.trim().toLowerCase();
  return CANCEL_WORDS.some(w => t === w || t.startsWith(w + ' '));
}

// ── 作業前 git pull ───────────────────────────────────────────────────────────
function gitPullBeforeWork(workDir) {
  const branchRes = spawnSync('git', ['rev-parse', '--abbrev-ref', 'HEAD'], {
    cwd: workDir, encoding: 'utf8', timeout: 10000, windowsHide: true,
  });
  const branch = (branchRes.stdout || '').trim() || 'main';
  const res = spawnSync('git', ['pull', '--rebase', 'origin', branch], {
    cwd: workDir, encoding: 'utf8', timeout: 30000, windowsHide: true,
  });
  return { ok: res.status === 0, branch, stdout: (res.stdout || '').trim(), stderr: (res.stderr || '').trim() };
}

// ── claude CLI (sync) ─────────────────────────────────────────────────────────
function callClaude(prompt, workDir = BASE_DIR) {
  const model = process.env.CLAUDE_MODEL || 'claude-opus-4-8';
  const result = spawnSync('claude', ['-p', prompt, '--model', model], {
    cwd: workDir,
    encoding: 'utf8',
    maxBuffer: 10 * 1024 * 1024,
    timeout: 300000,
    windowsHide: true,
  });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`claude exit ${result.status}: ${(result.stderr || '').slice(0, 200)}`);
  return (result.stdout || '').trim();
}

// ── 意図分類 (task / question) ────────────────────────────────────────────────
function classifyRequest(text, workDir = BASE_DIR) {
  if (/^\s*(git\s+(push|pull|stash|fetch|merge|rebase|status|log|diff)|tasklist)/i.test(text)) {
    return 'question';
  }

  const prompt = `You are an assistant that classifies the intent of messages.

Message: "${text}"

Classify using the following rules:
- "task": applies when the request requires creating or modifying ANY file on disk:
  1. Explicit task registration such as "태스크 등록", "task add", "작업 의뢰" etc.
  2. Code change, feature addition, bug fix, refactoring, or configuration file modification
  3. Document/spec creation and saving: "문서로 저장", "파일로 저장", "작성해서 저장", "만들어서 저장"
  4. Any request that results in writing output to a file or folder on disk

- "question": applies when NO file needs to be created or modified:
  1. Question, information inquiry, explanation request (no file output expected)
  2. Status check, log review, environment check
  3. Git push/pull only (no other file work)

Key principle: If the request involves writing, saving, or creating ANY file on disk — classify as "task".

Reply with only one word: "task" or "question". No explanation needed.`;

  const result = spawnSync('claude', ['-p', prompt, '--model', process.env.CLAUDE_MODEL || 'claude-opus-4-8'], {
    cwd: workDir, encoding: 'utf8', maxBuffer: 1024 * 1024, timeout: 60000, windowsHide: true,
  });
  if (result.error || result.status !== 0) return 'question';
  return (result.stdout || '').trim().toLowerCase().startsWith('task') ? 'task' : 'question';
}

// ── git push / pull 単純操作 ──────────────────────────────────────────────────
function isPureGitOp(text) {
  const stripped = text.replace(/<[^>]+>/g, '').replace(/[^\x00-\x7Fぁ-ん亜-熙ー]/g, ' ').trim();
  return /^git\s+(push|pull)(\s+\S+)?$/i.test(stripped);
}

async function handleSimpleGitOp({ channelId, replyTs, text, workDir = BASE_DIR }) {
  if (!isPureGitOp(text)) return false;
  const t = text.trim();
  if (/git\s+push/i.test(t)) {
    spawnSync('git', ['pull', '--rebase', 'origin'], { cwd: workDir, encoding: 'utf8', windowsHide: true });
    const res = spawnSync('git', ['push'], { cwd: workDir, encoding: 'utf8', windowsHide: true });
    await postMessage(channelId, res.status === 0 ? '✅ git push done' : `❌ git push failed\n\`\`\`${(res.stderr || '').slice(0, 500)}\`\`\``, replyTs);
    return true;
  }
  if (/git\s+pull/i.test(t)) {
    const res = spawnSync('git', ['pull', '--rebase', 'origin'], { cwd: workDir, encoding: 'utf8', windowsHide: true });
    await postMessage(channelId, res.status === 0 ? '✅ git pull done' : `❌ git pull failed\n\`\`\`${(res.stderr || '').slice(0, 500)}\`\`\``, replyTs);
    return true;
  }
  return false;
}

// ── チャンネル Q&A ────────────────────────────────────────────────────────────
async function answerInChannel({ channelId, replyTs, text, workDir = BASE_DIR }) {
  if (await handleSimpleGitOp({ channelId, replyTs, text, workDir })) return;

  const claims = searchKLayer(text);
  let issues = [];
  if (['issue', 'bug', 'task', 'github', '#'].some(k => text.toLowerCase().includes(k))) {
    issues = await getIssues();
  }

  const projectName = path.basename(workDir);
  let prompt = `You are ${BOT_NAME}, an AI assistant. Respond in the same language as the user's message.

Working project: ${projectName}
Working directory: ${workDir}

IMPORTANT: Answer based on your knowledge of the project and context below. If you don't know, say so clearly.`;
  if (claims.length) prompt += '\n\nK-Layer context:\n' + claims.map(c => `• ${c}`).join('\n');
  if (issues.length) prompt += '\n\nOpen Issues:\n' + issues.map(i => `• #${i.number} ${i.title}`).join('\n');
  prompt += `\n\nQuestion: ${text}\nAnswer:`;

  try {
    await postMessage(channelId, await callClaude(prompt, workDir), replyTs);
  } catch (err) {
    const msg = err.message && err.message.includes('ETIMEDOUT')
      ? '⏱️ Request timed out (5min). Please split into smaller requests.'
      : `Error: ${err.message}`;
    await postMessage(channelId, msg, replyTs);
  }
}

// ── DM 処理 ───────────────────────────────────────────────────────────────────
async function handleDM({ channelId, ts, threadTs, text, conversations, workDir = BASE_DIR }) {
  const convKey = channelId;
  const replyTs = threadTs || undefined;
  const cmd = text.trim().toLowerCase();

  if (cmd === '!help') {
    await postMessage(channelId, [
      `*${BOT_NAME} — DM Commands*`,
      '• `!issues` — GitHub Issue list',
      '• `!issues refresh` — Force refresh issues',
      '• `!klayer <keyword>` — K-Layer knowledge search',
      '• `!reset` — Reset conversation history',
    ].join('\n'), replyTs);
    return;
  }
  if (cmd === '!reset') {
    conversations[convKey] = [];
    await postMessage(channelId, 'Conversation history reset.', replyTs);
    return;
  }
  if (cmd === '!issues' || cmd === '!issues refresh') {
    const issues = cmd.includes('refresh') ? await refreshIssues() : await getIssues();
    if (!issues.length) { await postMessage(channelId, 'Check GITHUB_TOKEN / GITHUB_REPO settings.', replyTs); return; }
    await postMessage(channelId, `Issues (${issues.length}) — ${getCacheAge()}\n${issues.map(i => `• #${i.number} ${i.title}`).join('\n')}`, replyTs);
    return;
  }
  if (cmd.startsWith('!klayer ')) {
    const kw = cmd.slice(8).trim();
    const claims = searchKLayer(kw);
    await postMessage(channelId, claims.length ? `K-Layer "${kw}":\n${claims.map(c => `• ${c}`).join('\n')}` : `No claims found for "${kw}"`, replyTs);
    return;
  }

  const dmTaskMatch = text.trim().match(/^(?:status\s+)?(\d{14})$/);
  if (dmTaskMatch) {
    const targetId = dmTaskMatch[1];
    const taskFile = path.join(BASE_DIR, '.agent', 'tasks', `${targetId}.md`);
    if (fs.existsSync(taskFile)) {
      const fc = fs.readFileSync(taskFile, 'utf8');
      const status = (fc.match(/^status:\s*(.+)$/m) || [])[1] || 'unknown';
      const request = (fc.match(/^request:\s*"?([^\n"]{1,120})/m) || [])[1] || '(none)';
      await postMessage(channelId, `*Task \`${targetId}\` status*\n• Status: ${status}\n• Request: ${request}`, replyTs);
    } else {
      await postMessage(channelId, `⚠️ Task \`${targetId}\` not found.`, replyTs);
    }
    return;
  }

  const history = conversations[convKey] || [];
  const claims = searchKLayer(text);
  const projectName = path.basename(workDir);
  let prompt = `You are ${BOT_NAME}, an AI assistant. Respond in the same language as the user's message.\n\nWorking project: ${projectName}\nWorking directory: ${workDir}\n\nIMPORTANT: Answer based on your knowledge and context. If you don't know, say so clearly.`;
  if (claims.length) prompt += '\n\nK-Layer:\n' + claims.map(c => `• ${c}`).join('\n');
  if (history.length) {
    prompt += '\n\nHistory:';
    history.slice(-10).forEach(m => { prompt += `\n${m.role === 'user' ? 'User' : 'Assistant'}: ${m.content}`; });
  }
  prompt += `\n\nUser: ${text}\nAssistant:`;

  try {
    const reply = await callClaude(prompt, workDir);
    if (!conversations[convKey]) conversations[convKey] = [];
    conversations[convKey].push({ role: 'user', content: text });
    conversations[convKey].push({ role: 'assistant', content: reply });
    if (conversations[convKey].length > 20) conversations[convKey] = conversations[convKey].slice(-20);
    await postLong(channelId, reply, replyTs);
  } catch (err) {
    await postMessage(channelId, `Error: ${err.message}`, replyTs);
  }
}

// ── Task 実行共通処理 ─────────────────────────────────────────────────────────
async function startTaskExecution(pendingKey, pendingTask, channelId, replyTs, taskState, workDir = BASE_DIR) {
  delete taskState.pending[pendingKey];
  taskState.running[pendingKey] = { taskId: pendingTask.taskId, taskTitle: pendingTask.taskTitle, startedAt: new Date().toISOString() };
  saveJSON(TASK_STATE_FILE, taskState);
  tm.updateTasklistEntry(pendingTask.taskId, { status: 'running', startedAt: new Date().toISOString() });

  // git pull before work
  const pull = gitPullBeforeWork(workDir);
  if (pull.ok) {
    const alreadyLatest = /already up.to.date/i.test(pull.stdout);
    await postMessage(channelId,
      alreadyLatest ? `🔄 git pull \`${pull.branch}\`: already up to date` : `🔄 git pull \`${pull.branch}\` done\n\`\`\`${pull.stdout.slice(0, 300)}\`\`\``,
      replyTs
    );
  } else {
    await postMessage(channelId, `⚠️ git pull failed (continuing anyway)\n\`\`\`${(pull.stderr || pull.stdout).slice(0, 300)}\`\`\``, replyTs);
  }

  await postMessage(channelId,
    `⚙️ *Task started*: \`${pendingTask.taskId}\`\n• ${pendingTask.taskTitle}\n\n_Subagent is working. GitHub URL will be posted when done._`,
    replyTs
  );

  tm.startExecution(pendingTask.taskId, pendingTask.taskFile, {
    onComplete: async (resultFile) => {
      const ts2 = loadJSON(TASK_STATE_FILE, {});
      delete ts2.running[pendingKey];
      saveJSON(TASK_STATE_FILE, ts2);

      let doneTaskFile = null;
      try {
        const resultContent = fs.existsSync(resultFile) ? fs.readFileSync(resultFile, 'utf8') : '';
        doneTaskFile = tm.completeTaskFile(pendingTask.taskId, resultContent);
      } catch (e) {
        console.error('[Bot] completeTaskFile error:', e.message);
      }

      const githubUrl = tm.gitPushResult(pendingTask.taskId, pendingTask.taskTitle, resultFile, doneTaskFile);
      tm.updateTasklistEntry(pendingTask.taskId, { status: 'completed', completedAt: new Date().toISOString(), resultUrl: githubUrl || null });

      if (githubUrl) {
        await postMessage(channelId,
          `✅ *Task completed*: \`${pendingTask.taskId}\`\n• ${pendingTask.taskTitle}\n\n📋 Result report: ${githubUrl}`,
          replyTs
        );
      } else {
        await postMessage(channelId,
          `✅ *Task completed* (git push failed)\n• \`${pendingTask.taskId}\`: ${pendingTask.taskTitle}\nResult: \`.agent/tasks/done/${pendingTask.taskId}.md\``,
          replyTs
        );
        await postLong(channelId, checkAllRepoStatus(), replyTs);
      }
    },
    onError: async (err, resultFile) => {
      const ts2 = loadJSON(TASK_STATE_FILE, {});
      delete ts2.running[pendingKey];
      saveJSON(TASK_STATE_FILE, ts2);
      const githubUrl = resultFile ? tm.gitPushResult(pendingTask.taskId, pendingTask.taskTitle + ' (error)', resultFile, null) : null;
      tm.updateTasklistEntry(pendingTask.taskId, { status: 'cancelled', completedAt: new Date().toISOString(), resultUrl: githubUrl || null });
      await postMessage(channelId,
        `❌ *Task error*: ${err.message}${githubUrl ? `\n📄 Error log: ${githubUrl}` : ''}`,
        replyTs
      );
    },
  }, workDir);
}

// ── チャンネル Mention 処理 ───────────────────────────────────────────────────
async function handleChannelMention({ channelId, ts, threadTs, text, workDir = BASE_DIR }) {
  const convKey = `${channelId}:${threadTs || ts}`;
  const replyTs = threadTs || ts;
  const taskState = loadJSON(TASK_STATE_FILE, { pending: {}, running: {} });
  const cmd = text.trim().replace(/`/g, '').replace(/\s+/g, ' ').toLowerCase();

  if (cmd === '!help') {
    await postMessage(channelId, [
      `*${BOT_NAME} — Usage*`,
      '`@bot <question>` → Answer inline',
      '`@bot <work request>` → Analyze task → Confirm → Execute → GitHub result URL',
      '',
      '*Task management:*',
      '• `tasklist` — Pending task list',
      '• `tasklist all` — All tasks (including done/cancelled)',
      '• `go` — Show pending tasks',
      '• `go <TaskID>` — Execute specified task',
      '• `cancel <TaskID>` — Cancel specified task',
      '',
      '*Info:*',
      '• `!issues` — GitHub Issue list',
      '• `!klayer <keyword>` — K-Layer search',
      '• `!help` — Help',
    ].join('\n'), replyTs);
    return;
  }

  if (cmd === '!issues' || cmd === '!issues refresh') {
    const issues = cmd.includes('refresh') ? await refreshIssues() : await getIssues();
    if (!issues.length) { await postMessage(channelId, 'Check GITHUB_TOKEN / GITHUB_REPO settings.', replyTs); return; }
    await postMessage(channelId, `Issues (${issues.length}) — ${getCacheAge()}\n${issues.map(i => `• #${i.number} ${i.title}`).join('\n')}`, replyTs);
    return;
  }

  if (cmd.startsWith('!klayer ')) {
    const kw = cmd.slice(8).trim();
    const claims = searchKLayer(kw);
    await postMessage(channelId, claims.length ? `K-Layer "${kw}":\n${claims.map(c => `• ${c}`).join('\n')}` : `No claims found for "${kw}"`, replyTs);
    return;
  }

  if (cmd === 'tasklist' || cmd === 'tasklist all') {
    const showAll = cmd === 'tasklist all';
    const tasks = tm.getTasklistByStatus(showAll ? null : 'pending');
    if (!tasks.length) {
      await postMessage(channelId, showAll ? 'No tasks recorded.' : 'No pending tasks.\nUse `tasklist all` for full history.', replyTs);
      return;
    }
    const lines = tasks.map(t => {
      const emoji = tm.statusEmoji(t.status);
      const date = t.createdAt ? t.createdAt.slice(0, 10) : '';
      const result = t.resultUrl ? `\n     📄 ${t.resultUrl}` : '';
      return `${emoji} \`${t.taskId}\` [${t.status}] ${date}\n     *${t.title}*\n     ${t.summary}${result}`;
    });
    await postLong(channelId, [`*${showAll ? 'All' : 'Pending'} tasks (${tasks.length})*`, '', ...lines].join('\n'), replyTs);
    return;
  }

  const cancelWithId = cmd.match(/^(?:cancel|취소|キャンセル|中断)\s+(\d{14})$/);
  if (cancelWithId) {
    const targetId = cancelWithId[1];
    const entry = Object.entries(taskState.pending || {}).find(([, t]) => t.taskId === targetId);
    if (entry) {
      const [key, task] = entry;
      delete taskState.pending[key];
      saveJSON(TASK_STATE_FILE, taskState);
      tm.updateTasklistEntry(targetId, { status: 'cancelled', completedAt: new Date().toISOString() });
      try { tm.cancelTaskFile(targetId); } catch {}
      await postMessage(channelId, `🚫 Task \`${targetId}\` cancelled.\n• ${task.taskTitle}`, replyTs);
    } else {
      const taskFilePath = path.join(BASE_DIR, '.agent', 'tasks', `${targetId}.md`);
      if (fs.existsSync(taskFilePath)) {
        try {
          tm.cancelTaskFile(targetId);
          tm.updateTasklistEntry(targetId, { status: 'cancelled', completedAt: new Date().toISOString() });
          await postMessage(channelId, `🚫 Task \`${targetId}\` cancelled.`, replyTs);
        } catch (err) { await postMessage(channelId, `⚠️ Cancel failed: ${err.message}`, replyTs); }
      } else {
        await postMessage(channelId, `⚠️ Task \`${targetId}\` not found.`, replyTs);
      }
    }
    return;
  }

  if (isCancelCmd(text)) {
    const allPending = Object.entries(taskState.pending || {});
    if (!allPending.length) { await postMessage(channelId, 'No pending tasks.', replyTs); return; }
    const lines = allPending.map(([, t]) => `• \`${t.taskId}\` — ${t.taskTitle}`);
    await postMessage(channelId, [`*Pending tasks (${allPending.length})*`, ...lines, '', 'Cancel: `cancel <TaskID>`'].join('\n'), replyTs);
    return;
  }

  const goWithId = cmd.match(/^(?:go|start|실행|시작|진행|実行|開始)\s+(\d{14})$/);
  if (goWithId) {
    const targetId = goWithId[1];
    const entry = Object.entries(taskState.pending || {}).find(([, t]) => t.taskId === targetId);
    if (!entry) {
      if (Object.entries(taskState.running || {}).find(([, t]) => t.taskId === targetId)) {
        await postMessage(channelId, `⚙️ \`${targetId}\` is already running.`, replyTs); return;
      }
      const taskFileFallback = path.join(BASE_DIR, '.agent', 'tasks', `${targetId}.md`);
      if (fs.existsSync(taskFileFallback)) {
        const fc = fs.readFileSync(taskFileFallback, 'utf8');
        const taskTitle = (fc.match(/^# TASK:\s*(.+)$/m) || [])[1] || `Task ${targetId}`;
        const pendingKeyNew = `${channelId}:${replyTs}`;
        taskState.pending[pendingKeyNew] = { taskId: targetId, taskTitle, taskFile: taskFileFallback, requestText: '' };
        saveJSON(TASK_STATE_FILE, taskState);
        await startTaskExecution(pendingKeyNew, taskState.pending[pendingKeyNew], channelId, replyTs, taskState, workDir);
      } else {
        await postMessage(channelId, `⚠️ Task \`${targetId}\` not found.`, replyTs);
      }
      return;
    }
    const [pendingKey, pendingTask] = entry;
    await startTaskExecution(pendingKey, pendingTask, channelId, replyTs, taskState, workDir);
    return;
  }

  if (isGoCmd(text)) {
    const allPending = Object.entries(taskState.pending || {});
    if (!allPending.length) { await postMessage(channelId, 'No pending tasks.', replyTs); return; }
    const lines = allPending.map(([, t]) => `• \`${t.taskId}\` — ${t.taskTitle}`);
    await postMessage(channelId, [`*Pending tasks (${allPending.length})*`, ...lines, '', 'Execute: `go <TaskID>`'].join('\n'), replyTs);
    return;
  }

  const taskStatusMatch = text.trim().replace(/`/g, '').match(/^(?:status\s+)?(\d{14})$/);
  if (taskStatusMatch) {
    const targetId = taskStatusMatch[1];
    const taskFile = path.join(BASE_DIR, '.agent', 'tasks', `${targetId}.md`);
    if (fs.existsSync(taskFile)) {
      const fc = fs.readFileSync(taskFile, 'utf8');
      const status = (fc.match(/^status:\s*(.+)$/m) || [])[1] || 'unknown';
      const request = (fc.match(/^request:\s*"?([^\n"]{1,120})/m) || [])[1] || '(none)';
      await postMessage(channelId, `*Task \`${targetId}\`*\n• Status: ${status}\n• Request: ${request}\n\nExecute: \`go ${targetId}\` | Cancel: \`cancel ${targetId}\``, replyTs);
    } else {
      await postMessage(channelId, `⚠️ Task \`${targetId}\` not found.`, replyTs);
    }
    return;
  }

  if (isPushFailureNotice(text)) {
    await postLong(channelId, checkAllRepoStatus(), replyTs);
    return;
  }

  const mentionedIds = extractExistingTaskIds(text);
  if (mentionedIds.length > 0) {
    const targetId = mentionedIds[0];
    const activeFile = [
      path.join(BASE_DIR, '.agent', 'tasks', `${targetId}.md`),
      path.join(BASE_DIR, '.agent', 'tasks', 'done', `${targetId}.md`),
      path.join(BASE_DIR, '.agent', 'tasks', 'cancel', `${targetId}.md`),
    ].find(f => fs.existsSync(f));
    if (activeFile) {
      const fc = fs.readFileSync(activeFile, 'utf8');
      const status = (fc.match(/^status:\s*(.+)$/m) || [])[1] || 'unknown';
      const request = (fc.match(/^request:\s*"?([^\n"]{1,100})/m) || [])[1] || '(none)';
      await postMessage(channelId,
        `📌 Task \`${targetId}\` reference:\n• Status: ${status}\n• Request: ${request}\n\n_Task ID detected — no new task created._`,
        replyTs
      );
    }
    return;
  }

  if (taskState.running[convKey]) {
    await postMessage(channelId, `⚙️ Task \`${taskState.running[convKey].taskId}\` is running. Result will be posted when done.`, replyTs);
    return;
  }

  const intent = classifyRequest(text, workDir);
  console.log(`[Bot] intent="${intent}" text="${text.slice(0, 60)}"`);

  if (intent === 'question') {
    await answerInChannel({ channelId, replyTs, text, workDir });
    return;
  }

  // Auto-close similar pending tasks
  const similarTasks = findSimilarPendingTasks(text);
  let closedNotice = '';
  if (similarTasks.length > 0) {
    const closedLines = [];
    for (const old of similarTasks) {
      try { tm.cancelTaskFile(old.taskId); } catch {}
      Object.keys(taskState.pending).forEach(k => {
        if ((taskState.pending[k] || {}).taskId === old.taskId) delete taskState.pending[k];
      });
      tm.updateTasklistEntry(old.taskId, { status: 'cancelled', completedAt: new Date().toISOString() });
      closedLines.push(`• \`${old.taskId}\` — ${old.title.slice(0, 50)}`);
    }
    saveJSON(TASK_STATE_FILE, taskState);
    closedNotice = `\n\n⚠️ Similar pending tasks auto-closed:\n${closedLines.join('\n')}`;
  }

  await postMessage(channelId, '🔍 Analyzing request...', replyTs);

  let planContent;
  try {
    planContent = tm.analyzeRequest(text, null, workDir);
  } catch (err) {
    await postMessage(channelId, `Analysis error: ${err.message}`, replyTs);
    return;
  }

  const taskId = tm.getTimestampId();
  const taskFile = tm.createTaskFile(taskId, text, planContent);
  const taskTitle = tm.extractTitle(planContent);
  const taskSummary = tm.extractSummary(planContent);

  taskState.pending[convKey] = { taskId, taskTitle, taskFile, requestText: text };
  saveJSON(TASK_STATE_FILE, taskState);
  tm.addToTasklist(taskId, taskTitle, taskSummary, text);

  await postLong(channelId,
    `📋 *Task analysis complete* (\`${taskId}\`)${closedNotice}\n\n${planContent}\n\n---\n*Execute: \`go ${taskId}\` / Cancel: \`cancel ${taskId}\`*`,
    replyTs
  );
}

// ── メッセージ処理 ─────────────────────────────────────────────────────────────
function isActiveTaskThread(channelId, threadTs) {
  if (!threadTs) return false;
  const taskState = loadJSON(TASK_STATE_FILE, { pending: {}, running: {} });
  const convKey = `${channelId}:${threadTs}`;
  return !!(taskState.pending[convKey] || taskState.running[convKey]);
}

async function processMessage({ channelId, msg, isDM, conversations, threadTs }) {
  const effectiveThreadTs = threadTs || msg.thread_ts || null;
  const mentionsBot = BOT_USER_ID && msg.text.includes(`<@${BOT_USER_ID}>`);
  const isTaskReply = isActiveTaskThread(channelId, effectiveThreadTs);
  const isEngagedThread = isBotEngagedThread(channelId, effectiveThreadTs);

  const rawCleanText = msg.text
    .replace(/<@[A-Z0-9]+>/g, '')
    .replace(/<tel:(\d+)\|[^>]*>/g, '$1')
    .replace(/<tel:(\d+)>/g, '$1')
    .replace(/<(https?:\/\/[^|>]+)\|[^>]*>/g, '$1')
    .replace(/<(https?:\/\/[^>]+)>/g, '$1')
    .replace(/[*_~]/g, '')
    .replace(/`/g, '')
    .trim();

  // Project prefix detection: "<projectname> <request>" → switch workDir
  const { workDir, cleanText } = parseProjectPrefix(rawCleanText);

  const hasFiles = msg.files && msg.files.length > 0;
  if (hasFiles && !cleanText) {
    if (mentionsBot || isEngagedThread) {
      await postMessage(channelId, 'File-only messages are not supported. Please include text.', effectiveThreadTs || msg.ts);
    }
    return;
  }
  if (!cleanText) return;

  if (isDM) {
    await handleDM({ channelId, ts: msg.ts, threadTs: effectiveThreadTs, text: cleanText, conversations, workDir });
  } else if (mentionsBot || isTaskReply || isEngagedThread) {
    await handleChannelMention({ channelId, ts: msg.ts, threadTs: effectiveThreadTs, text: cleanText, workDir });
  }
}

// ── Socket Mode ───────────────────────────────────────────────────────────────
async function onSlackMessage(event, conversations) {
  if (event.bot_id || event.subtype || !event.text) return;
  const isDM = event.channel_type === 'im';
  try {
    await processMessage({ channelId: event.channel, msg: event, isDM, conversations });
  } catch (err) {
    console.error('[Bot] processMessage error:', err.message);
  }
  saveJSON(HISTORY_FILE, conversations);
}

async function main() {
  if (!BOT_TOKEN) { console.error('[Bot] SLACK_BOT_TOKEN is not set in .env'); process.exit(1); }
  if (!SLACK_APP_TOKEN) { console.error('[Bot] SLACK_APP_TOKEN is not set in .env'); process.exit(1); }

  const ver = spawnSync('claude', ['--version'], { encoding: 'utf8', windowsHide: true });
  if (ver.error) { console.error('[Bot] claude CLI not found. Check PATH.'); process.exit(1); }

  const auth = await slackGet('auth.test');
  if (!auth.ok) { console.error('[Bot] SLACK_BOT_TOKEN invalid:', auth.error); process.exit(1); }
  BOT_USER_ID = auth.user_id;

  console.log(`[${BOT_NAME}] Starting — Socket Mode`);
  console.log(`[Bot] ID: ${BOT_USER_ID} (${auth.user}) PID: ${process.pid}`);
  console.log(`[Bot] Workspace: ${BASE_DIR}`);
  console.log(`[Bot] Projects root: ${PROJECTS_ROOT}`);
  console.log(`[Bot] Channels: ${CHANNEL_IDS.join(', ') || '(DM only)'}`);

  const conversations = loadJSON(HISTORY_FILE, {});
  const socketClient = new SocketModeClient({
    appToken: SLACK_APP_TOKEN,
    clientPingTimeout: 60000,
    serverPingTimeout: 180000,
  });

  const safeAck = async (ack) => {
    try { await ack(); } catch (e) { console.warn('[Bot] ack failed:', e.message); }
  };

  socketClient.on('app_mention', async ({ event, ack }) => {
    await safeAck(ack);
    console.log('[Bot] app_mention:', event.channel, (event.text || '').slice(0, 60));
    await onSlackMessage(event, conversations);
  });

  socketClient.on('message', async ({ event, ack }) => {
    await safeAck(ack);
    const isDM = event.channel_type === 'im';
    const mentionsBot = BOT_USER_ID && (event.text || '').includes(`<@${BOT_USER_ID}>`);
    if (!isDM && mentionsBot) return;
    await onSlackMessage(event, conversations);
  });

  socketClient.on('error', (error) => {
    console.error('[Bot] Socket Mode error:', error.message || error);
  });

  await socketClient.start();
  console.log(`[Bot] Socket Mode connected — waiting for events`);
}

main().catch(err => { console.error('[Bot] Fatal:', err); process.exit(1); });
