// node --test slack-bot/tests/intent-jev.test.js
//
// giip 4221 — Slack 봇 의도 분류에 Jev 어댑터(②)를 넣고 ③(LLM 분류기)로 폴백하는 흐름의 회귀 테스트.
//
// 네트워크 정책: 외부 네트워크 호출 0건.
//   - Jev 전송은 `opts.jevRequest` 로 주입(모킹)한다.
//   - LLM 분류기는 `opts.spawn` 로 주입한다(실제 claude CLI 를 실행하지 않는다).
//   - 유일하게 실제 전송을 하는 케이스는 ⑭ 루프백 종단 간 검증인데, 127.0.0.1 의 ephemeral
//     포트에 띄운 대역 서버로만 communication 한다(외부 네트워크가 아니다).

const test = require('node:test');
const assert = require('node:assert');
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const querystring = require('node:querystring');
const { classifyRequest } = require('../intent');

// ── 테스트 픽스처 ────────────────────────────────────────────────────────────
// Jev 가 쓰는 sk(테스트용 가짜 값 — 실제 자격 증명 아님). 리터럴로 적지 않고 만들어
// 비밀 스캐너(GitGuardian 등)가 테스트 픽스처를 유출 키로 오인하지 않게 한다.
// maskString 의 20자 규칙에 걸리지 않게 짧게 잡았다(token 필드는 마스킹 대상이 아니다).
const SK = ['sk', 'unit', 'test', 'key'].join('-');
const ACCOUNT = { login_id: 'unit-test', sk: SK, csn: null };
const GATEWAY_URL = 'http://gateway.invalid/api';

// ①/② 어느 결정 규칙에도 걸리지 않아 Jev/LLM 단까지 내려가는 일반 문장.
const WORK_TEXT = '배포 스크립트 점검';
const QUESTION_TEXT = 'how many tasks are pending';

const ENV_KEYS = [
  'JEV_INTENT_ENABLED',
  'GIIP_JEV_GATEWAY_URL',
  'JEV_INTENT_TIMEOUT_MS',
  'JEV_INTENT_T_HI',
  'JEV_INTENT_P_HI',
  'JEV_INTENT_P_LO',
];

/** env 를 저장·초기화하고 테스트 종료 시 복원한다(테스트 간 오염 방지). */
function envSandbox(t, vars = {}) {
  const snapshot = {};
  for (const k of ENV_KEYS) snapshot[k] = process.env[k];
  for (const k of ENV_KEYS) delete process.env[k];
  for (const [k, v] of Object.entries(vars)) process.env[k] = v;
  t.after(() => {
    for (const k of ENV_KEYS) {
      if (snapshot[k] === undefined) delete process.env[k];
      else process.env[k] = snapshot[k];
    }
  });
}

/** 모킹 LLM 분류기. 호출 횟수와 인자를 기록한다. */
function makeSpawn(result) {
  const calls = [];
  const fn = async (cmd, args, opts) => {
    calls.push({ cmd, args, opts });
    if (typeof result === 'function') return result(calls.length);
    return result;
  };
  fn.calls = calls;
  return fn;
}

/** 모킹 Jev 전송. 호출 횟수와 (url, params, timeoutMs) 를 기록한다. */
function makeJev(responder) {
  const calls = [];
  const fn = async (url, params, timeoutMs) => {
    calls.push({ url, params, timeoutMs });
    return responder(url, params, timeoutMs);
  };
  fn.calls = calls;
  return fn;
}

const okBody = (over = {}) => ({
  success: true,
  intent: 'task',
  intent_confidence: 0.95,
  requires_file_change: 0.9,
  is_status_or_lookup: 0.02,
  engine: 'jev-unit',
  ...over,
});

/** console.log 을 잠시 잡아 판정 로그 줄을 모은다(비동기 판정까지 포함). */
async function captureLog(fn) {
  const lines = [];
  const original = console.log;
  console.log = (...args) => { lines.push(args.map(String).join(' ')); };
  try {
    await fn();
  } finally {
    console.log = original;
  }
  return lines;
}

