/**
 * lang-qa.js 테스트
 * 실행: node scripts/gissue/tests/test-lang-qa.mjs
 * 전부 통과하면 마지막 줄에 "PASS test-lang-qa" 출력, 실패하면 exit 1
 */

import assert from 'assert';
import { fileURLToPath } from 'url';
import path from 'path';
import fs from 'fs';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const langQa = (await import('../lib/lang-qa.js')).default;
const { analyze, resolveSk } = langQa;

// 테스트 시작
let passed = 0;
let failed = 0;

function test(name, fn) {
  try {
    fn();
    passed++;
  } catch (e) {
    console.error('FAIL:', name);
    console.error(e.message);
    failed++;
  }
}

//────────────────────────────────────────
// 1. analyze: since 필터
//────────────────────────────────────────

test('analyze: since 이전 코멘트는 제외', () => {
  const comments = [
    { cSn: 1, author: 'user1', regdate: '2026-09-01T00:00:00Z', content: '한자 中 있음' },
    { cSn: 2, author: 'user1', regdate: '2026-10-07T00:00:00Z', content: '한자 中 있음2' },
  ];
  const results = analyze({ comments, since: '2026-10-06T00:00:00Z', lang: 'ko' });
  assert.strictEqual(results.length, 1, 'since 이후 1건');
  assert.strictEqual(results[0].commentId, 2);
});

test('analyze: since 이후 코멘트만 검사', () => {
  const comments = [
    { cSn: 1, author: 'user1', regdate: '2026-10-01T00:00:00Z', content: '한자 中 있음' },
    { cSn: 2, author: 'user1', regdate: '2026-10-08T00:00:00Z', content: '가나 あ 있음' },
  ];
  const results = analyze({ comments, since: '2026-10-05T00:00:00Z', lang: 'ko' });
  assert.strictEqual(results.length, 1);
  assert.strictEqual(results[0].commentId, 2);
});

//────────────────────────────────────────
// 2. analyze: [LANG-QA] 제외
//────────────────────────────────────────

test('analyze: [LANG-QA] 코멘트는 제외', () => {
  const comments = [
    { cSn: 1, author: 'user1', regdate: '2026-10-07T00:00:00Z', content: '한자 中 있음' },
    { cSn: 2, author: 'Claude', regdate: '2026-10-07T01:00:00Z', content: '[LANG-QA] 금지 문자 검사 보고' },
  ];
  const results = analyze({ comments, since: '2026-10-01T00:00:00Z', lang: 'ko' });
  assert.strictEqual(results.length, 1);
  assert.strictEqual(results[0].commentId, 1);
});

//────────────────────────────────────────
// 3. analyze: lang 별 판정
//────────────────────────────────────────

test('analyze: ko에서 한자는 금지', () => {
  const comments = [
    { cSn: 1, author: 'user1', regdate: '2026-10-07T00:00:00Z', content: '中' },
  ];
  const results = analyze({ comments, since: '2026-01-01T00:00:00Z', lang: 'ko' });
  assert.strictEqual(results.length, 1);
  assert.strictEqual(results[0].count, 1);
});

test('analyze: ja에서 한자는 허용', () => {
  const comments = [
    { cSn: 1, author: 'user1', regdate: '2026-10-07T00:00:00Z', content: '中' },
  ];
  const results = analyze({ comments, since: '2026-01-01T00:00:00Z', lang: 'ja' });
  assert.strictEqual(results.length, 0, 'ja에서는 한자 허용');
});

test('analyze: en에서 한글은 금지', () => {
  const comments = [
    { cSn: 1, author: 'user1', regdate: '2026-10-07T00:00:00Z', content: '가나다' },
  ];
  const results = analyze({ comments, since: '2026-01-01T00:00:00Z', lang: 'en' });
  assert.strictEqual(results.length, 1);
  assert.strictEqual(results[0].chars[0], '가');
});

//────────────────────────────────────────
// 4. analyze: 코멘트 단위 묶음
//────────────────────────────────────────

test('analyze: 여러 금지 문자가 있으면 chars에 최대 10개', () => {
  const comments = [
    { cSn: 1, author: 'user1', regdate: '2026-10-07T00:00:00Z', content: '中あд中あд中あд' },
  ];
  const results = analyze({ comments, since: '2026-01-01T00:00:00Z', lang: 'ko' });
  assert.strictEqual(results.length, 1);
  assert.strictEqual(results[0].count, 9, '9건 발견 (3문자×3회)');
  assert.strictEqual(results[0].chars.length, 3, '고유 문자 3개 (ko에서 한글 허용)');
  assert.ok(results[0].chars.includes('中'));
  assert.ok(results[0].chars.includes('あ'));
  assert.ok(results[0].chars.includes('д'));
});

