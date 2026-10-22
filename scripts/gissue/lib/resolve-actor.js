#!/usr/bin/env node
/**
 * AI 행위자(actor) 자격증명 해석기 — giip #2613
 *
 * 배경(실측, 2026-09-16):
 *   giip 이슈 코멘트의 최근 30일 작성자 분포에서 `lowyshin.giip` 이 3,385건으로 1위였다.
 *   이건 사람 계정이다(tCorpUser usn=156, uloginid='lowy@naver.com', uname='lowyshin.giip').
 *   원인은 인증 경로다: 코멘트 SP(pApiGiipIssueCommentPutbyAK)가 dbo.lwGetUSNbyat(@ak) 로 주체를
 *   구하는데, 이 함수의 5번째 폴백이 "SK 가 가리키는 CSn 의 tCorpUserRel.isPay=1 사용자"를 돌려준다.
 *   csn 47 의 isPay=1 사용자가 usn 156 이라, csn47 스코프 SK 로 코멘트를 쓰면 전부 사람 이름으로
 *   기록됐다. 게다가 authorUsn 은 거의 전부 NULL 이라 사후 감사도 불가능했다.
 *
 * 해결: 주체별 tCorpUser 계정(ai.*)을 만들고, 코멘트 쓰기는 그 계정의 AccessToken(AK)으로 인증한다.
 *   AK 경로에서는 lwGetUSNbyat 이 그 계정의 usn 을 정확히 돌려주므로
 *   author = 그 계정의 uname, authorUsn = 그 계정의 usn 으로 서버가 확정한다(클라이언트 위조 불가).
 *
 * 왜 SK 가 아니라 AK 인가: tSecretKey 에는 uSn 컬럼 자체가 없다(SK 는 CSn/CGSn 스코프 공유키다).
 *   게다가 pApiSecretKeyAddbyAk 는 CGSn+cSn 조합에 활성 키가 이미 있으면 추가를 거부한다.
 *   즉 SK 로는 주체를 나눌 수 없다 — 주체 분리는 AK 경로가 유일한 방법이다.
 *
 * 파일 배치(둘로 나눈 이유):
 *   - scripts/gissue/ai-actors.json      : 공개 레지스트리(git 추적). 누가 있고 무슨 규칙인지.
 *   - slack-bot/.secrets/giip-accounts.json 의 actors[<uloginid>].ak : 비밀값(git 비추적).
 *   -> .agent/rules/49_no_plaintext_credential_persist.md
 *
 * 사용:
 *   const { resolveActor } = require('./resolve-actor');
 *   const actor = resolveActor();            // GIIP_ACTOR 또는 레지스트리 defaultActor
 *   const actor = resolveActor({ actorKey: 'ai.dp01.gissue-scheduler' });
 *
 * CLI(셸 스크립트용):
 *   node resolve-actor.js --ak      -> AccessToken 만 stdout 으로
 *   node resolve-actor.js --name    -> 주체 이름(uloginid)만
 *   node resolve-actor.js --json    -> {actor, usn, akLength} (AK 는 담지 않는다)
 */
const fs = require('fs');
const path = require('path');

const SCRIPT_DIR = __dirname;
const REGISTRY_FILE = path.join(SCRIPT_DIR, '..', 'ai-actors.json');
// giip-accounts.json 은 git 비추적이라 worktree 체크아웃에는 존재하지 않는다.
//
// [giip #2645 이식] 원본(lowyworkenv)은 폴백 경로로 이 PC 의 절대경로 2개를 박아 뒀었다. 이 레포는
// "다른 PC 에서 clone 만 하면 동작한다"가 요건이므로 절대경로를 넣지 않는다. 대신
//   1) 이 레포 루트의 slack-bot/.secrets/giip-accounts.json  (= SCRIPT_DIR/../../../slack-bot/...)
//   2) 환경변수 GIIP_ACCOUNTS_FILE 로 주어진 경로  (워크트리/다른 위치를 쓰는 배포용 탈출구)
// 순으로 본다. 환경변수 쪽이 우선이다 — 워크트리에서 돌릴 때 메인 체크아웃의 자격증명 파일을
// 가리키는 유일한 이식 가능한 수단이기 때문이다.
const ACCOUNTS_CANDIDATES = [
  process.env.GIIP_ACCOUNTS_FILE,
  path.join(SCRIPT_DIR, '..', '..', '..', 'slack-bot', '.secrets', 'giip-accounts.json'),
].filter(Boolean);
const DEFAULT_ACCOUNTS_FILE = ACCOUNTS_CANDIDATES.find((p) => fs.existsSync(p)) || ACCOUNTS_CANDIDATES[ACCOUNTS_CANDIDATES.length - 1];