// ── ⑴ 스위치 꺼짐(현행 동일성) ───────────────────────────────────────────────
test('스위치 꺼짐: Jev 전송 0회 + LLM 결과가 그대로 반환', async (t) => {
  envSandbox(t, { GIIP_JEV_GATEWAY_URL: GATEWAY_URL });
  const jev = makeJev(async () => { throw new Error('Jev 는 호출되면 안 된다'); });
  const spawn = makeSpawn({ status: 0, stdout: 'task\n', stderr: '' });

  const intent = await classifyRequest(WORK_TEXT, '/tmp/proj', {
    jevRequest: jev, spawn, accountResolver: () => ACCOUNT,
  });

  assert.strictEqual(intent, 'task');
  assert.strictEqual(jev.calls.length, 0, '스위치 OFF 면 Jev 전송은 0회여야 한다');
  assert.strictEqual(spawn.calls.length, 1, 'LLM 분류기는 1회 호출된다');
});

test('스위치 꺼짐: 결정적 rule 경로는 LLM 도 호출되지 않음', async (t) => {
  envSandbox(t, { GIIP_JEV_GATEWAY_URL: GATEWAY_URL });
  const jev = makeJev(async () => { throw new Error('Jev 는 호출되면 안 된다'); });
  const spawn = makeSpawn({ status: 0, stdout: 'task\n', stderr: '' });

  // isConfirmationQuery 가 true 인 메시지 → ①-b 에서 확정.
  const intent = await classifyRequest('지금 배포 상태 어때?', '/tmp/proj', {
    jevRequest: jev, spawn, accountResolver: () => ACCOUNT,
  });

  assert.strictEqual(intent, 'question');
  assert.strictEqual(jev.calls.length, 0);
  assert.strictEqual(spawn.calls.length, 0, '결정적 경로에서는 LLM 을 부르지 않는다');
});

// ── ⑵ 스위치 켬 + Jev 가 task / question ──────────────────────────────────────
test('스위치 켬 + Jev task(confidence≥T_hi, requires_file_change≥P_hi) → task, LLM 0회', async (t) => {
  envSandbox(t, { JEV_INTENT_ENABLED: '1', GIIP_JEV_GATEWAY_URL: GATEWAY_URL });
  const jev = makeJev(async () => ({ status: 200, body: okBody(), raw: '' }));
  const spawn = makeSpawn({ status: 0, stdout: 'question\n', stderr: '' });

  const intent = await classifyRequest(WORK_TEXT, '/tmp/proj', {
    jevRequest: jev, spawn, accountResolver: () => ACCOUNT,
  });

  assert.strictEqual(intent, 'task');
  assert.strictEqual(jev.calls.length, 1);
  assert.strictEqual(spawn.calls.length, 0, 'Jev 가 확정했으면 LLM 을 부르지 않는다');
});

test('스위치 켬 + Jev question(confidence≥T_hi, requires_file_change≤P_lo) → question, LLM 0회', async (t) => {
  envSandbox(t, { JEV_INTENT_ENABLED: '1', GIIP_JEV_GATEWAY_URL: GATEWAY_URL });
  const jev = makeJev(async () => ({
    status: 200,
    body: okBody({ intent: 'question', intent_confidence: 0.91, requires_file_change: 0.05, is_status_or_lookup: 0.88 }),
    raw: '',
  }));
  const spawn = makeSpawn({ status: 0, stdout: 'task\n', stderr: '' });

  const intent = await classifyRequest(QUESTION_TEXT, '/tmp/proj', {
    jevRequest: jev, spawn, accountResolver: () => ACCOUNT,
  });

  assert.strictEqual(intent, 'question');
  assert.strictEqual(jev.calls.length, 1);
  assert.strictEqual(spawn.calls.length, 0);
});

