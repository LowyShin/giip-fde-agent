const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const AGENT_ROOT = path.resolve(__dirname, '..');
const KEYWORDS = {
  'auth': ['auth', '인증', 'login', '로그인', 'jwt', 'token', 'sso'],
  'mobile-order': ['order', '주문', 'code', 'access', 'mobile', '코드'],
  'deployment': ['deploy', '배포', 'azure', 'git push', 'static', 'css'],
  'debug': ['error', 'bug', 'fail', '오류', '에러', '버그', '실패', '무효'],
  'api': ['api', 'endpoint', 'request', 'response', '엔드포인트'],
  'storage': ['storage', 'blob', 'file', '파일', 'upload'],
  'agent-setup': ['hook', 'trace', 'k-layer', 'skill', 'klayer'],
  'design-references': ['pjcatapult', 'design', 'デザイン', 'mock', 'html', 'kashiwa', 'top page', 'トップ', 'ローカル', 'local', 'github', 'raw.github'],
};

function field(block, name) {
  const match = block.match(new RegExp(`^\\s*-\\s*(?:\\*\\*)?${name}(?:\\*\\*)?\\s*:\\s*(.*?)\\s*$`, 'im'));
  return match ? match[1].trim() : null;
}
function dateValue(value) {
  if (!value) return null;
  const match = value.match(/^(\d{4})-?(\d{2})-?(\d{2})$/);
  if (!match) return null;
  const date = new Date(`${match[1]}-${match[2]}-${match[3]}T00:00:00Z`);
  return Number.isNaN(date.getTime()) || date.toISOString().slice(0, 10) !== `${match[1]}-${match[2]}-${match[3]}` ? null : date;
}
function freshSource(block, workspaceDir) {
  const hash = field(block, 'source_hash');
  if (!hash) return true;
  const source = field(block, 'source_file');
  if (!source || !/^[0-9a-f]{64}$/i.test(hash)) return false;
  const full = path.resolve(workspaceDir, source);
  const relative = path.relative(workspaceDir, full);
  if (!relative || relative.startsWith('..') || path.isAbsolute(relative)) return false;
  try {
    const actual = fs.realpathSync(full);
    const actualRelative = path.relative(fs.realpathSync(workspaceDir), actual);
    if (actualRelative.startsWith('..') || path.isAbsolute(actualRelative)) return false;
    const stat = fs.statSync(actual);
    if (!stat.isFile() || stat.size > 2 * 1024 * 1024) return false;
    return crypto.createHash('sha256').update(fs.readFileSync(actual)).digest('hex') === hash.toLowerCase();
  } catch { return false; }
}

/** Select only local workspace claims. Unscoped historic claims belong solely to this agent repo. */
function searchKLayer(prompt, opts = {}) {
  const workspaceDir = path.resolve(opts.workspaceDir || AGENT_ROOT);
  const project = String(opts.project || path.basename(workspaceDir)).trim().toLowerCase();
  const csn = opts.csn == null ? null : String(opts.csn).trim();
  const maxClaims = Math.min(10, Math.max(0, Number.isInteger(opts.maxClaims) ? opts.maxClaims : 10));
  const maxChars = Math.min(1600, Math.max(0, Number.isInteger(opts.maxChars) ? opts.maxChars : 1600));
  if (!maxClaims || !maxChars) return [];
  const today = dateValue(opts.now || new Date().toISOString().slice(0, 10));
  const ownRepo = workspaceDir === AGENT_ROOT && project === 'giip-fde-agent';
  const text = String(prompt || '').toLowerCase();
  const matchedTopics = Object.entries(KEYWORDS).filter(([, keys]) => keys.some(k => text.includes(k))).map(([topic]) => topic);
  const relevantClaims = [];
  let totalChars = 0;
  const notesDir = path.join(workspaceDir, '.agent', 'knowledge', 'notes');
  let files;
  try {
    const actualDir = fs.realpathSync(notesDir);
    const workspace = fs.realpathSync(workspaceDir);
    const relative = path.relative(workspace, actualDir);
    if (relative.startsWith('..') || path.isAbsolute(relative)) return [];
    files = fs.readdirSync(notesDir).filter(f => f.endsWith('.md')).sort();
  }
  catch { return relevantClaims; }
  for (const file of files) {
    if (matchedTopics.length && !matchedTopics.some(t => file.includes(t))) continue;
    let content;
    try {
      const actualFile = fs.realpathSync(path.join(notesDir, file));
      const relative = path.relative(fs.realpathSync(notesDir), actualFile);
      if (relative.startsWith('..') || path.isAbsolute(relative)) continue;
      content = fs.readFileSync(actualFile, 'utf8');
    }
    catch { continue; }
    const blocks = content.split(/\r?\n(?=\s*(?:#{1,6}\s*)?CLAIM-\d+:)/);
    for (const block of blocks) {
      const heading = block.match(/^\s*(?:#{1,6}\s*)?(CLAIM-\d+:.*)$/m);
      if (!heading || field(block, 'invalidated_at') !== 'null') continue;
      const claimProject = field(block, 'project');
      const claimCsn = field(block, 'csn');
      if (!claimProject && !claimCsn && !ownRepo) continue;
      if (claimProject && claimProject.toLowerCase() !== project) continue;
      if (claimCsn && (!csn || claimCsn !== csn)) continue;
      const expiry = field(block, 'expires_at');
      if (expiry && (!dateValue(expiry) || dateValue(expiry) < today)) continue;
      const reviewDue = field(block, 'review_due_at');
      if (reviewDue && (!dateValue(reviewDue) || dateValue(reviewDue) <= today)) continue;
      if (!freshSource(block, workspaceDir)) continue;
      const label = `[${file}] ${heading[1]}`;
      const length = label.length + (relevantClaims.length ? 1 : 0);
      if (length > maxChars - totalChars) continue;
      relevantClaims.push(label);
      totalChars += length;
      if (relevantClaims.length >= maxClaims) return relevantClaims;
    }
  }
  return relevantClaims;
}

module.exports = { searchKLayer };
