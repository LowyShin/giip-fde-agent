// giip 5144(원본 giip 4902): 엔진 타임아웃/heartbeat 단위 검증 (실제 Slack·claude 호출 없음)
const assert = require('assert');
const { engineTimeoutMs, engineHeartbeatMs, spawnAsync } = require('../claude-cli');
(async () => {
  for (const v of [undefined, '', '0', '-3', 'abc', '1.5']) assert.strictEqual(engineTimeoutMs({ SLACKBOT_ENGINE_TIMEOUT_MIN: v }), undefined, `timeout ${v}`);
  assert.strictEqual(engineTimeoutMs({ SLACKBOT_ENGINE_TIMEOUT_MIN: '7' }), 420000);
  assert.strictEqual(engineHeartbeatMs({}), 1800000);
  assert.strictEqual(engineHeartbeatMs({ SLACKBOT_ENGINE_HEARTBEAT_MIN: '0' }), 0);
  assert.strictEqual(engineHeartbeatMs({ SLACKBOT_ENGINE_HEARTBEAT_MIN: '5' }), 300000);
  assert.strictEqual(engineHeartbeatMs({ SLACKBOT_ENGINE_HEARTBEAT_MIN: 'x' }), 1800000);
  console.log('PASS (a) env 파싱');
  const sleep = ms => ['-e', `setTimeout(()=>{},${ms})`];
  const r = await spawnAsync('node', sleep(1000), { timeout: undefined, heartbeatMs: 0 });
  assert.strictEqual(r.status, 0);
  console.log('PASS (b) 무제한 정상 완료');
  await assert.rejects(spawnAsync('node', sleep(5000), { timeout: 300 }), e => e.code === 'ETIMEDOUT');
  console.log('PASS (c) 타임아웃 지정 시 ETIMEDOUT');
  const logs = [];
  const orig = console.log;
  console.log = (...a) => logs.push(a.join(' '));
  await spawnAsync('node', sleep(1100), { heartbeatMs: 300, label: 'C123' });
  console.log = orig;
  assert.ok(logs.length >= 2 && /엔진 실행 중 \d+분 경과 \(pid=\d+, 채널=C123\)/.test(logs[0]), logs.join('|'));
  console.log('PASS (d) heartbeat:', logs[0]);
  const h = process._getActiveHandles().filter(x => x.constructor.name === 'Timeout');
  assert.strictEqual(h.length, 0);
  console.log('PASS (e) 잔존 타이머 0');
})().catch(e => { console.error('FAIL', e); process.exit(1); });
