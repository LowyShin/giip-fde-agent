/**
 * slack-api.js — Slack API 呼び出しとスレッド読み取り
 *
 * index.js から behavior-preserving に切り出したモジュール。
 * BOT_USER_ID 参照は config.getBotUserId() に置換済み（挙動は同一）。
 */

const https = require('https');
const config = require('./config');
const { BOT_TOKEN, BOT_NAME } = config;
const { markThreadEngaged } = require('./state');

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

// ── スレッド全体を読み取る (conversations.replies) ───────────────────────────
// Bot は mention された1件のメッセージしか event で受け取らないため、スレッドの
// 前後文脈は Slack API で明示的に取得しないと Claude からは全く見えない。
// これを行わないと「이전 대화 기록이 없습니다 / no prior conversation」等の誤答になる。
// 必要スコープ: channels:history / groups:history（本文）, users:read（話者の実名解決/任意）。
const _userNameCache = new Map();
let _usersReadMissing = false; // users:read スコープ無し → users.info 呼び出しを打ち切る
async function resolveUserName(userId) {
  if (!userId) return null;
  if (config.getBotUserId() && userId === config.getBotUserId()) return BOT_NAME;
  if (_userNameCache.has(userId)) return _userNameCache.get(userId);
  // users:read が無い環境では users.info が missing_scope になる。一度失敗したら
  // 以降は API を叩かず ID をそのまま話者ラベルにフォールバック（同一話者は同一IDで一貫）。
  if (_usersReadMissing) { _userNameCache.set(userId, userId); return userId; }
  const res = await slackGet('users.info', { user: userId });
  if (res && res.ok === false && res.error === 'missing_scope') _usersReadMissing = true;
  const name = (res.ok && res.user)
    ? ((res.user.profile && res.user.profile.display_name) || res.user.real_name || res.user.name || userId)
    : userId;
  _userNameCache.set(userId, name);
  return name;
}

// Slack メッセージ本文を人間可読テキストへ整形（mention/tel/url/装飾記号を除去）
function cleanThreadText(t) {
  return (t || '')
    .replace(/<@[A-Z0-9]+>/g, '@mention')
    .replace(/<tel:(\d+)\|[^>]*>/g, '$1')
    .replace(/<tel:(\d+)>/g, '$1')
    .replace(/<(https?:\/\/[^|>]+)\|[^>]*>/g, '$1')
    .replace(/<(https?:\/\/[^>]+)>/g, '$1')
    .replace(/`/g, '')
    .trim();
}

// threadTs のスレッド全体を「話者: 発言」形式のテキストで返す。取得不可なら ''。
// 他の bot/app の発言も username 付きで含める。
async function fetchThreadTranscript(channelId, threadTs) {
  if (!threadTs) return '';
  const res = await slackGet('conversations.replies', {
    channel: channelId, ts: threadTs, limit: 200,
  });
  if (!res.ok || !Array.isArray(res.messages) || res.messages.length === 0) {
    if (res && res.ok === false) console.error(`[Bot] conversations.replies error: ${res.error}`);
    return '';
  }
  const lines = [];
  for (const m of res.messages) {
    let name = m.username || null;
    if (!name && m.user) name = await resolveUserName(m.user);
    if (!name) name = m.bot_id ? 'bot' : 'unknown';
    let body = cleanThreadText(m.text);
    if (!body && m.files && m.files.length) body = `(attachment x${m.files.length})`;
    if (!body && m.attachments && m.attachments.length) {
      body = cleanThreadText(m.attachments.map(a => a.text || a.fallback || '').join(' '));
    }
    if (!body) continue;
    lines.push(`${name}: ${body}`);
  }
  let transcript = lines.join('\n');
  const MAX = 12000; // プロンプト肥大を防ぐ上限（超過分は古い側を切る）
  if (transcript.length > MAX) transcript = '…(older messages truncated)\n' + transcript.slice(-MAX);
  return transcript;
}

// ── Read other threads referenced by URL (Method 2) ──────────────────────────
// Detect Slack permalinks pasted in the message → read that channel/thread via
// conversations.replies and inject it into the prompt. This is what lets a single
// line "summarize this URL thread" pull in another thread (same or other channel).
//   https://<workspace>.slack.com/archives/<channel>/p<16-digit ts>[?thread_ts=..]
//     channel   = <channel>
//     thread_ts = the ?thread_ts= value if present (thread root), else p<ts> → 10digits.6digits
// Requires: the bot is a member of that channel AND has channels:history (public) /
// groups:history (private) scope; otherwise the read fails gracefully.
const SLACK_ARCHIVE_RE = /https?:\/\/[a-z0-9][a-z0-9.-]*\.slack\.com\/archives\/([A-Z0-9]+)\/p(\d{10})(\d{6})(?:\?\S*?thread_ts=(\d+\.\d+))?/gi;

function parseSlackArchiveUrls(text) {
  const out = [];
  const seen = new Set();
  SLACK_ARCHIVE_RE.lastIndex = 0;
  let m;
  while ((m = SLACK_ARCHIVE_RE.exec(text)) !== null) {
    const channel = m[1];
    // Reply link (?thread_ts=..) → use the root ts; otherwise use p<ts>.
    const ts = m[4] ? m[4] : `${m[2]}.${m[3]}`;
    const key = `${channel}:${ts}`;
    if (seen.has(key)) continue;
    seen.add(key);
    out.push({ channel, ts, url: m[0] });
  }
  return out;
}

// Read every referenced URL and return a "▼ Referenced thread …" block string, or ''.
// Skips the very thread being answered (already provided as current-thread context).
async function fetchReferencedThreads(text, currentChannelId, currentThreadTs) {
  const refs = parseSlackArchiveUrls(text);
  if (!refs.length) return '';
  const blocks = [];
  for (const ref of refs) {
    if (ref.channel === currentChannelId && currentThreadTs && ref.ts === currentThreadTs) continue;
    let transcript = '';
    try {
      transcript = await fetchThreadTranscript(ref.channel, ref.ts);
    } catch (e) {
      console.error('[Bot] fetchReferencedThreads error:', e.message);
    }
    blocks.push(transcript
      ? `▼ Referenced thread (${ref.url})\n${transcript}`
      : `▼ Referenced thread (${ref.url})\n(could not read — the bot may not be a member of that channel, or lacks channels:history/groups:history scope.)`);
  }
  return blocks.join('\n\n');
}

module.exports = {
  slackGet,
  slackPost,
  postMessage,
  postLong,
  resolveUserName,
  cleanThreadText,
  fetchThreadTranscript,
  parseSlackArchiveUrls,
  fetchReferencedThreads,
};
