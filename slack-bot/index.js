/**
 * giipclaude Bot — Task workflow mode
 *
 * 채널 mention 흐름:
 *   1. mention 수신 → claude 로 TASK 파일 분석/생성 → Slack에 확인 요청
 *   2. 사용자 "시작/go" → subagent (claude -p) 실행
 *   3. 완료 → 결과 doc git push → GitHub URL을 Slack에 보고
 *
 * DM:
 *   일반 Q&A 대화 (claude -p)
 */

require('dotenv').config();

const https = require('https');
const fs = require('fs');
const path = require('path');
const { spawnSync, spawn } = require('child_process');
const { searchKLayer } = require('./k-layer');
const { getIssues, refreshIssues, getCacheAge } = require('./github-issues');
const tm = require('./task-manager');
const { SocketModeClient } = require('@slack/socket-mode');

// ── 設定 ─────────────────────────────────────────────────────────────────────
const BOT_TOKEN = process.env.SLACK_BOT_TOKEN;
const CHANNEL_IDS = (process.env.SLACK_CHANNEL_IDS || '').split(',').map(s => s.trim()).filter(Boolean);
const SLACK_APP_TOKEN = process.env.SLACK_APP_TOKEN;

const BOT_NAME        = process.env.BOT_NAME || 'giipclaude Bot'; // Slack 표시용 봇 이름 (BOT_NAME 환경변수로 변경 가능)
// WORKSPACE_DIR: 기본 작업 폴더(.agent 위치 / git push 대상). 미설정 시 slack-bot 상위 폴더로 자동 결정.
const BASE_DIR        = process.env.WORKSPACE_DIR ? path.resolve(process.env.WORKSPACE_DIR) : path.join(__dirname, '..');
// PROJECTS_ROOT: 여러 프로젝트의 상위 폴더(프로젝트 프리픽스 전환용). 미설정 시 BASE_DIR의 상위 폴더.
const PROJECTS_ROOT   = process.env.PROJECTS_ROOT || path.dirname(BASE_DIR);
const AGENT_DIR       = path.join(BASE_DIR, '.agent');           // 기본 .agent (BASE_DIR/.agent)
const HISTORY_FILE    = path.join(__dirname, '.conversations.json');
const TASK_STATE_FILE = path.join(__dirname, '.task-state.json');
const BOT_THREADS_FILE = path.join(__dirname, '.bot-threads.json');

let BOT_USER_ID = null;

// ── プロジェクトの .agent ディレクトリを解決 ─────────────────────────────────
// workDir 内に .agent があればそれを使い、なければ BASE_DIR/.agent にフォールバック
function getAgentDir(workDir) {
  const d = path.join(workDir, '.agent');
  return fs.existsSync(d) ? d : AGENT_DIR;
}

// ── プロジェクトプレフィックス検出 ────────────────────────────────────────────
// メッセージの先頭がプロジェクト名（PROJECTS_ROOT 直下のフォルダ名）なら
// そのフォルダを workDir として返し、プレフィックスを除去した本文を返す
function parseProjectPrefix(text) {
  const words = text.trim().split(/\s+/);
  if (words.length < 1) return { workDir: BASE_DIR, cleanText: text };
  // 助詞・接尾語を除去してプロジェクト名を抽出 (giipprj에서 → giipprj)
  const raw = words[0];
  const candidate = raw.toLowerCase().replace(/(에서|에서는|에서도|에서만|에게서|한테서|의|에|는|이|가|를|을|로|으로|와|과|도|만|까지|부터|처럼|라고|이라고|에서라도|에도)$/u, '');
  const projectDir = path.join(PROJECTS_ROOT, candidate);
  try {
    if (fs.statSync(projectDir).isDirectory()) {
      const suffix = raw.slice(candidate.length); // 除去した助詞部分
      const rest = suffix ? [suffix, ...words.slice(1)] : words.slice(1);
      console.log(`[Bot] プロジェクト切り替え: ${projectDir}`);
      return { workDir: projectDir, cleanText: rest.join(' ').trim() || text };
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
  // 7日以上前のエントリを削除
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
  // ボットが返答したスレッドを記録 → 以降の返信にも反応する
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

// ── PROJECTS_ROOT 直下の git リポジトリを動的スキャン ────────────────────────
function discoverGitRepos() {
  let entries;
  try { entries = fs.readdirSync(PROJECTS_ROOT, { withFileTypes: true }); }
  catch { return []; }

  return entries
    .filter(e => e.isDirectory() && fs.existsSync(path.join(PROJECTS_ROOT, e.name, '.git')))
    .map(e => {
      const dir = path.join(PROJECTS_ROOT, e.name);
      const branchRes = spawnSync('git', ['rev-parse', '--abbrev-ref', 'HEAD'], {
        cwd: dir, encoding: 'utf8', timeout: 5000, windowsHide: true,
      });
      const branch = (branchRes.stdout || '').trim() || 'main';
      return { name: e.name, dir, branch };
    });
}

// ── 全リポジトリ push 状況チェック ───────────────────────────────────────────
function checkAllRepoStatus() {
  const repos = discoverGitRepos();

  const lines = ['*📊 全リポジトリ push 状況チェック*', ''];
  let hasIssues = false;

  for (const repo of repos) {
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
        lines.push(`  • 未 push コミット: ${unpushedLines.length}件`);
        unpushedLines.slice(0, 3).forEach(l => lines.push(`    \`${l.slice(0, 72)}\``));
        if (unpushedLines.length > 3) lines.push(`    …他 ${unpushedLines.length - 3}件`);
      }
      if (dirtyLines.length > 0) {
        lines.push(`  • 未コミット変更: ${dirtyLines.length}ファイル`);
      }
    }
  }

  if (repos.length === 0) lines.push('_(git リポジトリが見つかりません)_');
  lines.push('');
  lines.push(hasIssues
    ? '🔧 未 push の変更があります。確認してください。'
    : '✅ 全リポジトリ最新 — push 漏れなし'
  );
  return lines.join('\n');
}

function isPushFailureNotice(text) {
  return /git\s*push\s*(失敗|failed|エラー|error)/i.test(text)
    || /push\s*(失敗|failed)/i.test(text)
    || /作業完了[^\n]*git\s*push\s*失敗/i.test(text);
}

// ── 既存タスクIDをメッセージから抽出 ────────────────────────────────────────
// 14桁数字 (自動生成) と YYYYMMDD_名前形式 (手動作成) の両方に対応
function extractExistingTaskIds(text) {
  const numericIds = text.match(/\b(\d{14})\b/g) || [];
  const namedIds   = text.match(/\b(\d{8}_[\w-]+)\b/g) || [];
  const candidates = [...new Set([...numericIds, ...namedIds])];
  return candidates.filter(id => {
    return [
      path.join(AGENT_DIR, 'tasks', `${id}.md`),
      path.join(AGENT_DIR, 'tasks', 'done', `${id}.md`),
      path.join(AGENT_DIR, 'tasks', 'cancel', `${id}.md`),
    ].some(f => fs.existsSync(f));
  });
}

// ── 類似 pending タスクを検索 ──────────────────────────────────────────────
function findSimilarPendingTasks(requestText) {
  const taskDir = path.join(AGENT_DIR, 'tasks');
  let files;
  try { files = fs.readdirSync(taskDir).filter(f => /^\d{14}\.md$/.test(f)); }
  catch { return []; }

  // ブラケット記法から内容を抽出: [SO/SS売上集計リデザイン] → "SO/SS売上集計リデザイン"
  const bracketM = requestText.match(/\[([^\]]{4,})\]/);
  const bracketKey = bracketM ? bracketM[1].slice(0, 20) : null;

  // 4文字以上の単語を抽出（日本語・英数字）
  const words = [...new Set(
    requestText.replace(/[^\w぀-鿿a-zA-Z0-9]/g, ' ')
      .split(/\s+/).filter(w => w.length >= 4)
  )];

  const similar = [];
  for (const file of files) {
    try {
      const content = fs.readFileSync(path.join(taskDir, file), 'utf8');
      const statusM = content.match(/^status:\s*(.+)$/m);
      const status = (statusM ? statusM[1].trim() : 'pending');
      if (status !== 'pending') continue;

      const reqLine = (content.match(/request:\s*"?([^\n"]{1,300})/) || [])[1] || '';
      const titleLine = (content.match(/# TASK:\s*(.+)/) || [])[1] || '';
      const combined = reqLine + ' ' + titleLine;

      let matched = false;
      if (bracketKey && combined.includes(bracketKey)) matched = true;
      if (!matched && words.length >= 2) {
        const hits = words.filter(w => combined.includes(w)).length;
        if (hits / words.length >= 0.5) matched = true;
      }

      if (matched) {
        const title = titleLine || reqLine.slice(0, 50);
        similar.push({ taskId: file.replace('.md', ''), title });
      }
    } catch {}
  }
  return similar;
}

