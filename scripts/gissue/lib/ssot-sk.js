#!/usr/bin/env node
/**
 * SK 단일 진실 소스(SSOT) 파서 — giip-fde-agent 가 보유한 계정 정본에서 "이 머신의 CSN" 에
 * 해당하는 SK 를 한 곳에서만 읽는다.
 *
 * 배경: 이 docker 배포 모델은 "컨테이너 1개 = 프로젝트(CSN) 1개"다. CSN 의 정본은
 * scripts/gissue/csn-projects.json 의 단일 csn 키(lib/ssot-csn.js), 그 CSN 의 SK 정본은
 * giip-fde-agent 가 먼저 설치되며 materialize 하는 slack-bot/.secrets/giip-accounts.json 이다
 * (docker/setup-registration.js 가 GIIP_CSN/GIIP_SK 로 생성). giipAgentLinux 의 giipAgent.cnf 는
 * 이 파서로 giip-fde-agent 의 정본에서 SK 를 끌어와, GIIP_SK 환경변수가 stale 해도 SSOT 와
 * 어긋나지 않게 한다(ssot-csn.js 가 CSN 에 대해 하는 역할의 SK 판).
 *
 * entrypoint.sh 와 check-csn-consistency.sh 가 공용으로 이 파서를 쓴다. CSN 은 코드에 박지 않고
 * 반드시 인자로 받는다(SSOT 에서 파생된 값을 넘겨받는다).
 *
 * 사용: node ssot-sk.js <path-to-giip-accounts.json> <csn>
 * stdout: 해당 csn 계정의 sk 1줄(그 외 아무것도 출력하지 않는다 — 명령치환으로 소비).
 * 종료코드:
 *   0 = csn 과 일치하는 계정의 sk 를 찾음(그 값을 stdout 에 출력)
 *   1 = 파일 없음 / JSON 파싱 실패 / csn 인자 없음 / 일치 계정·sk 없음 (stderr 에 사유, sk 는 미출력)
 */
const fs = require('fs');

const acctPath = process.argv[2];
const wantCsn = process.argv[3];
if (!acctPath || !wantCsn) {
  console.error('사용법: node ssot-sk.js <path-to-giip-accounts.json> <csn>');
  process.exit(1);
}
if (!fs.existsSync(acctPath)) {
  console.error(`[ssot-sk] 파일 없음: ${acctPath}`);
  process.exit(1);
}

let doc;
try {
  const raw = fs.readFileSync(acctPath, 'utf8');
  const bom = raw.charCodeAt(0) === 0xfeff;
  doc = JSON.parse(bom ? raw.slice(1) : raw);
} catch (e) {
  console.error(`[ssot-sk] JSON 파싱 실패: ${e.message}`);
  process.exit(1);
}

// default 계정과 channels.* 를 모두 후보로 보고, csn 이 일치하는 첫 계정의 sk 를 돌려준다.
// (giip-accounts.json 구조: { default: {sk, csn, ...}, channels: { <id>: {sk, csn, ...} } })
const candidates = [];
if (doc && doc.default) candidates.push(doc.default);
if (doc && doc.channels) {
  for (const key of Object.keys(doc.channels)) candidates.push(doc.channels[key]);
}

const match = candidates.find((a) => a && String(a.csn) === String(wantCsn) && a.sk);
if (!match) {
  console.error(`[ssot-sk] csn=${wantCsn} 과 일치하는 sk 계정을 찾지 못했습니다 (${acctPath}).`);
  process.exit(1);
}
process.stdout.write(String(match.sk) + '\n');
