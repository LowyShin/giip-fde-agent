/**
 * claude-cli.js — child-process / spawn ヘルパーと claude CLI 呼び出し
 *
 * index.js から behavior-preserving に切り出したモジュール。
 * gitPullBeforeWork は spawnAsync に依存するためここに同居させ、
 * モジュール間依存を減らしている。
 */

const { spawn } = require('child_process');
const config = require('./config');
const { BASE_DIR, PROJECTS_ROOT, getAgentDir } = config;

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
        timeout: 20 * 60 * 1000, // 20分
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

module.exports = {
  spawnAsync,
  isClaudeAuthed,
  reAuthClaude,
  callClaude,
  gitPullBeforeWork,
};
