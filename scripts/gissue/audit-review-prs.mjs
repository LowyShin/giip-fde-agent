#!/usr/bin/env node
/**
 * audit-review-prs.mjs — "REVIEW인데 배포 0" 이슈 감사(백스톱)
 *
 * 배경: 슬랙봇이 nested repo(giipv3/giipdb) 변경을 PR 로 반영하지 못한 채 giip issue 를
 *   REVIEW 로 전이해, "상태는 REVIEW 인데 실제 배포된 산출물은 0"인 이슈가 누적됐다
 *   (근본원인: nested repo 가 남의 브랜치에 파킹→foreign branch skip→스트랜드).
 *   task-manager/handlers 의 예방·게이트 수정으로 신규 발생은 막지만, 이 스크립트는
 *   (1) 기존 백로그를 찾아내고 (2) 어떤 원인으로든 재발하는 거짓 REVIEW 를 상시 탐지하는
 *   봇 내부와 독립된 안전망이다. 기본은 읽기 전용.
 *
 * 판정: 각 REVIEW 이슈 isn 에 대해 대상 repo 들에서 그 isn 에 대응하는 PR(상태 무관)이 하나라도
 *   있으면 "반영됨(OK)". 어디에도 없으면 "PR 없음(거짓 REVIEW 의심)"으로 보고한다.
 *   ※ 순수 조사/문서성 이슈는 원래 PR 이 없을 수 있으므로 '의심'으로만 표기하고 사람 판단에 맡긴다.
 *
 * ── 탐지 기준 통일 (giip #2464, 2026-09-14) ────────────────────────────────────────────────
 *   이 감사 결과는 `run-audit-review-prs.ps1` 이 `tAuditReviewPrsResult` 에 적재하고, 대시보드
 *   ③층 "막힌 이슈"의 `REVIEW_NO_PR` 배지(SP `pApiGIIPDashboardBlockedIssuesbyAK`)가 그걸 그대로
 *   읽는다. 즉 **여기서 못 찾으면 대시보드에 "PR 없음"으로 뜬다.**
 *   2026-09-14 이전 구현은 두 군데가 좁아 대량 오탐을 냈다(실측: csn 47 REVIEW 29건 중 23건이
 *   "PR 없음"인데 대부분 실제로는 MERGED PR 이 있었다):
 *     (a) 브랜치 매칭 — `bot/task-giip-<isn>` 정확 매치 1회뿐. 실제 브랜치는
 *         `fix/giip-2438-2440-junction-exception` 같은 형태라 전부 탈락.
 *     (b) 레포 범위 — giipv3/giipdb/Lowyworkenv 3개 하드코딩. csn 47 의 실제 nested 레포인
 *         giipprj-hub / giipfaw 가 빠져 그쪽에만 PR 이 있는 이슈는 영영 못 찾음.
 *   같은 판정을 하는 PowerShell 쪽(`gissue-audit-lib.ps1`)은 giip #2077/#2083 에서 이미 둘 다
 *   갖췄는데 Node 쪽만 보강을 못 받은 상태였다. 이제 판정은 `lib/pr-lookup.mjs`, 레포 목록은
 *   `lib/audit-repos.mjs` 로 분리해 PowerShell 쪽 규칙을 그대로 옮겼다(새 기준 창작 없음).
 *   ⚠️ 넓은검색에는 반드시 정규식 재필터가 붙는다 — 빼면 "PR 없는 이슈"까지 PR 있음으로 뒤집혀
 *      게이트가 무력화된다. 양방향 회귀 테스트: `scripts/gissue/tests/test-pr-lookup.mjs`.
 *
 * 사용:
 *   node scripts/gissue/audit-review-prs.mjs                 # 등록된 모든 csn 감사(읽기전용)
 *   node scripts/gissue/audit-review-prs.mjs --csn 47        # 특정 csn 만
 *   node scripts/gissue/audit-review-prs.mjs --comment       # 의심 이슈에 감사 코멘트 등록
 *   node scripts/gissue/audit-review-prs.mjs --json          # 기계가독 JSON 출력
 *
 * SK 출처: slack-bot/.secrets/giip-accounts.json (git 비추적).
 */
