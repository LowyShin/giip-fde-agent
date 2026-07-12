/**
 * config.js — 共有定数・プロジェクトパス解決・botUserId アクセサ
 *
 * index.js から behavior-preserving に切り出したモジュール。
 * 定数の計算式は index.js のものをそのまま踏襲する。
 */

const fs = require('fs');
const path = require('path');

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

// ── botUserId (main() で auth.test 後にセット、processMessage / socket handler で参照) ──
let botUserId = null;
function getBotUserId() { return botUserId; }
function setBotUserId(id) { botUserId = id; }

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

module.exports = {
  BOT_TOKEN,
  CHANNEL_IDS,
  SLACK_APP_TOKEN,
  BOT_NAME,
  BASE_DIR,
  PROJECTS_ROOT,
  AGENT_DIR,
  HISTORY_FILE,
  TASK_STATE_FILE,
  BOT_THREADS_FILE,
  getBotUserId,
  setBotUserId,
  getAgentDir,
  parseProjectPrefix,
};