// ── ⑶ Jev 폴백 사유별 LMM 호출 ───────────────────────────────────────────────
test('Jev ambiguous → LLM 호출되고 LLM 결과 채택', async (t) => {
  envSandbox(t, { JEV_INTENT_ENABLED: '1', GIIP_JEV_GATEWAY_URL: GATEWAY_URL });
  const jev = makeJev(async () => ({
    status: 200, body: okBody({ intent: 'ambiguous', intent_confidence: 0.4 }), raw: '',
  }));
  const spawn = makeSpawn({ status: 0, stdout: 'task\n', stderr: '' });

  const intent = await classifyRequest(WORK_TEXT, '/tmp/proj', {
    jevRequest: jev, spawn, accountResolver: () => ACCOUNT,
  });

  assert.strictEqual(intent, 'task');
  assert.strictEqual(jev.calls.length, 1);
  assert.strictEqual(spawn.calls.length, 1);
});

test('Jev HTTP 500 → LLM 호출', async (t) => {
  envSandbox(t, { JEV_INTENT_ENABLED: '1', GIIP_JEV_GATEWAY_URL: GATEWAY_URL });
  const jev = makeJev(async () => ({ status: 500, body: { error: 'boom' }, raw: '' }));
  const spawn = makeSpawn({ status: 0, stdout: 'question\n', stderr: '' });

  const intent = await classifyRequest(WORK_TEXT, '/tmp/proj', {
    jevRequest: jev, spawn, accountResolver: () => ACCOUNT,
  });

  assert.strictEqual(intent, 'question');
  assert.strictEqual(spawn.calls.length, 1);
});

test('Jev 타임아웃(전송 reject) → LLM 호출', async (t) => {
  envSandbox(t, { JEV_INTENT_ENABLED: '1', GIIP_JEV_GATEWAY_URL: GATEWAY_URL });
  const jev = makeJev(async () => { throw new Error('ETIMEDOUT'); });
  const spawn = makeSpawn({ status: 0, stdout: 'task\n', stderr: '' });

  const intent = await classifyRequest(WORK_TEXT, '/tmp/proj', {
    jevRequest: jev, spawn, accountResolver: () => ACCOUNT,
  });

  assert.strictEqual(intent, 'task');
  assert.strictEqual(jev.calls.length, 1);
  assert.strictEqual(spawn.calls.length, 1);
});

// ── ⑷ 응답 형식 불일치 — 분류값을 지어내지 않는다 ────────────────────────────
test('Jev 응답에 intent 누락 → LLM 호출, 분류값을 지어내지 않음', async (t) => {
  envSandbox(t, { JEV_INTENT_ENABLED: '1', GIIP_JEV_GATEWAY_URL: GATEWAY_URL });
  // requires_file_change 만으로는 task 로 추정하면 안 된다 → LLM 결과(question)를 따른다.
  const jev = makeJev(async () => ({
    status: 200,
    body: { success: true, intent_confidence: 0.95, requires_file_change: 0.9 },
    raw: '',
  }));
  const spawn = makeSpawn({ status: 0, stdout: 'question\n', stderr: '' });

  const intent = await classifyRequest(WORK_TEXT, '/tmp/proj', {
    jevRequest: jev, spawn, accountResolver: () => ACCOUNT,
  });

  assert.strictEqual(intent, 'question', 'intent 가 없는데 task 로 지어내면 안 된다');
  assert.strictEqual(spawn.calls.length, 1);
});

test('Jev 응답에 intent_confidence 누락 → LLM 호출, confidence 를 추정하지 않음', async (t) => {
  envSandbox(t, { JEV_INTENT_ENABLED: '1', GIIP_JEV_GATEWAY_URL: GATEWAY_URL });
  const jev = makeJev(async () => ({
    status: 200,
    body: { success: true, intent: 'task', requires_file_change: 0.9 },
    raw: '',
  }));
  const spawn = makeSpawn({ status: 0, stdout: 'question\n', stderr: '' });

  const intent = await classifyRequest(WORK_TEXT, '/tmp/proj', {
    jevRequest: jev, spawn, accountResolver: () => ACCOUNT,
  });

  assert.strictEqual(intent, 'question', 'confidence 가 없는데 task 로 지어내면 안 된다');
  assert.strictEqual(spawn.calls.length, 1);
});

