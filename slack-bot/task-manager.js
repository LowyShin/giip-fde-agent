/**
 * task-manager.js
 * Task lifecycle: 분석 → 파일 생성 → subagent 실행 → git push → GitHub URL 반환
 */

const fs = require('fs');
const path = require('path');
const { spawnSync, spawn } = require('child_process');
const { searchKLayer } = require('./k-layer');

const BASE_DIR = path.join(__dirname, '..');
const TASKS_DIR = path.join(BASE_DIR, '.agent', 'tasks');
const RESULTS_DIR = path.join(BASE_DIR, '.agent', 'results');
const ROLES_DIR = path.join(BASE_DIR, '.agent', 'roles');
const TASKLIST_FILE = path.join(__dirname, 'tasklist.json');

function ensureDirs() {
  [TASKS_DIR, RESULTS_DIR].forEach(d => {
    try { fs.mkdirSync(d, { recursive: true }); } catch {}
  });
}

function getTimestampId() {
  const now = new Date();
  const p = n => String(n).padStart(2, '0');
  return `${now.getFullYear()}${p(now.getMonth()+1)}${p(now.getDate())}${p(now.getHours())}${p(now.getMinutes())}${p(now.getSeconds())}`;
}

// baseDir 配下の .agent/roles/ を読む。なければ BASE_DIR の roles にフォールバック
// filesRead に読んだファイルの絶対パスを push する
function readRolesContext(baseDir = BASE_DIR, filesRead = []) {
  const dirs = [
    path.join(baseDir, '.agent', 'roles'),
    ROLES_DIR,
  ];
  for (const dir of dirs) {
    try {
      const files = fs.readdirSync(dir).filter(f => f.endsWith('.md'));
      if (files.length === 0) continue;
      return files.map(f => {
        const fullPath = path.join(dir, f);
        filesRead.push(fullPath);
        const content = fs.readFileSync(fullPath, 'utf8');
        return `### ${f}\n${content.slice(0, 800)}`;
      }).join('\n\n---\n\n');
    } catch {}
  }
  return '';
}

// .agent/rules/ 配下のルールファイル一覧を収集（内容はプロンプトに含めず、ファイル名のみ記録）
function collectRulesFiles(baseDir = BASE_DIR, filesRead = []) {
  const dirs = [
    path.join(baseDir, '.agent', 'rules'),
    path.join(BASE_DIR, '.agent', 'rules'),
  ];
  const seen = new Set();
  for (const dir of dirs) {
    try {
      const files = fs.readdirSync(dir).filter(f => f.endsWith('.md'));
      for (const f of files) {
        const fullPath = path.join(dir, f);
        if (!seen.has(fullPath)) {
          seen.add(fullPath);
          filesRead.push(fullPath);
        }
      }
    } catch {}
  }
}

// .agent/skills/ 配下のスキルファイル一覧を収集
function collectSkillsFiles(baseDir = BASE_DIR, filesRead = []) {
  const dirs = [
    path.join(baseDir, '.agent', 'skills'),
    path.join(BASE_DIR, '.agent', 'skills'),
  ];
  const seen = new Set();
  for (const dir of dirs) {
    try {
      const entries = fs.readdirSync(dir, { withFileTypes: true });
      for (const e of entries) {
        const skillMd = e.isDirectory()
          ? path.join(dir, e.name, 'SKILL.md')
          : path.join(dir, e.name);
        if (fs.existsSync(skillMd) && !seen.has(skillMd)) {
          seen.add(skillMd);
          filesRead.push(skillMd);
        }
      }
    } catch {}
  }
}

function getCurrentBranch(cwd = BASE_DIR) {
  const res = spawnSync('git', ['rev-parse', '--abbrev-ref', 'HEAD'], { cwd, encoding: 'utf8', windowsHide: true });
  return (res.stdout || '').trim() || 'master';
}

function runClaude(args, cwd = BASE_DIR) {
  const result = spawnSync('claude', args, {
    cwd,
    encoding: 'utf8',
    maxBuffer: 10 * 1024 * 1024,
    timeout: 300000,
    windowsHide: true,
  });
  if (result.error) throw result.error;
  return (result.stdout || '').trim();
}

