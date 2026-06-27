const fs = require('fs');
const path = require('path');

const BASE_DIR = process.env.WORKSPACE_DIR ? path.resolve(process.env.WORKSPACE_DIR) : path.join(__dirname, '..');
const NOTES_DIR = path.join(BASE_DIR, '.agent', 'knowledge', 'notes');

const KEYWORDS = {
  'auth': ['auth', '인증', 'login', '로그인', 'jwt', 'token', 'sso', '認証'],
  'order': ['order', '주문', '注文', 'checkout'],
  'deployment': ['deploy', '배포', 'デプロイ', 'git push', 'release', '릴리스'],
  'debug': ['error', 'bug', 'fail', '오류', '에러', '버그', '실패', 'エラー', 'バグ'],
  'api': ['api', 'endpoint', 'request', 'response', '엔드포인트'],
  'storage': ['storage', 'blob', 'file', '파일', 'upload', 'ファイル'],
  'agent-setup': ['hook', 'trace', 'k-layer', 'skill', 'klayer'],
  'design': ['design', 'デザイン', 'mock', 'html', 'top page', 'github'],
};

function searchKLayer(prompt) {
  const text = (prompt || '').toLowerCase();
  const matchedTopics = new Set();

  for (const [topic, keys] of Object.entries(KEYWORDS)) {
    if (keys.some(k => text.includes(k))) matchedTopics.add(topic);
  }

  const relevantClaims = [];
  try {
    const noteFiles = fs.readdirSync(NOTES_DIR).filter(f => f.endsWith('.md'));
    for (const file of noteFiles) {
      const topicKey = file.replace('.md', '');
      const isRelevant =
        matchedTopics.size === 0 ||
        [...matchedTopics].some(t => file.includes(t) || topicKey.includes(t));

      if (!isRelevant) continue;

      const content = fs.readFileSync(path.join(NOTES_DIR, file), 'utf8');
      const claimBlocks = content.split(/\n(?=CLAIM-\d+:)/);
      for (const block of claimBlocks) {
        if (!block.startsWith('CLAIM-')) continue;
        if (block.includes('invalidated_at**: null') || block.includes('invalidated_at: null')) {
          const firstLine = block.split('\n')[0];
          relevantClaims.push(`[${file}] ${firstLine}`);
          if (relevantClaims.length >= 10) break;
        }
      }
      if (relevantClaims.length >= 10) break;
    }
  } catch {}

  return relevantClaims;
}

module.exports = { searchKLayer };
