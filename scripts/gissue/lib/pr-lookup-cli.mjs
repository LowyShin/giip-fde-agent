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
 *   node pr-lookup-cli.mjs <isn> <repoRoot> [<repoRoot> ...]
 *
 * 출력(항상 stdout 에 JSON 1줄, 실패해도 JSON):
 *   {
 *     "ok": true,
 *     "isn": 2490,
 *     "primary": { "number": 816, "url": "...", "title": "...", "state": "MERGED",
 *                  "headRefName": "...", "repo": "<repoRoot>", "slug": "owner/repo", "how": "broad" },
 *     "all": [ …같은 모양 … ],   // 매칭된 모든 PR (레포 횡단, 대표 PR 포함)
 *     "errors": [ "repoRoot: 메시지" ]
 *   }
 *   매칭이 하나도 없으면 primary=null, all=[].
 *
 * 대표 PR(primary) 선택 규칙 — "실제로 배송된 산출물"을 우선한다:
 *   MERGED > OPEN > CLOSED, 같은 등급이면 PR 번호가 큰 쪽(더 최근).
 *   scope-gate 는 이 대표 PR 의 diff 로 판정하므로, 열려만 있고 머지 안 된 PR 보다
 *   이미 머지된 PR 을 보는 것이 실제 완료 여부 판정에 정확하다.
 */
import { findIssuePrsInRepo } from './pr-lookup.mjs';

/** PR url 에서 owner/repo 슬러그를 뽑는다(gissue-audit-lib.ps1 의 Get-RepoSlugFromUrl 과 동일 규칙). */
function slugFromUrl(url) {
  if (!url) return null;
  const m = /github\.com\/([^/]+\/[^/]+?)(?:\.git)?\/(?:pull|issues)\/\d+/.exec(url);
  return m ? m[1] : null;
}

const STATE_RANK = { MERGED: 0, OPEN: 1, CLOSED: 2 };

function rank(pr) {
  const s = String(pr.state || '').toUpperCase();
  return Object.prototype.hasOwnProperty.call(STATE_RANK, s) ? STATE_RANK[s] : 3;
}

function main() {
  const [, , isnArg, ...repoRoots] = process.argv;
  const isn = Number(isnArg);
  if (!Number.isInteger(isn) || isn <= 0 || repoRoots.length === 0) {
    process.stdout.write(JSON.stringify({
      ok: false, isn: isn || null, primary: null, all: [],
      errors: ['사용법: node pr-lookup-cli.mjs <isn> <repoRoot> [<repoRoot> ...]'],
    }));
    process.exit(2);
  }

  const all = [];
  const errors = [];
  for (const root of repoRoots) {
    let res;
    try {
      res = findIssuePrsInRepo(root, isn);
    } catch (e) {
      errors.push(`${root}: ${e && e.message ? e.message : String(e)}`);
      continue;
    }
    if (!res.ok && res.err) errors.push(`${root}: ${res.err}`);
    for (const pr of res.prs || []) {
      // 번호가 없는 행은 애초에 판정 대상이 될 수 없다(giip #2504 의 `PR #()` 재발 방지).
      if (!Number.isInteger(pr.number) || pr.number <= 0) continue;
      all.push({
        number: pr.number,
        url: pr.url || '',
        title: pr.title || '',
        state: String(pr.state || '').toUpperCase(),
        headRefName: pr.headRefName || '',
        repo: root,
        slug: slugFromUrl(pr.url) || '',
        how: res.how,
      });
    }
  }

  all.sort((a, b) => (rank(a) - rank(b)) || (b.number - a.number));
  process.stdout.write(JSON.stringify({
    ok: true, isn, primary: all.length ? all[0] : null, all, errors,
  }));
}

main();