// ── 確認コマンド判定 ──────────────────────────────────────────────────────────
const GO_WORDS = ['go', 'start', '시작', '실행', '진행', 'ok', 'yes', '예', '응', '開始', 'はい', 'よし', '実行', '進める'];
const CANCEL_WORDS = ['cancel', '취소', 'no', '아니', '중단', 'stop', 'キャンセル', '中断', 'やめ'];

function isGoCmd(text) {
  const t = text.trim().toLowerCase();
  return GO_WORDS.some(w => t === w || t.startsWith(w + ' ') || t.includes('시작') || t.includes('진행'));
}
function isCancelCmd(text) {
  const t = text.trim().toLowerCase();
  return CANCEL_WORDS.some(w => t === w || t.startsWith(w + ' '));
}

// ── 作業前 git pull (非同期、git repo でない場合はスキップ) ─────────────────
async function gitPullBeforeWork(workDir) {
  const check = await spawnAsync('git', ['rev-parse', '--git-dir'], { cwd: workDir, timeout: 5000 });
  if (check.status !== 0) {
    return { ok: true, skipped: true, branch: '', stdout: '', stderr: '' };
  }
  const branchRes = await spawnAsync('git', ['rev-parse', '--abbrev-ref', 'HEAD'], { cwd: workDir, timeout: 10000 });
  const branch = (branchRes.stdout || '').trim() || 'main';
  const res = await spawnAsync('git', ['pull', '--rebase', 'origin', branch], { cwd: workDir, timeout: 60000 });
  return {
    ok: res.status === 0,
    skipped: false,
    branch,
    stdout: (res.stdout || '').trim(),
    stderr: (res.stderr || '').trim(),
  };
}

// ── spawn → Promise 래퍼 (이벤트 루프 비차단) ────────────────────────────────
function spawnAsync(cmd, args, opts = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(cmd, args, {
      cwd: opts.cwd,
      windowsHide: opts.windowsHide !== false, // 기본 true; false 명시 시 브라우저 팝업 허용
    });
    const stdout = [], stderr = [];
    if (child.stdout) child.stdout.on('data', d => stdout.push(d));
    if (child.stderr) child.stderr.on('data', d => stderr.push(d));
    let timer;
    if (opts.timeout) {
      timer = setTimeout(() => {
        child.kill();
        const e = new Error('ETIMEDOUT'); e.code = 'ETIMEDOUT';
        reject(e);
      }, opts.timeout);
    }
    child.on('error', err => { clearTimeout(timer); reject(err); });
    child.on('close', code => {
      clearTimeout(timer);
      resolve({
        status: code,
        stdout: Buffer.concat(stdout).toString('utf8'),
        stderr: Buffer.concat(stderr).toString('utf8'),
      });
    });
  });
}

// ── Claude 인증 상태 확인 ──────────────────────────────────────────────────────
async function isClaudeAuthed() {
  try {
    const r = await spawnAsync('claude', ['auth', 'status'], { timeout: 10000 });
    return JSON.parse(r.stdout || '{}').loggedIn === true;
  } catch { return true; } // 확인 실패 시 인증됨으로 간주
}

// ── Claude 웹 재인증 (브라우저 팝업) ───────────────────────────────────────────
async function reAuthClaude() {
  console.log('[Auth] claude 인증 만료 감지 — 브라우저 인증 시작...');
  try {
    const r = await spawnAsync('claude', ['auth', 'login', '--email', 'yusuke.shikatani@bloomin.world'], {
      timeout: 5 * 60 * 1000,
      windowsHide: false, // 브라우저가 열릴 수 있도록
    });
    const ok = r.status === 0;
    console.log(`[Auth] 재인증 ${ok ? '성공' : '실패'} (exit ${r.status})`);
    return ok;
  } catch (e) {
    console.log(`[Auth] 재인증 오류: ${e.message}`);
    return false;
  }
}

// ── claude CLI (비동기 — 이벤트 루프 비차단) ──────────────────────────────────
async function callClaude(prompt, workDir = BASE_DIR) {
  const agentDir = getAgentDir(workDir);
  for (let attempt = 0; attempt < 2; attempt++) {
    let result;
    try {
      result = await spawnAsync('claude', [
        '-p', prompt,
        '--model', 'claude-opus-4-8',
        '--add-dir', workDir,        // プロジェクトディレクトリ (サンドボックスに明示追加)
        '--add-dir', agentDir,       // roles/rules/skills/workflows アクセス
        '--add-dir', PROJECTS_ROOT,  // 全プロジェクト横断アクセス
      ], {
        cwd: workDir,
        timeout: 300000,
      });
    } catch (err) {
      throw err; // ETIMEDOUT 등
    }
    if (result.status === 0) return (result.stdout || '').trim();

    // exit 1 — 인증 만료 여부 확인 후 자동 재인증 (1회)
    if (attempt === 0 && !(await isClaudeAuthed())) {
      const ok = await reAuthClaude();
      if (!ok) throw new Error('claude 인증 재시도 실패 — 터미널에서 `claude auth login` 실행 필요');
      continue;
    }
    throw new Error(`claude exit ${result.status}: ${(result.stderr || '').slice(0, 200)}`);
  }
}

