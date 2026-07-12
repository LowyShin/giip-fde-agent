/**
 * intent.js — コマンド判定と意図分類
 *
 * index.js から behavior-preserving に切り出したモジュール。
 */

const { spawnAsync } = require('./claude-cli');
const { BASE_DIR } = require('./config');

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

// ── 意図分類 (task / question) ────────────────────────────────────────────────
// 「タスク登録」「task登録」等の明記、または明確な作業依頼 → "task"
// 曖昧・質問・情報照会 → "question"
async function classifyRequest(text, workDir = BASE_DIR) {
  // git push / pull / stash などの単純操作はタスク不要 → 即 question
  if (/^\s*(git\s+(push|pull|stash|fetch|merge|rebase|status|log|diff)|タスク(?:一覧|リスト|確認|状況)|tasklist|task7d)/i.test(text.replace(/[^\x00-\x7Fぁ-ん亜-熙ー]/g, ' '))) {
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

module.exports = {
  isGoCmd,
  isCancelCmd,
  isPureGitOp,
  classifyRequest,
};
