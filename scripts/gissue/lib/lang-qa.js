#!/usr/bin/env node
/**
 * lang-qa.js — 이슈 처리 뒤 "작성한 글" 검사기
 *
 * 사용법:
 *   node lang-qa.js --isn <N> --csn <C> --since <ISO> --lang <ko|en|ja|zh-CN|zh-TW>
 *              --accounts <giip-accounts.json 경로> [--api-base <URL>]
 *              [--repo <경로> ...] [--post] [--json]
 *
 * 의존성 주입: run({deps}) 형태로 네트워크 의존성을 테스트에서 교체 가능.
 */

'use strict';

const fs = require('fs');
const path = require('path');

// lang-check.js 의 detect 를 재사용
const { detect } = require('./lang-check');

//────────────────────────────────────────
// 순수 분석 함수 (테스트 가능)
//────────────────────────────────────────

/**
 * 코멘트 배열에서 금지 문자를 검출하고 코멘트 단위로 묶는다.
 * @param {{comments: Array, since?: string, lang?: string}} opts
 * @returns {Array<{commentId: string|number, author: string, regdate: string, count: number, chars: string[], excerpt: string}>}
 */
function analyze({ comments = [], since, lang = 'ko' }) {
  const results = [];

  for (const comment of comments) {
    // since 이후만
    if (since && comment.regdate) {
      const regDate = new Date(comment.regdate);
      const sinceDate = new Date(since);
      if (regDate < sinceDate) continue;
    }

    const content = comment.content || '';
    // [LANG-QA] 로 시작하는 코멘트는 제외 (우리 자신의 보고)
    if (content.startsWith('[LANG-QA]')) continue;

    const findings = detect(content, lang);
    if (findings.length === 0) continue;

    const chars = [...new Set(findings.map(f => f.char))].slice(0, 10);
    const first = findings[0];

    results.push({
      commentId: comment.cSn || comment.gicSn || 'unknown',
      author: comment.author || 'unknown',
      regdate: comment.regdate || '',
      count: findings.length,
      chars,
      excerpt: first.excerpt || '',
    });
  }

  return results;
}

//────────────────────────────────────────
// SK 해석
//────────────────────────────────────────

/**
 * accounts 파일에서 csn 에 맞는 sk 를 찾는다.
 * resolve-sk.js 와 같은 규칙.
 * @param {string} accountsFile
 * @param {string|number} csn
 * @returns {string|null}
 */
function resolveSk(accountsFile, csn) {
  const data = JSON.parse(fs.readFileSync(accountsFile, 'utf-8'));
  const channels = Object.values(data.channels || {});
  const defaultEntry = data.default ? [data.default] : [];
  const allEntries = [...channels, ...defaultEntry];
  const match = allEntries.find(c => String(c.csn) === String(csn));
  return match ? match.sk : null;
}

//────────────────────────────────────────
// 코멘트 조회 (의존성 — 테스트에서 교체 가능)
//────────────────────────────────────────

async function defaultListComments({ apiBase, apiKey, isn }) {
  const { listComments } = require('./comment-api');
  return listComments({ apiBase, apiKey, isn });
}

//────────────────────────────────────────
// 코멘트 등록 (의존성 — 테스트에서 교체 가능)
//────────────────────────────────────────

async function defaultPostCommentVerified({ apiBase, apiKey, isn, content }) {
  const { postCommentVerified } = require('./comment-api');
  return postCommentVerified({ apiBase, apiKey, isn, content, issuetype: 'note' });
}

//────────────────────────────────────────
// run — CLI 논리 (의존성 주입 가능)
//────────────────────────────────────────

/**
 * @param {{deps?: {listComments?: Function, postCommentVerified?: Function, exit?: Function}}} opts
 */