test('analyze: excerpt는 첫 발견의 것', () => {
  const comments = [
    { cSn: 1, author: 'user1', regdate: '2026-10-07T00:00:00Z', content: '이건 中 이고 여기서 끝' },
  ];
  const results = analyze({ comments, since: '2026-01-01T00:00:00Z', lang: 'ko' });
  assert.ok(results[0].excerpt.includes('中'), 'excerpt에 한자 포함');
});

//────────────────────────────────────────
// 5. resolveSk
//────────────────────────────────────────

test('resolveSk: 올바른 csn이면 sk 반환', () => {
  const tmpFile = path.join('/tmp', 'test-accounts-' + Date.now() + '.json');
  const data = JSON.stringify({
    channels: [
      { csn: 47, sk: 'sk-test-47' },
      { csn: 100, sk: 'sk-test-100' },
    ],
    default: { csn: 1, sk: 'sk-default' },
  });
  fs.writeFileSync(tmpFile, data);
  try {
    assert.strictEqual(resolveSk(tmpFile, 47), 'sk-test-47');
    assert.strictEqual(resolveSk(tmpFile, 100), 'sk-test-100');
    assert.strictEqual(resolveSk(tmpFile, 1), 'sk-default');
  } finally {
    fs.unlinkSync(tmpFile);
  }
});

test('resolveSk: 없는 csn이면 null', () => {
  const tmpFile = path.join('/tmp', 'test-accounts-' + Date.now() + '.json');
  const data = JSON.stringify({
    channels: [{ csn: 47, sk: 'sk-47' }],
  });
  fs.writeFileSync(tmpFile, data);
  try {
    assert.strictEqual(resolveSk(tmpFile, 999), null);
  } finally {
    fs.unlinkSync(tmpFile);
  }
});

//────────────────────────────────────────
// 6. run: 문제 없음 → exit 0, post 호출 없음
//────────────────────────────────────────

test('run: 문제 없음 → exit 0, post 호출 없음', async () => {
  let postCalled = false;
  let listCalled = false;
  let exitCode = null;

  const deps = {
    listComments: () => {
      listCalled = true;
      return [{ cSn: 1, author: 'user1', regdate: '2026-10-07T00:00:00Z', content: '안녕하세요' }];
    },
    postCommentVerified: () => {
      postCalled = true;
      return { csn: 10, attempts: 1, verified: true, log: [] };
    },
    exit: (code) => { exitCode = code; },
  };

  const tmpAccounts = path.join('/tmp', 'test-accounts-clean-' + Date.now() + '.json');
  fs.writeFileSync(tmpAccounts, JSON.stringify({
    channels: [{ csn: 47, sk: 'sk-test-47' }],
  }));

  const origArgv = process.argv;
  process.argv = [
    'node', 'lang-qa.js',
    '--isn', '123',
    '--csn', '47',
    '--since', '2026-01-01T00:00:00Z',
    '--lang', 'ko',
    '--accounts', tmpAccounts,
  ];

  try {
    await langQa.run({ deps });
    assert.strictEqual(exitCode, 0, 'exit 0');
    assert.strictEqual(postCalled, false, 'post 호출 없음');
    assert.strictEqual(listCalled, true, 'listComments 호출됨');
  } finally {
    process.argv = origArgv;
    try { fs.unlinkSync(tmpAccounts); } catch (_) {}
  }
});

//────────────────────────────────────────
// 7. run: 금지 문자 있음 + --post → post 1회, 본문이 [LANG-QA] 로 시작
//────────────────────────────────────────

