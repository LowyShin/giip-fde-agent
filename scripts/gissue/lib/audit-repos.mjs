/**
 * audit-repos.mjs — PR 감사 대상 저장소 목록 결정 (Node 쪽 정본)
 *
 * 배경 (giip #2464, 2026-09-14):
 *   `audit-review-prs.mjs` 는 감사 대상 레포를 `giipv3 / giipdb / Lowyworkenv` **3개로 하드코딩**하고
 *   있었다. 그런데 csn 47 의 실제 nested 레포는 4개다 —
 *     giipprj(=giipprj-hub) / giipfaw / giipv3 / giipdb  (+ 형제 레포 lowyworkenv)
 *   그래서 `giipprj-hub`(.agent/k_layer 지식 등록 등) 나 `giipfaw`(API) 에만 PR 이 있는 이슈는
 *   어떤 경로로도 탐지되지 않고 `REVIEW_NO_PR` 로 적재됐다.
 *
 *   PowerShell 쪽 동일 판정(`gissue-audit-lib.ps1` 의 `Get-NestedRepoPaths`)은 이미
 *   "workdir 자신 + 바로 아래 1단계 nested 레포 + lowyworkenv, origin URL 기준 중복제거"로
 *   동적 탐색하고 있었다. 두 탐지기의 기준이 갈라져 있던 것을 여기서 맞춘다 —
 *   새 기준을 창작하지 않고 PowerShell 함수의 규칙을 그대로 옮긴다.
 */
import { spawnSync } from 'node:child_process';
import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { basename, dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

/**
 * 체크아웃이 없는 추가 감사 대상 레포 슬러그 (giip #2504).
 *
 * 정본은 `scripts/gissue/audit-extra-repos.json` 파일 하나이고, PowerShell 쪽
 * `Get-ExtraAuditRepoSlugs`(gissue-audit-lib.ps1)도 **같은 파일**을 읽는다 — 두 탐지기의
 * 대상 레포 목록이 갈라지지 않게 하기 위함(giip #2464 에서 얻은 교훈: 한쪽만 넓히면
 * 다른 쪽에서 같은 오탐이 계속 난다).
 * 파일이 없거나 깨졌으면 조용히 빈 목록 — 감사를 막지 않는다.
 */
export function loadExtraRepoSlugs() {
  try {
    const here = dirname(fileURLToPath(import.meta.url));
    const cfg = resolve(here, '..', 'audit-extra-repos.json');
    if (!existsSync(cfg)) return [];
    const json = JSON.parse(readFileSync(cfg, 'utf8'));
    return (json.slugs || []).map((s) => String(s).trim()).filter(Boolean);
  } catch { return []; }
}

/**
 * 이 lowyworkenv 체크아웃이 **워크트리**여도 "진짜 프로젝트 컨테이너 디렉터리"를 찾아낸다.
 *
 * 왜 필요한가(giip #2464 실측): 이 스크립트는 자기 파일 위치에서 `../..` 로 lowyworkenv 루트를,
 * 다시 그 부모로 `…/projects` 를 유도한다. 그런데 워크트리(D:/temp/worktrees/lowyworkenv/<name>)
 * 에서 실행하면 부모가 `D:/temp/worktrees/lowyworkenv` 라 giipprj 가 없고, 결과적으로 감사 대상
 * 레포가 **0개**가 된다. 0개면 모든 REVIEW 이슈가 "PR 없음"으로 적재돼 대시보드가 통째로 오탐이 된다.
 * `git rev-parse --git-common-dir` 는 워크트리에서도 **메인 체크아웃의 .git** 을 가리키므로,
 * 그걸로 원래 체크아웃 위치를 되찾아 컨테이너를 유도한다.
 *
 * @returns {string|null} 프로젝트 컨테이너(…/projects) 절대경로. 못 찾으면 null.
 */
export function resolveProjectsDir(lowyenv) {
  const r = spawnSync('git', ['-C', lowyenv, 'rev-parse', '--path-format=absolute', '--git-common-dir'],
    { encoding: 'utf8', windowsHide: true });
  if (r.status !== 0) return null;
  const commonDir = (r.stdout || '').trim();       // …/projects/lowyworkenv/.git
  if (!commonDir) return null;
  const mainCheckout = resolve(commonDir, '..');   // …/projects/lowyworkenv
  return resolve(mainCheckout, '..');              // …/projects
}

function gitOriginUrl(root) {
  const r = spawnSync('git', ['-C', root, 'remote', 'get-url', 'origin'],
    { encoding: 'utf8', windowsHide: true });
  if (r.status !== 0) return null;
  const url = (r.stdout || '').trim();
  return url ? url.toLowerCase().replace(/\.git$/, '') : null;
}

function isGitRepo(root) {
  // .git 은 디렉터리(일반 체크아웃)일 수도 파일(worktree 링크)일 수도 있으므로 existsSync 로 본다.
  return existsSync(resolve(root, '.git'));
}

/**
 * 감사 대상 레포 목록.
 * @param {string} workdir   프로젝트 컨테이너(csn 47 → …/projects/giipprj)
 * @param {string} lowyenv   lowyworkenv 루트(형제 디렉터리라 workdir 하위 스캔으로는 안 잡힌다)
 * @returns {Array<{name: string, root: string}>} origin URL 기준 중복 제거됨
 */
export function discoverAuditRepos(workdir, lowyenv) {
  const candidates = [];
  if (workdir && isGitRepo(workdir)) candidates.push(workdir);
  if (workdir && existsSync(workdir)) {
    let entries = [];
    try { entries = readdirSync(workdir, { withFileTypes: true }); } catch { entries = []; }
    for (const e of entries) {
      if (!e.isDirectory()) continue;
      const p = resolve(workdir, e.name);
      if (isGitRepo(p)) candidates.push(p);
    }
  }
  if (lowyenv && isGitRepo(lowyenv)) candidates.push(lowyenv);

  const seen = new Set();
  const repos = [];
  for (const root of candidates) {
    const origin = gitOriginUrl(root);
    if (!origin) continue;          // origin 없는 디렉터리는 PR 조회 불가 → 제외
    if (seen.has(origin)) continue; // 워크트리/임시 체크아웃이 같은 origin 을 공유하면 1개만
    seen.add(origin);
    repos.push({ name: basename(root), root });
  }

  // [giip #2504] 체크아웃이 없는 레포는 `slug:OWNER/REPO` 로 덧붙인다.
  // findIssuePrsInRepo/runGh(pr-lookup.mjs)가 이 접두어를 보고 `--repo <slug>` 로 조회한다.
  //
  // ⚠️ 로컬 레포를 하나도 못 찾았으면 추가 슬러그도 붙이지 않고 0개를 유지한다.
  //    "0개면 audit-review-prs.mjs 가 exit 2 로 중단한다"는 기존 안전장치를 지키기 위함이다 —
  //    컨테이너 경로가 틀렸을 때 슬러그 2개만으로 감사를 계속하면 나머지 레포의 PR 이 전부
  //    "PR 없음"으로 적재돼 대시보드가 통째로 오탐이 된다(giip #2464 가 막으려던 바로 그 사고).
  if (repos.length === 0) return repos;
  for (const slug of loadExtraRepoSlugs()) {
    const origin = `git@github.com:${slug}`.toLowerCase();
    const altOrigin = `https://github.com/${slug}`.toLowerCase();
    if (seen.has(origin) || seen.has(altOrigin)) continue;
    seen.add(origin);
    repos.push({ name: slug, root: `slug:${slug}` });
  }
  return repos;
}
