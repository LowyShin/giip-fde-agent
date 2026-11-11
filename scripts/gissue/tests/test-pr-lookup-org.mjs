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
 * 네트워크 없이 돈다 — gh 실행부를 `setGhSpawn` 으로 갈아끼운다.
 * (PATH 에 가짜 gh 를 끼우는 방식은 OS 별 동작이 달라 Windows CI 에서 깨진다 — 실측 2026-11-11)
 *
 * 실행: node scripts/gissue/tests/test-pr-lookup-org.mjs
 */
import {
  setGhSpawn, findIssuePrsInOrg, findIssuePrsByBranchInRepo, selectPrimaryPr,
  prDeclaresIsn, commitMatchesIsn, branchMatchesIsn,
} from '../lib/pr-lookup.mjs';
import { parseLookupArgs, runLookup } from '../lib/pr-lookup-cli.mjs';

let pass = 0, fail = 0;
function check(name, actual, expected) {
  if (actual === expected) { pass++; console.log(`  PASS  ${name}`); }
  else { fail++; console.log(`  FAIL  ${name} — expected ${expected}, got ${actual}`); }
}
function checkTrue(name, cond, detail = '') {
  if (cond) { pass++; console.log(`  PASS  ${name}`); }
  else { fail++; console.log(`  FAIL  ${name}${detail ? ' — ' + detail : ''}`); }
}

const ISN = 4840;
const PR = (n, title, body, extra = {}) => Object.assign({
  number: n, state: 'OPEN', url: `https://github.com/TestOrg/giipv3/pull/${n}`,
  title, body, repository: { fullName: 'TestOrg/giipv3' },
}, extra);

/** 가짜 gh — 인자를 보고 "어떤 호출인지"를 판단해 정해진 JSON 을 돌려준다. 호출 횟수도 기록한다. */
const ghCalls = [];
function fakeGh(args) {
  ghCalls.push(args.join(' '));
  const joined = args.join(' ');

  if (args[0] === 'search' && args[1] === 'prs') {
    // head: 한정 질의(규약 브랜치) — 조직 전 1회로 잡는다.
    if (joined.includes('head:bot/task-giip-4840')) {
      return { ok: true, rows: [PR(900, 'fix: 규약 브랜치 PR (giip #4840)', '', { state: 'MERGED' })] };
    }
    const q = args[2] || '';
    if (q.includes('4840')) {
      return {
        ok: true,
        rows: [
          // (1) 이 isn 을 제목으로 선언한 PR
          PR(400, 'fix(giip): 4840 번 버그 수정', '', { state: 'MERGED' }),
          // (2) 본문에서만 4840 를 인용한 PR (참조 — 담당 산출물 아님). 번호가 더 크고 MERGED 다.
          PR(950, 'fix: 문서 정정', '근거: 관련 이슈 giip #4840 를 참조합니다', { state: 'MERGED' }),
          // (3) 이 isn 과 무관한 PR (오탐 방지 확인용)
          PR(600, 'fix: 무관한 수정', '내용 없음', { state: 'MERGED' }),
        ],
      };
    }
    return { ok: true, rows: [] };
  }

  if (args[0] === 'search' && args[1] === 'commits') {
    const q = args[2] || '';
    if (q.includes('4840')) {
      return {
        ok: true,
        rows: [{
          sha: 'abc1234def5678',
          url: 'https://github.com/TestOrg/giipv3/commit/abc1234def5678',
          repository: { fullName: 'TestOrg/giipv3' },
          commit: { message: 'fix(gissue): 4840 건 처리 (giip #4840)' },
        }],
      };
    }
    return { ok: true, rows: [] };
  }

  if (args[0] === 'api') {
    const uri = args[1] || '';
    if (uri.includes('/commits/abc1234def5678/pulls')) {
      return {
        ok: true,
        rows: [{
          number: 700, state: 'open', html_url: 'https://github.com/TestOrg/giipv3/pull/700',
          title: 'chore: 커밋 메시지에만 isn 이 있는 PR', body: '',
          head: { sha: 'abc1234def5678', ref: 'work/커밋만' },
        }],
      };
    }
    if (uri.includes('/branches')) {
      return { ok: true, rows: [{ name: 'main' }, { name: 'docs/giip-4840-spec' }, { name: 'docs/giip-48401-other' }] };
    }
    return { ok: true, rows: [] };
  }

  // gh pr list --repo <slug> --head <branch> --state all
  if (args[0] === 'pr' && args[1] === 'list') {
    const headIdx = args.indexOf('--head');
    const head = headIdx >= 0 ? args[headIdx + 1] : '';
    if (head === 'docs/giip-4840-spec') {
      return {
        ok: true,
        rows: [{
          number: 800, state: 'MERGED', url: 'https://github.com/TestOrg/giipv3/pull/800',
          title: 'docs: 브랜치에만 isn 이 있는 PR', body: '', headRefName: 'docs/giip-4840-spec',
        }],
      };
    }
    return { ok: true, rows: [] };
  }

  return { ok: true, rows: [] };
}

