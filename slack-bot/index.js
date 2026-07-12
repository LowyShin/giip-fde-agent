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

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');
const tm = require('./task-manager');
const { SocketModeClient } = require('@slack/socket-mode');

// ── 機能別モジュール (index.js から切り出し) ─────────────────────────────────
const config = require('./config');
const { BOT_TOKEN, CHANNEL_IDS, SLACK_APP_TOKEN, AGENT_DIR, HISTORY_FILE, TASK_STATE_FILE } = config;
const { loadJSON, saveJSON } = require('./state');
const { slackGet } = require('./slack-api');
const { onSlackMessage } = require('./handlers');

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
  config.setBotUserId(auth.user_id);

  console.log('[giipclaude Bot] 起動 — Socket Mode');
  console.log(`[Bot] ID: ${config.getBotUserId()} (${auth.user}) PID: ${process.pid}`);
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
    const mentionsBot = config.getBotUserId() && (event.text || '').includes(`<@${config.getBotUserId()}>`);
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

if (require.main === module) {
  main().catch(err => { console.error('[Bot] Fatal:', err); process.exit(1); });
}
