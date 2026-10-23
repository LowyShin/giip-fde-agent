// giip 4045 결함 A 회귀 테스트 — 실행: node slack-bot/tools/test-context-catalog.js
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { buildContextCatalog, readSelectedContext } = require('../context-builder');

function dirs(t) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'ctxcat-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const project = path.join(root, 'project');      // 대상 프로젝트: .agent/rules 가 비어 있음
  const workspace = path.join(root, 'workspace');  // 에이전트 자신: 규칙·역할·스킬 보유
  fs.mkdirSync(path.join(project, '.agent', 'rules'), { recursive: true });
  for (const [sub, file] of [['rules', '00_core.md'], ['roles', 'dev.md']]) {
    fs.mkdirSync(path.join(workspace, '.agent', sub), { recursive: true });
    fs.writeFileSync(path.join(workspace, '.agent', sub, file), `# ${file}\n\nbody of ${file}\n`);
  }
  fs.mkdirSync(path.join(workspace, '.agent', 'skills', 's1'), { recursive: true });
  fs.writeFileSync(path.join(workspace, '.agent', 'skills', 's1', 'SKILL.md'), '# s1\n\nskill body\n');
  return { project, workspace };
}

test('프로젝트에 .agent 파일이 없으면 폴백한 파일 경로도 ".." 없이 workspace 기준이다 (결함 A)', t => {
  const { project, workspace } = dirs(t);
  const cat = buildContextCatalog(project, workspace);
  assert.ok(cat.length >= 3, `catalog size ${cat.length}`);
  for (const c of cat) {
    assert.ok(!c.path.split('/').includes('..'), `escaped path: ${c.path}`);
    assert.ok(!path.isAbsolute(c.path), c.path);
  }
});
test('폴백 카탈로그를 readSelectedContext 가 범위 오류 없이 읽는다', t => {
  const { project, workspace } = dirs(t);
  const cat = buildContextCatalog(project, workspace);
  const r = readSelectedContext(cat.map(c => ({ path: c.path })), project, { workspaceDir: workspace });
  assert.ok(r.filesRead.length >= 1);
});
test('프로젝트 자신이 .agent 파일을 가지면 프로젝트 기준 상대경로를 유지한다', t => {
  const { project, workspace } = dirs(t);
  fs.writeFileSync(path.join(project, '.agent', 'rules', 'own.md'), '# own\n\nx\n');
  const rules = buildContextCatalog(project, workspace).filter(c => c.type === 'rule');
  assert.deepEqual(rules.map(c => c.path), ['.agent/rules/own.md']);
});