// ── ⑸ 신뢰도 부족 / 두 신호 모순 ─────────────────────────────────────────────
test('Jev 신뢰도 부족(confidence<T_hi) → LLM 호출', async (t) => {
  envSandbox(t, { JEV_INTENT_ENABLED: '1', GIIP_JEV_GATEWAY_URL: GATEWAY_URL });
  const jev = makeJev(async () => ({
    status: 200, body: okBody({ intent: 'task', intent_confidence: 0.5, requires_file_change: 0.95 }), raw: '',
  }));
  const spawn = makeSpawn({ status: 0, stdout: 'question\n', stderr: '' });

  const intent = await classifyRequest(WORK_TEXT, '/tmp/proj', {
    jevRequest: jev, spawn, accountResolver: () => ACCOUNT,
  });

  assert.strictEqual(intent, 'question');
  assert.strictEqual(spawn.calls.length, 1);
});

test('Jev 두 신호 모순(task 인데 requires_file_change<P_hi) → LLM 호출', async (t) => {
  envSandbox(t, { JEV_INTENT_ENABLED: '1', GIIP_JEV_GATEWAY_URL: GATEWAY_URL });
  const jev = makeJev(async () => ({
    status: 200, body: okBody({ intent: 'task', intent_confidence: 0.95, requires_file_change: 0.2 }), raw: '',
  }));
  const spawn = makeSpawn({ status: 0, stdout: 'question\n', stderr: '' });

  const intent = await classifyRequest(WORK_TEXT, '/tmp/proj', {
    jevRequest: jev, spawn, accountResolver: () => ACCOUNT,
  });

  assert.strictEqual(intent, 'question');
  assert.strictEqual(spawn.calls.length, 1);
});

// ── ⑹ Jev·LLM 모두 실패 → question + 안내문 ─────────────────────────────────
test('Jev 실패 + LLM 예외 → question + 안내문 1회', async (t) => {
  envSandbox(t, { JEV_INTENT_ENABLED: '1', GIIP_JEV_GATEWAY_URL: GATEWAY_URL });
  const jev = makeJev(async () => { throw new Error('ETIMEDOUT'); });
  const spawn = makeSpawn(async () => { throw new Error('llm down'); });
  const hints = [];

  const intent = await classifyRequest(WORK_TEXT, '/tmp/proj', {
    jevRequest: jev, spawn, accountResolver: () => ACCOUNT,
    onFallbackHint: (h) => hints.push(h),
  });

  assert.strictEqual(intent, 'question');
  assert.strictEqual(hints.length, 1, '안내문은 정확히 1회 전달된다');
  assert.ok(hints[0] && hints[0].length > 0, '안내문이 비어있으면 안 된다');
});

test('Jev 실패 + LLM 종료코드≠0 → question + 안내문 1회', async (t) => {
  envSandbox(t, { JEV_INTENT_ENABLED: '1', GIIP_JEV_GATEWAY_URL: GATEWAY_URL });
  const jev = makeJev(async () => ({ status: 502, body: {}, raw: '' }));
  const spawn = makeSpawn({ status: 1, stdout: '', stderr: 'boom' });
  const hints = [];

  const intent = await classifyRequest(WORK_TEXT, '/tmp/proj', {
    jevRequest: jev, spawn, accountResolver: () => ACCOUNT,
    onFallbackHint: (h) => hints.push(h),
  });

  assert.strictEqual(intent, 'question');
  assert.strictEqual(hints.length, 1);
  assert.ok(hints[0].length > 0);
});