async function run(opts = {}) {
  const deps = opts.deps || {};
  const listCommentsFn = deps.listComments || defaultListComments;
  const postCommentVerifiedFn = deps.postCommentVerified || defaultPostCommentVerified;
  const doExit = deps.exit || ((code) => process.exit(code));

  // CLI 인자 파싱
  const argv = process.argv.slice(2);
  const args = {};
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === '--isn' && i + 1 < argv.length) args.isn = argv[++i];
    else if (argv[i] === '--csn' && i + 1 < argv.length) args.csn = argv[++i];
    else if (argv[i] === '--since' && i + 1 < argv.length) args.since = argv[++i];
    else if (argv[i] === '--lang' && i + 1 < argv.length) args.lang = argv[++i];
    else if (argv[i] === '--accounts' && i + 1 < argv.length) args.accounts = argv[++i];
    else if (argv[i] === '--api-base' && i + 1 < argv.length) args.apiBase = argv[++i];
    else if (argv[i] === '--repo' && i + 1 < argv.length) {
      if (!args.repos) args.repos = [];
      args.repos.push(argv[++i]);
    }
    else if (argv[i] === '--post') args.post = true;
    else if (argv[i] === '--json') args.asJson = true;
  }

  const { isn, csn, since, lang = 'ko', accounts, apiBase, repos = [], post, asJson } = args;

  // 인자 검증
  if (!isn || !csn || !since || !accounts) {
    console.error('사용법: node lang-qa.js --isn <N> --csn <C> --since <ISO> --lang <lang> --accounts <파일> [--api-base <URL>] [--repo <경로> ...] [--post] [--json]');
    doExit(2);
  }

  // SK 해석
  const sk = resolveSk(accounts, csn);
  if (!sk) {
    console.error('SK 없음');
    doExit(2);
  }

  const apiBaseUrl = apiBase || 'https://giipfaw.azurewebsites.net/api';

  // 코멘트 조회
  let comments = [];
  let commentError = null;
  try {
    const raw = await listCommentsFn({ apiBase: apiBaseUrl, apiKey: sk, isn });
    // 배열이거나 {comments: [...]} 형태
    if (Array.isArray(raw)) {
      comments = raw;
    } else if (raw && Array.isArray(raw.comments)) {
      comments = raw.comments;
    }
  } catch (e) {
    commentError = e.message || String(e);
  }

  // 코멘트 검사
  const commentResults = analyze({ comments, since, lang });

  // git 저장소 검사
  const { checkGit } = require('./lang-check');
  /** @type {Array<any>} */
  let gitResults = [];
  const gitErrors = [];

  if (repos.length > 0) {
    for (const repoPath of repos) {
      if (!fs.existsSync(repoPath)) {
        gitErrors.push({ path: repoPath, error: `존재하지 않는 경로: ${repoPath}` });
        continue;
      }
      try {
        const findings = checkGit(repoPath, { since, lang, maxFindings: 50 });
        gitResults = gitResults.concat(findings.filter(f => !f.error));
        findings.filter(f => f.error).forEach(f => gitErrors.push({ path: repoPath, error: f.error }));
      } catch (e) {
        gitErrors.push({ path: repoPath, error: e.message || String(e) });
      }
    }
  }

  // 출력
  if (asJson) {
    const output = {
      commentResults,
      gitResults,
      gitErrors,
      commentError: commentError || undefined,
    };
    console.log(JSON.stringify(output, null, 2));
  } else {
    // 사람이 읽는 한국어 요약
    if (commentError) {
      console.log(`[WARN] 코멘트 조회 실패: ${commentError}`);
    }
    if (commentResults.length > 0) {
      console.log(`코멘트에서 발견: ${commentResults.length}건`);
      for (const r of commentResults.slice(0, 10)) {
        console.log(`  [${r.author} ${r.regdate}] ${r.count}건: ${r.chars.join(', ')}`);
        console.log(`    "${r.excerpt}"`);
      }
    } else {
      console.log('코멘트: 문제 없음');
    }

    if (gitResults.length > 0) {
      console.log(`저장소 검사에서 발견: ${gitResults.length}건`);
      for (const f of gitResults.slice(0, 10)) {
        const loc = f.file ? `${f.file}@${f.line || '?'}` : `커밋 ${f.commit} (${f.kind})`;
        console.log(`  [${loc}] ${f.char} (${f.codePoint}) — ${f.script}`);
        console.log(`    "${f.excerpt}"`);
      }
    } else if (gitErrors.length === 0) {
      console.log('저장소: 문제 없음');
    }
    for (const err of gitErrors) {
      console.log(`[WARN] 저장소 ${err.path}: ${err.error}`);
    }
  }

  // 종료코드: 0 문제 없음, 4 금지 문자 발견, 2 오류
  const hasForbidden = commentResults.length > 0 || gitResults.length > 0;
  const hasError = !!commentError || gitErrors.length > 0;

  if (hasForbidden) {
    // --post 이면 코멘트 등록
    if (post) {
      await postReport({ deps, apiBaseUrl, sk, isn, since, lang, commentResults, gitResults });
    }
    doExit(4);
  } else if (hasError) {
    doExit(2);
  } else {
    doExit(0);
  }
}