import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';
import { discoverAuditRepos, resolveProjectsDir } from './lib/audit-repos.mjs';
import { findIssuePrsInRepo } from './lib/pr-lookup.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));
const LOWYENV = resolve(__dirname, '../..');           // …/Lowyworkenv
const PROJECTS = dirname(LOWYENV);                       // …/projects
const require = createRequire(import.meta.url);
const giip = require(resolve(LOWYENV, 'slack-bot/giip-api.js'));

const argv = process.argv.slice(2);
const OPT = {
  csn: (() => { const i = argv.indexOf('--csn'); return i >= 0 ? Number(argv[i + 1]) : null; })(),
  workdir: (() => { const i = argv.indexOf('--workdir'); return i >= 0 ? argv[i + 1] : null; })(),
  comment: argv.includes('--comment'),
  json: argv.includes('--json'),
};

// [giip #2645 이식] 감사 대상 workdir 결정.
// 원본(lowyworkenv)은 `resolve(PROJECTS_ROOT, 'giipprj')` 로 **컨테이너 이름을 하드코딩**했다.
// 이 레포는 다른 PC 에서 clone 만 하면 동작해야 하므로 그 이름을 박아 둘 수 없다. 우선순위:
//   1) --workdir <경로>                          (명시 지정 — 스케줄러/수동 호출 공통 탈출구)
//   2) csn-projects.json 의 csn[<--csn>].workdir  (이 레포의 CSN 설정 정본)
//   3) 예전 동작(<projects>/giipprj)              (기존 배포 호환. 없으면 아래 "0건" 가드가 잡는다)
// 워크트리에서 실행되면 PROJECTS(부모 디렉터리)가 엉뚱한 곳을 가리키므로 git 으로 되찾는다.
const PROJECTS_ROOT = resolveProjectsDir(LOWYENV) || PROJECTS;

function resolveWorkdir() {
  if (OPT.workdir) return resolve(OPT.workdir);
  if (OPT.csn != null) {
    try {
      const raw = readFileSync(resolve(__dirname, 'csn-projects.json'), 'utf8').replace(/^﻿/, '');
      const wd = ((JSON.parse(raw).csn || {})[String(OPT.csn)] || {}).workdir;
      if (wd) return resolve(wd);
    } catch { /* 설정이 없거나 깨졌으면 조용히 다음 후보로 — 감사를 여기서 막지 않는다. */ }
  }
  return resolve(PROJECTS_ROOT, 'giipprj');
}

// 감사 대상 repo — workdir 컨테이너(자신 + 1단계 nested) + 이 레포 자신을 동적으로 찾는다.
// origin URL 기준 중복 제거까지 lib/audit-repos.mjs 가 담당한다(giip #2464).
const WORKDIR = resolveWorkdir();
const REPOS = discoverAuditRepos(WORKDIR, LOWYENV);

function loadAccounts() {
  // [giip #2645 이식] 자격증명 파일은 git 비추적이라 워크트리 체크아웃에는 없다.
  // lib/resolve-actor.js 와 동일하게 GIIP_ACCOUNTS_FILE 환경변수를 먼저 본다.
  const p = process.env.GIIP_ACCOUNTS_FILE || resolve(LOWYENV, 'slack-bot/.secrets/giip-accounts.json');
  const j = JSON.parse(readFileSync(p, 'utf8'));
  const apiBase = j.GIIP_API_BASE || 'https://giipfaw.azurewebsites.net/api';
  const seen = new Set();
  const accounts = [];
  const add = (a) => {
    if (!a || !a.sk || a.csn == null) return;
    if (seen.has(a.csn)) return;
    seen.add(a.csn);
    accounts.push({ login_id: a.login_id, sk: a.sk, csn: a.csn, apiBase });
  };
  add(j.default);
  for (const ch of Object.values(j.channels || {})) add(ch);
  return accounts;
}

function repoExists(root) {
  const r = spawnSync('git', ['-C', root, 'rev-parse', '--git-dir'], { encoding: 'utf8', windowsHide: true });
  return r.status === 0;
}