test('LLM 이 성공해서 question 이면 안내문은 붙지 않는다', async (t) => {
  envSandbox(t, { JEV_INTENT_ENABLED: '1', GIIP_JEV_GATEWAY_URL: GATEWAY_URL });
  const jev = makeJev(async () => ({ status: 500, body: {}, raw: '' }));
  const spawn = makeSpawn({ status: 0, stdout: 'question\n', stderr: '' });
  const hints = [];

  const intent = await classifyRequest(WORK_TEXT, '/tmp/proj', {
    jevRequest: jev, spawn, accountResolver: () => ACCOUNT,
    onFallbackHint: (h) => hints.push(h),
  });

  assert.strictEqual(intent, 'question');
  assert.strictEqual(hints.length, 0, '분류기가 성공한 경우에는 안내문을 붙이지 않는다');
});

// ── ⑺ 계정 없음 / 게이트웨이 URL 미설정 ─────────────────────────────────────
test('채널에 계정 없음 → Jev 호출 0회, LLM 호출', async (t) => {
  envSandbox(t, { JEV_INTENT_ENABLED: '1', GIIP_JEV_GATEWAY_URL: GATEWAY_URL });
  const jev = makeJev(async () => { throw new Error('Jev 는 호출되면 안 된다'); });
  const spawn = makeSpawn({ status: 0, stdout: 'task\n', stderr: '' });

  const intent = await classifyRequest(WORK_TEXT, '/tmp/proj', {
    jevRequest: jev, spawn, accountResolver: () => null,
  });

  assert.strictEqual(intent, 'task');
  assert.strictEqual(jev.calls.length, 0, '계정이 없으면 Jev 단계를 생략한다');
  assert.strictEqual(spawn.calls.length, 1);
});

test('게이트웨이 URL 미설정 → Jev 호출 0회, LLM 호출', async (t) => {
  envSandbox(t, { JEV_INTENT_ENABLED: '1' });
  const jev = makeJev(async () => { throw new Error('Jev 는 호출되면 안 된다'); });
  const spawn = makeSpawn({ status: 0, stdout: 'task\n', stderr: '' });

  const intent = await classifyRequest(WORK_TEXT, '/tmp/proj', {
    jevRequest: jev, spawn, accountResolver: () => ACCOUNT,
  });

  assert.strictEqual(intent, 'task');
  assert.strictEqual(jev.calls.length, 0, '게이트웨이 주소가 없으면 Jev 단계를 생략한다');
  assert.strictEqual(spawn.calls.length, 1);
});

// ── ⑻ 마스킹 — 원문 비밀 패턴이 요청 본문에 남지 않는다 ─────────────────────
test('마스킹: Jev 요청 본문에 원문 비밀 패턴이 없다', async (t) => {
  envSandbox(t, { JEV_INTENT_ENABLED: '1', GIIP_JEV_GATEWAY_URL: GATEWAY_URL });
  // 마스킹 대상을 확인하기 위한 가짜 비밀 문자열(실제 값 아님) — 리터럴로 적지 않는다.
  const secret = ['sk', 'ant', 'abcdefgh12345678'].join('-');
  const raw = `이 요청에 키 ${secret} 가 들어있다`;
  const jev = makeJev(async () => ({ status: 200, body: okBody(), raw: '' }));
  const spawn = makeSpawn({ status: 0, stdout: 'task\n', stderr: '' });

  await classifyRequest(raw, '/tmp/proj', {
    jevRequest: jev, spawn, accountResolver: () => ACCOUNT,
  });

  assert.strictEqual(jev.calls.length, 1);
  const { jsondata } = jev.calls[0].params;
  const parsed = JSON.parse(jsondata);
  assert.ok(parsed.text_masked.includes('***REDACTED***'), '비밀 패턴이 REDACTED 로 바뀌어야 한다');
  assert.ok(!parsed.text_masked.includes(secret), '마스킹 통과본에 원문이 남아 있으면 안 된다');
  assert.ok(!jsondata.includes(secret), '요청 본문 어디에도 원문 비밀이 있으면 안 된다');
});

