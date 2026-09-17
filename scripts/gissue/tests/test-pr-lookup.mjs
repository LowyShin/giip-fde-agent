#!/usr/bin/env node
/**
 * test-pr-lookup.mjs — lib/pr-lookup.mjs 양방향 회귀 테스트 (giip #2464)
 *
 * 이 게이트에서 제일 위험한 회귀는 "넓은검색을 넣었더니 아무 PR 이나 매칭돼 게이트가 무력화되는 것"이다.
 * 그래서 **양방향**을 전부 고정한다:
 *   (A) 실제로 PR 이 있는 isn 은 찾는다          — 안 찾으면 대시보드에 REVIEW_NO_PR 오탐
 *   (B) 실제로 PR 이 없는 isn 은 여전히 못 찾는다 — 찾아버리면 진짜 미완료 이슈를 놓친다
 *
 * 실행:
 *   node scripts/gissue/tests/test-pr-lookup.mjs          # 순수 단위(오프라인) 테스트만
 *   node scripts/gissue/tests/test-pr-lookup.mjs --live   # + gh 라이브 조회 테스트(네트워크 필요)
 */
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { prMatchesIsn, prDeclaresIssue, findIssuePrsInRepo } from '../lib/pr-lookup.mjs';
import { discoverAuditRepos, resolveProjectsDir } from '../lib/audit-repos.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));
const LOWYENV = resolve(__dirname, '../../..');   // tests/ → gissue/ → scripts/ → 레포 루트
// 워크트리에서 테스트를 돌려도 진짜 컨테이너를 찾도록(테스트 대상 로직 자신을 이용).
const PROJECTS = resolveProjectsDir(LOWYENV) || resolve(LOWYENV, '..');

let pass = 0, fail = 0;
function check(name, actual, expected) {
  if (actual === expected) { pass++; console.log(`  PASS  ${name}`); }
  else { fail++; console.log(`  FAIL  ${name} — expected ${expected}, got ${actual}`); }
}

console.log('\n=== 단위: prMatchesIsn 재필터 규칙 ===');
// (A) 매치해야 하는 것
check('브랜치 fix/giip-2438-2440-junction-exception 이 2438 에 매치',
  prMatchesIsn({ headRefName: 'fix/giip-2438-2440-junction-exception' }, 2438), true);
check('같은 브랜치가 2440 에도 매치(1 PR 2 이슈)',
  prMatchesIsn({ headRefName: 'fix/giip-2438-2440-junction-exception' }, 2440), true);
check('규약 브랜치 bot/task-giip-1234 매치',
  prMatchesIsn({ headRefName: 'bot/task-giip-1234' }, 1234), true);
check('제목에 "giip #2445" 있으면 매치',
  prMatchesIsn({ headRefName: 'feat/dash-phase2', title: 'feat(sp): 통합 SP (giip #2445)' }, 2445), true);
check('본문에만 "#2077" 있어도 매치(PS Test-IssueHasPr 와 동일)',
  prMatchesIsn({ headRefName: 'fix/body-match', title: '무관한 제목', body: '관련 giip #2077 참조' }, 2077), true);

// (B) 매치하면 안 되는 것 — 이쪽이 깨지면 게이트가 무력화된다
check('24380 은 2438 에 매치되면 안 됨(뒤 숫자 경계)',
  prMatchesIsn({ headRefName: 'fix/giip-24380-other' }, 2438), false);
check('12438 은 2438 에 매치되면 안 됨(앞 숫자 경계)',
  prMatchesIsn({ headRefName: 'fix/giip-12438-other' }, 2438), false);
check('무관한 PR(제목 giip #2449)은 2438 에 매치 안 됨',
  prMatchesIsn({ headRefName: 'fix/giip-2449-remnant-cleanup', title: 'fix(worktree): ... (giip #2449)' }, 2438), false);
check('본문의 bare 숫자 2077 은 매치 안 됨("#" 표기만 인정)',
  prMatchesIsn({ headRefName: 'x', title: 'y', body: '작업시간 2077 분 소요' }, 2077), false);
check('본문 "#20770" 은 2077 에 매치 안 됨',
  prMatchesIsn({ headRefName: 'x', title: 'y', body: 'giip #20770' }, 2077), false);
check('빈 PR 객체는 매치 안 됨', prMatchesIsn({}, 2438), false);

console.log('\n=== 단위: body 폴백 좁히기(giip #2464 후속 오탐) ===');
// 실제 오탐: PR #750(브랜치 fix/giip-2464-…)이 본문에 증거로 인용한 #2456/#2457 까지 매치했다.
const pr750 = {
  headRefName: 'fix/giip-2464-blocked-triage',
  title: 'fix(gissue): audit-review-prs 탐지 갭 (giip #2464)',
  body: '없는 PR 은 못 찾는다: #2457 무매치, #2456 무매치',
};
check('담당이슈를 브랜치로 선언한 PR 은 declares=true', prDeclaresIssue(pr750), true);
check('그 PR 본문의 인용 #2456 은 매치 안 됨(참조일 뿐)', prMatchesIsn(pr750, 2456), false);
check('그 PR 본문의 인용 #2457 은 매치 안 됨(참조일 뿐)', prMatchesIsn(pr750, 2457), false);
check('그래도 자기 이슈 2464 에는 매치(브랜치)', prMatchesIsn(pr750, 2464), true);
// 실제 오탐 2: 본문에 "giip #2438" 을 인용한 PR #742/#746
check('브랜치 fix/giip-2449-… PR 본문의 #2438 인용은 매치 안 됨',
  prMatchesIsn({ headRefName: 'fix/giip-2449-remnant-cleanup', title: 'fix(worktree) (giip #2449)', body: 'giip #2438 이 고친 교착과 같은 계열' }, 2438), false);