// ── 意図分類 (task / question) ────────────────────────────────────────────────
// 「タスク登録」「task登録」等の明記、または明確な作業依頼 → "task"
// 曖昧・質問・情報照会 → "question"
async function classifyRequest(text, workDir = BASE_DIR) {
  // git push / pull / stash などの単純操作はタスク不要 → 即 question
  if (/^\s*(git\s+(push|pull|stash|fetch|merge|rebase|status|log|diff)|タスク(?:一覧|リスト|確認|状況)|tasklist)/i.test(text.replace(/[^\x00-\x7Fぁ-ん亜-熙ー]/g, ' '))) {
    return 'question';
  }

  const prompt = `You are an assistant that classifies the intent of Slack messages.

Message: "${text}"

Classify using the following rules:
- "task": applies when the request requires creating or modifying ANY file on disk:
  1. Explicit registration instruction such as "태스크 등록", "task 추가", "작업 의뢰" etc.
  2. Code change, feature addition, bug fix, refactoring, or configuration file modification
  3. A combination like "do A, and also git push" where A involves file changes
  4. Document/spec creation and saving: "사양서 만들어 저장", "문서로 저장", "파일로 저장해줘", "작성해서 저장", "만들어서 저장"
  5. Any request that ends with saving/writing output to a file or folder on disk

- "question": applies when NO file needs to be created or modified:
  1. Question, information inquiry, explanation request (no file output expected)
  2. Status check, deployment check, environment check, log review
  3. File path inquiry, dashboard check, system status confirmation
  4. Investigation or research only (no file output expected)
  5. Message consisting only of "git push" or "git pull" (no other work instructions)

Key principle: If the request involves writing, saving, or creating ANY file on disk — classify as "task".

Reply with only one word: "task" or "question". No explanation needed.`;

  try {
    const result = await spawnAsync('claude', ['-p', prompt, '--model', 'claude-opus-4-8'], {
      cwd: workDir,
      timeout: 60000,
    });
    if (result.status !== 0) return 'question';
    const out = (result.stdout || '').trim().toLowerCase();
    return out.startsWith('task') ? 'task' : 'question';
  } catch {
    return 'question'; // timeout·오류 시 질문으로 폴백
  }
}

// ── チャンネル Q&A (質問と判定されたときのインライン回答) ────────────────────
// git push / pull のみ（他の作業を含まない）を実行して結果を返す
// 「A機能を修正して git push して」のような複合指示には反応しない
function isPureGitOp(text) {
  // Korean/Chinese/全角を除去し、残ったテキストが git コマンドとその助詞のみか確認
  const stripped = text
    .replace(/<[^>]+>/g, '')          // Slack mrkdwn タグ除去
    .replace(/[^\x00-\x7Fぁ-ん亜-熙ー]/g, ' ')  // Korean等を空白に
    .trim();
  // "git push [して/する/お願い/etc]" のみで構成されているか
  return /^git\s+(push|pull)(\s+(して|する|してください|お願い|please|원|해줘|해주세요))?$/i.test(stripped);
}

async function handleSimpleGitOp({ channelId, replyTs, text, workDir = BASE_DIR }) {
  if (!isPureGitOp(text)) return false;
  const t = text.trim();
  if (/git\s+push/i.test(t)) {
    spawnSync('git', ['pull', '--rebase', 'origin'], { cwd: workDir, encoding: 'utf8', windowsHide: true });
    const res = spawnSync('git', ['push'], { cwd: workDir, encoding: 'utf8', windowsHide: true });
    const ok = res.status === 0;
    await postMessage(channelId, ok ? '✅ git push 完了' : `❌ git push 失敗\n\`\`\`${(res.stderr || '').slice(0, 500)}\`\`\``, replyTs);
    return true;
  }
  if (/git\s+pull/i.test(t)) {
    const res = spawnSync('git', ['pull', '--rebase', 'origin'], { cwd: workDir, encoding: 'utf8', windowsHide: true });
    const ok = res.status === 0;
    await postMessage(channelId, ok ? '✅ git pull 完了' : `❌ git pull 失敗\n\`\`\`${(res.stderr || '').slice(0, 500)}\`\`\``, replyTs);
    return true;
  }
  return false;
}

async function answerInChannel({ channelId, replyTs, text, workDir = BASE_DIR }) {
  if (await handleSimpleGitOp({ channelId, replyTs, text, workDir })) return;

  const claims = searchKLayer(text);
  let issues = [];
  if (['issue', 'bug', 'イシュー', 'バグ', 'task', 'github', '#'].some(k => text.toLowerCase().includes(k))) {
    issues = await getIssues();
  }

  const projectName = path.basename(workDir);
  const agentDir = getAgentDir(workDir);
  let prompt = `You are ${BOT_NAME}, an AI assistant. Respond in the same language as the user's message.

Working project: ${projectName}
Working directory: ${workDir}
Agent context directory: ${agentDir}
  - roles/    : project role definitions
  - rules/    : coding and workflow rules
  - skills/   : available skills
  - workflows/: workflow definitions
Read relevant files from the agent context directory as needed to apply the correct role and rules.

IMPORTANT: Answer based on your knowledge of the project directory and K-Layer context below. If you do not know the answer, say so clearly.

MANDATORY RULE — Task Number: If the user's message contains a 14-digit task number (e.g. 20260630170105), you MUST start your response with "[task \`<task_number>\`]" on the very first line. Never omit the task number from your response.`;
  if (claims.length) prompt += '\n\nK-Layer:\n' + claims.map(c => `• ${c}`).join('\n');
  if (issues.length) prompt += '\n\nOpen Issues:\n' + issues.map(i => `• #${i.number} ${i.title}`).join('\n');
  prompt += `\n\nQuestion: ${text}\nAnswer:`;

  try {
    const reply = await callClaude(prompt, workDir);
    // 코드레벨 강제: 사용자 메시지의 태스크 ID가 응답에 없으면 첫 줄에 삽입
    const missingIds = extractExistingTaskIds(text).filter(id => !reply.includes(id));
    const finalReply = missingIds.length > 0
      ? `[task \`${missingIds.join('`, `')}\`]\n\n${reply}`
      : reply;
    await postLong(channelId, finalReply, replyTs);
  } catch (err) {
    const isTimeout = err.code === 'ETIMEDOUT' || (err.message && err.message.includes('ETIMEDOUT'));
    const msg2 = isTimeout
      ? '⏱️ 処理がタイムアウトしました（5分超過）。もう少し短い要求に分けて送ってください。'
      : `回答エラー: ${err.message}`;
    await postMessage(channelId, msg2, replyTs);
  }
}