// ── Phase 1: 요청 분석 → TASK 파일 생성 ─────────────────────────────────────
// returns { planContent, filesRead }
function analyzeRequest(requestText, taskId, baseDir = BASE_DIR) {
  ensureDirs();
  const filesRead = [];

  const claims = searchKLayer(requestText);
  const projectName = path.basename(baseDir);
  const rolesContext = readRolesContext(baseDir, filesRead);
  collectRulesFiles(baseDir, filesRead);
  collectSkillsFiles(baseDir, filesRead);

  const analysisPrompt = `You are a senior software architect. Respond in the same language as the task/request.

Working project: ${projectName}
Working directory: ${baseDir}

A team member sent this request via Slack:
"${requestText}"
${rolesContext ? `\n=== 프로젝트 역할/컨텍스트 ===\n${rolesContext}\n` : ''}${claims.length > 0 ? `\n=== K-Layer 관련 지식 ===\n${claims.map(c => `• ${c}`).join('\n')}\n` : ''}
Analyze the request and output a task specification in this EXACT format (in Korean):

# TASK: [짧은 제목]

## 요청 내용
[요청 요약 — 1~2줄]

## 실행 계획
1. [구체적인 실행 단계]
2. [단계 2]
3. [단계 3]
(최대 7단계)

## 영향 파일/서브시스템
- [변경될 파일 또는 서브시스템]

## 주의사항
- [배포 주의사항, 부작용 등]

Output ONLY the task specification, no extra commentary.`;

  const planContent = runClaude(['-p', analysisPrompt, '--model', 'claude-opus-4-8'], baseDir);
  return { planContent, filesRead };
}

function createTaskFile(taskId, requestText, planContent, filesRead = []) {
  ensureDirs();

  const fileList = filesRead.length > 0
    ? '\n' + filesRead.map(f => `#   - ${path.relative(BASE_DIR, f).replace(/\\/g, '/')}`).join('\n')
    : '\n#   (없음)';

  const header = `---
task_id: ${taskId}
status: pending
requested_at: ${new Date().toISOString()}
request: "${requestText.replace(/\\/g, '\\\\').replace(/"/g, '\\"')}"
# 분석 시 참조한 파일 목록 (roles / rules / skills):${fileList}
---

`;
  const taskFile = path.join(TASKS_DIR, `${taskId}.md`);
  fs.writeFileSync(taskFile, header + planContent);
  return taskFile;
}

