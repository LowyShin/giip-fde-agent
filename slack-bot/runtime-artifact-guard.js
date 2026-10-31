'use strict';
// 런타임 상태 경로(.agent/runtime/**) 가드 (giip #4300).
//
// 배경: 작업 브랜치 커밋이 `git add -A` 라서 봇/세션이 쓰는 런타임 기록(checkpoints, evidence,
//   receipts, progress, cost-usage 등)까지 스테이징돼, 실제 산출물이 하나도 없는 "런타임 전용" PR 이
//   열리고 기본 브랜치에 머지된 사고가 있었다. 이 모듈은 git 을 직접 부르지 않는 순수 함수와,
//   주입받은 `git(args)` 러너로 동작하는 얇은 헬퍼만 제공한다(LLM·네트워크 없이 단위 테스트 가능).
//
//   (a) 스테이징 제외 — stageDeliverables(): `.agent/runtime/**` 를 add 대상에서 뺀다.
//   (b) PR 억제   — branchHasDeliverables(): base 대비 변경이 런타임 경로뿐이면 PR 을 열지 않는다.

const RUNTIME_PREFIX = '.agent/runtime/';
const RUNTIME_EXCLUDE_PATHSPEC = ':(exclude).agent/runtime';

function norm(p) { return String(p || '').replace(/\\/g, '/').replace(/^\.\//, '').trim(); }

function isRuntimePath(p) {
  const n = norm(p);
  return n === '.agent/runtime' || n.startsWith(RUNTIME_PREFIX);
}

// 비어 있지 않고 전부 런타임 경로일 때만 true(= 산출물 없음). 빈 목록은 "변경 자체가 없음"이라 별개다.
function isRuntimeOnly(paths) {
  const list = (paths || []).map(norm).filter(Boolean);
  return list.length > 0 && list.every(isRuntimePath);
}

function deliverablesOf(paths) {
  return (paths || []).map(norm).filter(p => p && !isRuntimePath(p));
}

// `git add -A` 대체: 런타임 경로를 제외하고 스테이징한다. 이미 스테이징돼 있던 런타임 경로도 index 에서만 뺀다.
function stageDeliverables(git) {
  const add = git(['add', '-A', '--', '.', RUNTIME_EXCLUDE_PATHSPEC]);
  const staged = git(['diff', '--cached', '--name-only']);
  const stagedRuntime = (staged.stdout || '').split(/\r?\n/).map(norm).filter(p => p && isRuntimePath(p));
  if (stagedRuntime.length) git(['reset', '-q', '--', ...stagedRuntime]);
  return add;
}

// base 대비 브랜치 변경 파일 중 런타임이 아닌 산출물이 있는가. 판정 불가(git 실패)는 true(기존 동작 유지 = fail-open).
function branchHasDeliverables(git, base, branch) {
  for (const baseRef of [`origin/${base}`, base]) {
    const r = git(['diff', '--name-only', `${baseRef}...${branch}`]);
    if (r.status === 0) {
      const files = (r.stdout || '').split(/\r?\n/).map(norm).filter(Boolean);
      return deliverablesOf(files).length > 0;
    }
  }
  return true;
}

module.exports = { isRuntimePath, isRuntimeOnly, deliverablesOf, stageDeliverables, branchHasDeliverables, RUNTIME_EXCLUDE_PATHSPEC };
