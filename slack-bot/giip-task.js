/**
 * giip-task.js — task-manager 생명주기 ↔ giip issue 연동(얇은 훅, best-effort).
 * rule 40: 연결 시 giip issue 우선 등록, 미연결/실패 시 null → 로컬 타임스탬프 폴백.
 * 설계: docs/DESIGN_slackbot_giip_issue_integration.md §4.
 * 모든 함수는 절대 throw 하지 않는다(봇 무중단). 실패는 로그 + null/no-op.
 */
const accounts = require('./giip-accounts');
const giip = require('./giip-api');

/** 태스크 생성 시: 연결되어 있으면 issue 생성(IN_PROGRESS) → isn. 아니면 null(로컬 폴백).
 *  csn: 프로젝트명 기반 매핑(config.resolveProjectCsn) 결과. null 이면 account 기본 csn 로 폴백. */
async function maybeCreateIssue(channelId, title, content, csn = null) {
  const acct = accounts.resolve(channelId);
  if (!acct) return null;
  try {
    const r = await giip.issueCreate(acct, {
      title: (title || '(무제)').slice(0, 200),
      content: (content || title || '').slice(0, 8000),
      status: 'IN_PROGRESS',
      csn,
    });
    return r && r.isn ? Number(r.isn) : null;
  } catch (e) {
    console.error('[giip-task] issue 생성 실패(로컬 폴백):', e.message);
    return null;
  }
}

/** 완료/에러 시: 코멘트 + 상태전이(best-effort, 실패해도 무시). */
async function maybeFinish(channelId, isn, status, comment) {
  if (!isn) return;
  const acct = accounts.resolve(channelId);
  if (!acct) return;
  try { if (comment) await giip.issueComment(acct, isn, comment); }
  catch (e) { console.error('[giip-task] comment 실패:', e.message); }
  try { if (status) await giip.issueUpdate(acct, { isn, status }); }
  catch (e) { console.error('[giip-task] status 실패:', e.message); }
}

module.exports = { maybeCreateIssue, maybeFinish };