function extractTitle(planContent) {
  const match = planContent.match(/^#\s*TASK:\s*(.+)$/m);
  return match ? match[1].trim() : '作業';
}

// ── Phase 2: subagent 실행 (비동기) ─────────────────────────────────────────
function startExecution(taskId, taskFilePath, { onComplete, onError }, baseDir = BASE_DIR) {
  ensureDirs();

  // taskFilePath が未指定 or 存在しない場合は TASKS_DIR/{taskId}.md にフォールバック
  if (!taskFilePath || !fs.existsSync(taskFilePath)) {
    const fallback = path.join(TASKS_DIR, `${taskId}.md`);
    if (fs.existsSync(fallback)) {
      taskFilePath = fallback;
    } else {
      const err = new Error(`タスクファイルが見つかりません: ${taskId}`);
      if (onError) setImmediate(() => onError(err, null));
      return;
    }
  }

  const taskContent = fs.readFileSync(taskFilePath, 'utf8');
  const resultFile = path.join(RESULTS_DIR, `${taskId}.md`);
  const rolesContext = readRolesContext(baseDir);
  const claims = searchKLayer(taskContent);

  const currentBranch = getCurrentBranch(baseDir);
  const executionPrompt = `You are a senior software engineer working in the current workspace. Respond in the same language as the task.
Working directory: ${baseDir}
Current branch: ${currentBranch}

=== 담당 태스크 ===
${taskContent}

=== 사용 가능한 역할 ===
${rolesContext || '(roles not found)'}

=== K-LAYER 지식 ===
${claims.length > 0 ? claims.map(c => `• ${c}`).join('\n') : '(없음)'}

=== 작업 지시 ===
1. 위 태스크의 실행 계획을 순서대로 실행하세요.
2. Read/Edit/Write/Bash 도구를 사용해 실제 코드 변경을 수행하세요.
3. **파일을 변경하면 즉시 git push (명시적 지시 없어도 필수)**:
   - 현재 브랜치(${currentBranch})에 그대로 push — 브랜치 전환 금지
   - git add -A && git commit -m "feat/fix/chore(...): 설명" && git pull --rebase origin ${currentBranch} && git push origin ${currentBranch}
   - 커밋 메시지는 .agent/rules/11_structured_commit.md 형식 준수
4. 모든 단계 완료 후 반드시 다음 경로에 결과 보고서를 작성하세요:
   ${resultFile}

결과 보고서 형식:
---
# 작업 완료 보고서: [태스크 제목]

## 완료 일시
${new Date().toISOString()}

## 실시 내용
(실제 수행한 작업의 상세 설명)

## 변경 파일
- path/to/file — 변경 내용 요약

## 결과/상태
(성공 / 부분 완료 / 실패, 이유)

## 다음 단계
(후속 작업이 필요한 경우 명기)
---

지금 바로 작업을 시작하세요.`;

  // 実行サブエージェントが roles/rules/skills/workflows を参照できるよう .agent を許可
  // （baseDir に .agent が無ければ BASE_DIR/.agent にフォールバック — index.js の getAgentDir と同じ規則）
  const agentDir = fs.existsSync(path.join(baseDir, '.agent'))
    ? path.join(baseDir, '.agent')
    : path.join(BASE_DIR, '.agent');
  const proc = spawn('claude', ['-p', executionPrompt, '--dangerously-skip-permissions', '--add-dir', agentDir], {
    cwd: baseDir,
    stdio: ['ignore', 'pipe', 'pipe'],
  });

  let stdout = '';
  let stderr = '';
  proc.stdout.on('data', d => { stdout += d; process.stdout.write(`[Subagent] ${d}`); });
  proc.stderr.on('data', d => { stderr += d; });

  proc.on('close', (code) => {
    // 결과 파일이 없으면 기본 파일 생성
    if (!fs.existsSync(resultFile)) {
      fs.writeFileSync(resultFile, [
        `# 작업 결과: ${taskId}`,
        `\n완료 일시: ${new Date().toISOString()}`,
        `\n## Claude 출력\n${stdout.slice(0, 3000)}`,
        stderr ? `\n## Errors\n${stderr.slice(0, 500)}` : '',
      ].join('\n'));
    }

    if (code === 0) {
      onComplete(resultFile);
    } else {
      onError(new Error(`claude exit ${code}: ${stderr.slice(0, 200)}`), resultFile);
    }
  });

  proc.on('error', (err) => onError(err, null));

  return proc;
}

// ── 작업 완료: 결과를 태스크 파일에 추가 후 done/ 폴더로 이동 ─────────────────
function completeTaskFile(taskId, resultContent) {
  const candidates = [
    path.join(TASKS_DIR, `${taskId}.md`),
    path.join(TASKS_DIR, `task-${taskId}.md`),
  ];
  const taskFile = candidates.find(f => fs.existsSync(f));
  if (!taskFile) throw new Error(`Task file not found for ${taskId}`);

  const now = new Date().toISOString();
  let content = fs.readFileSync(taskFile, 'utf8');

  // status を completed に更新
  content = /status:\s*.+/i.test(content)
    ? content.replace(/status:\s*.+/i, 'status: completed')
    : `status: completed\ncompleted_at: ${now}\n${content}`;

  // 결과 보고서를 파일 말미에 추가
  content = `${content.trimEnd()}\n\n---\n\n## 작업 완료 보고서\n\n완료 일시: ${now}\n\n${(resultContent || '').trim()}\n`;
  fs.writeFileSync(taskFile, content);

  // done/ 폴더로 이동
  const doneDir = path.join(TASKS_DIR, 'done');
  if (!fs.existsSync(doneDir)) fs.mkdirSync(doneDir, { recursive: true });
  const destPath = path.join(doneDir, path.basename(taskFile));
  fs.renameSync(taskFile, destPath);

  console.log(`[TaskManager] task ${taskId} → done/${path.basename(taskFile)}`);
  return destPath;
}

// ── Phase 3: Git commit + push → GitHub URL 반환 ─────────────────────────────
// doneTaskFile が指定された場合はそのファイルを優先的に stage し URL を返す
function gitPushResult(taskId, taskTitle, resultFile, doneTaskFile = null) {
  const branch = getCurrentBranch();
  const relResult = path.relative(BASE_DIR, resultFile).replace(/\\/g, '/');

  // result file を stage
  spawnSync('git', ['add', relResult], { cwd: BASE_DIR, encoding: 'utf8', windowsHide: true });

  // done task file を stage（あれば優先）、なければ元のタスクファイルを試みる
  let relDoneTask = null;
  if (doneTaskFile && fs.existsSync(doneTaskFile)) {
    relDoneTask = path.relative(BASE_DIR, doneTaskFile).replace(/\\/g, '/');
    spawnSync('git', ['add', relDoneTask], { cwd: BASE_DIR, encoding: 'utf8', windowsHide: true });
  } else {
    const relTask = `.agent/tasks/${taskId}.md`;
    if (fs.existsSync(path.join(BASE_DIR, relTask))) {
      spawnSync('git', ['add', relTask], { cwd: BASE_DIR, encoding: 'utf8', windowsHide: true });
    }
  }

  // commit
  const msg = `task(${taskId}): ${taskTitle.slice(0, 60)}\n\nAuto-committed by giipclaude Bot\n\nDirective: task result push on ${branch}`;
  const commitRes = spawnSync('git', ['commit', '-m', msg], { cwd: BASE_DIR, encoding: 'utf8', windowsHide: true });
  if (commitRes.status !== 0 && !(commitRes.stdout || '').includes('nothing to commit')) {
    console.error('[TaskManager] git commit:', (commitRes.stderr || '').trim());
    return null;
  }

  // Rebase onto latest remote and push, retrying once on non-fast-forward.
  // --autostash so uncommitted runtime state (bot json) never blocks the rebase. This was the
  // bug that silently dropped result URLs: dirty tree → rebase refused → push rejected → null.
  const runGit = (args) => spawnSync('git', args, { cwd: BASE_DIR, encoding: 'utf8', windowsHide: true });
  const rebaseAndPush = () => {
    const pull = runGit(['pull', '--rebase', '--autostash', 'origin', branch]);
    if (pull.status !== 0) {
      console.error('[TaskManager] git pull --rebase:', (pull.stderr || '').trim());
      runGit(['rebase', '--abort']); // never leave the repo mid-rebase
    }
    return runGit(['push', 'origin', branch]);
  };
  let pushRes = rebaseAndPush();
  if (pushRes.status !== 0) {
    console.error('[TaskManager] git push rejected, retrying after fetch:', (pushRes.stderr || '').trim());
    runGit(['fetch', 'origin', branch]);
    pushRes = rebaseAndPush();
  }
  if (pushRes.status !== 0) {
    console.error('[TaskManager] git push:', (pushRes.stderr || '').trim());
    return null;
  }

  // done task file の URL を優先返却
  return buildGitHubUrl(relDoneTask || relResult);
}

function buildGitHubUrl(relativePath) {
  const remoteRes = spawnSync('git', ['remote', 'get-url', 'origin'], { cwd: BASE_DIR, encoding: 'utf8', windowsHide: true });
  const remote = (remoteRes.stdout || '').trim();

  // git@github.com:Owner/Repo.git  →  https://github.com/Owner/Repo
  // https://github.com/Owner/Repo.git  →  https://github.com/Owner/Repo
  const base = remote
    .replace(/^git@github\.com:/, 'https://github.com/')
    .replace(/\.git$/, '');

  const branchRes = spawnSync('git', ['rev-parse', '--abbrev-ref', 'HEAD'], { cwd: BASE_DIR, encoding: 'utf8', windowsHide: true });
  const branch = (branchRes.stdout || '').trim() || 'master';

  return `${base}/blob/${branch}/${relativePath}`;
}

// ── Tasklist ファイル管理 ──────────────────────────────────────────────────────
function loadTasklist() {
  try { return JSON.parse(fs.readFileSync(TASKLIST_FILE, 'utf8')); } catch { return []; }
}

function saveTasklist(list) {
  try { fs.writeFileSync(TASKLIST_FILE, JSON.stringify(list, null, 2)); } catch {}
}

function extractSummary(planContent) {
  // "## リクエスト内容" の直後の行を1行サマリとして使う
  const m = planContent.match(/##\s*リクエスト内容\s*\n+(.+)/);
  if (m) return m[1].trim().slice(0, 80);
  // フォールバック: 最初の非ヘッダ行
  const line = planContent.split('\n').find(l => l.trim() && !l.startsWith('#'));
  return (line || '').trim().slice(0, 80);
}

function addToTasklist(taskId, title, summary, requestText) {
  const list = loadTasklist();
  list.push({
    taskId,
    title,
    summary: summary || requestText.slice(0, 80),
    status: 'pending',
    createdAt: new Date().toISOString(),
    startedAt: null,
    completedAt: null,
    resultUrl: null,
  });
  saveTasklist(list);
}

function updateTasklistEntry(taskId, updates) {
  const list = loadTasklist();
  const idx = list.findIndex(t => t.taskId === taskId);
  if (idx >= 0) {
    list[idx] = { ...list[idx], ...updates };
    saveTasklist(list);
  }
}

// status: 'pending' | 'running' | 'completed' | 'cancelled' | null(全件)
function getTasklistByStatus(status = null) {
  const list = loadTasklist();
  return status ? list.filter(t => t.status === status) : list;
}

// ステータス絵文字
function statusEmoji(status) {
  return { pending: '🕐', running: '⚙️', completed: '✅', cancelled: '🚫' }[status] || '❓';
}

// タスクファイルの GitHub URL を動的に生成
function getTaskFileUrl(taskId) {
  const candidates = [
    path.join(TASKS_DIR, `${taskId}.md`),
    path.join(TASKS_DIR, 'done', `${taskId}.md`),
    path.join(TASKS_DIR, 'cancel', `${taskId}.md`),
  ];
  const found = candidates.find(f => fs.existsSync(f));
  if (!found) return null;
  const rel = path.relative(BASE_DIR, found).replace(/\\/g, '/');
  return buildGitHubUrl(rel);
}

// タスクファイルをキャンセル状態にして cancel/ フォルダへ移動
function cancelTaskFile(taskId) {
  const candidates = [
    path.join(TASKS_DIR, `${taskId}.md`),
    path.join(TASKS_DIR, `task-${taskId}.md`),
  ];
  const taskFile = candidates.find(f => fs.existsSync(f));
  if (!taskFile) throw new Error(`Task file not found for ${taskId}`);

  const now = new Date().toISOString();
  let content = fs.readFileSync(taskFile, 'utf8');
  content = /status:\s*.+/i.test(content)
    ? content.replace(/status:\s*.+/i, 'status: cancelled')
    : `status: cancelled\n${content}`;
  if (content.includes('## 進捗ログ')) {
    content = content.replace(/(## 進捗ログ[\s\S]*?)(\n## |\s*$)/, (m, s, n) => `${s.trimEnd()}\n| ${now} | Slack cancel |\n${n}`);
  } else {
    content = `${content.trimEnd()}\n\n## 進捗ログ\n\n| ${now} | Slack cancel |\n`;
  }
  fs.writeFileSync(taskFile, content);

  const cancelDir = path.join(TASKS_DIR, 'cancel');
  if (!fs.existsSync(cancelDir)) fs.mkdirSync(cancelDir, { recursive: true });
  const destPath = path.join(cancelDir, path.basename(taskFile));

  // task files are untracked runtime files — use fs.rename instead of git mv
  fs.renameSync(taskFile, destPath);

  return path.relative(BASE_DIR, destPath).replace(/\\/g, '/');
}

module.exports = {
  getTimestampId,
  analyzeRequest,
  createTaskFile,
  extractTitle,
  extractSummary,
  startExecution,
  completeTaskFile,
  gitPushResult,
  addToTasklist,
  updateTasklistEntry,
  getTasklistByStatus,
  statusEmoji,
  cancelTaskFile,
  getTaskFileUrl,
};