setGhSpawn(fakeGh);

console.log('\n=== 조직 전 탐색: 후보를 찾는다 ===');
const org = findIssuePrsInOrg('TestOrg', ISN, { limit: 50, maxCommits: 5 });
checkTrue('ok=true', org.ok === true, JSON.stringify(org.errors || []).slice(0, 200));
const nums = org.prs.map(p => p.number);
checkTrue('제목/본문 경로(org-pr)로 이 isn 을 선언한 PR 을 찾는다', nums.includes(400), `nums=${nums}`);
checkTrue('커밋 메시지 경로(org-commit)으로 PR 을 찾는다', nums.includes(700), `nums=${nums}`);
checkTrue('규약 head 브랜치 경로(org-branch)로 PR 을 찾는다', nums.includes(900), `nums=${nums}`);
checkTrue('탐색 경로가 sources 에 기록된다',
  org.sources.includes('org-pr') && org.sources.includes('org-commit') && org.sources.includes('org-branch'),
  org.sources.join(','));

console.log('\n=== 오탐 방지: 이 isn 을 담지 않은 PR 은 후보가 아니다 ===');
checkTrue('무관한 PR(#600)은 후보가 아니다', !nums.includes(600), `nums=${nums}`);
checkTrue('본문 인용만 한 PR(#950)은 후보이되 how 로 구분된다', nums.includes(950), `nums=${nums}`);

console.log('\n=== 대표 PR 선택 (giip #4840: 판정 대상이 아닌 PR 을 근거로 한 오탐) ===');
const primary = selectPrimaryPr(org.prs, ISN);
checkTrue('대표 PR 이 존재한다', !!primary);
checkTrue('본문 인용만 한 PR(#950)은 대표가 아니다', primary && primary.number !== 950, `primary=#${primary && primary.number}`);
checkTrue('대표 PR 은 이 isn 을 브랜치/제목으로 선언한 PR 이다',
  !!(primary && (String(primary.headRefName || '').includes(String(ISN)) || String(primary.title || '').includes(String(ISN)))),
  `primary=#${primary && primary.number} head=${primary && primary.headRefName} title=${primary && primary.title}`);
// 선언 + MERGED 후보 = {400, 800, 900} → 동률 규칙(번호 큰 쪽)이 900 을 고른다. 규칙을 정확히 고정한다.
check('대표 PR 번호(선언 우선 → MERGED → 번호 큰 순)', primary && primary.number, 900);

console.log('\n=== 레포 브랜치명 경로 (브랜치에만 isn 이 있는 PR) ===');
const branchRes = findIssuePrsByBranchInRepo('slug:TestOrg/giipv3', ISN, { maxBranches: 10 });
const bnums = branchRes.prs.map(p => p.number);
checkTrue('브랜치 열거로 isn 을 담는 브랜치의 PR 을 찾는다(#800)', bnums.includes(800), `nums=${bnums}`);
checkTrue('탐색 경로가 how=branch 로 기록된다', branchRes.prs.some(p => p.how === 'branch'),
  branchRes.prs.map(p => `#${p.number}:${p.how}`).join(','));
checkTrue('숫자 경계를 넘는 브랜치(giip-48401)는 잡지 않는다', !bnums.includes(801));