// ── ⑼ 요청 스키마 ────────────────────────────────────────────────────────────
test('요청 스키마: jsondata 필드와 token 이 계약을 따른다', async (t) => {
  envSandbox(t, { JEV_INTENT_ENABLED: '1', GIIP_JEV_GATEWAY_URL: GATEWAY_URL });
  const jev = makeJev(async () => ({ status: 200, body: okBody(), raw: '' }));
  const spawn = makeSpawn({ status: 0, stdout: 'task\n', stderr: '' });

  await classifyRequest(WORK_TEXT, '/tmp/proj', {
    jevRequest: jev, spawn, accountResolver: () => ACCOUNT,
    inThread: true, mentionsTaskId: true, mentionsIssueRef: false,
  });

  const call = jev.calls[0];
  assert.strictEqual(call.url, GATEWAY_URL, '게이트웨이 주소는 env 값만 사용한다');
  assert.strictEqual(call.params.token, SK, 'token 필드는 sk 다');
  assert.strictEqual(typeof call.params.jsondata, 'string');

  const parsed = JSON.parse(call.params.jsondata);
  assert.strictEqual(parsed.v, 1);
  assert.strictEqual(parsed.kind, 'intent_route');
  assert.strictEqual(typeof parsed.ts, 'string');
  assert.ok(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z$/.test(parsed.ts), 'ts 는 ISO8601 문자열이어야 한다');
  assert.ok(['ko', 'ja', 'en', 'unknown'].includes(parsed.lang), `lang 규약 위반: ${parsed.lang}`);
  assert.strictEqual(parsed.in_thread, true);
  assert.strictEqual(parsed.mentions_task_id, true);
  assert.strictEqual(parsed.mentions_issue_ref, false);
});

test('lang 감지: 한글 우세 → ko / 일본어 우세 → ja / 라틴 우세 → en', async (t) => {
  envSandbox(t, { JEV_INTENT_ENABLED: '1', GIIP_JEV_GATEWAY_URL: GATEWAY_URL });
  const seen = [];
  const jev = makeJev(async (_url, params) => {
    seen.push(JSON.parse(params.jsondata).lang);
    return { status: 200, body: okBody(), raw: '' };
  });
  const spawn = makeSpawn({ status: 0, stdout: 'task\n', stderr: '' });

  for (const text of ['배포 스크립트 점검', 'デプロイスクリプトの確認', 'deployment script review']) {
    await classifyRequest(text, '/tmp/proj', {
      jevRequest: jev, spawn, accountResolver: () => ACCOUNT,
    });
  }

  assert.deepStrictEqual(seen, ['ko', 'ja', 'en']);
});

// ── ⑽ 판정 로그에 원문 없음 ──────────────────────────────────────────────────
test('판정 로그: 원문 메시지가 로그에 등장하지 않는다(해시·길이만)', async (t) => {
  envSandbox(t, { JEV_INTENT_ENABLED: '1', GIIP_JEV_GATEWAY_URL: GATEWAY_URL });
  const marker = 'RAW-BODY-MARKER-DO-NOT-LOG';
  const jev = makeJev(async () => ({ status: 200, body: okBody(), raw: '' }));
  const spawn = makeSpawn({ status: 0, stdout: 'task\n', stderr: '' });

  const lines = await captureLog(() => classifyRequest(`${marker}please reflect this`, '/tmp/proj', {
    jevRequest: jev, spawn, accountResolver: () => ACCOUNT,
  }));

  const classifyLines = lines.filter(l => l.includes('intent-classify'));
  assert.ok(classifyLines.length >= 1, '판정 로그가 남아야 한다');
  for (const line of classifyLines) {
    assert.ok(!line.includes(marker), '판정 로그에 원문 메시지가 남아 있으면 안 된다');
    assert.ok(line.includes('source=jev'), 'source 가 남아야 한다');
    assert.ok(/textHash=[0-9a-f]{8}/.test(line), 'textHash(앞 8 hex) 가 남아야 한다');
    assert.ok(/maskedLen=\d+/.test(line), 'maskedLen 이 남아야 한다');
  }
});