//────────────────────────────────────────
// 보고 코멘트 등록
//────────────────────────────────────────

async function postReport({ deps, apiBaseUrl, sk, isn, since, lang, commentResults, gitResults }) {
  const postFn = deps.postCommentVerified || defaultPostCommentVerified;
  const listCommentsFn = deps.listComments || defaultListComments;

  // 이미 [LANG-QA] 코멘트가 있는지 확인
  try {
    const comments = await listCommentsFn({ apiBase: apiBaseUrl, apiKey: sk, isn });
    const langQaExists = comments.some(c =>
      (c.content || '').startsWith('[LANG-QA]') &&
      c.author && c.author.includes('Claude')
    );
    if (langQaExists) {
      console.log('[WARN] 이미 [LANG-QA] 코멘트가 있어 새로 등록하지 않음');
      return;
    }
  } catch (e) {
    console.log(`[WARN] 기존 [LANG-QA] 코멘트 확인 실패: ${e.message}`);
  }

  // 보고 본문 작성
  const total = commentResults.length + gitResults.length;
  const bodyLines = [
    '[LANG-QA] 금지 문자 검사 보고',
    '',
    `검사 구간: ${since} ~ ${new Date().toISOString()}`,
    '',
    `코멘트 ${commentResults.length}건, 커밋/파일 ${gitResults.length}건에서 발견`,
    '',
  ];

  if (commentResults.length > 0) {
    bodyLines.push('코멘트:');
    for (const r of commentResults.slice(0, 10)) {
      bodyLines.push(`- ${r.author} ${r.regdate}: ${r.count}건 (${r.chars.join(', ')})`);
      bodyLines.push(`  "${r.excerpt}"`);
    }
  }

  if (gitResults.length > 0) {
    bodyLines.push('저장소:');
    for (const f of gitResults.slice(0, 10)) {
      const loc = f.file ? `${f.file}@${f.line || '?'}` : `커밋 ${f.commit} (${f.kind})`;
      bodyLines.push(`- ${loc}: ${f.char} (${f.codePoint})`);
      bodyLines.push(`  "${f.excerpt}"`);
    }
  }

  bodyLines.push('');
  bodyLines.push('다음 처리에서 해당 글을 100% 한글로 교정해야 한다.');

  const content = bodyLines.join('\n');

  try {
    await postFn({ apiBase: apiBaseUrl, apiKey: sk, isn, content });
    console.log('[INFO] [LANG-QA] 보고 코멘트 등록 완료');
  } catch (e) {
    console.log(`[WARN] 보고 코멘트 등록 실패: ${e.message} — 종료코드는 4로 유지`);
  }
}

//────────────────────────────────────────
// exports / CLI 실행
//────────────────────────────────────────

module.exports = {
  analyze,
  resolveSk,
  run,
};

// CLI 실행
if (require.main === module) {
  run().catch(e => {
    console.error('오류:', e.message);
    doExit(2);
  });
}