// giip #2077 (2) 가 살리려던 케이스는 그대로 살아있어야 한다
const pr666 = { headRefName: 'fix/gissue-audit-pr-body-match', title: 'fix: body 매칭 보강', body: '관련 giip #2077' };
check('브랜치/제목에 이슈번호가 없는 PR 은 declares=false', prDeclaresIssue(pr666), false);
check('그 PR 은 본문 #2077 로 매치(giip #2077 (2) 케이스 유지)', prMatchesIsn(pr666, 2077), true);

console.log('\n=== 단위: discoverAuditRepos ===');
const repos = discoverAuditRepos(resolve(PROJECTS, 'giipprj'), LOWYENV);
const names = repos.map(r => r.name.toLowerCase());
console.log(`  발견: ${repos.map(r => r.name).join(', ')}`);
// 워크트리에서 돌리면 basename 이 워크트리 이름이라 이름이 아니라 경로로 확인한다.
check('이 체크아웃(레포 자신) 포함', repos.some(r => r.root === LOWYENV), true);
check('origin 중복 없음', repos.length === new Set(repos.map(r => r.root)).size, true);
// 가드 발동 조건: 컨테이너가 없으면 0개 → audit-review-prs.mjs 가 exit 2 로 중단한다.
check('존재하지 않는 workdir + 비-git lowyenv → 0개',
  discoverAuditRepos(resolve(PROJECTS, '__no_such_dir__'), resolve(PROJECTS, '__no_such_dir__')).length, 0);

// [giip #2645 이식] 아래 4건은 giip #2464 를 낸 **그 PC 의 실제 배치**(…/projects/giipprj 아래에
// giipv3/giipdb/giipfaw 가 nested 로 있는 구성)에 묶인 회귀 고정이다. 이 레포는 "clone 만 하면
// 다른 PC 에서도 돈다"가 요건이라, 그 배치가 없는 호스트에서는 있지도 않은 레포를 못 찾았다고
// FAIL 을 내는 대신 건너뛴다. 조건을 지운 게 아니라 **해당 배치에서만 강제**하는 것이다 —
// 그 배치를 가진 호스트(이 PC 포함)에서는 예전과 똑같이 4건 전부 검사된다.
if (names.some(n => n === 'giipprj')) {
  check('giipprj(컨테이너 자신=giipprj-hub) 포함', names.some(n => n === 'giipprj'), true);
  check('giipv3 포함', names.includes('giipv3'), true);
  check('giipdb 포함', names.includes('giipdb'), true);
  check('giipfaw 포함(수정 전 누락돼 있던 레포)', names.includes('giipfaw'), true);
} else {
  console.log(`  SKIP  giipprj 컨테이너 배치 고정 4건 — 이 호스트에는 ${resolve(PROJECTS, 'giipprj')} 가 없습니다.`);
}

if (process.argv.includes('--live')) {
  console.log('\n=== 라이브(gh): 양방향 실증 ===');
  const lw = repos.find(r => r.root === LOWYENV);
  // (A) PR #744(MERGED, 브랜치 fix/giip-2438-2440-junction-exception) 가 있는 isn
  const a = findIssuePrsInRepo(lw.root, 2438);
  console.log(`  isn 2438 → how=${a.how}, prs=${a.prs.map(p => '#' + p.number + '(' + p.state + ')').join(',')}`);
  check('라이브: isn 2438 은 PR 을 찾는다(수정 전엔 못 찾았음)', a.prs.length > 0, true);
  // (B) 존재할 수 없는 isn — 여전히 못 찾아야 한다
  const b = findIssuePrsInRepo(lw.root, 999999);
  console.log(`  isn 999999 → how=${b.how}, prs=${b.prs.length}건`);
  check('라이브: isn 999999 는 여전히 PR 없음', b.prs.length === 0, true);
  // (B-2) PR #750 본문에 인용만 된 isn — 실제로 PR 이 없는 이슈이므로 못 찾아야 한다.
  for (const isn of [2456, 2457]) {
    const c = findIssuePrsInRepo(lw.root, isn);
    console.log(`  isn ${isn} → how=${c.how}, prs=${c.prs.map(p => '#' + p.number).join(',') || '0건'}`);
    check(`라이브: isn ${isn} 은 PR 없음(본문 인용에 오탐되지 않음)`, c.prs.length === 0, true);
  }
}

console.log(`\n결과: PASS ${pass} / FAIL ${fail}\n`);
process.exit(fail ? 1 : 0);
