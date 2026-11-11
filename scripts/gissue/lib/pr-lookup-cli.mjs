#!/usr/bin/env node
/**
 * pr-lookup-cli.mjs — `pr-lookup.mjs` 판정 규칙을 PowerShell 쪽에서도 그대로 쓰기 위한 CLI 어댑터
 *
 * 배경 (giip #2504, 2026-09-14):
 *   `gissue-audit-lib.ps1` 의 `Get-IssuePrInfo`(scope-gate 가 평가할 PR 을 특정하는 함수)는
 *   `gh pr list --head bot/task-giip-<isn>` 정확매치 1회 + 자체 넓은검색을 **PowerShell 로 따로
 *   구현**하고 있었다. 반면 Node 쪽 감사기는 giip #2464 에서 `lib/pr-lookup.mjs` 로 판정 규칙을
 *   정본화하며 (a) 넓은검색 재필터 (b) body 폴백 + `prDeclaresIssue` 좁히기 를 갖췄다.
 *   두 탐지기가 갈라지면 같은 종류의 오탐이 한쪽에서만 재발한다 — 실제로 giip #2504 에서
 *   PowerShell 쪽만 PR 특정에 실패해 36건이 잘못 되돌려졌다.
 *
 *   그래서 규칙을 **복붙하지 않고** 이 CLI 로 노출해 PowerShell 이 그대로 호출하게 한다.
 *   판정 규칙의 정본은 여전히 `pr-lookup.mjs` 하나뿐이다(이 파일은 인자 파싱 + 결과 조립만 한다).
 *
 * 사용:
 *   node pr-lookup-cli.mjs <isn> <repoRoot> [<repoRoot> ...] [--org <org>] [--org-mode all|fallback]
 *                            [--org-limit N] [--org-max-commits N]
 *
 *   --org <org>          조직 전 레포까지 탐색할 GitHub 조직(반복 가능). PowerShell 쪽은
 *                        `Get-AttributionOrgs` 로 레포 origin 에서 유도해 넘긴다.
 *   --org-mode fallback  (기본) 로컬 스캔에서 후보가 하나도 없거나, 찾은 후보가 **이 isn 을 선언하지
 *                        않은** 경우에만 조직 전 탐색을 한다(비용 가드 + giip #4840 정정).
 *   --org-mode all       항상 조직 전 탐색을 한다.
 *
 * 출력(항상 stdout 에 JSON 1줄, 실패해도 JSON):
 *   {
 *     "ok": true,
 *     "isn": 2490,
 *     "primary": { "number": 816, "url": "...", "title": "...", "state": "MERGED",
 *                  "headRefName": "...", "repo": "<repoRoot>", "slug": "owner/repo", "how": "broad" },
 *     "all": [ …같은 모양 … ],   // 매칭된 모든 PR (레포 횡단, 대표 PR 포함)
 *     "sources": ["exact","broad"],  // 어느 탐색면에서 후보가 나왔는지
 *     "errors": [ "repoRoot: 메시지" ]
 *   }
 *   매칭이 하나도 없으면 primary=null, all=[].
 *
 * 대표 PR(primary) 선택 규칙은 `pr-lookup.mjs` 의 `selectPrimaryPr`(정본)를 그대로 쓴다.
 */
import { pathToFileURL } from 'node:url';
import {
  findIssuePrsInRepo, findIssuePrsInOrg, findIssuePrsByBranchInRepo, selectPrimaryPr, prDeclaresIsn,
} from './pr-lookup.mjs';

/** PR url 에서 owner/repo 슬러그를 뽑는다(gissue-audit-lib.ps1 의 Get-RepoSlugFromUrl 과 동일 규칙). */
function slugFromUrl(url) {
  if (!url) return null;
  const m = /github\.com\/([^/]+\/[^/]+?)(?:\.git)?\/(?:pull|issues)\/\d+/.exec(url);
  return m ? m[1] : null;
}

/**
 * 인자 파싱 — CLI 와 테스트(import 후 직접 호출)가 공유한다.
 * @returns {{isn: number|null, repoRoots: string[], orgs: string[], orgMode: string, orgLimit: number, orgMaxCommits: number}}
 */
export function parseLookupArgs(argv) {
  const orgs = [];
  const repoRoots = [];
  let orgMode = 'fallback';
  let orgLimit = 50;
  let orgMaxCommits = 5;
  let isnArg = null;

  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--org') { if (argv[i + 1]) { orgs.push(argv[++i]); } continue; }
    if (a === '--org-mode') { if (argv[i + 1]) { orgMode = String(argv[++i]).toLowerCase(); } continue; }
    if (a === '--org-limit') { const n = Number(argv[++i]); if (Number.isFinite(n) && n > 0) orgLimit = n; continue; }
    if (a === '--org-max-commits') { const n = Number(argv[++i]); if (Number.isFinite(n) && n > 0) orgMaxCommits = n; continue; }
    if (isnArg === null) { isnArg = a; continue; }
    repoRoots.push(a);
  }
  return { isn: Number(isnArg), repoRoots, orgs, orgMode, orgLimit, orgMaxCommits };
}

