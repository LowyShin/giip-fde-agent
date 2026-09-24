#!/usr/bin/env node
/*
 * register-issue.js — Claude Code 세션(또는 CLI)에서 giip issue 를 바로 등록하는 재사용 도구.
 *
 * 배경: Slack 봇의 `<프로젝트> issue 등록 <내용>` 커맨드(slack-bot/handlers.js §515~)와
 *       "같은 경로(giip-accounts + giip-api.issueCreate)"를 헤드리스로 호출한다.
 *       채팅에만 남긴 요청이 세션이 죽으면 통째로 유실되던 문제를 막기 위해, 요청을
 *       받자마자 issue(=영속 기록)로 남기는 용도.
 *
 * 인증/계정: slack-bot/.secrets/giip-accounts.json 의 default 계정(login_id + SK + csn)을
 *            그대로 재사용한다(별도 설정 불필요). SK 는 절대 출력하지 않는다.
 *
 * 상태: 항상 PENDING 으로 등록한다(유실 방지). 무인 처리기(run-gissue-claude 의 refine [B])가
 *       다음 스케줄에 작업지시서로 정제(READY 승격)한다. → 봇의 create-first-PENDING 과 동일 취지.
 *
 * 사용법:
 *   node register-issue.js --title "<제목>" --content-file <경로> [--csn 47]
 *   node register-issue.js --title "<제목>" --content "<본문(짧을 때)>" [--csn 47]
 *   echo "<본문>" | node register-issue.js --title "<제목>"        # stdin 도 가능
 *   기본 csn: default 계정의 csn(=47, giipprj). --csn 으로 상위 지정 가능.
 */
'use strict';
const fs = require('fs');
const path = require('path');

const BOT_DIR = path.resolve(__dirname, '..', '..', 'slack-bot');
const accounts = require(path.join(BOT_DIR, 'giip-accounts'));
const giip = require(path.join(BOT_DIR, 'giip-api'));

function parseArgs(argv) {
  const a = { status: 'PENDING' };
  for (let i = 2; i < argv.length; i++) {
    const k = argv[i];
    const next = () => argv[++i];
    if (k === '--title') a.title = next();
    else if (k === '--content') a.content = next();
    else if (k === '--content-file') a.contentFile = next();
    else if (k === '--csn') a.csn = Number(next());
    else if (k === '--status') a.status = next();
    else if (k === '--user-request') a.userRequest = true;
    else if (k === '--help' || k === '-h') a.help = true;
  }
  return a;
}

function readStdin() {
  try { return fs.readFileSync(0, 'utf8'); } catch { return ''; }
}

async function main() {
  const a = parseArgs(process.argv);
  if (a.help) {
    console.log('usage: node register-issue.js --title "<제목>" (--content-file <경로> | --content "<본문>" | stdin) [--csn N] [--status PENDING] [--user-request]');
    process.exit(0);
  }

  let content = a.content;
  if (a.contentFile) content = fs.readFileSync(a.contentFile, 'utf8');
  if (!content && !process.stdin.isTTY) content = readStdin();
  content = (content || '').trim();

  const title = (a.title || content.split(/\r?\n/)[0] || '(무제)').slice(0, 200).trim();
  if (!content) { console.error('❌ 본문이 비었습니다. --content-file / --content / stdin 중 하나로 내용을 주세요.'); process.exit(1); }

  const acct = accounts.resolve(null); // default 계정
  if (!acct) { console.error('❌ giip 계정 미설정 (slack-bot/.secrets/giip-accounts.json 의 default 확인).'); process.exit(1); }
  const csn = (a.csn === 0 || a.csn) ? a.csn : (acct.csn ?? null);

  try {
    const r = await giip.issueCreate(acct, { title, content: content.slice(0, 8000), status: a.status, csn });
    const isn = r && r.isn ? Number(r.isn) : null;
    if (!isn) { console.error('❌ 등록 응답에 isn 이 없습니다:', JSON.stringify(r)); process.exit(1); }
    // [출력 계약 — giip #2645] 아래 "giip issue #<isn>" 형식은 run-gissue-claude.ps1 의 이슈 1건
    // 시간박스 초과 경로(giip #1565)가 정규식 `giip issue #(\d+)` 으로 새 isn 을 뽑아내는 계약이다.
    // 문구를 바꾸면 후속 이슈 번호를 못 읽어 "(등록 실패 또는 응답 파싱 실패)" 로 기록되므로,
    // 바꿀 때는 그 호출부도 같이 고칠 것.
    console.log(`✅ giip issue #${isn} 등록 완료 (status=${a.status}, csn=${csn})`);
    console.log(`   제목: ${title}`);
    console.log(`   보기: https://giip.littleworld.net/ko/admin/giip-issues/${isn}`);

    // [USER-REQUEST] 마커: 사용자가 직접 요청한 경로로 등록한 경우만 자동 첨부
    // (giip #2417 — 봇 자동 등록 이슈와 구분, 오케스트레이터가 --user-request로 명시时才添付)
    if (a.userRequest) {
      try {
        await giip.issueComment(acct, isn, '[USER-REQUEST]');
        console.log(`   [USER-REQUEST] 마커 코멘트 첨부됨`);
      } catch (e) {
        console.error(`   ⚠ [USER-REQUEST] 마커 코멘트 실패: ${e.message} (issue 등록은 성공)`);
      }
    }
  } catch (e) {
    console.error('❌ issue 등록 실패:', e.message);
    process.exit(1);
  }
}

main();