console.log('\n=== CLI 조립(구·신 경로 통합) ===');
const parsed = parseLookupArgs([String(ISN), '--org', 'TestOrg', '--org-limit', '50']);
check('인자 파싱: isn', parsed.isn, ISN);
check('인자 파싱: 조직 목록', parsed.orgs.join(','), 'TestOrg');
check('인자 파싱: 기본 org-mode', parsed.orgMode, 'fallback');
const cliRes = runLookup(ISN, [], ['TestOrg'], { orgMode: 'fallback' });
const cliNums = cliRes.all.map(p => p.number);
checkTrue('CLI 결과에 조직 전 후보가 실린다', cliNums.includes(400) && cliNums.includes(700) && cliNums.includes(900),
  `nums=${cliNums}`);
checkTrue('CLI 대표 PR 도 선언 우선 규칙을 따른다', cliRes.primary && cliRes.primary.number !== 950,
  `primary=#${cliRes.primary && cliRes.primary.number}`);

console.log('\n=== selectPrimaryPr 규칙 순서 (CLI/대시보드가 공유하는 정본) ===');
check('선언한 PR 이 MERGED 를 앞선다 — 선언 우선(giip #4840 의 핵심 규칙)',
  selectPrimaryPr([
    { number: 10, state: 'MERGED', title: 'fix: 문서 정정', body: 'giip #4840 참조' },
    { number: 11, state: 'OPEN', headRefName: 'bot/task-giip-4840' },
  ], ISN).number, 11);
check('선언 등급이 같으면 MERGED 우선',
  selectPrimaryPr([
    { number: 12, state: 'OPEN', headRefName: 'bot/task-giip-4840' },
    { number: 13, state: 'MERGED', headRefName: 'bot/task-giip-4840' },
  ], ISN).number, 13);
check('상태도 같으면 PR 번호 큰 쪽(더 최근)',
  selectPrimaryPr([
    { number: 20, state: 'MERGED', headRefName: 'bot/task-giip-4840' },
    { number: 21, state: 'MERGED', headRefName: 'bot/task-giip-4840' },
  ], ISN).number, 21);
check('후보가 없으면 null', selectPrimaryPr([], ISN), null);
check('번호가 없는 행은 후보에서 제외된다', selectPrimaryPr([{ state: 'MERGED' }], ISN), null);

console.log('\n=== 조직·레포 미지정 시: gh 호출 0(네트워크 0) ===');
ghCalls.length = 0;
const noOrg = runLookup(ISN, [], [], { orgMode: 'fallback' });
checkTrue('조직·레포 미지정 → primary=null', noOrg.primary === null, `primary=${JSON.stringify(noOrg.primary)}`);
checkTrue('조직·레포 미지정 → 후보 0건', noOrg.all.length === 0, `n=${noOrg.all.length}`);
checkTrue('조직·레포 미지정 → gh 호출 0회', ghCalls.length === 0, `calls=${ghCalls.join(' | ')}`);

console.log('\n=== 순수 규칙 함수 ===');
check('prDeclaresIsn: 브랜치가 isn 을 선언', prDeclaresIsn({ headRefName: 'docs/giip-4840-x' }, ISN), true);
check('prDeclaresIsn: 다른 isn 만 선언', prDeclaresIsn({ headRefName: 'docs/giip-4840-x' }, 9999), false);
check('commitMatchesIsn: "giip 4840"', commitMatchesIsn('feat: (giip 4840)', ISN), true);
check('commitMatchesIsn: "giip-4840"', commitMatchesIsn('feat: giip-4840', ISN), true);
check('commitMatchesIsn: "#4840"', commitMatchesIsn('fix #4840', ISN), true);
check('commitMatchesIsn: "giip 48401" (숫자 경계)', commitMatchesIsn('fix giip 48401', ISN), false);
check('commitMatchesIsn: 숫자 단독', commitMatchesIsn('took 4840 minutes', ISN), false);
check('branchMatchesIsn: isn 을 담는 브랜치', branchMatchesIsn('docs/giip-4840-x', ISN), true);
check('branchMatchesIsn: 숫자 경계', branchMatchesIsn('docs/giip-48401-x', ISN), false);

setGhSpawn(null);

console.log(`\n결과: PASS ${pass} / FAIL ${fail}\n`);
process.exit(fail ? 1 : 0);
