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
 *   판정 규칙의 정본은 여전히 `pr-lookup.mjs` 하나뿐이다(이 파일은 인자 파싱 + 대표 PR 선택만 한다).
 *
 * 사용:
 *   node pr-lookup-cli.mjs <isn> <repoRoot> [<repoRoot> ...] [--org <org>] [--org-mode all|fallback]
 *                            [--org-limit N] [--org-max-commits N]
 *
 *   --org <org>          조직 전 레포까지 탐색할 GitHub 조직(반복 가능). PowerShell 쪽은
 *                        `Get-AttributionOrgs` 로 레포 origin 에서 유도해 넘긴다.
 *   --org-mode fallback  (기본) 로컬 스캔에서 후보가 하나도 없을 때만 조직 전 탐색을 한다.
 *                        비용을 issue당 1회로 묶기 위한 기본값 — "PR 없음" 으로 되돌릴 수 있는
 *                       (=탐색이 필요한) 이슈에서만 조직 전을 훑는다.
 *   --org-mode all       항상 조직 전 탐색을 한다(후보 집합을 최대로 Wanted 경우).
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
 * 대표 PR(primary) 선택 규칙 — "실제로 배송된 산출물"을 우선한다:
 *   1) **이 isn 을 브랜치/제목으로 선언한 PR** (강한 귀속) — giip #4840 정정.
 *      본문에만 isn 을 인용한 PR 은 "참조"이지 담당 산출물이 아니므로 뒤로 밀린다.
 *   2) MERGED > OPEN > CLOSED, 같은 등급이면 PR 번호가 큰 쪽(더 최근).
 *      scope-gate 는 이 대표 PR 의 diff 로 판정하므로, 열려만 있고 머지 안 된 PR 보다
 *      이미 머지된 PR 을 보는 것이 실제 완료 여부 판정에 정확하다.
 */
import { findIssuePrsInRepo, findIssuePrsInOrg, findIssuePrsByBranchInRepo, prDeclaresIsn } from './pr-lookup.mjs';

/** PR url 에서 owner/repo 슬러그를 뽑는다(gissue-audit-lib.ps1 의 Get-RepoSlugFromUrl 과 동일 규칙). */
function slugFromUrl(url) {
  if (!url) return null;
  const m = /github\.com\/([^/]+\/[^/]+?)(?:\.git)?\/(?:pull|issues)\/\d+/.exec(url);
  return m ? m[1] : null;
}

const STATE_RANK = { MERGED: 0, OPEN: 1, CLOSED: 2 };

/**
 * 대표 PR 정렬 키. isn 을 선언한 PR(강한 귀속)이 항상 먼저다 — 없으면 상태/번호 순.
 * @param {object} pr  @param {number} isn
 */
function rank(pr, isn) {
  const declares = prDeclaresIsn(pr, isn) ? 0 : 1;
  const s = String(pr.state || '').toUpperCase();
  const state = Object.prototype.hasOwnProperty.call(STATE_RANK, s) ? STATE_RANK[s] : 3;
  return [declares, state, -Number(pr.number || 0)];
}

function compare(a, b, isn) {
  const ra = rank(a, isn);
  const rb = rank(b, isn);
  for (let i = 0; i < ra.length; i++) {
    if (ra[i] !== rb[i]) return ra[i] - rb[i];
  }
  return 0;
}

function main() {
  const argv = process.argv.slice(2);
  const orgs = [];
  let orgMode = 'fallback';
  let orgLimit = 50;
  let orgMaxCommits = 5;
  const repoRoots = [];
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

  const isn = Number(isnArg);
  if (!Number.isInteger(isn) || isn <= 0) {
    process.stdout.write(JSON.stringify({
      ok: false, isn: isn || null, primary: null, all: [], sources: [],
      errors: ['사용법: node pr-lookup-cli.mjs <isn> <repoRoot> [<repoRoot> ...] [--org <org>]'],
    }));
    process.exit(2);
  }

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
  // 기본(fallback) 조건: "로컬에서 아무것도 못 찾었거나, 찾은 후보가 **이 isn 을 선언하지 않은** 경우"에만 돈다.
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

  all.sort((a, b) => compare(a, b, isn));
  process.stdout.write(JSON.stringify({
    ok: true, isn, primary: all.length ? all[0] : null, all, sources, errors,
  }));
}

main();