// ── DM 처리 (일반 Q&A) ───────────────────────────────────────────────────────
async function handleDM({ channelId, ts, threadTs, text, conversations, workDir = BASE_DIR }) {
  const convKey = channelId;
  const replyTs = threadTs || undefined;
  const cmd = text.trim().toLowerCase();

  if (cmd === '!help') {
    await postMessage(channelId, [
      '*giipclaude AI — DM コマンド一覧*',
      '• `!issues` — GitHub Issue 一覧',
      '• `!issues refresh` — Issue 強制更新',
      '• `!klayer <キーワード>` — K-Layer 知識検索',
      '• `!reset` — 会話履歴リセット',
      'チャンネルで `@ボット名 要求内容` と書くと Task ワークフローが始まります。',
    ].join('\n'), replyTs);
    return;
  }
  if (cmd === '!reset') {
    conversations[convKey] = [];
    await postMessage(channelId, '会話履歴をリセットしました。', replyTs);
    return;
  }
  if (cmd === '!issues' || cmd === '!issues refresh') {
    const issues = cmd.includes('refresh') ? await refreshIssues() : await getIssues();
    if (!issues.length) { await postMessage(channelId, 'GITHUB_TOKEN / GITHUB_REPO の設定を確認してください。', replyTs); return; }
    const lines = issues.map(i => `• #${i.number} ${i.title}`);
    await postMessage(channelId, `Issues (${issues.length}件) — ${getCacheAge()}\n${lines.join('\n')}`, replyTs);
    return;
  }
  if (cmd.startsWith('!klayer ')) {
    const kw = cmd.slice(8).trim();
    const claims = searchKLayer(kw);
    await postMessage(channelId, claims.length ? `K-Layer "${kw}":\n${claims.map(c=>`• ${c}`).join('\n')}` : `"${kw}" に関連する claim はありません`, replyTs);
    return;
  }

  // ── タスク番号による状況照会（DM）────────────────────────────────────────
  const dmTaskMatch = text.trim().match(/^(?:status\s+)?(\d{14})$/);
  if (dmTaskMatch) {
    const targetId = dmTaskMatch[1];
    const taskFile = path.join(AGENT_DIR, 'tasks', `${targetId}.md`);
    if (fs.existsSync(taskFile)) {
      const fc = fs.readFileSync(taskFile, 'utf8');
      const statusM = fc.match(/^status:\s*(.+)$/m);
      const requestM = fc.match(/^request:\s*"?([^\n"]{1,120})/m);
      const status = statusM ? statusM[1].trim() : '不明';
      const request = requestM ? requestM[1].trim() : '（内容なし）';
      const logMatch = fc.match(/## 進捗ログ([\s\S]*)/);
      const logLines = logMatch ? logMatch[1].trim().split('\n').filter(l => l.startsWith('|')).slice(-5).join('\n') : null;
      let reply = `*タスク \`${targetId}\` — 状況報告*\n• ステータス: ${status}\n• 内容: ${request}`;
      if (logLines) reply += `\n\n*進捗ログ（直近）:*\n${logLines}`;
      await postMessage(channelId, reply, replyTs);
    } else {
      await postMessage(channelId, `⚠️ タスク \`${targetId}\` が見つかりません。`, replyTs);
    }
    return;
  }

  // 일반 대화
  const history = conversations[convKey] || [];
  const claims = searchKLayer(text);
  let issues = [];
  if (['issue','bug','이슈','버그','task','github','#'].some(k => text.toLowerCase().includes(k))) {
    issues = await getIssues();
  }

  const projectName = path.basename(workDir);
  const agentDirDM = getAgentDir(workDir);
  let prompt = `You are ${BOT_NAME}, an AI assistant. Respond in the same language as the user's message.\n\nWorking project: ${projectName}\nWorking directory: ${workDir}\nAgent context directory: ${agentDirDM} (roles/, rules/, skills/, workflows/)\nRead relevant files from the agent context directory to apply the correct role and rules.\n\nIMPORTANT: Answer based on your knowledge of the project and K-Layer context. If you do not know the answer, say so clearly.\n\nMANDATORY RULE — Task Number: If the user's message contains a 14-digit task number (e.g. 20260630170105), you MUST start your response with "[task \`<task_number>\`]" on the very first line. Never omit the task number from your response.`;
  if (claims.length) prompt += '\n\nK-Layer:\n' + claims.map(c=>`• ${c}`).join('\n');
  if (issues.length) prompt += '\n\nOpen Issues:\n' + issues.map(i=>`• #${i.number} ${i.title}`).join('\n');
  if (history.length) {
    prompt += '\n\nHistory:';
    history.slice(-10).forEach(m => { prompt += `\n${m.role==='user'?'User':'Assistant'}: ${m.content}`; });
  }
  prompt += `\n\nUser: ${text}\nAssistant:`;

  try {
    const reply = await callClaude(prompt, workDir);
    if (!conversations[convKey]) conversations[convKey] = [];
    conversations[convKey].push({ role: 'user', content: text });
    conversations[convKey].push({ role: 'assistant', content: reply });
    if (conversations[convKey].length > 20) conversations[convKey] = conversations[convKey].slice(-20);
    // 코드레벨 강제: 사용자 메시지의 태스크 ID가 응답에 없으면 첫 줄에 삽입
    const missingIdsDM = extractExistingTaskIds(text).filter(id => !reply.includes(id));
    const finalReplyDM = missingIdsDM.length > 0
      ? `[task \`${missingIdsDM.join('`, `')}\`]\n\n${reply}`
      : reply;
    await postLong(channelId, finalReplyDM, replyTs);
  } catch (err) {
    await postMessage(channelId, `오류: ${err.message}`, replyTs);
  }
}