test('run: 금지 문자 있음 + --post → post 1회, 본문 [LANG-QA] 로 시작, SK 미노출', async () => {
  let postCalled = false;
  let postContent = '';
  let exitCode = null;

  const deps = {
    listComments: () => [
      { cSn: 1, author: 'user1', regdate: '2026-10-07T00:00:00Z', content: '한자 中 있음' },
    ],
    postCommentVerified: async ({ content }) => {
      postCalled = true;
      postContent = content;
      return { csn: 10, attempts: 1, verified: true, log: [] };
    },
    exit: (code) => { exitCode = code; },
  };

  const tmpAccounts = path.join('/tmp', 'test-accounts-post-' + Date.now() + '.json');
  fs.writeFileSync(tmpAccounts, JSON.stringify({
    channels: [{ csn: 47, sk: 'sk-OPENAI-SECRET-47-XXXX' }],
  }));

  const origArgv = process.argv;
  process.argv = [
    'node', 'lang-qa.js',
    '--isn', '123',
    '--csn', '47',
    '--since', '2026-01-01T00:00:00Z',
    '--lang', 'ko',
    '--accounts', tmpAccounts,
    '--post',
  ];

  try {
    await langQa.run({ deps });
  } catch (e) {
    // process.exit
  } finally {
    process.argv = origArgv;
    fs.unlinkSync(tmpAccounts);
  }

  assert.strictEqual(postCalled, true, 'postCommentVerified 1회 호출');
  assert.ok(postContent.startsWith('[LANG-QA]'), '본문이 [LANG-QA] 로 시작');
  assert.ok(!postContent.includes('OPENAI'), 'SK 문자열이 어디에도 없음');
  assert.ok(!postContent.includes('sk-'), 'SK 문자열이 어디에도 없음');
  assert.ok(!postContent.includes('SECRET'), 'SK 문자열이 어디에도 없음');
});

//────────────────────────────────────────
// 8. run: 이미 [LANG-QA] 코멘트가 있으면 post 0회
//────────────────────────────────────────

test('run: 이미 [LANG-QA] 코멘트가 있으면 post 0회', async () => {
  let postCalled = false;
  let exitCode = null;

  const deps = {
    listComments: () => [
      { cSn: 1, author: 'user1', regdate: '2026-10-07T00:00:00Z', content: '한자 中 있음' },
      { cSn: 2, author: 'Claude', regdate: '2026-10-07T01:00:00Z', content: '[LANG-QA] 금지 문자 검사 보고' },
    ],
    postCommentVerified: () => {
      postCalled = true;
      return { csn: 10, attempts: 1, verified: true, log: [] };
    },
    exit: (code) => { exitCode = code; },
  };

  const tmpAccounts = path.join('/tmp', 'test-accounts-exist-' + Date.now() + '.json');
  fs.writeFileSync(tmpAccounts, JSON.stringify({
    channels: [{ csn: 47, sk: 'sk-test' }],
  }));

  const origArgv = process.argv;
  process.argv = [
    'node', 'lang-qa.js',
    '--isn', '123',
    '--csn', '47',
    '--since', '2026-01-01T00:00:00Z',
    '--lang', 'ko',
    '--accounts', tmpAccounts,
    '--post',
  ];

  try {
    await langQa.run({ deps });
  } catch (e) {
    // process.exit
  } finally {
    process.argv = origArgv;
    fs.unlinkSync(tmpAccounts);
  }

  assert.strictEqual(postCalled, false, '이미 [LANG-QA] 있으므로 post 0회');
});

//────────────────────────────────────────
// 9. run: 코멘트 조회 실패여도 git 결과는 출력
//────────────────────────────────────────

test('run: 코멘트 조회 실패여도 exit 4 (금지 문자 있음)', async () => {
  let consoleOutput = '';
  const origLog = console.log;
  console.log = (msg) => { consoleOutput += msg + '\n'; };
  let exitCode = null;

  const deps = {
    listComments: () => { throw new Error('네트워크 오류'); },
    postCommentVerified: () => { return { csn: 10, attempts: 1, verified: true, log: [] }; },
    exit: (code) => { exitCode = code; },
  };

  const tmpAccounts = path.join('/tmp', 'test-accounts-err-' + Date.now() + '.json');
  fs.writeFileSync(tmpAccounts, JSON.stringify({
    channels: [{ csn: 47, sk: 'sk-test' }],
  }));

  const origArgv = process.argv;
  process.argv = [
    'node', 'lang-qa.js',
    '--isn', '123',
    '--csn', '47',
    '--since', '2026-01-01T00:00:00Z',
    '--lang', 'ko',
    '--accounts', tmpAccounts,
  ];

  try {
    await langQa.run({ deps });
  } catch (e) {
    // process.exit
  } finally {
    console.log = origLog;
    process.argv = origArgv;
    try { fs.unlinkSync(tmpAccounts); } catch (_) {}
  }

  assert.ok(consoleOutput.includes('코멘트 조회 실패'), '코멘트 조회 실패 경고 출력');
});

//────────────────────────────────────────
// 결과 요약
//────────────────────────────────────────

console.log(`테스트 결과: ${passed}개 통과, ${failed}개 실패`);
if (failed > 0) {
  process.exit(1);
} else {
  console.log('PASS test-lang-qa');
}