async function main() {
  const accounts = loadAccounts().filter(a => OPT.csn == null || a.csn === OPT.csn);
  if (!accounts.length) { console.error('감사할 계정(csn)이 없습니다. --csn 또는 giip-accounts.json 확인.'); process.exit(2); }

  const activeRepos = REPOS.filter(r => repoExists(r.root));
  // 감사 대상 레포가 0개면 모든 REVIEW 이슈가 "PR 없음"으로 적재돼 대시보드가 통째로 오탐이 된다.
  // 조용히 진행하지 말고 실패(exit 2)로 끊는다 — 래퍼가 이걸 실제 실패로 취급한다(giip #2464).
  if (!activeRepos.length) {
    console.error(`감사 대상 저장소를 하나도 찾지 못했습니다(workdir=${WORKDIR}, lowyenv=${LOWYENV}). ` +
      `이 상태로 진행하면 모든 REVIEW 이슈가 거짓으로 "PR 없음" 처리되므로 중단합니다.`);
    process.exit(2);
  }
  const report = { checkedAt: new Date().toISOString(), csns: [], suspects: [], ok: [] };

  for (const acct of accounts) {
    let issues = [];
    try { issues = await giip.issueList(acct, { status: 'REVIEW', csn: acct.csn }); }
    catch (e) { console.error(`[csn ${acct.csn}] issueList 실패: ${e.message}`); continue; }
    report.csns.push({ csn: acct.csn, reviewCount: issues.length });

    for (const it of issues) {
      const isn = it.isn ?? it.iSn ?? it.ISN;
      if (isn == null) continue;
      // `branch` 는 "기대했던 규약 브랜치" 표기용으로만 남긴다(DB/코멘트 문구 하위호환).
      // 실제 판정은 규약 브랜치 + 넓은검색 재필터 양쪽을 본다(giip #2464).
      const branch = `bot/task-giip-${isn}`;
      const hits = [];
      for (const repo of activeRepos) {
        const { ok, prs, how } = findIssuePrsInRepo(repo.root, isn);
        if (ok && prs.length) hits.push(...prs.map(p => ({ repo: repo.name, matchedBy: how, ...p })));
      }
      const rec = { csn: acct.csn, isn, title: it.title || '', branch, prs: hits };
      if (hits.length) report.ok.push(rec);
      else report.suspects.push(rec);
    }
  }

  if (OPT.json) { console.log(JSON.stringify(report, null, 2)); }
  else {
    console.log(`\n=== REVIEW-PR 감사 (${report.checkedAt}) ===`);
    console.log(`검사 repo: ${activeRepos.map(r => r.name).join(', ')}`);
    for (const c of report.csns) console.log(`  csn ${c.csn}: REVIEW ${c.reviewCount}건`);
    console.log(`\n✅ PR 반영 확인: ${report.ok.length}건`);
    for (const r of report.ok) console.log(`   #${r.isn} [csn ${r.csn}] ${r.prs.map(p => `${p.repo}#${p.number}(${p.state},${p.matchedBy})`).join(', ')} — ${r.title.slice(0, 40)}`);
    console.log(`\n🚨 PR 없음(거짓 REVIEW 의심): ${report.suspects.length}건`);
    for (const r of report.suspects) console.log(`   #${r.isn} [csn ${r.csn}] 규약브랜치(${r.branch})·넓은검색 모두 무매치 — ${r.title.slice(0, 50)}`);
    console.log('');
  }

  // --comment: 의심 이슈에 감사 코멘트 등록(사람 판단 유도).
  if (OPT.comment && report.suspects.length) {
    for (const r of report.suspects) {
      const acct = accounts.find(a => a.csn === r.csn);
      if (!acct) continue;
      try {
        await giip.issueComment(acct, r.isn,
          `🔎 [자동감사] 이 이슈는 REVIEW 이지만 대상 저장소(${activeRepos.map(x => x.name).join('/')})에서 ` +
          `이 이슈(#${r.isn})에 대응하는 PR 을 찾지 못했습니다 — 규약 브랜치 \`${r.branch}\` 도, ` +
          `넓은검색(브랜치/제목/본문에 ${r.isn} 참조)도 무매치입니다. 코드가 실제로 PR·배포됐는지 확인이 ` +
          `필요합니다. 순수 조사/문서 이슈라면 무시하세요.`);
        console.log(`  코멘트 등록: #${r.isn}`);
      } catch (e) { console.error(`  코멘트 실패 #${r.isn}: ${e.message}`); }
    }
  }

  // 종료코드: 의심 건이 있으면 1(스케줄러/CI 가 감지 가능). 읽기전용 감사에도 신호로 사용.
  process.exit(report.suspects.length ? 1 : 0);
}

main().catch(e => { console.error('audit 실패:', e); process.exit(2); });
