// node --test slack-bot/tests/dashboard.test.js  (LLM/네트워크/실제 git 미사용)
// child_process.spawnSync 를 스텁으로 바꿔 git 호출 여부를 기록하고, 실제 레포 파일은 건드리지 않는다.
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const path = require('path');
const cp = require('child_process');

const calls = [];
const realSpawnSync = cp.spawnSync;
cp.spawnSync = (cmd, args) => { calls.push([cmd, ...(args || [])]); return { status: 1, stdout: '', stderr: '' }; };

for (const dir of ['slack-bot', 'slack-bot-minimax']) {
  const modPath = path.join(__dirname, '..', '..', dir, 'dashboard.js');
  const dashFile = path.join(__dirname, '..', '..', 'LOWY_ACTION_DASHBOARD.md');
  const load = () => { delete require.cache[require.resolve(modPath)]; return require(modPath); };

  test(`${dir}: SLACKBOT_DASHBOARD 미설정이면 파일 생성·git 호출 없이 skip`, () => {
    delete process.env.SLACKBOT_DASHBOARD;
    const existed = fs.existsSync(dashFile);
    const d = load(); calls.length = 0;
    assert.deepStrictEqual(d.refreshDashboard('x'), { skipped: 'disabled' });
    assert.strictEqual(calls.length, 0);
    assert.strictEqual(fs.existsSync(dashFile), existed);
  });

  test(`${dir}: on 이 아닌 값(1/true/off)도 skip`, () => {
    const d = load();
    for (const v of ['1', 'true', 'off', 'onn', '']) {
      process.env.SLACKBOT_DASHBOARD = v; calls.length = 0;
      assert.strictEqual(d.refreshDashboard('x').skipped, 'disabled', v);
      assert.strictEqual(calls.length, 0);
    }
    delete process.env.SLACKBOT_DASHBOARD;
  });

  test(`${dir}: on(대소문자 무시)이면 기존 경로로 진행(git 호출 발생, 스텁이라 push 없음)`, () => {
    const existed = fs.existsSync(dashFile);
    const d = load();
    for (const v of ['on', 'ON', ' On ']) {
      process.env.SLACKBOT_DASHBOARD = v; calls.length = 0;
      const r = d.refreshDashboard('x');
      assert.notStrictEqual(r.skipped, 'disabled', v);
      assert.ok(calls.some(c => c[0] === 'git'), `git 호출 있어야 함(${v})`);
      assert.ok(!calls.some(c => c[0] === 'git' && /^(push|commit|add)$/.test(c[1])), 'push/commit/add 없음');
    }
    delete process.env.SLACKBOT_DASHBOARD;
    assert.strictEqual(fs.existsSync(dashFile), existed);
  });
}

test.after(() => { cp.spawnSync = realSpawnSync; });
