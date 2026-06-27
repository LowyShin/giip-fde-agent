/**
 * task-manager.js
 * Task lifecycle: analyze → create file → subagent execution → git push → GitHub URL
 */

const fs = require('fs');
const path = require('path');
const { spawnSync, spawn } = require('child_process');
const { searchKLayer } = require('./k-layer');

const BASE_DIR = process.env.WORKSPACE_DIR ? path.resolve(process.env.WORKSPACE_DIR) : path.join(__dirname, '..');
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

function readRolesContext() {
  try {
    return fs.readdirSync(ROLES_DIR)
      .filter(f => f.endsWith('.md'))
      .map(f => {
        const content = fs.readFileSync(path.join(ROLES_DIR, f), 'utf8');
        return `### ${f}\n${content.slice(0, 800)}`;
      })
      .join('\n\n---\n\n');
  } catch { return ''; }
}

function getCurrentBranch(cwd = BASE_DIR) {
  const res = spawnSync('git', ['rev-parse', '--abbrev-ref', 'HEAD'], { cwd, encoding: 'utf8', windowsHide: true });
  return (res.stdout || '').trim() || 'main';
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

// ── Phase 1: Analyze request → create TASK file ──────────────────────────────
function analyzeRequest(requestText, taskId, baseDir = BASE_DIR) {
  ensureDirs();
  const claims = searchKLayer(requestText);
  const projectName = path.basename(baseDir);
  const botName = process.env.BOT_NAME || 'giipclaude Bot';

  const analysisPrompt = `You are a senior software architect working on the "${projectName}" project. Respond in the same language as the request below.

A team member sent this request:
"${requestText}"

Project directory: ${baseDir}
${claims.length > 0 ? '\nK-Layer related knowledge:\n' + claims.map(c => `• ${c}`).join('\n') : ''}

Analyze the request and output a task specification in this EXACT format:

# TASK: [Short title]

## Request Summary
[Summary of the request — 1-2 lines]

## Execution Plan
1. [Specific execution step]
2. [Step 2]
3. [Step 3]
(maximum 7 steps)

## Affected Files / Subsystems
- [Files or subsystems to be changed]

## Notes
- [Deployment notes, side effects, dependencies]

Output ONLY the task specification, no extra commentary.`;

  return runClaude(['-p', analysisPrompt, '--model', process.env.CLAUDE_MODEL || 'claude-opus-4-8'], baseDir);
}

function createTaskFile(taskId, requestText, planContent) {
  ensureDirs();
  const header = `---
task_id: ${taskId}
status: pending
requested_at: ${new Date().toISOString()}
request: "${requestText.replace(/\\/g, '\\\\').replace(/"/g, '\\"')}"
---

`;
  const taskFile = path.join(TASKS_DIR, `${taskId}.md`);
  fs.writeFileSync(taskFile, header + planContent);
  return taskFile;
}

function extractTitle(planContent) {
  const match = planContent.match(/^#\s*TASK:\s*(.+)$/m);
  return match ? match[1].trim() : 'Task';
}

// ── Phase 2: Subagent execution (async) ──────────────────────────────────────
function startExecution(taskId, taskFilePath, { onComplete, onError }, baseDir = BASE_DIR) {
  ensureDirs();

  const taskContent = fs.readFileSync(taskFilePath, 'utf8');
  const resultFile = path.join(RESULTS_DIR, `${taskId}.md`);
  const rolesContext = readRolesContext();
  const claims = searchKLayer(taskContent);
  const projectName = path.basename(baseDir);

  const currentBranch = getCurrentBranch(baseDir);
  const executionPrompt = `You are a senior software engineer working on the "${projectName}" project. Respond in the same language as the task content below.
Working directory: ${baseDir}
Current branch: ${currentBranch}

=== Assigned Task ===
${taskContent}

=== Available Roles ===
${rolesContext || '(no roles found)'}

=== K-LAYER Knowledge ===
${claims.length > 0 ? claims.map(c => `• ${c}`).join('\n') : '(none)'}

=== Work Instructions ===
1. Execute the task's execution plan in order.
2. Use Read/Edit/Write/Bash tools to make actual code changes.
3. **When files are changed, immediately git push (mandatory even without explicit instruction)**:
   - Push to current branch (${currentBranch}) — do not switch branches
   - git add -A && git commit -m "feat/fix/chore(...): description" && git pull --rebase origin ${currentBranch} && git push origin ${currentBranch}
   - Follow commit message format in .agent/rules/11_structured_commit.md if it exists
4. After all steps complete, write a result report to:
   ${resultFile}

Result report format:
---
# Task Completion Report: [Task Title]

## Completed At
${new Date().toISOString()}

## Work Done
(Detailed description of what was performed)

## Changed Files
- path/to/file — summary of changes

## Result / Status
(success / partial / failure, with reason)

## Next Steps
(List any follow-up work needed)
---

Start working now.`;

  const proc = spawn('claude', ['-p', executionPrompt, '--dangerously-skip-permissions'], {
    cwd: baseDir,
    stdio: ['ignore', 'pipe', 'pipe'],
  });

  let stdout = '';
  let stderr = '';
  proc.stdout.on('data', d => { stdout += d; process.stdout.write(`[Subagent] ${d}`); });
  proc.stderr.on('data', d => { stderr += d; });

  proc.on('close', (code) => {
    if (!fs.existsSync(resultFile)) {
      fs.writeFileSync(resultFile, [
        `# Task Result: ${taskId}`,
        `\nCompleted at: ${new Date().toISOString()}`,
        `\n## Claude Output\n${stdout.slice(0, 3000)}`,
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

// ── Task complete: append result to task file, move to done/ ──────────────────
function completeTaskFile(taskId, resultContent) {
  const candidates = [
    path.join(TASKS_DIR, `${taskId}.md`),
    path.join(TASKS_DIR, `task-${taskId}.md`),
  ];
  const taskFile = candidates.find(f => fs.existsSync(f));
  if (!taskFile) throw new Error(`Task file not found for ${taskId}`);

  const now = new Date().toISOString();
  let content = fs.readFileSync(taskFile, 'utf8');

  content = /status:\s*.+/i.test(content)
    ? content.replace(/status:\s*.+/i, 'status: completed')
    : `status: completed\ncompleted_at: ${now}\n${content}`;

  content = `${content.trimEnd()}\n\n---\n\n## Task Completion Report\n\nCompleted at: ${now}\n\n${(resultContent || '').trim()}\n`;
  fs.writeFileSync(taskFile, content);

  const doneDir = path.join(TASKS_DIR, 'done');
  if (!fs.existsSync(doneDir)) fs.mkdirSync(doneDir, { recursive: true });
  const destPath = path.join(doneDir, path.basename(taskFile));
  fs.renameSync(taskFile, destPath);

  console.log(`[TaskManager] task ${taskId} → done/${path.basename(taskFile)}`);
  return destPath;
}

// ── Phase 3: Git commit + push → return GitHub URL ──────────────────────────
function gitPushResult(taskId, taskTitle, resultFile, doneTaskFile = null) {
  const branch = getCurrentBranch();
  const relResult = path.relative(BASE_DIR, resultFile).replace(/\\/g, '/');

  spawnSync('git', ['add', relResult], { cwd: BASE_DIR, encoding: 'utf8', windowsHide: true });

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

  const botName = process.env.BOT_NAME || 'giipclaude Bot';
  const msg = `task(${taskId}): ${taskTitle.slice(0, 60)}\n\nAuto-committed by ${botName}\n\nDirective: task result push on ${branch}`;
  const commitRes = spawnSync('git', ['commit', '-m', msg], { cwd: BASE_DIR, encoding: 'utf8', windowsHide: true });
  if (commitRes.status !== 0 && !(commitRes.stdout || '').includes('nothing to commit')) {
    console.error('[TaskManager] git commit:', (commitRes.stderr || '').trim());
    return null;
  }

  spawnSync('git', ['pull', '--rebase', 'origin', branch], { cwd: BASE_DIR, encoding: 'utf8', windowsHide: true });
  const pushRes = spawnSync('git', ['push', 'origin', branch], { cwd: BASE_DIR, encoding: 'utf8', windowsHide: true });
  if (pushRes.status !== 0) {
    console.error('[TaskManager] git push:', (pushRes.stderr || '').trim());
    return null;
  }

  return buildGitHubUrl(relDoneTask || relResult);
}

function buildGitHubUrl(relativePath) {
  const remoteRes = spawnSync('git', ['remote', 'get-url', 'origin'], { cwd: BASE_DIR, encoding: 'utf8', windowsHide: true });
  const remote = (remoteRes.stdout || '').trim();

  const base = remote
    .replace(/^git@github\.com:/, 'https://github.com/')
    .replace(/\.git$/, '');

  const branchRes = spawnSync('git', ['rev-parse', '--abbrev-ref', 'HEAD'], { cwd: BASE_DIR, encoding: 'utf8', windowsHide: true });
  const branch = (branchRes.stdout || '').trim() || 'main';

  return `${base}/blob/${branch}/${relativePath}`;
}

// ── Tasklist file management ──────────────────────────────────────────────────
function loadTasklist() {
  try { return JSON.parse(fs.readFileSync(TASKLIST_FILE, 'utf8')); } catch { return []; }
}

function saveTasklist(list) {
  try { fs.writeFileSync(TASKLIST_FILE, JSON.stringify(list, null, 2)); } catch {}
}

function extractSummary(planContent) {
  const m = planContent.match(/##\s*Request Summary\s*\n+(.+)/);
  if (m) return m[1].trim().slice(0, 80);
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

function getTasklistByStatus(status = null) {
  const list = loadTasklist();
  return status ? list.filter(t => t.status === status) : list;
}

function statusEmoji(status) {
  return { pending: '🕐', running: '⚙️', completed: '✅', cancelled: '🚫' }[status] || '❓';
}

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
  content = `${content.trimEnd()}\n\n## Progress Log\n\n| ${now} | Slack cancel |\n`;
  fs.writeFileSync(taskFile, content);

  const cancelDir = path.join(TASKS_DIR, 'cancel');
  if (!fs.existsSync(cancelDir)) fs.mkdirSync(cancelDir, { recursive: true });
  const destPath = path.join(cancelDir, path.basename(taskFile));
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
};
