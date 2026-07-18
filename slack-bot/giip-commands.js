/**
 * giip-commands.js — Slack `giip ...` 커맨드 핸들러 (자립 모듈).
 * index.js 는 한 줄 훅으로 연결:
 *   const gc = await handleGiipCommand(text, channelId); if (gc.handled) { await reply(gc.text); return; }
 * 설계: docs/DESIGN_slackbot_giip_issue_integration.md §5. 규칙 39/40.
 */
const accounts = require('./giip-accounts');
const giip = require('./giip-api');
const config = require('./config');

function code(obj, max = 1800) {
  return '```\n' + JSON.stringify(obj, null, 2).slice(0, max) + '\n```';
}

/**
 * @returns {Promise<{handled:boolean, text?:string}>}
 */
async function handleGiipCommand(rawText, channelId) {
  const text = (rawText || '').trim();
  const m = text.match(/^giip\s+(\S+)\s*([\s\S]*)$/i);
  if (!m) return { handled: false };
  const sub = m[1].toLowerCase();
  const rest = (m[2] || '').trim();

  // ── giip account ... — 채널 계정 매핑(대화로 변경 → .secrets 영속화) ──
  if (sub === 'account') {
    const setM = rest.match(/^set(-default)?\s+(\S+)\s+(\S+)\s*(\d+)?/i);
    if (setM) {
      const asDefault = !!setM[1];
      const login_id = setM[2];
      const sk = setM[3];
      const csn = setM[4] || null;
      accounts.setAccount(asDefault ? null : channelId, { login_id, sk, csn }, asDefault);
      return {
        handled: true,
        text: `✅ giip 계정 저장(${asDefault ? 'default' : channelId}) — login=${login_id}${csn ? `, csn=${csn}` : ''}.\n⚠️ 보안: SK 가 포함된 이 메시지는 삭제하세요.`,
      };
    }
    if (/^(show|status)/i.test(rest)) {
      const acct = accounts.resolve(channelId);
      return {
        handled: true,
        text: acct ? `login=${acct.login_id}, csn=${acct.csn ?? '-'} (SK 숨김)` : '계정 미설정',
      };
    }
    return {
      handled: true,
      text: '사용법: `giip account set <login_id> <sk> [csn]` | `set-default <login_id> <sk> [csn]` | `show`',
    };
  }

  // ── giip project ... — 프로젝트명 ↔ csn 매핑 관리(project-csn.json, 재시작 불필요) ──
  //   giip 계정과 무관하므로 account 확인 게이트보다 먼저 처리한다.
  //   `<프로젝트명> issue 등록 <내용>` 이 어떤 csn 으로 등록되는지를 여기서 관리.
  if (sub === 'project' || sub === 'proj' || sub === 'csn') {
    const pm = rest.match(/^(set|add|del|delete|rm|remove|list|ls|show)?\s*([\s\S]*)$/i);
    const action = (pm && pm[1] ? pm[1].toLowerCase() : 'list');
    const pargs = pm ? (pm[2] || '').trim() : '';
    const USAGE = '사용법: `giip project set <프로젝트명> <csn>` | `giip project list` | `giip project del <프로젝트명>`';
    try {
      if (action === 'set' || action === 'add') {
        const sm = pargs.match(/^(\S+)\s+(-?\d+)$/);
        if (!sm) return { handled: true, text: USAGE };
        const { name, csn } = config.setProjectCsn(sm[1], sm[2]);
        return {
          handled: true,
          text: `✅ 프로젝트 CSN 매핑 저장: \`${name}\` → csn ${csn}\n이제 \`${name} issue 등록 <내용>\` 은 csn ${csn} 로 등록됩니다(봇 재시작 불필요).`,
        };
      }
      if (action === 'del' || action === 'delete' || action === 'rm' || action === 'remove') {
        const name = pargs.split(/\s+/)[0];
        if (!name) return { handled: true, text: USAGE };
        const ok = config.deleteProjectCsn(name);
        return { handled: true, text: ok ? `✅ 매핑 삭제: \`${name.toLowerCase()}\`` : `⚠️ \`${name.toLowerCase()}\` 매핑이 없습니다.` };
      }
      // list / ls / show / (인자 없음)
      const map = config.listProjectCsn();
      const keys = Object.keys(map);
      const body = keys.length ? keys.map((k) => `• \`${k}\` → csn ${map[k]}`).join('\n') : '(등록된 매핑 없음)';
      return { handled: true, text: `📋 프로젝트 → CSN 매핑 (project-csn.json)\n${body}\n\n${USAGE}` };
    } catch (e) {
      return { handled: true, text: `❌ ${e.message}\n${USAGE}` };
    }
  }

  const acct = accounts.resolve(channelId);
  if (!acct) {
    return {
      handled: true,
      text: '⚠️ giip 계정 미설정. `giip account set <login_id> <sk> [csn]` 로 등록하세요(DM 권장).',
    };
  }

  // ── giip issue ... ──
  if (sub === 'issue') {
    const im = rest.match(/^(\w+)?\s*([\s\S]*)$/);
    const action = (im && im[1] ? im[1] : 'list').toLowerCase();
    const arg = im ? (im[2] || '').trim() : '';
    try {
      if (action === 'new' || action === 'create') {
        const title = arg.replace(/^["']|["']$/g, '').trim() || '(무제)';
        const r = await giip.issueCreate(acct, { title, content: title, status: 'IN_PROGRESS' });
        return { handled: true, text: `✅ 이슈 생성 #${r.isn} — ${title}` };
      }
      if (action === 'done') { await giip.issueUpdate(acct, { isn: Number(arg), status: 'DONE' }); return { handled: true, text: `✅ #${arg} → DONE` }; }
      if (action === 'review') { await giip.issueUpdate(acct, { isn: Number(arg), status: 'REVIEW' }); return { handled: true, text: `✅ #${arg} → REVIEW` }; }
      if (action === 'progress' || action === 'start') { await giip.issueUpdate(acct, { isn: Number(arg), status: 'IN_PROGRESS' }); return { handled: true, text: `✅ #${arg} → IN_PROGRESS` }; }
      if (action === 'get' || action === 'show') { const i = await giip.issueGet(acct, Number(arg)); return { handled: true, text: code(i, 1500) }; }
      if (action === 'comment') {
        const cm = arg.match(/^(\d+)\s+([\s\S]+)$/);
        if (cm) { await giip.issueComment(acct, Number(cm[1]), cm[2]); return { handled: true, text: `✅ #${cm[1]} 코멘트 추가` }; }
        return { handled: true, text: '사용법: `giip issue comment <isn> <내용>`' };
      }
      if (action === 'list') {
        const list = await giip.issueList(acct, { status: arg || '', csn: acct.csn || '' });
        return {
          handled: true,
          text: list.length ? list.slice(0, 20).map((i) => `#${i.isn} [${i.status}] ${i.title}`).join('\n') : '(이슈 없음)',
        };
      }
      return { handled: true, text: '사용법: `giip issue new "<title>"` | `list [status]` | `get <isn>` | `done|review|progress <isn>` | `comment <isn> <text>`' };
    } catch (e) {
      return { handled: true, text: `❌ ${e.message}` };
    }
  }

  // ── giip api <Verb> [jsondata] — 범용 giip API 호출 ──
  if (sub === 'api') {
    const am = rest.match(/^(\S+)\s*([\s\S]*)$/);
    if (!am) return { handled: true, text: '사용법: `giip api <Verb> [jsondata]`' };
    const verb = am[1];
    let jsondata = null;
    const jsonPart = (am[2] || '').trim();
    if (jsonPart) {
      try { jsondata = JSON.parse(jsonPart); } catch { return { handled: true, text: 'jsondata JSON 파싱 실패' }; }
    }
    try {
      const r = await giip.apiCall(acct, verb, jsondata);
      return { handled: true, text: code(r) };
    } catch (e) {
      return { handled: true, text: `❌ ${e.message}` };
    }
  }

  return { handled: false };
}

module.exports = { handleGiipCommand };
