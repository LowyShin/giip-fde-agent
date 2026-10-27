'use strict';
// 작업 브랜치 생성(`git checkout -B`) 시 "untracked 파일 ↔ startPoint 의 tracked 파일" 충돌을
// 다루는 순수 함수 모음. git/파일 I/O 는 task-manager.js 의 prepareTaskBranch 가 담당한다.
// (LLM·네트워크·git 없이 단위 테스트 가능하도록 분리)

// git 이 "untracked working tree files would be overwritten by checkout/merge:" 다음에
// 탭/공백으로 들여쓴 경로를 나열하고 "Please move or remove them" 로 끝낸다.
function parseConflictFiles(stderr) {
  const out = [];
  let inList = false;
  for (const raw of String(stderr || '').split(/\r?\n/)) {
    if (/would be overwritten by (checkout|merge)/i.test(raw)) { inList = true; continue; }
    if (!inList) continue;
    if (/^\s+\S/.test(raw)) out.push(raw.trim());
    else inList = false;
  }
  return [...new Set(out)];
}

// 봇이 계속 append 하는 로그성 파일 → checkout 후 (tracked 줄 + 로컬 고유 줄)로 병합 대상.
function isMergeableLogPath(relPath) {
  const p = String(relPath || '').replace(/\\/g, '/');
  return /^\.agent\/runtime\/.+\.(jsonl|log)$/i.test(p);
}

// tracked 본문 줄 + 로컬에만 있던 줄(줄 단위 중복 제거, 순서 보존). 빈 줄은 버린다.
function mergeLogLines(trackedText, localText) {
  const split = (t) => String(t || '').split(/\r?\n/).filter(l => l.length > 0);
  const seen = new Set();
  const merged = [];
  for (const line of [...split(trackedText), ...split(localText)]) {
    if (seen.has(line)) continue;
    seen.add(line);
    merged.push(line);
  }
  return merged.length ? merged.join('\n') + '\n' : '';
}

// 브랜치 생성 실패의 서명: 충돌 파일이 있으면 정렬한 파일 집합, 없으면 정규화한 오류 문자열.
function branchFailSignature(failure) {
  const files = (failure && failure.conflictFiles) || [];
  if (files.length) return 'files:' + [...files].map(f => String(f).replace(/\\/g, '/')).sort().join('|');
  const err = String((failure && failure.error) || '').replace(/\s+/g, ' ').trim();
  return 'err:' + err;
}

// 핸들러의 재시도 결정. lastBranchFailSig 가 없는 기존 상태는 기존 동작(횟수 기반)과 같다.
//  - stop-same-cause: 직전 시도와 같은 서명 → 남은 재시도를 소진하지 않고 즉시 중단
//  - retry / exhausted: 기존 횟수 기반 동작
function decideBranchFailAction(pendingTask, failure, max) {
  const sig = branchFailSignature(failure);
  const retries = ((pendingTask && pendingTask.branchFailRetries) || 0) + 1;
  const prev = pendingTask && pendingTask.lastBranchFailSig;
  if (prev && prev === sig) return { action: 'stop-same-cause', sig, retries };
  if (retries <= max) return { action: 'retry', sig, retries };
  return { action: 'exhausted', sig, retries };
}

module.exports = { parseConflictFiles, isMergeableLogPath, mergeLogLines, branchFailSignature, decideBranchFailAction };