// ── Task 実行共通処理 ─────────────────────────────────────────────────────────
async function startTaskExecution(pendingKey, pendingTask, channelId, replyTs, taskState, workDir = BASE_DIR) {
  delete taskState.pending[pendingKey];
  const startedAt = new Date().toISOString();
  taskState.running[pendingKey] = {
    taskId: pendingTask.taskId,
    taskTitle: pendingTask.taskTitle,
    startedAt,
  };
  saveJSON(TASK_STATE_FILE, taskState);
  tm.updateTasklistEntry(pendingTask.taskId, { status: 'running', startedAt });

  // ── 作業前に対象ディレクトリで git pull ──────────────────────────────────
  const pull = await gitPullBeforeWork(workDir);
  if (!pull.skipped) {
    if (pull.ok) {
      const alreadyLatest = /already up.to.date/i.test(pull.stdout);
      const pullMsg = alreadyLatest
        ? `🔄 git pull \`${pull.branch}\`: 最新状態`
        : `🔄 git pull \`${pull.branch}\` 完了\n\`\`\`${pull.stdout.slice(0, 300)}\`\`\``;
      await postMessage(channelId, pullMsg, replyTs);
    } else {
      await postMessage(channelId,
        `⚠️ git pull 失敗（作業は続行します）\n\`\`\`${(pull.stderr || pull.stdout).slice(0, 300)}\`\`\``,
        replyTs
      );
    }
  }

  await postMessage(channelId,
    `⚙️ *Task 実行開始*: \`${pendingTask.taskId}\`\n• ${pendingTask.taskTitle}\n\n_サブエージェントが作業中です。完了したら結果 URL をお知らせします。_`,
    replyTs
  );

  tm.startExecution(pendingTask.taskId, pendingTask.taskFile, {
    onComplete: async (resultFile) => {
      const ts2 = loadJSON(TASK_STATE_FILE, {});
      delete ts2.running[pendingKey];
      saveJSON(TASK_STATE_FILE, ts2);

      // 결과 내용을 태스크 파일에 추가하고 done/ 폴더로 이동
      let doneTaskFile = null;
      try {
        const resultContent = fs.existsSync(resultFile) ? fs.readFileSync(resultFile, 'utf8') : '';
        doneTaskFile = tm.completeTaskFile(pendingTask.taskId, resultContent);
      } catch (e) {
        console.error('[Bot] completeTaskFile error:', e.message);
      }

      const githubUrl = tm.gitPushResult(pendingTask.taskId, pendingTask.taskTitle, resultFile, doneTaskFile);
      tm.updateTasklistEntry(pendingTask.taskId, {
        status: 'completed',
        completedAt: new Date().toISOString(),
        resultUrl: githubUrl || null,
      });
      if (githubUrl) {
        await postMessage(channelId,
          `✅ *작업 완료*: \`${pendingTask.taskId}\`\n• ${pendingTask.taskTitle}\n\n📋 태스크 결과 보고서: ${githubUrl}`,
          replyTs
        );
      } else {
        await postMessage(channelId,
          `✅ *작업 완료* (⚠️ git push 실패 — 원격 미반영이라 GitHub URL 미생성)\n• \`${pendingTask.taskId}\`: ${pendingTask.taskTitle}\n결과 파일: \`.agent/tasks/done/${pendingTask.taskId}.md\`\n봇 로그의 git push 오류를 확인하세요.`,
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
      tm.updateTasklistEntry(pendingTask.taskId, {
        status: 'cancelled',
        completedAt: new Date().toISOString(),
        resultUrl: githubUrl || null,
      });
      await postMessage(channelId,
        `❌ *작업 에러* (\`${pendingTask.taskId}\`): ${err.message}${githubUrl ? `\n📄 에러 로그: ${githubUrl}` : ''}`,
        replyTs
      );
    },
  }, workDir);
}

// ── チャンネル Mention 処理 (Task ワークフロー) ───────────────────────────────
async function handleChannelMention({ channelId, ts, threadTs, text, workDir = BASE_DIR }) {
  const convKey = `${channelId}:${threadTs || ts}`;
  const replyTs = threadTs || ts;
  const taskState = loadJSON(TASK_STATE_FILE, { pending: {}, running: {} });

  // バッククォート・全角スペース等を除去してからコマンド判定
  const cmd = text.trim().replace(/`/g, '').replace(/\s+/g, ' ').toLowerCase();
  console.log(`[Bot] handleChannelMention cmd="${cmd}" convKey="${convKey}"`);

  // ── 내장 명령어 ─────────────────────────────────────────────────────────────
  if (cmd === '!help') {
    await postMessage(channelId, [
      '*giipclaude AI — 使い方*',
      '`@ボット名 <質問>` → その場で回答（曖昧な内容も質問扱い）',
      '`@ボット名 <作業依頼>` → Task 分析 → 確認 → 実行 → GitHub 結果 URL',
      '`@ボット名 タスク登録: <内容>` → 強制的に Task として登録',
      '',
      '*Task 管理:*',
      '• `tasklist` — 待機中 Task 一覧',
      '• `tasklist all` — 全 Task 一覧 (完了・キャンセル含む)',
      '• `go` — 待機中 Task の一覧を表示',
      '• `go <Task番号>` — 指定した Task を実行',
      '• `cancel` — 待機中 Task の一覧を表示',
      '• `cancel <Task番号>` — 指定した Task をキャンセル',
      '',
      '*ワークフロー:*',
      '• `<プロジェクト名> wflist` — そのプロジェクトの .agent/workflows 一覧',
      '• `<プロジェクト名> wflist <絞り込み語>` — 名前で絞り込み',
      '• `<プロジェクト名> wflist all` — 参考ドキュメントも表示',
      '• `<プロジェクト名> 워크플로우 <名>` — ワークフローを実行 (`wfrun <名>` も可)',
      '',
      '*情報:*',
      '• `!issues` — GitHub Issue 一覧',
      '• `!klayer <キーワード>` — K-Layer 検索',
      '• `!help` — ヘルプ',
    ].join('\n'), replyTs);
    return;
  }
  if (cmd === '!issues' || cmd === '!issues refresh') {
    const issues = cmd.includes('refresh') ? await refreshIssues() : await getIssues();
    if (!issues.length) { await postMessage(channelId, 'GITHUB_TOKEN / GITHUB_REPO の設定を確認してください。', replyTs); return; }
    const lines = issues.map(i => `• #${i.number} ${i.title}`);
    await postMessage(channelId, `Issues (${issues.length}件) — ${getCacheAge()}\n${lines.join('\n')}`, replyTs);
    return;
  }
  if (cmd.startsWith('!klayer ')) {
    const kw = cmd.slice(8).trim();
    const claims = searchKLayer(kw);
    await postMessage(channelId, claims.length ? `K-Layer "${kw}":\n${claims.map(c=>`• ${c}`).join('\n')}` : `"${kw}" に関連する claim はありません`, replyTs);
    return;
  }

  // ── wflist — 指定プロジェクトの .agent/workflows 一覧 ──────────────────────
  //   使い方: `<プロジェクト名> wflist [絞り込み語|all]`
  //   プロジェクト名は parseProjectPrefix で workDir に解決済み。
  //   例: `giipprj wflist` → giipprj/.agent/workflows を一覧表示。
  //   `all` を付けると README 等の参考ドキュメントも表示。
  if (cmd === 'wflist' || cmd.startsWith('wflist ')) {
    const filter = cmd === 'wflist' ? '' : cmd.slice('wflist '.length).trim();
    const showAll = filter === 'all';
    const agentDir = getAgentDir(workDir);
    const wfDir = path.join(agentDir, 'workflows');
    const projName = path.basename(workDir);
    const usingFallback = !fs.existsSync(path.join(workDir, '.agent'));
    let files = [];
    try { files = fs.readdirSync(wfDir).filter(f => f.toLowerCase().endsWith('.md')); } catch { files = []; }
    if (!files.length) {
      await postMessage(channelId,
        `📂 \`${projName}\` の .agent/workflows にワークフローがありません。\n探索パス: \`${wfDir}\``,
        replyTs);
      return;
    }
    const isDoc = f => /^(readme|common_|scheduling|_)/i.test(f);
    const nameOf = f => f.replace(/\.md$/i, '');
    let wf = files.filter(f => !isDoc(f)).sort();
    const docs = files.filter(isDoc).sort();
    if (filter && !showAll) wf = wf.filter(f => f.toLowerCase().includes(filter));
    const header = usingFallback
      ? `📋 *\`${projName}\` に .agent が無いため既定(${path.basename(BASE_DIR)}/.agent)を表示* (${wf.length}件)`
      : `📋 *\`${projName}\` ワークフロー一覧* (${wf.length}件${filter && !showAll ? ` / 絞り込み: "${filter}"` : ''})`;
    const lines = wf.length ? wf.map(f => `• \`${nameOf(f)}\``) : ['(該当なし)'];
    if (showAll && docs.length) lines.push('', '_参考ドキュメント:_ ' + docs.map(f => `\`${nameOf(f)}\``).join(', '));
    await postMessage(channelId, `${header}\n${lines.join('\n')}`, replyTs);
    return;
  }

  // ── wfrun / 워크플로우 <이름> — 指定ワークフローをサブエージェントで実行 ──────
  //   使い方: `<プロジェクト名> 워크플로우 <ワークフロー名>` または `<プロジェクト名> wfrun <名>`
  //   名前は wflist の表示名（拡張子なし）。完全一致 → 部分一致の順で解決。
  //   例: `giipprj 워크플로우 gissue-sync` → giipprj/.agent/workflows/gissue-sync.md を実行。
  {
    const wfRun = cmd.match(/^(?:wfrun|wf run|워크플로우\s*실행|워크플로우|워크플로)\s+(.+)$/);
    if (wfRun) {
      const query = wfRun[1].trim().replace(/\.md$/i, '');
      const agentDir = getAgentDir(workDir);
      const wfDir = path.join(agentDir, 'workflows');
      const projName = path.basename(workDir);
      let files = [];
      try { files = fs.readdirSync(wfDir).filter(f => f.toLowerCase().endsWith('.md')); } catch { files = []; }
      const isDoc = f => /^(readme|common_|scheduling|_)/i.test(f);
      const candidates = files.filter(f => !isDoc(f));
      const nameOf = f => f.replace(/\.md$/i, '');
      const q = query.toLowerCase();
      let match = candidates.find(f => nameOf(f).toLowerCase() === q);
      if (!match) {
        const subs = candidates.filter(f => f.toLowerCase().includes(q));
        if (subs.length === 1) match = subs[0];
        else if (subs.length > 1) {
          await postMessage(channelId,
            `🔎 \`${query}\` に一致するワークフローが複数あります。1つに絞ってください:\n${subs.map(f => `• \`${nameOf(f)}\``).join('\n')}`,
            replyTs);
          return;
        }
      }
      if (!match) {
        const list = candidates.length ? candidates.map(f => `• \`${nameOf(f)}\``).join('\n') : '(なし)';
        await postMessage(channelId,
          `❓ \`${projName}\` に \`${query}\` というワークフローが見つかりません。\n利用可能:\n${list}\n\n一覧: \`${projName} wflist\``,
          replyTs);
        return;
      }
      const wfPath = path.join(wfDir, match);
      const wfName = nameOf(match);
      let wfContent = '';
      try { wfContent = fs.readFileSync(wfPath, 'utf8'); }
      catch (e) { await postMessage(channelId, `⚠️ ワークフロー読み込み失敗: ${e.message}`, replyTs); return; }
      const relWf = path.relative(workDir, wfPath).replace(/\\/g, '/');
      const taskId = tm.getTimestampId();
      const planContent = [
        `# TASK: 워크플로우 실행 — ${wfName} (${projName})`,
        '',
        '## リクエスト内容',
        `プロジェクト \`${projName}\` のワークフロー \`${wfName}\` を定義どおり実行`,
        '',
        '## 実行方針',
        `- 対象ワークフロー定義: \`${relWf}\``,
        '- 下記「ワークフロー定義」を上から順に、記載どおり忠実に実行する。',
        '- 定義が他の roles/rules/skills/workflows を参照する場合、.agent 配下の該当ファイルを読んで従う。',
        '- ファイルを変更したら実行プロンプトの共通規則に従い即コミット＆push する。',
        '',
        '## ワークフロー定義（この内容を実行）',
        `===== BEGIN WORKFLOW: ${wfName} =====`,
        wfContent.trim(),
        `===== END WORKFLOW: ${wfName} =====`,
      ].join('\n');
      const taskFile = tm.createTaskFile(taskId, `[wfrun] ${projName}/${wfName}`, planContent, [wfPath]);
      const taskTitle = tm.extractTitle(planContent);
      const taskSummary = tm.extractSummary(planContent);
      taskState.pending[convKey] = { taskId, taskTitle, taskFile, requestText: `wfrun ${wfName}` };
      saveJSON(TASK_STATE_FILE, taskState);
      tm.addToTasklist(taskId, taskTitle, taskSummary, `wfrun ${wfName}`);
      await postMessage(channelId,
        `🚀 *ワークフロー実行*: \`${wfName}\` (プロジェクト \`${projName}\`)\nTask \`${taskId}\` として開始します。`,
        replyTs);
      await startTaskExecution(convKey, taskState.pending[convKey], channelId, replyTs, taskState, workDir);
      return;
    }
  }

  // ── tasklist / tasklist all ────────────────────────────────────────────────
  if (cmd === 'tasklist' || cmd === 'tasklist all') {
    const showAll = cmd === 'tasklist all';
    const tasks = tm.getTasklistByStatus(showAll ? null : 'pending');
    if (tasks.length === 0) {
      await postMessage(channelId,
        showAll ? '記録された Task はありません。' : '待機中の Task はありません。\n全履歴は `tasklist all` で確認できます。',
        replyTs
      );
      return;
    }
    const lines = tasks.map(t => {
      const emoji = tm.statusEmoji(t.status);
      const date = t.createdAt ? t.createdAt.slice(0, 10) : '';
      const taskUrl = tm.getTaskFileUrl(t.taskId);
      const taskLink = taskUrl ? `\n     📁 ${taskUrl}` : '';
      const result = t.resultUrl ? `\n     📄 ${t.resultUrl}` : '';
      return `${emoji} \`${t.taskId}\` [${t.status}] ${date}\n     *${t.title}*\n     ${t.summary}${taskLink}${result}`;
    });
    const header = showAll
      ? `*全 Task 一覧 (${tasks.length}件)*`
      : `*待機中 Task 一覧 (${tasks.length}件)*`;
    await postLong(channelId, [header, '', ...lines].join('\n'), replyTs);
    return;
  }

  // ── cancel <Task番号> — スレッド不問でどこからでもキャンセル ──────────────
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
      await postMessage(channelId, `🚫 Task \`${targetId}\` をキャンセルしました。\n• ${task.taskTitle}`, replyTs);
    } else {
      const runEntry = Object.entries(taskState.running || {}).find(([, t]) => t.taskId === targetId);
      if (runEntry) {
        await postMessage(channelId, `⚠️ \`${targetId}\` は実行中のためキャンセルできません。`, replyTs);
      } else {
        // taskState にないが .agent/tasks/ ファイルがあればキャンセル
        const taskFilePath = path.join(AGENT_DIR, 'tasks', `${targetId}.md`);
        if (fs.existsSync(taskFilePath)) {
          try {
            const dest = tm.cancelTaskFile(targetId);
            tm.updateTasklistEntry(targetId, { status: 'cancelled', completedAt: new Date().toISOString() });
            await postMessage(channelId, `🚫 Task \`${targetId}\` をキャンセルしました。\n📁 移動先: \`${dest}\``, replyTs);
          } catch (err) {
            await postMessage(channelId, `⚠️ キャンセル失敗: ${err.message}`, replyTs);
          }
        } else {
          await postMessage(channelId, `⚠️ Task \`${targetId}\` が見つかりません。\n\`tasklist\` で一覧を確認してください。`, replyTs);
        }
      }
    }
    return;
  }

  // ── bare cancel — 待機中 Task の一覧を表示 ───────────────────────────────
  if (isCancelCmd(text)) {
    const allPending = Object.entries(taskState.pending || {});
    if (allPending.length === 0) {
      await postMessage(channelId, '待機中の Task はありません。', replyTs);
      return;
    }
    const lines = allPending.map(([, t]) => `• \`${t.taskId}\` — ${t.taskTitle}`);
    await postMessage(channelId, [
      `*待機中 Task 一覧 (${allPending.length}件)*`,
      ...lines,
      '',
      'キャンセルするには: `cancel <Task番号>`',
      '例: `cancel ' + allPending[0][1].taskId + '`',
    ].join('\n'), replyTs);
    return;
  }

  // ── go <Task番号> — スレッド不問で指定 Task を実行 ──────────────────────
  const goWithId = cmd.match(/^(?:go|start|실행|시작|진행|実行|開始)\s+(\d{14})$/);
  if (goWithId) {
    const targetId = goWithId[1];
    const entry = Object.entries(taskState.pending || {}).find(([, t]) => t.taskId === targetId);
    if (!entry) {
      const runEntry = Object.entries(taskState.running || {}).find(([, t]) => t.taskId === targetId);
      if (runEntry) {
        await postMessage(channelId, `⚙️ \`${targetId}\` はすでに実行中です。`, replyTs);
        return;
      }
      // .task-state.json になくても .agent/tasks/{id}.md があれば実行
      const taskFileFallback = path.join(AGENT_DIR, 'tasks', `${targetId}.md`);
      if (fs.existsSync(taskFileFallback)) {
        const fc = fs.readFileSync(taskFileFallback, 'utf8');
        const titleMatch = fc.match(/^# TASK:\s*(.+)$/m);
        const taskTitle = titleMatch ? titleMatch[1].trim() : `タスク ${targetId}`;
        const pendingKeyNew = `${channelId}:${replyTs}`;
        taskState.pending[pendingKeyNew] = { taskId: targetId, taskTitle, taskFile: taskFileFallback, requestText: '' };
        saveJSON(TASK_STATE_FILE, taskState);
        await startTaskExecution(pendingKeyNew, taskState.pending[pendingKeyNew], channelId, replyTs, taskState, workDir);
      } else {
        const doneFile   = path.join(AGENT_DIR, 'tasks', 'done',   `${targetId}.md`);
        const cancelFile = path.join(AGENT_DIR, 'tasks', 'cancel', `${targetId}.md`);
        if (fs.existsSync(doneFile)) {
          await postMessage(channelId, `✅ Task \`${targetId}\` はすでに完了しています。\nファイル: \`.agent/tasks/done/${targetId}.md\``, replyTs);
        } else if (fs.existsSync(cancelFile)) {
          await postMessage(channelId, `🚫 Task \`${targetId}\` はキャンセル済みです。`, replyTs);
        } else {
          await postMessage(channelId, `⚠️ Task \`${targetId}\` が見つかりません。\n\`tasklist\` で一覧を確認してください。`, replyTs);
        }
      }
      return;
    }
    const [pendingKey, pendingTask] = entry;
    await startTaskExecution(pendingKey, pendingTask, channelId, replyTs, taskState, workDir);
    return;
  }

  // ── bare go — 待機中 Task の一覧を表示 ──────────────────────────────────
  if (isGoCmd(text)) {
    const allPending = Object.entries(taskState.pending || {});
    if (allPending.length === 0) {
      await postMessage(channelId, '待機中の Task はありません。新しいリクエストを入力してください。', replyTs);
      return;
    }
    const lines = allPending.map(([, t]) => `• \`${t.taskId}\` — ${t.taskTitle}`);
    await postMessage(channelId, [
      `*待機中 Task 一覧 (${allPending.length}件)*`,
      ...lines,
      '',
      '実行するには: `go <Task番号>`',
      '例: `go ' + allPending[0][1].taskId + '`',
    ].join('\n'), replyTs);
    return;
  }

  // ── タスク番号による状況照会（14桁数字のみ or "status <14桁>"） ──────────
  const taskStatusMatch = text.trim().replace(/`/g, '').match(/^(?:status\s+)?(\d{14})$/);
  if (taskStatusMatch) {
    const targetId = taskStatusMatch[1];
    const taskFile = path.join(AGENT_DIR, 'tasks', `${targetId}.md`);
    if (fs.existsSync(taskFile)) {
      const fc = fs.readFileSync(taskFile, 'utf8');
      const statusM = fc.match(/^status:\s*(.+)$/m);
      const requestM = fc.match(/^request:\s*"?([^\n"]{1,120})/m);
      const status = statusM ? statusM[1].trim() : '不明';
      const request = requestM ? requestM[1].trim() : '（内容なし）';
      const logMatch = fc.match(/## 進捗ログ([\s\S]*)/);
      const logLines = logMatch ? logMatch[1].trim().split('\n').filter(l => l.startsWith('|')).slice(-5).join('\n') : null;
      let reply = `*タスク \`${targetId}\` — 状況報告*\n• ステータス: ${status}\n• 内容: ${request}`;
      if (logLines) reply += `\n\n*進捗ログ（直近）:*\n${logLines}`;
      reply += `\n\n実行: \`go ${targetId}\` | キャンセル: \`cancel ${targetId}\``;
      await postMessage(channelId, reply, replyTs);
    } else {
      await postMessage(channelId, `⚠️ タスク \`${targetId}\` が見つかりません。`, replyTs);
    }
    return;
  }

  // ── push 失敗通知 → 全リポジトリ状況を自動チェック ──────────────────────
  if (isPushFailureNotice(text)) {
    await postLong(channelId, checkAllRepoStatus(), replyTs);
    return;
  }

  // ── 既存タスクIDへの言及 → 質問なら答える、作業依頼なら新規作成を防ぐ ────
  const mentionedIds = extractExistingTaskIds(text);
  if (mentionedIds.length > 0) {
    const targetId = mentionedIds[0];
    const activeFile = [
      path.join(AGENT_DIR, 'tasks', `${targetId}.md`),
      path.join(AGENT_DIR, 'tasks', 'done', `${targetId}.md`),
      path.join(AGENT_DIR, 'tasks', 'cancel', `${targetId}.md`),
    ].find(f => fs.existsSync(f));

    // テキストがタスクIDだけでなく質問内容も含む場合は意図を判定する
    const isOnlyId = text.trim().replace(/`/g, '').match(/^(\d{14}|\d{8}_[\w-]+)$/);
    if (!isOnlyId) {
      const mentionIntent = await classifyRequest(text, workDir);
      if (mentionIntent === 'question') {
        // 質問なのでそのまま回答する（タスクファイルのパスをコンテキストとして付加）
        const taskContext = activeFile
          ? `\n\n[参考] タスク ${targetId} のファイルパス: ${activeFile}`
          : '';
        await answerInChannel({ channelId, replyTs, text: text + taskContext, workDir });
        return;
      }
    }

    // 作業依頼 or IDのみ → 状態を表示して新規タスク作成を防ぐ
    if (activeFile) {
      const fc = fs.readFileSync(activeFile, 'utf8');
      const statusM = fc.match(/^status:\s*(.+)$/m);
      const requestM = fc.match(/^request:\s*"?([^\n"]{1,100})/m);
      const status = statusM ? statusM[1].trim() : '不明';
      const request = requestM ? requestM[1].trim() : '（内容なし）';
      await postMessage(channelId,
        `📌 タスク \`${targetId}\` 参照:\n• ステータス: ${status}\n• 内容: ${request}\n📁 ファイル: \`${activeFile}\`\n\n_タスク番号が含まれるため新規タスクは作成しません。_\n別の作業指示は新しいメッセージで送ってください。`,
        replyTs
      );
    }
    return;
  }

  // ── 実行中チェック ────────────────────────────────────────────────────────
  const running = taskState.running[convKey];
  if (running) {
    await postMessage(channelId,
      `⚙️ \`${running.taskId}\` の作業が進行中です。完了次第、結果をお知らせします。`,
      replyTs
    );
    return;
  }

  // ── 意図を分類してルーティング ──────────────────────────────────────────────
  const intent = await classifyRequest(text, workDir);
  console.log(`[Bot] intent="${intent}" text="${text.slice(0, 60)}"`);

  if (intent === 'question') {
    // 質問・曖昧 → その場で回答
    await answerInChannel({ channelId, replyTs, text, workDir });
    return;
  }

  // ── タスク確定 → 類似タスク自動クローズ → Task 分析 ──────────────────────
  // 同一内容の旧タスクを自動検出してクローズ
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
    closedNotice = `\n\n⚠️ 同一内容の旧タスクを自動クローズしました:\n${closedLines.join('\n')}`;
  }

  await postMessage(channelId, '🔍 作業内容を分析中です...', replyTs);

  let planContent, filesRead;
  try {
    ({ planContent, filesRead } = tm.analyzeRequest(text, null, workDir));
  } catch (err) {
    await postMessage(channelId, `分析エラー: ${err.message}`, replyTs);
    return;
  }

  const taskId = tm.getTimestampId();
  const taskFile = tm.createTaskFile(taskId, text, planContent, filesRead);
  const taskTitle = tm.extractTitle(planContent);
  const taskSummary = tm.extractSummary(planContent);

  taskState.pending[convKey] = { taskId, taskTitle, taskFile, requestText: text };
  saveJSON(TASK_STATE_FILE, taskState);
  tm.addToTasklist(taskId, taskTitle, taskSummary, text);

  await postLong(channelId,
    `📋 *Task 分析完了* (\`${taskId}\`)${closedNotice}\n\n${planContent}\n\n---\n*実行: \`go ${taskId}\` / キャンセル: \`cancel ${taskId}\`*`,
    replyTs
  );
}

