#!/usr/bin/env node
/**
 * test-pr-lookup-org.mjs — 증거 기반 조직 전 귀속 경로 회귀 테스트 (giip #4840/#4839)
 *
 * 이 테스트가 고정하는 것:
 *   (A) 조직 전 레포에서 PR 을 **찾는다**   — 제목/본문(org-pr) · 커밋 메시지(org-commit) ·
 *                                             규약 head 브랜치(org-branch) · 레포 브랜치명(branch)
 *   (B) 이 isn 을 담지 않은 PR 은 **못 찾는다** (오탐 방지 — 게이트 무력화 방지)
 *   (C) 대표 PR(primary) 선택 — **이 isn 을 브랜치/제목으로 선언한 PR** 이 우선이다.
 *       (giip #4840: "판정 대상이 아닌 PR 을 근거로 한 오탐" 의 직접 원인)
 *
 * 네트워크 없이 돈다 — PATH 앞에 가짜 `gh` 를 끼워 넣는다(gh 호출 자체를 대체).
 * 실행: node scripts/gissue/tests/test-pr-lookup-org.mjs
 */
import { spawnSync } from 'node:child_process';
import { dirname, resolve, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { mkdtempSync, writeFileSync, chmodSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';

const __dirname = dirname(fileURLToPath(import.meta.url));
const CLI = resolve(__dirname, '../lib/pr-lookup-cli.mjs');

let pass = 0, fail = 0;
function check(name, actual, expected) {
  if (actual === expected) { pass++; console.log(`  PASS  ${name}`); }
  else { fail++; console.log(`  FAIL  ${name} — expected ${expected}, got ${actual}`); }
}
function checkTrue(name, cond, detail = '') {
  if (cond) { pass++; console.log(`  PASS  ${name}`); }
  else { fail++; console.log(`  FAIL  ${name}${detail ? ' — ' + detail : ''}`); }
}

// ── 가짜 gh 구현 ────────────────────────────────────────────────────────────
// 인자를 보고 "어떤 gh 호출인지"를 판단해 정해진 JSON 을 돌려준다.
const GH_IMPL = `
const args = process.argv.slice(2);
const isSearchPrs = args[0] === 'search' && args[1] === 'prs';
const isSearchCommits = args[0] === 'search' && args[1] === 'commits';
const isApi = args[0] === 'api';
const joined = args.join(' ');

const pr = (n, title, body, extra = {}) => Object.assign({
  number: n, state: 'OPEN', url: 'https://github.com/TestOrg/giipv3/pull/' + n,
  title, body, repository: { fullName: 'TestOrg/giipv3' },
}, extra);

if (isSearchPrs) {
  // head: 한정 질의(규약 브랜치)
  if (joined.includes('head:bot/task-giip-4840')) {
    process.stdout.write(JSON.stringify([pr(900, 'fix: 규약 브랜치 PR (giip #4840)', '', { state: 'MERGED' })]));
    process.exit(0);
  }
  const q = args[2] || '';
  if (q.includes('4840')) {
    process.stdout.write(JSON.stringify([
      // (1) 이 isn 을 제목으로 선언한 PR
      pr(400, 'fix(giip): 4840 번 버그 수정', '', { state: 'MERGED' }),
      // (2) 본문에서만 4840 를 인용한 PR (참조 — 담당 산출물 아님). 번호가 더 크고 MERGED 이지만 대표가 되면 안 된다.
      pr(950, 'fix: 문서 정정', '근거: 관련 이슈 giip #4840 를 참조합니다', { state: 'MERGED' }),
      // (3) 이 isn 과 무관한 PR (오탐 방지 확인용)
      pr(600, 'fix: 무관한 수정', '내용 없음', { state: 'MERGED' }),
    ]));
    process.exit(0);
  }
  process.stdout.write(JSON.stringify([]));
  process.exit(0);
}

if (isSearchCommits) {
  const q = args[2] || '';
  if (q.includes('4840')) {
    process.stdout.write(JSON.stringify([{
      sha: 'abc1234def5678',
      url: 'https://github.com/TestOrg/giipv3/commit/abc1234def5678',
      repository: { fullName: 'TestOrg/giipv3' },
      commit: { message: 'fix(gissue): 4840 건 처리 (giip #4840)' },
    }]));
    process.exit(0);
  }
  process.stdout.write(JSON.stringify([]));
  process.exit(0);
}

if (isApi) {
  const uri = args[1] || '';
  if (uri.includes('/commits/abc1234def5678/pulls')) {
    process.stdout.write(JSON.stringify([{
      number: 700, state: 'open', html_url: 'https://github.com/TestOrg/giipv3/pull/700',
      title: 'chore: 커밋 메시지에만 isn 이 있는 PR', body: '',
      head: { sha: 'abc1234def5678', ref: 'work/커밋만' },
    }]));
    process.exit(0);
  }
  if (uri.includes('/branches')) {
    process.stdout.write(JSON.stringify([
      { name: 'main' },
      { name: 'docs/giip-4840-spec' },
      { name: 'docs/giip-48401-other' },
    ]));
    process.exit(0);
  }
  process.stdout.write(JSON.stringify([]));
  process.exit(0);
}

// gh pr list --repo <slug> --head <branch> --state all
if (args[0] === 'pr' && args[1] === 'list') {
  const headIdx = args.indexOf('--head');
  const head = headIdx >= 0 ? args[headIdx + 1] : '';
  if (head === 'docs/giip-4840-spec') {
    process.stdout.write(JSON.stringify([{
      number: 800, state: 'MERGED', url: 'https://github.com/TestOrg/giipv3/pull/800',
      title: 'docs: 브랜치에만 isn 이 있는 PR', body: '', headRefName: 'docs/giip-4840-spec',
    }]));
    process.exit(0);
  }
  process.stdout.write(JSON.stringify([]));
  process.exit(0);
}

process.stdout.write(JSON.stringify([]));
process.exit(0);
`;

function makeFakeGh(dir) {
  const impl = join(dir, 'gh-impl.mjs');
  writeFileSync(impl, GH_IMPL, 'utf8');
  // POSIX: 셸 래퍼 + Windows: 배치 래퍼 (둘 다 같은 구현을 부른다)
  writeFileSync(join(dir, 'gh'), `#!/bin/sh\nexec node "${impl}" "$@"\n`, 'utf8');
  writeFileSync(join(dir, 'gh.cmd'), `@echo off\r\nnode "${impl.replace(/\\/g, '\\\\')}" %*\r\n`, 'utf8');
  chmodSync(join(dir, 'gh'), 0o755);
}

const tmp = mkdtempSync(join(tmpdir(), 'pr-lookup-org-'));
makeFakeGh(tmp);

function runCli(args) {
  const r = spawnSync(process.execPath, [CLI, ...args], {
    encoding: 'utf8',
    env: { ...process.env, PATH: `${tmp}${process.platform === 'win32' ? ';' : ':'}${process.env.PATH}` },
  });
  if (r.status !== 0) {
    console.log(`  (cli exit=${r.status}: ${(r.stderr || '').trim().slice(0, 200)})`);
    return null;
  }
  try { return JSON.parse(r.stdout || '{}'); } catch { return null; }
}

const ISN = '4840';

console.log('\n=== 조직 전 탐색: 후보를 찾는다 ===');
const org = runCli([ISN, '--org', 'TestOrg']);
if (!org) { console.log('  FAIL  CLI 실행 실패'); fail++; }
else {
  checkTrue('ok=true', org.ok === true, JSON.stringify(org.errors || []).slice(0, 200));
  const all = org.all || [];
  const nums = all.map(p => p.number);
  checkTrue('제목/본문 경로(org-pr)로 이 isn 을 선언한 PR 을 찾는다', nums.includes(400), `nums=${nums}`);
  checkTrue('커밋 메시지 경로(org-commit)으로 PR 을 찾는다', nums.includes(700), `nums=${nums}`);
  checkTrue('규약 head 브랜치 경로(org-branch)로 PR 을 찾는다', nums.includes(900), `nums=${nums}`);
  checkTrue('탐색 경로가 how 에 기록된다', all.some(p => p.how === 'org-pr') && all.some(p => p.how === 'org-commit') && all.some(p => p.how === 'org-branch'),
    all.map(p => `#${p.number}:${p.how}`).join(','));
}

console.log('\n=== 오탐 방지: 이 isn 을 담지 않은 PR 은 후보가 아니다 ===');
if (org) {
  const nums = (org.all || []).map(p => p.number);
  checkTrue('무관한 PR(#600)은 후보가 아니다', !nums.includes(600), `nums=${nums}`);
}

console.log('\n=== 대표 PR 선택 (giip #4840: 판정 대상이 아닌 PR 을 근거로 한 오탐) ===');
if (org) {
  const p = org.primary;
  checkTrue('대표 PR 이 존재한다', !!p);
  // #950 은 본문에서만 4840 를 인용(참조)했고 번호도 더 크고 MERGED 다. 그럼에도 대표가 되면 안 된다 —
  //(scope 판정이 무관한 PR diff 로 MISMATCH 가 나던 giip #4840 사고)
  checkTrue('본문 인용만 한 PR(#950)은 대표가 아니다', p && p.number !== 950, `primary=#${p && p.number}`);
  checkTrue('대표 PR 은 이 isn 을 브랜치/제목으로 선언한 PR 이다',
    !!(p && (String(p.headRefName || '').includes(ISN) || String(p.title || '').includes(ISN))),
    `primary=#${p && p.number} head=${p && p.headRefName} title=${p && p.title}`);
}

console.log('\n=== 레포 브랜치명 경로 (브랜치에만 isn 이 있는 PR) ===');
const branchRes = runCli([ISN, 'slug:TestOrg/giipv3']);
if (!branchRes) { console.log('  FAIL  CLI 실행 실패(브랜치 경로)'); fail++; }
else {
  const nums = (branchRes.all || []).map(p => p.number);
  checkTrue('브랜치 열거로 isn 을 담는 브랜치의 PR 을 찾는다(#800)', nums.includes(800), `nums=${nums}`);
  checkTrue('탐색 경로가 how=branch 로 기록된다', (branchRes.all || []).some(p => p.how === 'branch'),
    (branchRes.all || []).map(p => `#${p.number}:${p.how}`).join(','));
  checkTrue('숫자 경계를 넘는 브랜치(giip-48401)는 잡지 않는다', !nums.includes(801));
}

console.log('\n=== 조직 미지정 시: 네트워크 호출 없이 결과만 반환 ===');
const noOrg = runCli([ISN]);
checkTrue('조직 미지정 + 레포 미지정 → primary=null', noOrg && noOrg.primary === null);

rmSync(tmp, { recursive: true, force: true });

console.log(`\n결과: PASS ${pass} / FAIL ${fail}\n`);
process.exit(fail ? 1 : 0);
