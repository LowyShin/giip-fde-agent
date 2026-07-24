/**
 * handlers.js — Slack メッセージ処理ハンドラ群
 *
 * index.js から behavior-preserving に切り出したモジュール。
 * BOT_USER_ID 参照は config.getBotUserId() に置換済み（挙動は同一）。
 * インラインの require("./giip-commands") / require("./giip-task") は原文どおり維持。
 */

const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");
const config = require("./config");
const {
  BOT_NAME, BASE_DIR, AGENT_DIR, TASK_STATE_FILE, HISTORY_FILE,
  getAgentDir, parseProjectPrefix,
} = config;
const { loadJSON, saveJSON, isBotEngagedThread } = require("./state");
const {
  postMessage, postLong, fetchThreadTranscript, fetchReferencedThreads,
} = require("./slack-api");
const { checkAllRepoStatus, isPushFailureNotice } = require("./repo-status");
const { callClaude, gitPullBeforeWork } = require("./claude-cli");
const { isGoCmd, isCancelCmd, isPureGitOp, classifyRequest } = require("./intent");
const {
  extractExistingTaskIds, findSimilarPendingTasks,
  findDuplicatePendingClusters, applyTaskMerge,
} = require("./task-dedup");
const tm = require("./task-manager");
const { searchKLayer } = require("./k-layer");
const { getIssues, refreshIssues, getCacheAge } = require("./github-issues");

// ── チャンネル Q&A (質問と判定されたときのインライン回答) ────────────────────
// git push / pull のみ（他の作業を含まない）を実行して結果を返す
// 「A機能を修正して git push して」のような複合指示には反応しない
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

async function answerInChannel({ channelId, replyTs, text, workDir = BASE_DIR, threadTs = null }) {
  if (await handleSimpleGitOp({ channelId, replyTs, text, workDir })) return;

  // スレッド内での質問なら、スレッド全体を取得して文脈として渡す。
  // Bot は mention された1件しか受け取らないため、これをやらないと
  // 「スレッドを要約して」に対して「会話履歴がない」と誤答してしまう。
  let threadTranscript = '';
  try {
    threadTranscript = await fetchThreadTranscript(channelId, threadTs);
  } catch (e) {
    console.error('[Bot] fetchThreadTranscript error:', e.message);
  }

  // Slack permalinks pasted in the message → read those threads too (Method 2)
  let referencedThreads = '';
  try {
    referencedThreads = await fetchReferencedThreads(text, channelId, threadTs);
  } catch (e) {
    console.error('[Bot] fetchReferencedThreads error:', e.message);
  }

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
  if (threadTranscript) {
    prompt += `\n\n── Full current Slack thread (chronological, "speaker: message") ──\n${threadTranscript}\n── end of thread ──\n\nThe thread above is what the user means by "this thread / this conversation / this Slack message". When asked to summarize the thread, explain who said what, or check the surrounding context, you MUST answer based on the content above. Never reply that there is no conversation history.`;
  }
  if (referencedThreads) {
    prompt += `\n\n── Other Slack thread(s) the user referenced by URL ──\n${referencedThreads}\n── end of referenced thread(s) ──\n\nIf the user pasted a Slack link, the block above is that link's thread content. Base any summary, comparison, or answer about it strictly on this content.`;
  }
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
      ? '⏱️ 処理がタイムアウトしました（20分超過）。もう少し短い要求に分けて送ってください。'
      : `回答エラー: ${err.message}`;
    await postMessage(channelId, msg2, replyTs);
  }
}