// ── ⑾ 루프백 종단 간 검증 — 실제 postForm 전송 ───────────────────────────────
test('루프백 종단 간: 실제 전송이 form-urlencoded 로 token/jsondata 를 보낸다', async (t) => {
  const received = [];
  const server = http.createServer((req, res) => {
    const chunks = [];
    req.on('data', (d) => chunks.push(d));
    req.on('end', () => {
      const body = Buffer.concat(chunks).toString('utf8');
      received.push({ method: req.method, contentType: req.headers['content-type'], body });
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({
        success: true,
        intent: 'task',
        intent_confidence: 0.95,
        requires_file_change: 0.9,
        is_status_or_lookup: 0.03,
        engine: 'jev-loopback',
      }));
    });
  });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  t.after(() => new Promise((resolve) => server.close(resolve)));

  const port = server.address().port;
  envSandbox(t, { JEV_INTENT_ENABLED: '1', GIIP_JEV_GATEWAY_URL: `http://127.0.0.1:${port}/api/intent` });
  // 실제 postForm 을 쓰므로 jevRequest 는 주입하지 않는다.
  const spawn = makeSpawn({ status: 0, stdout: 'question\n', stderr: '' });

  const intent = await classifyRequest(WORK_TEXT, '/tmp/proj', {
    spawn, accountResolver: () => ACCOUNT,
  });

  assert.strictEqual(intent, 'task', '게이트웨이 응답 task 가 채택되어야 한다');
  assert.strictEqual(received.length, 1);
  assert.strictEqual(received[0].method, 'POST');
  assert.match(received[0].contentType, /application\/x-www-form-urlencoded/);

  const form = querystring.parse(received[0].body);
  assert.strictEqual(form.token, SK, 'token 필드는 sk');
  const parsed = JSON.parse(form.jsondata);
  assert.strictEqual(parsed.v, 1);
  assert.strictEqual(parsed.kind, 'intent_route');
  assert.strictEqual(typeof parsed.text_masked, 'string');
});

// ── ⑿ isForceTaskCmd 선평가 유지(소스 수준 회귀 가드) ─────────────────────────
// 호출부 3곳은 모두 `isForceTaskCmd` 를 먼저 평가하고 그 결과가 false 일 때만 classifyRequest 를
//   호출한다. 즉 force-task 문구이면 classifyRequest 는 아예 호출되지 않는다(① 우선 원칙).
test('isForceTaskCmd 선평가 유지: 호출부 3곳 소스 수준 회귀 가드', () => {
  const src = fs.readFileSync(path.join(__dirname, '..', 'handlers.js'), 'utf8');

  const forceCount = (src.match(/isForceTaskCmd\(text\)/g) || []).length;
  assert.strictEqual(forceCount, 3, 'isForceTaskCmd(text) 는 호출부 3곳에서 평가되어야 한다');

  const classifyCount = (src.match(/classifyRequest\(text, workDir/g) || []).length;
  assert.strictEqual(classifyCount, 3, 'classifyRequest 호출은 3곳이어야 한다');

  // 각 호출부는 isForceTaskCmd 결과로 단락된다.
  const callLines = src.split(/\r?\n/).filter(l => l.includes('classifyRequest(text, workDir'));
  assert.strictEqual(callLines.length, 3);
  for (const line of callLines) {
    const guarded = /isForceTaskCmd\(text\)/.test(line) || /forcedGiip/.test(line) || /forcedTask/.test(line);
    assert.ok(guarded, `호출부가 isForceTaskCmd 선평가로 단락되지 않는다: ${line.trim()}`);
  }

  // forcedGiip / forcedTask 는 반드시 isForceTaskCmd(text) 의 결과다.
  assert.ok(/const forcedGiip = isForceTaskCmd\(text\);/.test(src));
  assert.ok(/const forcedTask = isForceTaskCmd\(text\);/.test(src));
});