function readJson(file, label) {
  if (!fs.existsSync(file)) {
    throw new Error(`${label} 을(를) 찾을 수 없습니다: ${file}`);
  }
  // BOM 이 붙어 있으면 JSON.parse 가 터진다(PowerShell 로 저장한 파일에서 실제로 발생).
  const raw = fs.readFileSync(file, 'utf8').replace(/^﻿/, '');
  try {
    return JSON.parse(raw);
  } catch (e) {
    throw new Error(`${label} 파싱 실패(${file}): ${e.message}`);
  }
}

/**
 * 이번 실행의 주체를 확정하고 그 AK 를 돌려준다.
 *
 * 우선순위: 인자 actorKey > 환경변수 GIIP_ACTOR > ai-actors.json 의 defaultActor.
 * 하드코딩된 주체 이름은 이 파일 어디에도 없다(요구사항: 주체 식별을 코드에 박지 말 것).
 *
 * 실패 시 던진다 — 조용히 예전 SK 로 폴백하지 않는다. 폴백하면 그 순간 다시 사람 계정
 * (lowyshin.giip)으로 기록되기 시작하는데, 그건 이 변경이 막으려는 바로 그 상태라 침묵이 더 나쁘다.
 *
 * @returns {{actor:string, usn:number|null, ak:string, source:string}}
 */
function resolveActor({ actorKey, accountsFile } = {}) {
  const registry = readJson(REGISTRY_FILE, 'AI 행위자 레지스트리(ai-actors.json)');
  const accounts = readJson(accountsFile || DEFAULT_ACCOUNTS_FILE, '자격증명 파일(giip-accounts.json)');

  let source = 'ai-actors.json:defaultActor';
  let key = actorKey;
  if (!key && process.env.GIIP_ACTOR) {
    key = process.env.GIIP_ACTOR.trim();
    source = 'env:GIIP_ACTOR';
  } else if (key) {
    source = 'arg:actorKey';
  }
  if (!key) key = registry.defaultActor;

  if (!key) {
    throw new Error('주체를 결정하지 못했습니다: GIIP_ACTOR 환경변수도, ai-actors.json 의 defaultActor 도 없습니다.');
  }

  const known = registry.actors || {};
  if (!Object.prototype.hasOwnProperty.call(known, key)) {
    throw new Error(
      `'${key}' 는 등록된 AI 행위자가 아닙니다(출처: ${source}). ` +
        `등록된 주체: ${Object.keys(known).join(', ')}. ` +
        `새 주체를 추가하려면 scripts/gissue/AI_ACTOR_ACCOUNTS.md 절차를 따르세요.`
    );
  }

  const cred = (accounts.actors || {})[key];
  if (!cred || !cred.ak) {
    // [giip #2645 이식] 이 레포에는 DB 직접접속 수단이 없어 AK 를 DB 에서 끌어오는
    // sync-ai-actor-credentials.ps1 이 이식되지 않았다. 존재하지 않는 스크립트를 실행하라고
    // 안내하면 그 자리에서 다시 막히므로, 실제로 할 수 있는 조치만 적는다.
    throw new Error(
      `'${key}' 의 AccessToken 이 자격증명 파일에 없습니다(파일: ${accountsFile || DEFAULT_ACCOUNTS_FILE}). ` +
        `이 레포는 DB 직접접속 수단이 없어 AK 를 스스로 발급/조회하지 못합니다 — ` +
        `giipdb 접근 권한이 있는 호스트에서 만든 giip-accounts.json 을 이 체크아웃의 ` +
        `slack-bot/.secrets/ 에 두거나, 환경변수 GIIP_ACCOUNTS_FILE 로 그 파일 경로를 지정하세요. ` +
        `절차: scripts/gissue/AI_ACTOR_ACCOUNTS.md §0-1 (AK 는 git 에 커밋하지 않습니다).`
    );
  }

  return { actor: key, usn: typeof cred.usn === 'number' ? cred.usn : null, ak: cred.ak, source };
}

module.exports = { resolveActor, REGISTRY_FILE, DEFAULT_ACCOUNTS_FILE };

if (require.main === module) {
  const mode = process.argv[2] || '--json';
  try {
    const a = resolveActor();
    if (mode === '--ak') process.stdout.write(a.ak);
    else if (mode === '--name') process.stdout.write(a.actor);
    else process.stdout.write(JSON.stringify({ actor: a.actor, usn: a.usn, akLength: a.ak.length, source: a.source }));
  } catch (e) {
    process.stderr.write(`${e.message}\n`);
    process.exit(2);
  }
}