// ── DM 처리 (일반 Q&A) ───────────────────────────────────────────────────────
async function handleDM({ channelId, ts, threadTs, text, conversations, workDir = BASE_DIR }) {
  const convKey = channelId;
  const replyTs = threadTs || undefined;
  const cmd = text.trim().toLowerCase();

  // ── giip 커맨드 (giip api|issue|account) — DM 은 특히 account set(SK) 에 안전 ──
  try {
    const { handleGiipCommand } = require('./giip-commands');
    const gc = await handleGiipCommand(text.trim(), channelId);
    if (gc.handled) { await postMessage(channelId, gc.text, replyTs); return; }
  } catch (e) { console.error('[Bot] giip command error:', e.message); }

  if (cmd === '!help') {
    await postMessage(channelId, [
      '*giipclaude AI — DM コマンド一覧*',
      '• `!issues` — GitHub Issue 一覧',
      '• `!issues refresh` — Issue 強制更新',
      '• `!klayer <キーワード>` — K-Layer 知識検索',
      '• `!reset` — 会話履歴リセット',
      '',
      '*giip issue 連携:*',
      '• `giip account set <login_id> <sk> [csn]` — チャンネル連携（DM推奨・SK含むので channel では避ける）',
      '• `giip account show` — 現在の連携アカウント表示',
      '• `giip issue list [status]` — イシュー一覧',
      '• `giip issue get <isn>` — イシュー詳細',
      '• `giip issue new "<title>"` — イシュー新規作成',
      '• `giip issue done|review|progress <isn>` — ステータス変更',
      '• `giip issue comment <isn> <text>` — コメント追加',
      '• `giip api <Verb> [jsondata]` — 汎用 giip API 呼び出し',
      '',
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

      // ── giip issue 통일(rule 40): 완료 시 코멘트 + REVIEW 전이(best-effort). ──
      try {
        const gt = require('./giip-task');
        const cmt = githubUrl ? `✅ 작업 완료\n결과: ${githubUrl}` : '✅ 작업 완료(로컬, git push 실패)';
        await gt.maybeFinish(channelId, pendingTask.isn, 'REVIEW', cmt);
      } catch (e) { console.error('[Bot] giip finish 훅 오류:', e.message); }
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

      // ── giip issue 통일(rule 40): 에러 시 코멘트 + REVIEW 전이(best-effort). ──
      try {
        const gt = require('./giip-task');
        await gt.maybeFinish(channelId, pendingTask.isn, 'REVIEW', `❌ 작업 에러: ${err.message}${githubUrl ? `\n로그: ${githubUrl}` : ''}`);
      } catch (e) { console.error('[Bot] giip finish 훅 오류:', e.message); }
    },
  }, workDir);
}

