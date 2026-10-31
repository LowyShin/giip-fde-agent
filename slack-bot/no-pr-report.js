'use strict';
// 조사/답변형(코드 변경·PR 없음) 작업 완료 보고 코멘트 생성 (giip 4231).
//
// 용도: slack-bot handlers.js onComplete 가 PR 이 하나도 없는 완료(allUrls 비어 있음)를 만났을 때,
//   (a) REVIEW 전이 코멘트에 실을 "## 실행자 결론" 블록과
//   (b) PR 완료 게이트(scripts/gissue/pr-gate-sweep.ps1)가 보고형으로 인정하는 독립 코멘트 본문을 만든다.
// 게이트 계약(scripts/gissue/gissue-audit-lib.ps1 Test-HasNoPrReasonMarker): 어떤 코멘트의 첫 줄이
//   `[NO-PR-REASON]` 이고 그 아래 비어 있지 않은 사유가 1줄 이상이어야 한다. 그러므로 이 본문은
//   행위자 헤더(giip-task buildNoteComment)를 붙이지 않고 giip-task.maybeCommentRaw 로 그대로 보낸다.
// 보고형 완료 판정(Invoke-ReportCompletionJudge, giip 3801)이 의뢰와 결과를 대조하므로, 본문에
//   (1) 의뢰 요약 (2) 요청 항목별 결과 (3) 최종 판정을 모두 넣는다.
// 저장: 이 모듈은 문자열만 만든다. 게시는 giip-task.maybeCommentRaw -> giipIssueComments (tGiipIssueComment).
// 소비처: pr-gate-sweep.ps1 의 PR 게이트/보고형 완료 게이트. 테스트: tests/no-pr-report.test.js

const MARKER = '[NO-PR-REASON]';

function clip(s, max) {
  const str = String(s == null ? '' : s).trim();
  return str.length > max ? `${str.slice(0, max)}\n…(${str.length - max}자 생략)` : str;
}

/** 요청 본문에서 목록 항목(`- `, `* `, `1. `, `1) `)을 최대 max 개 뽑는다. */
function extractRequestItems(requestText, max = 12) {
  const items = [];
  for (const line of String(requestText || '').split(/\r?\n/)) {
    const m = line.match(/^\s*(?:[-*]|\d+[.)])\s+(.+\S)\s*$/);
    if (m) items.push(clip(m[1], 200));
    if (items.length >= max) break;
  }
  return items;
}

/** REVIEW 전이 코멘트에 덧붙일 실행자 결론 블록. 결론이 없으면 빈 문자열. */
function buildConclusionBlock(resultContent, heading = '## 실행자 결론') {
  const body = clip(resultContent, 4000);
  return body ? `\n\n${heading}\n${body}` : '';
}

/**
 * 독립 [NO-PR-REASON] 코멘트 본문. 첫 줄은 항상 마커다.
 * L: 문구 사전({reason, requestHeading, itemsHeading, itemsResultRef, itemsFallback, conclusionHeading, verdictHeading, verdict}).
 */
function buildNoPrReasonComment({ requestText, resultContent, taskId }, L) {
  const conclusion = clip(resultContent, 4000);
  const items = extractRequestItems(requestText);
  const lines = [
    MARKER,
    L.reason,
    '',
    `## ${L.requestHeading}`,
    clip(requestText, 1500) || '-',
    '',
    `## ${L.itemsHeading}`,
    ...(items.length
      ? items.map((it, i) => `${i + 1}. ${it} -> ${L.itemsResultRef}`)
      : [L.itemsFallback]),
    '',
    `## ${L.conclusionHeading}`,
    conclusion || '-',
    '',
    `## ${L.verdictHeading}`,
    L.verdict,
  ];
  if (taskId) lines.push('', `(task: ${taskId})`);
  return lines.join('\n');
}

/** 완료 분기에서 "코드 변경·PR 없음 + 보고할 결론 있음"인지. */
function isReportOnlyCompletion(allUrls, resultContent) {
  return (!allUrls || allUrls.length === 0) && String(resultContent || '').trim().length > 0;
}

module.exports = { MARKER, clip, extractRequestItems, buildConclusionBlock, buildNoPrReasonComment, isReportOnlyCompletion };