/**
 * 판정 수행(CLI 본체). gh 호출은 pr-lookup.mjs 를 통해간다 — 규칙 정본은 그 파일 하나뿐이다.
 * @returns {{ok, isn, primary, all, sources, errors}}
 */
export function runLookup(isn, repoRoots, orgs, opts = {}) {
  const orgMode = opts.orgMode || 'fallback';
  const orgLimit = opts.orgLimit || 50;
  const orgMaxCommits = opts.orgMaxCommits || 5;
  const all = [];
  const errors = [];
  const sources = [];
  const seen = new Set();

  const push = (pr, how) => {
    // 번호가 없는 행은 애초에 판정 대상이 될 수 없다(giip #2504 의 `PR #()` 재발 방지).
    if (!Number.isInteger(pr.number) || pr.number <= 0) return;
    const slug = pr.slug || slugFromUrl(pr.url) || '';
    const key = `${slug}#${pr.number}`;
    if (seen.has(key)) return;
    seen.add(key);
    all.push({
      number: pr.number,
      url: pr.url || '',
      title: pr.title || '',
      state: String(pr.state || '').toUpperCase(),
      headRefName: pr.headRefName || '',
      repo: pr.repo || '',
      slug,
      how,
    });
    if (!sources.includes(how)) sources.push(how);
  };

  // ── 1) 레포 스캔 (기존 동작) ──
  for (const root of repoRoots) {
    let res;
    try {
      res = findIssuePrsInRepo(root, isn);
    } catch (e) {
      errors.push(`${root}: ${e && e.message ? e.message : String(e)}`);
      continue;
    }
    if (!res.ok && res.err) errors.push(`${root}: ${res.err}`);
    for (const pr of res.prs || []) push(pr, res.how === 'none' ? 'none' : res.how);
  }

  // ── 2) 레포 브랜치명 탐색 (로컬/등록 레포 한정) ──
  // GitHub 검색은 브랜치명을 색인하지 않는다 → `docs/giip-4219-…` 같은 브랜치 PR 을
  // 제목/본문에 isn 이 없으면 못 잡는다(실측 2026-11-11). 후보가 하나도 없을 때만 돌린다.
  if (all.length === 0) {
    for (const root of repoRoots) {
      let res;
      try {
        res = findIssuePrsByBranchInRepo(root, isn, { maxBranches: 10 });
      } catch (e) {
        errors.push(`${root}: ${e && e.message ? e.message : String(e)}`);
        continue;
      }
      if (!res.ok) { for (const er of res.errors || []) errors.push(`${root}: ${er}`); continue; }
      for (const pr of res.prs || []) push(pr, 'branch');
    }
  }

  // ── 3) 조직 전 레포 탐색 (제목/본문 + 커밋 메시지 + 규약 브랜치) ──
  // 기본(fallback) 조건: "로컬에서 아무것도 못 찾았거나, 찾은 후보가 **이 isn 을 선언하지 않은** 경우".
  //   - 아무것도 못 찾음 → "PR 없음" 되돌림을 막으려면 조직 전을 봐야 한다.
  //   - 찾았지만 **선언하지 않은** 후보(본문 인용만) → 그 PR 이 판정 대상이 되면 무관한 diff 로 MISMATCH 가
  //     나던 giip #4840 패턴이므로, 진짜 담당 PR 이 다른 레포에 있을 수 있다 → 조직 전을 본다.
  //   - 찾은 후보가 **이 isn 을 선언했다**면 그 PR 이 판정 대상이다 → 조직 전 탐색 불필요(비용 0).
  const localDeclares = all.some((pr) => prDeclaresIsn(pr, isn));
  if (orgs.length > 0 && (orgMode === 'all' || all.length === 0 || !localDeclares)) {
    for (const org of orgs) {
      let res;
      try {
        res = findIssuePrsInOrg(org, isn, { limit: orgLimit, maxCommits: orgMaxCommits });
      } catch (e) {
        errors.push(`org:${org}: ${e && e.message ? e.message : String(e)}`);
        continue;
      }
      for (const er of res.errors || []) errors.push(`org:${org}: ${er}`);
      for (const pr of res.prs || []) push(pr, pr.how || 'org');
    }
  }

  return {
    ok: true,
    isn,
    primary: selectPrimaryPr(all, isn),
    all,
    sources,
    errors,
  };
}

function main() {
  const parsed = parseLookupArgs(process.argv.slice(2));
  const isn = parsed.isn;
  if (!Number.isInteger(isn) || isn <= 0) {
    process.stdout.write(JSON.stringify({
      ok: false, isn: isn || null, primary: null, all: [], sources: [],
      errors: ['사용법: node pr-lookup-cli.mjs <isn> <repoRoot> [<repoRoot> ...] [--org <org>]'],
    }));
    process.exit(2);
  }
  const res = runLookup(isn, parsed.repoRoots, parsed.orgs, {
    orgMode: parsed.orgMode, orgLimit: parsed.orgLimit, orgMaxCommits: parsed.orgMaxCommits,
  });
  process.stdout.write(JSON.stringify(res));
}

// 이 모듈을 import 만 하면 CLI 가 실행되면 안 된다(테스트가 직접 호출한다).
const invokedDirectly = process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href;
if (invokedDirectly) main();