// ── チャンネル Mention 処理 (Task ワークフロー) ───────────────────────────────
async function handleChannelMention({ channelId, ts, threadTs, text, workDir = BASE_DIR, projectName = null }) {
  const convKey = `${channelId}:${threadTs || ts}`;
  const replyTs = threadTs || ts;
  const taskState = loadJSON(TASK_STATE_FILE, { pending: {}, running: {} });

  // バッククォート・全角スペース等を除去してからコマンド判定
  const cmd = text.trim().replace(/`/g, '').replace(/\s+/g, ' ').toLowerCase();
  console.log(`[Bot] handleChannelMention cmd="${cmd}" convKey="${convKey}"`);

  // ── giip 커맨드 (giip api|issue|account|project) ──
  try {
    const { handleGiipCommand } = require('./giip-commands');
    const gc = await handleGiipCommand(text.trim(), channelId);
    if (gc.handled) { await postMessage(channelId, gc.text, replyTs); return; }
  } catch (e) { console.error('[Bot] giip command error:', e.message); }

  // ── "issue 등록 <내용>" — 分類器を通さず明示的に giip issue として登録 ──────
  //   利用形: `<プロジェクト名> issue 등록 <内容>` / `issue 등록 <内容>`
  //   (プロジェクト名は parseProjectPrefix で workDir/projectName に解決済み → text は接頭辞除去済み)
  //   csn は project-csn.json のマッピング(projectName)で決定。未登録なら account 既定 csn にフォールバック。
  //   区切り(空白 / コロン / 文字列末)を必須にして「issue 등록됐어?」等の質問誤爆を防ぐ
  //   (JS の \b は ASCII 専用でハングル境界を検出できないため明示的に区切りを要求)。
  const issueTrigger = /^(?:issue|이슈|イシュー)\s*(?:등록|登録|register)(?:\s+|\s*[:：]\s*|$)/i;
  if (issueTrigger.test(text.trim())) {
    const body = text.trim().replace(issueTrigger, '').trim();
    if (!body) {
      await postMessage(channelId, '사용법: `<프로젝트> issue 등록 <내용>` — 내용을 그대로 giip issue 로 등록합니다.', replyTs);
      return;
    }
    const title = body.split(/\r?\n/)[0].slice(0, 200).trim() || '(무제)';
    try {
      const giipAccounts = require('./giip-accounts');
      const giip = require('./giip-api');
      const acct = giipAccounts.resolve(channelId);
      if (!acct) {
        await postMessage(channelId,
          '⚠️ giip 계정 미설정입니다. `giip account set <login_id> <sk> [csn]` 로 먼저 등록하세요(SK 포함이라 DM 권장).',
          replyTs);
        return;
      }
      const csn = config.resolveProjectCsn(projectName || workDir);
      const r = await giip.issueCreate(acct, { title, content: body.slice(0, 8000), status: 'PENDING', csn });
      const isn = r && r.isn ? Number(r.isn) : null;
      await postMessage(channelId,
        isn
          ? `✅ giip issue #${isn} 등록 완료 (PENDING · csn=${csn ?? acct.csn ?? '-'})\n• 제목: ${title}`
          : '⚠️ issue 등록 응답에 isn 이 없습니다. 계정/CSN 설정을 확인하세요.',
        replyTs);
    } catch (e) {
      console.error('[Bot] issue 등록 실패:', e.message);
      await postMessage(channelId, `❌ issue 등록 실패: ${e.message}`, replyTs);
    }
    return;
  }

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
      '• `task7days` — 直近7日間の全 Task (完了・キャンセル含む／未処理・異常検知用)',
      '• `go` — 待機中 Task の一覧を表示',
      '• `go <Task番号>` — 指定した Task を実行',
      '• `cancel` — 待機中 Task の一覧を表示',
      '• `cancel <Task番号>` — 指定した Task をキャンセル',
      '• `taskmerge` — 未完了の重複タスクを検出（プレビュー）',
      '• `taskmerge go` — 重複タスクを統合（代表1件に集約し残りを取消）',
      '',
      '*ワークフロー:*',
      '• `<プロジェクト名> wflist` — そのプロジェクトの .agent/workflows 一覧',
      '• `<プロジェクト名> wflist <絞り込み語>` — 名前で絞り込み',
      '• `<プロジェクト名> wflist all` — 参考ドキュメントも表示',
      '• *ワークフロー実行* — 次のどの形でもOK（実行サブエージェント経路で走るので DB/スクリプトが権限に阻まれない）:',
      '    ‣ `<プロジェクト> workflow <名>` / `wf <名>` / `wfrun <名>` / `워크플로우 <名>`  （「워크플로우」が長い時は workflow / wf でOK）',
      '    ‣ `<プロジェクト> <名> 실행` / `<プロジェクト> /<名>` / `<プロジェクト> <名>`',
      '    例) `giipprj wf errorproc` = `giipprj errorproc 실행` = `giipprj /errorproc` = `giipprj workflow errorproc`',
      '    ※ 「<名> 실행」「<名>」の形は実在ワークフロー名と完全一致した時のみ実行（誤爆防止）',
      '',
      '*giip issue 連携:*',
      '• `giip account set <login_id> <sk> [csn]` — チャンネル連携（SK含むので DM 推奨）',
      '• `giip account show` — 現在の連携アカウント表示',
      '• `giip issue list [status]` — イシュー一覧',
      '• `giip issue get <isn>` — イシュー詳細',
      '• `giip issue new "<title>"` — イシュー新規作成',
      '• `giip issue done|review|progress <isn>` — ステータス変更',
      '• `giip issue comment <isn> <text>` — コメント追加',
      '• `giip api <Verb> [jsondata]` — 汎用 giip API 呼び出し',
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

  // ── ワークフロー実行 — 指定ワークフローをサブエージェントで実行 ────────────────
  //   受け付ける言い回し（すべて実行サブエージェント経路 = --dangerously-skip-permissions）:
  //     明示形（keyword-first / slash）— 部分一致も許可:
  //       `<プロジェクト> 워크플로우 <名>` / `workflow <名>` / `wfrun <名>` / `wf <名>` / `/<名>`
  //       （「워크플로우」は長いので英語別名 workflow / wf / wfrun いずれも可）
  //     ゆるい形（name-first / 単語のみ）— 一般質問の誤爆を防ぐため .agent/workflows に
  //     完全一致する時だけ実行:
  //       `<プロジェクト> <名> 실행[해/해줘]` / `<名> 워크플로우 실행` / `<名> run|start` / `<名>`
  //   例: `giipprj wf errorproc` / `giipprj errorproc 실행` / `giipprj /errorproc` → errorproc.md を実行。
  //   なぜ必須か: DB照会等の .ps1 を含むワークフローは、この実行経路（権限スキップ）
  //   でしか非対話 Slack セッションの権限ポリシーを越えられない。Q&A経路(callClaude)は
  //   skip 権限が無いため必ずブロックされる。ワークフローは必ずここへ載せること。
  {
    let wfQuery = null, looseForm = false, mWf;
    if ((mWf = cmd.match(/^(?:wfrun|workflow|wf\s+run|wf|워크플로우\s*실행|워크플로우|워크플로)\s+(.+)$/))) {
      wfQuery = mWf[1];                                   // 明示: keyword-first (wfrun/workflow/wf/워크플로우)
    } else if ((mWf = cmd.match(/^\/([\w가-힣-]+)$/))) {
      wfQuery = mWf[1];                                   // 明示: slash-command "/name"
    } else if ((mWf = cmd.match(/^(.+?)\s*(?:워크플로우\s*)?(?:실행(?:\s*해\s*주세요|\s*해\s*줘|\s*해|\s*하기)?|run|start)$/))) {
      wfQuery = mWf[1]; looseForm = true;                 // ゆるい: "<name> 実行/실행/run"
    } else if (/^[\w가-힣-]+$/.test(cmd)) {
      wfQuery = cmd; looseForm = true;                    // ゆるい: 単語のみ "<name>"
    }

    if (wfQuery) {
      const query = wfQuery.trim().replace(/\.md$/i, '');
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
      // 明示形のみ部分一致を許可（ゆるい形は完全一致に限定して誤爆を防ぐ）
      if (!match && !looseForm) {
        const subs = candidates.filter(f => f.toLowerCase().includes(q));
        if (subs.length === 1) match = subs[0];
        else if (subs.length > 1) {
          await postMessage(channelId,
            `🔎 \`${query}\` に一致するワークフローが複数あります。1つに絞ってください:\n${subs.map(f => `• \`${nameOf(f)}\``).join('\n')}`,
            replyTs);
          return;
        }
      }
      // ゆるい形で未一致 → ワークフロー指示ではない。通常ルーティングへフォールスルー。
      if (!match && !looseForm) {
        const list = candidates.length ? candidates.map(f => `• \`${nameOf(f)}\``).join('\n') : '(なし)';
        await postMessage(channelId,
          `❓ \`${projName}\` に \`${query}\` というワークフローが見つかりません。\n利用可能:\n${list}\n\n一覧: \`${projName} wflist\``,
          replyTs);
        return;
      }
      if (match) {
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

  // ── task7days — 直近7日間の全 Task (完了・キャンセル含む) ─────────────────
  //   未処理・異常処理された Task を洗い出すため、期間内は全ステータスを列挙する
  if (cmd === 'task7days' || cmd === 'task 7days' || cmd === 'task7d' || cmd === 'tasklist 7days') {
    const DAY_MS = 24 * 60 * 60 * 1000;
    const cutoff = Date.now() - 7 * DAY_MS;
    const inWindow = (t) => {
      // createdAt / startedAt / completedAt のいずれかが直近7日以内なら対象
      const stamps = [t.createdAt, t.startedAt, t.completedAt]
        .filter(Boolean)
        .map(s => Date.parse(s))
        .filter(n => !isNaN(n));
      return stamps.some(n => n >= cutoff);
    };
    const tasks = tm.getTasklistByStatus(null)
      .filter(inWindow)
      .sort((a, b) => String(b.createdAt || '').localeCompare(String(a.createdAt || '')));
    if (tasks.length === 0) {
      await postMessage(channelId, '直近7日間に記録された Task はありません。', replyTs);
      return;
    }
    // ステータス別に件数を集計（未処理／異常検知の手がかりに）
    const counts = tasks.reduce((acc, t) => { acc[t.status] = (acc[t.status] || 0) + 1; return acc; }, {});
    const summary = ['pending', 'running', 'completed', 'cancelled']
      .filter(s => counts[s])
      .map(s => `${tm.statusEmoji(s)} ${s} ${counts[s]}`)
      .join('  ');
    const lines = tasks.map(t => {
      const emoji = tm.statusEmoji(t.status);
      const date = t.createdAt ? t.createdAt.slice(0, 10) : '';
      const taskUrl = tm.getTaskFileUrl(t.taskId);
      const taskLink = taskUrl ? `\n     📁 ${taskUrl}` : '';
      const result = t.resultUrl ? `\n     📄 ${t.resultUrl}` : '';
      return `${emoji} \`${t.taskId}\` [${t.status}] ${date}\n     *${t.title}*\n     ${t.summary}${taskLink}${result}`;
    });
    const header = `*直近7日間の全 Task 一覧 (${tasks.length}件)*\n${summary}`;
    await postLong(channelId, [header, '', ...lines].join('\n'), replyTs);
    return;
  }

  // ── taskmerge — 未完了の重複タスクを検出・統合 ─────────────────────────────
  //   `taskmerge`           → プレビュー（何を統合するか表示のみ、変更なし）
  //   `taskmerge go/실행/apply` → 実際に統合（重複を survivor に集約し残りを取消）
  const mergeCmd = cmd.match(/^(?:taskmerge|task\s*merge|dedupe|중복\s*통합|타스크\s*통합|머지)(?:\s+(go|실행|확정|apply|yes|はい|실시))?$/);
  if (mergeCmd) {
    const doApply = !!mergeCmd[1];
    const clusters = findDuplicatePendingClusters();
    if (clusters.length === 0) {
      await postMessage(channelId, '🔍 統合対象の重複した未完了タスクはありません。', replyTs);
      return;
    }

    if (!doApply) {
      // プレビュー（dry-run）
      const blocks = clusters.map((cl, i) => {
        const merged = cl.members.filter(m => m.taskId !== cl.survivor.taskId);
        return [
          `*グループ ${i + 1}* (${cl.members.length}件)`,
          `  ✅ 維持: \`${cl.survivor.taskId}\` — ${cl.survivor.title}`,
          ...merged.map(m => `  🚫 統合→取消: \`${m.taskId}\` — ${m.title}`),
        ].join('\n');
      });
      await postLong(channelId, [
        `*🔀 重複した未完了タスク ${clusters.length}グループを検出*`,
        '',
        ...blocks,
        '',
        '統合を実行するには: `taskmerge go`',
        '（維持タスクに重複要請を統合記録し、残りは cancel フォルダへ移動します。取消済みは復元可能です。）',
      ].join('\n'), replyTs);
      return;
    }

    // 実行
    const report = applyTaskMerge(clusters, taskState);
    saveJSON(TASK_STATE_FILE, taskState);
    await postLong(channelId, report, replyTs);
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

  // ── go <Task番号> [追加指示] — スレッド不問で指定 Task を実行 ──────────────
  //   末尾に $ を張らず、`go <番号>` の後ろに続くテキストを「追加指示」として許容する。
  //   （旧: $ 固定 → コメント行を付けると bare go に落ちて Task 一覧が出るバグ）
  const goWithId = cmd.match(/^(?:go|start|실행|시작|진행|実行|開始)\s+(\d{14})\b/);
  if (goWithId) {
    const targetId = goWithId[1];
    // go <番号> の後ろに続くテキスト = その Task への「追加指示」。原文 text から抽出し
    //   (大小文字/改行/한글 保持)、Task ファイルへの追記は tm.appendTaskNote に委譲する。
    const extraNote = text.trim()
      .replace(/^(?:go|start|실행|시작|진행|実行|開始)\s+\d{14}[ \t]*/i, '')
      .trim();
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
        if (extraNote && tm.appendTaskNote(targetId, extraNote)) {
          await postMessage(channelId, `📎 追加指示 (${extraNote.length}字) を Task \`${targetId}\` に反映しました。`, replyTs);
        }
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
    if (extraNote && tm.appendTaskNote(targetId, extraNote)) {
      await postMessage(channelId, `📎 追加指示 (${extraNote.length}字) を Task \`${targetId}\` に反映しました。`, replyTs);
    }
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

  // ── 既存タスクIDへの言及 → 3分岐: 質問=回答 / 修正依頼=再実行 / ID単独=状態表示 ──
  //   注意: ここでの分類結果は下流の intent 判定でも再利用し、二重の classifyRequest 呼び出しを避ける。
  let preIntent = null;        // この分岐で確定した意図（下流で再分類しないため）
  let refTaskContext = '';     // 修正依頼時に本文へ付加する親タスク文脈
  const mentionedIds = extractExistingTaskIds(text);
  if (mentionedIds.length > 0) {
    const targetId = mentionedIds[0];
    const activeFile = [
      path.join(AGENT_DIR, 'tasks', `${targetId}.md`),
      path.join(AGENT_DIR, 'tasks', 'done', `${targetId}.md`),
      path.join(AGENT_DIR, 'tasks', 'cancel', `${targetId}.md`),
    ].find(f => fs.existsSync(f));

    // テキストがタスクID単独（些末な語のみ）か、指示を含むかを判定
    const isOnlyId = text.trim().replace(/`/g, '').match(/^(\d{14}|\d{8}_[\w-]+)$/);
    if (isOnlyId) {
      // ① ID単独 → 状態表示のみ（新規タスクは作らない）
      if (activeFile) {
        const fc = fs.readFileSync(activeFile, 'utf8');
        const statusM = fc.match(/^status:\s*(.+)$/m);
        const requestM = fc.match(/^request:\s*"?([^\n"]{1,100})/m);
        const status = statusM ? statusM[1].trim() : '不明';
        const request = requestM ? requestM[1].trim() : '（内容なし）';
        await postMessage(channelId,
          `📌 タスク \`${targetId}\` 参照:\n• ステータス: ${status}\n• 内容: ${request}\n📁 ファイル: \`${activeFile}\`\n\n実行: \`go ${targetId}\` | キャンセル: \`cancel ${targetId}\``,
          replyTs
        );
      } else {
        await postMessage(channelId, `⚠️ タスク \`${targetId}\` が見つかりません。`, replyTs);
      }
      return;
    }

    // ID以外の指示を含む → 意図を判定（下流と共有するため preIntent に保持）
    preIntent = await classifyRequest(text, workDir);
    if (preIntent === 'question') {
      // ② 質問 → その場で回答（タスクファイルのパスをコンテキストとして付加）
      const taskContext = activeFile
        ? `\n\n[参考] タスク ${targetId} のファイルパス: ${activeFile}`
        : '';
      await answerInChannel({ channelId, replyTs, text: text + taskContext, workDir, threadTs });
      return;
    }

    // ③ 修正・再実行依頼（task）→ 拒否せず、親タスクを文脈に付けて通常のタスク生成フローへ流す
    if (activeFile) {
      refTaskContext = `\n\n[修正対象] このリクエストは既存タスク ${targetId}（${activeFile}）に対する修正/再実行依頼です。元タスクの内容・成果物を踏まえて対応してください。`;
      await postMessage(channelId,
        `🔧 タスク \`${targetId}\` への修正依頼として受け付けました。内容を分析して新しいタスクを作成します。`,
        replyTs
      );
    }
    // ここで return せず、下流の「タスク確定 → 分析 → 作成」フローへ落とす
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
  // preIntent（既存タスクID分岐で確定済み）があれば再分類せず流用する
  const intent = preIntent || await classifyRequest(text, workDir);
  console.log(`[Bot] intent="${intent}"${preIntent ? ' (reused)' : ''} text="${text.slice(0, 60)}"`);

  if (intent === 'question') {
    // 質問・曖昧 → その場で回答（スレッド内なら全文脈を渡す）
    await answerInChannel({ channelId, replyTs, text, workDir, threadTs });
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

  // 修正依頼（既存タスクID言及）の場合は親タスク文脈を本文に付加して分析・保存する
  const taskRequestText = text + refTaskContext;

  let planContent, filesRead;
  try {
    ({ planContent, filesRead } = tm.analyzeRequest(taskRequestText, null, workDir));
  } catch (err) {
    await postMessage(channelId, `分析エラー: ${err.message}`, replyTs);
    return;
  }

  const taskId = tm.getTimestampId();
  const taskFile = tm.createTaskFile(taskId, taskRequestText, planContent, filesRead);
  const taskTitle = tm.extractTitle(planContent);
  const taskSummary = tm.extractSummary(planContent);

  taskState.pending[convKey] = { taskId, taskTitle, taskFile, requestText: taskRequestText };
  saveJSON(TASK_STATE_FILE, taskState);
  tm.addToTasklist(taskId, taskTitle, taskSummary, taskRequestText);

  // ── giip issue 통일(rule 40): 연결 시 issue 우선 등록(IN_PROGRESS). 실패/미연결 시 로컬 태스크만. ──
  let giipIsn = null;
  try {
    const gt = require('./giip-task');
    // csn 은 처음 언급한 프로젝트명(projectName, 폴더 없어도 해석) 기준(project-csn.json). 없으면 account.csn 폴백.
    giipIsn = await gt.maybeCreateIssue(channelId, taskTitle, planContent, config.resolveProjectCsn(projectName || workDir));
    if (giipIsn) { taskState.pending[convKey].isn = giipIsn; saveJSON(TASK_STATE_FILE, taskState); }
  } catch (e) { console.error('[Bot] giip issue 등록 훅 오류:', e.message); }
  const isnLine = giipIsn ? `\n🔗 giip issue #${giipIsn} (IN_PROGRESS)` : '';

  await postLong(channelId,
    `📋 *Task 分析完了* (\`${taskId}\`)${isnLine}${closedNotice}\n\n${planContent}\n\n---\n*実行: \`go ${taskId}\` / キャンセル: \`cancel ${taskId}\`*`,
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
  const mentionsBot = config.getBotUserId() && msg.text.includes(`<@${config.getBotUserId()}>`);
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
  //   さらにチャンネル固定マッピング(channel-project.json)を適用: 明示接頭辞が無ければ
  //   このチャンネルの既定プロジェクトへ workDir/projectName を固定する。
  //   優先順位: 明示接頭辞(Rule 32) > チャンネル固定。cleanText は不変。
  const { workDir, cleanText, projectName } =
    config.applyChannelPin(channelId, parseProjectPrefix(rawCleanText));

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
    await handleChannelMention({ channelId, ts: msg.ts, threadTs: effectiveThreadTs, text: cleanText, workDir, projectName });
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

module.exports = {
  handleSimpleGitOp,
  answerInChannel,
  handleDM,
  startTaskExecution,
  handleChannelMention,
  isActiveTaskThread,
  processMessage,
  onSlackMessage,
};