// pending/running task があるスレッドかどうかを確認
function isActiveTaskThread(channelId, threadTs) {
  if (!threadTs) return false;
  const taskState = loadJSON(TASK_STATE_FILE, { pending: {}, running: {} });
  const convKey = `${channelId}:${threadTs}`;
  return !!(taskState.pending[convKey] || taskState.running[convKey]);
}

// ── メッセージ1件を処理 ───────────────────────────────────────────────────────
async function processMessage({ channelId, msg, isDM, conversations, threadTs }) {
  const effectiveThreadTs = threadTs || msg.thread_ts || null;
  const mentionsBot = BOT_USER_ID && msg.text.includes(`<@${BOT_USER_ID}>`);
  const isTaskReply = isActiveTaskThread(channelId, effectiveThreadTs);
  const isEngagedThread = isBotEngagedThread(channelId, effectiveThreadTs);

  const rawCleanText = msg.text
    .replace(/<@[A-Z0-9]+>/g, '')
    // Slack tel: link <tel:0120...|0120...> → 数字だけ残す（タスク番号が電話番号リンク化される対策）
    .replace(/<tel:(\d+)\|[^>]*>/g, '$1')
    .replace(/<tel:(\d+)>/g, '$1')
    // Slack URL形式 <https://url|表示テキスト> → URL本体だけ残す
    .replace(/<(https?:\/\/[^|>]+)\|[^>]*>/g, '$1')
    // Slack URL形式 <https://url> → URL本体だけ残す
    .replace(/<(https?:\/\/[^>]+)>/g, '$1')
    // Slack装飾記号を除去 (*bold* → bold, _italic_ → italic)
    .replace(/[*_~]/g, '')
    .replace(/`/g, '')
    .trim();

  // プロジェクトプレフィックス検出: "giipprj 何か" → giipprj フォルダに切り替え
  const { workDir, cleanText } = parseProjectPrefix(rawCleanText);

  const hasFiles = msg.files && msg.files.length > 0;
  if (hasFiles && !cleanText) {
    if (mentionsBot || isEngagedThread) {
      await postMessage(channelId, '画像やファイルのみのメッセージは処理できません。テキストで質問してください。', effectiveThreadTs || msg.ts);
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

// ── Socket Mode イベントハンドラ ─────────────────────────────────────────────
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

// ── 重複プロセス検出・自己終了 ───────────────────────────────────────────────
function killDuplicateBots() {
  const myPid = process.pid;
  const result = spawnSync('powershell', [
    '-NonInteractive', '-NoProfile', '-Command',
    `Get-WmiObject Win32_Process -Filter "Name='node.exe'" | Where-Object { $_.CommandLine -like '*index.js*' } | Select-Object -ExpandProperty ProcessId`,
  ], { encoding: 'utf8', timeout: 6000, windowsHide: true });

  if (result.error) return;

  const otherPids = (result.stdout || '')
    .split(/\r?\n/)
    .map(l => parseInt(l.trim(), 10))
    .filter(p => !isNaN(p) && p !== myPid);

  if (otherPids.length === 0) return;

  console.log(`[Bot] 重複インスタンス検出: PID ${otherPids.join(', ')} → 終了します`);
  otherPids.forEach(p => {
    spawnSync('taskkill', ['/F', '/PID', String(p)], { encoding: 'utf8', timeout: 3000, windowsHide: true });
  });
}

// ── 起動時 stale タスク状態のクリーンアップ ──────────────────────────────────
// ボットが再起動した際、running 状態のまま残っているタスクを reconcile する
// - done/ または cancel/ フォルダにファイルがあれば → running から除去
// - tasks/ にもファイルがなければ → 行方不明として running から除去
function reconcileTaskState() {
  const taskState = loadJSON(TASK_STATE_FILE, { pending: {}, running: {} });
  const runningEntries = Object.entries(taskState.running || {});
  if (!runningEntries.length) return;

  const TASKS_DIR = path.join(AGENT_DIR, 'tasks');
  let changed = false;

  for (const [key, entry] of runningEntries) {
    const taskId = entry.taskId;
    const inDone   = fs.existsSync(path.join(TASKS_DIR, 'done',   `${taskId}.md`));
    const inCancel = fs.existsSync(path.join(TASKS_DIR, 'cancel', `${taskId}.md`));
    const inPending = fs.existsSync(path.join(TASKS_DIR, `${taskId}.md`));

    if (inDone || inCancel || !inPending) {
      const reason = inDone ? 'done' : inCancel ? 'cancelled' : 'missing';
      console.log(`[Bot] reconcile: task ${taskId} (${reason}) — removing from running`);
      delete taskState.running[key];
      tm.updateTasklistEntry(taskId, { status: inDone ? 'completed' : 'cancelled' });
      changed = true;
    }
  }

  if (changed) saveJSON(TASK_STATE_FILE, taskState);
}

// ── 起動 ──────────────────────────────────────────────────────────────────────
async function main() {
  if (!BOT_TOKEN) { console.error('[Bot] SLACK_BOT_TOKEN が .env にありません'); process.exit(1); }
  if (!SLACK_APP_TOKEN) { console.error('[Bot] SLACK_APP_TOKEN が .env にありません'); process.exit(1); }

  const ver = spawnSync('claude', ['--version'], { encoding: 'utf8', windowsHide: true });
  if (ver.error) { console.error('[Bot] claude CLI が見つかりません (PATH 確認)'); process.exit(1); }

  const auth = await slackGet('auth.test');
  if (!auth.ok) { console.error('[Bot] SLACK_BOT_TOKEN 無効:', auth.error); process.exit(1); }
  BOT_USER_ID = auth.user_id;

  console.log('[giipclaude Bot] 起動 — Socket Mode');
  console.log(`[Bot] ID: ${BOT_USER_ID} (${auth.user}) PID: ${process.pid}`);
  console.log(`[Bot] 監視チャンネル: ${CHANNEL_IDS.join(', ') || '(DM のみ)'}`);

  killDuplicateBots();
  reconcileTaskState();

  const conversations = loadJSON(HISTORY_FILE, {});

  const socketClient = new SocketModeClient({
    appToken: SLACK_APP_TOKEN,
    clientPingTimeout: 10000,  // 10s
    serverPingTimeout: 60000,  // 1min
  });

  const safeAck = async (ack) => {
    try { await ack(); } catch (e) { console.warn('[Bot] ack failed (reconnecting?):', e.message); }
  };

  // チャンネルでの @mention (app_mention イベント)
  socketClient.on('app_mention', async ({ event, ack }) => {
    await safeAck(ack);
    console.log('[Bot] app_mention:', event.channel, (event.text || '').slice(0, 60));
    await onSlackMessage(event, conversations);
  });

  // DM・スレッド返信 (message イベント — message.im / message.channels 購読時)
  // @mention を含むチャンネルメッセージは app_mention で処理済みのためスキップ
  socketClient.on('message', async ({ event, ack }) => {
    await safeAck(ack);
    const isDM = event.channel_type === 'im';
    const mentionsBot = BOT_USER_ID && (event.text || '').includes(`<@${BOT_USER_ID}>`);
    if (!isDM && mentionsBot) return; // app_mention ハンドラで処理済み — 重複スキップ
    console.log('[Bot] message:', event.channel_type, (event.text || '').slice(0, 60));
    await onSlackMessage(event, conversations);
  });

  // 全WebSocketメッセージをデバッグログ
  socketClient.on('ws_message', (data) => {
    try {
      const p = JSON.parse(data.toString());
      if (p.type !== 'hello' && p.type !== 'disconnect') {
        console.log('[Debug ws]', p.type, p.payload?.event?.type || '', p.payload?.event?.channel_type || '');
      }
    } catch {}
  });

  socketClient.on('error', (error) => {
    console.error('[Bot] Socket Mode error:', error.message || error);
  });

  await socketClient.start();
  console.log('[Bot] Socket Mode 接続完了 — イベント待機中');
}

main().catch(err => { console.error('[Bot] Fatal:', err); process.exit(1); });
